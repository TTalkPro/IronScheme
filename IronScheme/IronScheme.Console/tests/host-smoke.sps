;;; 新宿主冒烟测试（iron-029）：在 stage1 boot 上以顶层程序运行；全部通过时退出码 0。
(import (rnrs) (rnrs eval) (ironscheme) (ironscheme clr))

(display "hello")
(newline)

(define failures 0)
(define-syntax check
  (syntax-rules ()
    ((_ expr expected)
     (let ((got (guard (e (#t (list 'exception (if (message-condition? e) (condition-message e) e)))) expr)))
       (unless (equal? got expected)
         (set! failures (+ failures 1))
         (display "FAIL: ") (write 'expr) (display " => ") (write got) (newline))))))

(define (square x) (* x x))
(define (fact n) (if (= n 0) 1 (* n (fact (- n 1)))))
(define-record-type point (fields x y))
(define-syntax my-or
  (lambda (x)
    (syntax-case x ()
      ((_) #'#f)
      ((_ e) #'e)
      ((_ e r ...) #'(let ((t e)) (if t t (my-or r ...)))))))

(check (square 12) 144)
(check (fact 25) 15511210043330985984000000)
(check (map square '(1 2 3)) '(1 4 9))
(check (let loop ((i 0) (acc 0)) (if (= i 1000000) acc (loop (+ i 1) (+ acc i)))) 499999500000)
(check (point-y (make-point 1 2)) 2)
(check (my-or #f 3) 3)
(check (let ((t 5)) (my-or #f t)) 5)
(check (eval '(let-values (((q r) (div-and-mod 17 5))) (list q r)) (environment '(rnrs))) '(3 2))
(check (call/cc (lambda (k) (dynamic-wind (lambda () #f) (lambda () (k 'escaped)) (lambda () #f)))) 'escaped)
(check (guard (e ((assertion-violation? e) 'caught)) (vector-ref (vector 1) 5)) 'caught)
(check (string-append "a" (number->string 1/3) (symbol->string 'b)) "a1/3b")
(check (list-sort < '(3 1 2)) '(1 2 3))
(check (let ((h (make-eq-hashtable))) (hashtable-set! h 'k 'v) (hashtable-ref h 'k #f)) 'v)
(check (call-with-string-output-port (lambda (p) (write '(1 "x" #\y 2.5) p))) "(1 \"x\" #\\y 2.5)")
(check (clr-static-call System.Math Max 3 9) 9)
(check (exact->inexact 1/8) 0.125)
(check (command-line) (list (car (command-line)) "arg1"))
;; eval 经 boot 镜像中的新编译器：结果过程来自内存程序集 eval$…
(check (let ((p (eval '(lambda (x) (+ x 1)) (environment '(rnrs)))))
         (list (p 41)
               (string=? (substring (clr-prop-get System.Reflection.AssemblyName Name
                                      (clr-call System.Reflection.Assembly GetName
                                        (clr-prop-get System.Type Assembly (clr-call System.Object GetType p)))) 0 5)
                         "eval$")))
       '(42 #t))

(display "host smoke: ")
(display (if (= failures 0) "all checks passed" "FAILED"))
(newline)
(unless (= failures 0) (exit 1))
