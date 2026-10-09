;;; iron-050：Task 的互操作与原语（designs/10-async.md §2 D8、§1 D5）。async-lambda 本身的测试在 iron-053 补。
(import (ironscheme) (ironscheme clr)
        (only (ironscheme core)
              task? task-completed? task-faulted? task-result task-from-result task-from-exception
              task-delay task-yield task-run task-then task-when-all task-when-any
              make-task-source task-source-task task-source-set-result! task-source-set-exception!))

(clr-using System)
(clr-using System.IO)
(clr-using System.Threading)
(clr-using System.Threading.Tasks)

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

;;; A：.NET 返回的 Task<T> / Task 进入 Scheme 时是 Task<object>
(define text-task
  (clr-static-call File (ReadAllTextAsync String CancellationToken)
                   "tests/async/interop.sps" (clr-static-prop-get CancellationToken None)))
(check (task? text-task) => #t)
(check (clr-is (Task Object) text-task) => #t)
(check (string? (task-result text-task)) => #t)
(check (let ((s (task-result text-task))) (substring s 0 3)) => ";;;")

(define int-task (clr-static-call Task (FromResult #(Int32)) 41))
(check (clr-is (Task Object) int-task) => #t)
(check (task-result int-task) => 41)
(define delay-task (clr-static-call Task Delay 1))              ; 非泛型 Task → 结果为未指定值
(check (clr-is (Task Object) delay-task) => #t)
(check (unspecified? (task-result delay-task)) => #t)

;;; B：返回 task 的 Scheme 过程转成 Func<Task<int>>，.NET 端 await 得到整数
(define as-func (clr-cast (Func (Task Int32)) (lambda () (task-from-result 42))))
(check (clr-is (Func (Task Int32)) as-func) => #t)
(define invoked (clr-call (Func (Task Int32)) Invoke as-func))   ; Task<int>，回到 Scheme 又成 Task<object>
(check (task-result invoked) => 42)
(check (task-result (clr-static-call Task (FromResult #(Int64)) 5)) => 5)   ; Task<long> 的结果转成 fixnum
(check (task-result (clr-call (Func (Task Int32)) Invoke (clr-cast (Func (Task Int32)) (lambda () 7)))) => 7)   ; 同步值也行

;;; C：原语
(check (task-result (task-then (task-from-result 1) (lambda (x) (+ x 1)))) => 2)
(check (task-result (task-then (task-delay 5) (lambda (x) (task-from-result 'nested)))) => 'nested)
(check (task-result (task-when-all (list (task-from-result 1) (task-run (lambda () 2)) (task-from-result 3)))) => '(1 2 3))
(check (task-result (task-result (task-when-any (list (task-delay 500) (task-from-result 'first))))) => 'first)   ; 结果是最先完成的 task
(check (task-faulted? (task-from-exception (make-message-condition "bad"))) => #t)
(check (guard (e ((message-condition? e) (condition-message e)))
         (task-result (task-from-exception (make-message-condition "bad"))))
       => "bad")                                                  ; 条件原样回到 guard
(check (let ((src (make-task-source)))
         (task-source-set-result! src 'ready)
         (task-result (task-source-task src)))
       => 'ready)
(check (task-completed? (task-yield)) => #f)                      ; 让给线程池，不同步完成
(check (unspecified? (task-result (task-yield))) => #t)
(check (task-result (task-run (lambda () (task-from-result 'unwrapped)))) => 'unwrapped)

;;; D：参数对象随 ExecutionContext 流入 task-run 的子任务，子任务里的赋值不流出
(define p (make-parameter 'outer))
(check (parameterize ((p 'inner))
         (list (task-result (task-run (lambda () (p))))
               (task-result (task-run (lambda () (p 'child) (p))))
               (p)))
       => '(inner child inner))
(check (p) => 'outer)
(check (let ((q (make-parameter '()))) (q '(1)) (q '()) (q)) => '())   ; 空表不是"未设置"

;;; E：guard 的处理器在线程池子任务里仍能接住 raise（处理器栈也是 AsyncLocal）
(check (with-exception-handler
         (lambda (e) (list 'handled e))
         (lambda () (task-result (task-run (lambda () (raise-continuable 'from-pool))))))
       => '(handled from-pool))
(check (task-result (task-run (lambda () (guard (e (#t 'inner-guard)) (raise 'x))))) => 'inner-guard)

(display (if (= failures 0) "async-interop: all passed" "async-interop: failed"))
(newline)
(display count) (display " checks") (newline)
