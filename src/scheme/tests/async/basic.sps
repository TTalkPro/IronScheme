;;; iron-052：async-lambda / await 的状态机后端（designs/10-async.md §3.3）。iron-049 spike 的测试矩阵改写成 Scheme。
(import (ironscheme) (ironscheme clr)
        (only (ironscheme core)
              task? task-completed? task-result task-from-result task-from-exception
              task-delay task-yield task-run task-when-all make-task-source task-source-task task-source-set-result!))

(clr-using System.Threading)

(define failures 0)
(define count 0)
(define-syntax check
  (syntax-rules (=>)
    ((_ expr => expected)
     (let ((v (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e)))) expr)))
       (set! count (+ count 1))
       (unless (equal? v expected)
         (set! failures (+ failures 1))
         (display "FAIL: ") (write 'expr) (display " => ") (write v)
         (display ", expected ") (write expected) (newline))))))

(define (thread-id) (clr-prop-get Thread ManagedThreadId (clr-static-prop-get Thread CurrentThread)))
(define (after ms v) (task-run (lambda () (task-result (task-delay ms)) v)))   ; ms 后完成、结果为 v 的 task

;;; fast：已完成的 task，同步完成、不换线程
(define-async (echo t) (await t))
(check (task? (echo (task-from-result 42))) => #t)
(check (task-completed? (echo (task-from-result 42))) => #t)
(check (task-result (echo (task-from-result 42))) => 42)
(define-async (tid-fast t) (let ((a (thread-id))) (await t) (list (= a (thread-id)))))
(check (task-result (tid-fast (task-from-result 1))) => '(#t))

;;; suspend：未完成的 task，挂起后恢复，结果正确
(check (task-completed? (echo (after 50 'later))) => #f)
(check (task-result (echo (after 50 'later))) => 'later)

;;; 参数与局部变量跨挂起
(define-async (add3 a b t) (let ((c (await t))) (+ a b c)))
(check (task-result (add3 1 2 (after 10 3))) => 6)

;;; loop：命名 let 与 do 里 await
(define-async (sum-loop n)
  (let loop ((i 0) (sum 0))
    (if (= i n)
        sum
        (begin (await (task-yield)) (loop (+ i 1) (+ sum i))))))
(check (task-result (sum-loop 100)) => 4950)
(define-async (do-loop ts)
  (do ((ts ts (cdr ts)) (acc '() (cons (await (car ts)) acc)))
      ((null? ts) (reverse acc))))
(check (task-result (do-loop (list (task-from-result 1) (after 10 2) (task-from-result 3)))) => '(1 2 3))

;;; try-finally：dynamic-wind 跨 await，after 只跑一次
(define wind-log '())
(define-async (wind t)
  (dynamic-wind
    (lambda () (set! wind-log (cons 'in wind-log)))
    (lambda () (await t) (set! wind-log (cons 'body wind-log)) 'done)
    (lambda () (set! wind-log (cons 'out wind-log)))))
(check (task-result (wind (after 20 #f))) => 'done)
(check (reverse wind-log) => '(in body out))
(set! wind-log '())
(check (task-result (wind (task-from-result #f))) => 'done)
(check (reverse wind-log) => '(in body out))

;;; guard 跨 await：被等待的 task 以 Scheme 条件失败时回到 guard；.NET 异常原样
(define-async (guarded t)
  (guard (e ((message-condition? e) (list 'caught (condition-message e)))
            ((symbol? e) (list 'caught e)))
    (await t)))
(check (task-result (guarded (task-from-result 'ok))) => 'ok)
(check (task-result (guarded (task-from-exception (make-message-condition "bad")))) => '(caught "bad"))
(check (task-result (guarded (task-run (lambda () (task-result (task-delay 10)) (raise 'late))))) => '(caught late))
(define-async (raising t) (await t) (raise 'inside))
(check (task-result (guarded (raising (after 10 #f)))) => '(caught inside))
(check (with-clr-exception-handler
         (lambda (e) (clr-is System.InvalidOperationException e))
         (lambda () (task-result (echo (task-from-exception (clr-new System.InvalidOperationException "x"))))))
       => #t)

;;; with-exception-handler 跨 await
(define-async (handled t)
  (with-exception-handler
    (lambda (e) (list 'handled e))
    (lambda () (await t) (raise-continuable 'r))))
(check (task-result (handled (after 10 #f))) => '(handled r))

;;; parameterize 跨 await（恢复可能在另一个线程上）
(define p (make-parameter 'outer))
(define-async (param-test t) (parameterize ((p 'inner)) (await t) (p)))
(check (task-result (param-test (after 10 #f))) => 'inner)
(check (p) => 'outer)

;;; nested：async 调 async，深递归
(define-async (nested t) (await (echo t)))
(check (task-result (nested (after 10 'n))) => 'n)
(define-async (recurse n) (if (= n 0) (begin (await (task-yield)) 0) (+ 1 (await (recurse (- n 1))))))
(check (task-result (recurse 10000)) => 10000)
(define-async (sync-recurse n) (if (= n 0) 0 (+ 1 (await (sync-recurse (- n 1))))))
(check (task-result (sync-recurse 10000)) => 10000)

;;; 闭包：捕获自由变量；async-lambda 作为值
(define (make-adder k) (async-lambda (t) (+ k (await t))))
(check (task-result ((make-adder 10) (after 5 5))) => 15)
(check (map (lambda (f) (task-result (f (task-from-result 1)))) (list (make-adder 1) (make-adder 2))) => '(2 3))

;;; 剩余参数、多值
(define-async (rest-args t . more) (cons (await t) more))
(check (task-result (rest-args (task-from-result 0) 1 2)) => '(0 1 2))
(define-async (two-values t) (await t) (values 1 2))
(check (call-with-values (lambda () (task-result (two-values (task-from-result #f)))) list) => '(1 2))

;;; 操作数位置的 await 按从左到右求值
(define order '())
(define (note x) (set! order (cons x order)) x)
(define-async (operands t) (list (note 'a) (await t) (note 'c)))
(check (task-result (operands (after 5 'b))) => '(a b c))
(check (reverse order) => '(a c))

;;; 并发：100 个 300 ms 的等待总共不到 1 秒（不占线程）
(define-async (sleep-ms ms) (await (task-delay ms)) ms)
(define t0 (clr-static-prop-get System.Environment TickCount))
(define all (task-when-all (let loop ((i 0) (acc '())) (if (= i 100) acc (loop (+ i 1) (cons (sleep-ms 300) acc))))))
(check (length (task-result all)) => 100)
(define elapsed (- (clr-static-prop-get System.Environment TickCount) t0))
(check (< elapsed 1000) => #t)
(display "100 x 300 ms: ") (display elapsed) (display " ms") (newline)

;;; 由 TaskCompletionSource 驱动
(define src (make-task-source))
(define waiting (echo (task-source-task src)))
(check (task-completed? waiting) => #f)
(task-source-set-result! src 'signalled)
(check (task-result waiting) => 'signalled)

(display (if (= failures 0) "async-basic: all passed" "async-basic: failed"))
(newline)
(display count) (display " checks") (newline)
