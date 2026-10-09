;;; (ironscheme std ports) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 6 / 38 的测试，
;;; 按 SRFI 6、SRFI 38 的文本编写，每个导出名至少一项。
(import (rnrs) (rnrs mutable-pairs) (only (ironscheme) include) (ironscheme std ports))
(include "tests/std/check.ss")

(define (ss->string obj) (call-with-string-output-port (lambda (p) (write-with-shared-structure obj p))))
(define (read-ss s) (read-with-shared-structure (open-input-string s)))

;;; ———————————————— SRFI 6 ————————————————
(define p (open-input-string "(a b) 42"))
(check (textual-port? p) => #t)
(check (read p) => '(a b))
(check (read p) => 42)
(check (eof-object? (read p)) => #t)
(check (get-string-all (open-input-string "xyz")) => "xyz")

;;; ———————————————— SRFI 38：写出 ————————————————
;; 没有共享时与 write 相同
(check (ss->string '(1 "a" #\b #(2 3) sym)) => "(1 \"a\" #\\b #(2 3) sym)")
;; 循环
(define c (list 1 2))
(set-cdr! (cdr c) c)
(check (ss->string c) => "#1=(1 2 . #1#)")
;; 共享（非循环）的子结构
(define s (list 'x))
(check (ss->string (list s s)) => "(#1=(x) #1#)")
;; 向量中的循环
(define v (vector 1 #f))
(vector-set! v 1 v)
(check (ss->string v) => "#1=#(1 #1#)")
;; 简写
(check (call-with-string-output-port (lambda (port) (write/ss (list s s) port))) => "(#1=(x) #1#)")

;;; ———————————————— SRFI 38：读入 ————————————————
(check (read-ss "(1 2 3)") => '(1 2 3))
(check (read-ss "#(a \"s\" #\\c)") => '#(a "s" #\c))
(define r (read-ss "#0=(a . #0#)"))
(check (eq? r (cdr r)) => #t)
(define r2 (read-ss "(#1=(x) #1#)"))
(check (eq? (car r2) (cadr r2)) => #t)
(define r3 (read-ss "#2=#(1 #2#)"))
(check (eq? r3 (vector-ref r3 1)) => #t)
(check (eof-object? (read-ss "")) => #t)
(check (read/ss (open-input-string "(b c)")) => '(b c))
;; 往返：写出再读入，结构相同
(define back (read-ss (ss->string c)))
(check (list (car back) (cadr back) (eq? back (cddr back))) => '(1 2 #t))

;;; ———————————————— with-output-to-string / with-input-from-string（iron-054） ————————————————
(check (with-output-to-string (lambda () (display "a") (write "b") (newline))) => "a\"b\"\n")
(check (with-output-to-string (lambda () #f)) => "")
(check (with-input-from-string "(1 2) x" (lambda () (list (read) (read)))) => '((1 2) x))
(check (with-input-from-string "" read-char) => (eof-object))

(check-report "std ports")
