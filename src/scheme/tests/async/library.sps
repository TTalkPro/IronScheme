;;; iron-053：(ironscheme async) 库——再导出、for-each-async / map-async、编译期错误、与 .NET 委托的互操作。
;;; 状态机本身的用例在 basic.sps，原语与 Task 转换在 interop.sps。
(import (rnrs) (rnrs eval) (ironscheme) (ironscheme clr) (ironscheme async))

(clr-using System)
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

(define (after ms v) (task-run (lambda () (task-result (task-delay ms)) v)))

;;; A：只 import (ironscheme async) 就能写 async 过程
(define-async (twice t) (* 2 (await t)))
(check (task? (twice (task-from-result 1))) => #t)
(check (task-result (twice (after 5 21))) => 42)
(check (task-result ((async-lambda (a b) (+ (await a) (await b))) (after 5 1) (task-from-result 2))) => 3)

;;; B：for-each-async / map-async 顺序执行；回调里不能 await 的场景
(define order '())
(define-async (visit x) (await (task-delay (- 10 x))) (set! order (cons x order)) (* x x))
(check (unspecified? (task-result (for-each-async visit '(1 2 3)))) => #t)
(check (reverse order) => '(1 2 3))                                ; 顺序，不是并发
(check (task-result (map-async visit '(3 2 1))) => '(9 4 1))
(check (task-result (map-async (lambda (x) (task-from-result (+ x 1))) '(1 2))) => '(2 3))
(check (task-result (map-async visit '())) => '())
(check (task-result (task-when-all (map visit '(1 2)))) => '(1 4))  ; 并发的写法

;;; C：多值跨 await
(define-async (two) (await (task-delay 1)) (values 1 2))
(define-async (use-two) (call-with-values (lambda () (await (two))) list))
(check (task-result (use-two)) => '(1 2))

;;; D：编译期错误——await 出现在不允许的位置
(define env (environment '(rnrs) '(ironscheme async)))
(define (compile-error expr)
  (guard (e ((message-condition? e) (condition-message e)) (#t 'other))
    (eval expr env)
    'no-error))
(define (contains? s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring s i (+ i m)) sub) #t)
            (else (loop (+ i 1)))))))
(check (contains? (compile-error '(async-lambda (l) (for-each (lambda (x) (await x)) l))) "nested lambda") => #t)
(check (contains? (compile-error '(async-lambda (l) (let loop ((l l)) (if (null? l) 0 (+ 1 (loop (cdr (await l))))))))
                  "non-tail position")
       => #t)
(check (contains? (compile-error '(async-lambda (t) (dynamic-wind (lambda () #f) (lambda () #f) (lambda () (await t)))))
                  "finally")
       => #t)
(check (contains? (compile-error '(lambda (t) (await t))) "not inside an async-lambda") => #t)
(check (contains? (compile-error '(async-lambda (t) (guard (e (#t (await t))) 1))) "nested lambda") => #t)
(check (compile-error '(async-lambda (t) (guard (e (#t e)) (await t)))) => 'no-error)   ; guard 的体可以

;;; E：返回 task 的 Scheme 过程当 Func<Task<int>> 交给 .NET，.NET 端 await 得到整数
(define as-func (clr-cast (Func (Task Int32)) (async-lambda () (await (task-delay 1)) 7)))
(check (task-result (clr-call (Func (Task Int32)) Invoke as-func)) => 7)
(define as-plain (clr-cast (Func (Task Int32)) (lambda () 8)))              ; 同步值也包成 Task
(check (task-result (clr-call (Func (Task Int32)) Invoke as-plain)) => 8)
;; .NET 返回的 Task 直接 await
(define-async (delay-then-answer) (await (clr-static-call Task Delay 1)) 'answered)
(check (task-result (delay-then-answer)) => 'answered)

;;; F：失败经 task 传递；在等待方接住
(define-async (fails) (await (task-delay 1)) (raise 'boom))
(check (guard (e ((symbol? e) (list 'caught e))) (task-result (fails))) => '(caught boom))
(define-async (catches) (guard (e ((symbol? e) (list 'inner e))) (await (fails))))
(check (task-result (catches)) => '(inner boom))
(let ((t (fails))) (guard (e (#t #f)) (task-result t)) (check (task-faulted? t) => #t))

(display (if (= failures 0) "async-library: all passed" "async-library: failed"))
(newline)
(display count) (display " checks") (newline)
