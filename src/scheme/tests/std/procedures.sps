;;; (ironscheme std procedures) 的测试（designs/08-std-library.md D8）。cut 部分改写自 chez-srfi 的
;;; %3a26/check.scm 与 tests/cut.sps（Sebastian Egner；Derick Eddington，MIT 许可）。
(import (rnrs) (rnrs eval) (only (ironscheme) include procedure-arity) (ironscheme std procedures))
(include "tests/std/check.ss")

;;; ———————————————— cut / cute（SRFI 26）————————————————
(for-each
  (lambda (case)
    (check (eval case (environment '(rnrs) '(ironscheme std procedures))) => #t))
  '( 
     (equal? ((cut list)) '())
     (equal? ((cut list <...>)) '())
     (equal? ((cut list 1)) '(1))
     (equal? ((cut list <>) 1) '(1))
     (equal? ((cut list <...>) 1) '(1))
     (equal? ((cut list 1 2)) '(1 2))
     (equal? ((cut list 1 <>) 2) '(1 2))
     (equal? ((cut list 1 <...>) 2) '(1 2))
     (equal? ((cut list 1 <...>) 2 3 4) '(1 2 3 4))
     (equal? ((cut list 1 <> 3 <>) 2 4) '(1 2 3 4))
     (equal? ((cut list 1 <> 3 <...>) 2 4 5 6) '(1 2 3 4 5 6))
     (equal? (let* ((x 'wrong) (y (cut list x))) (set! x 'ok) (y)) '(ok))
     (equal? 
      (let ((a 0))
	(map (cut + (begin (set! a (+ a 1)) a) <>)
	     '(1 2))
	a)
      2)
      ; cutes
     (equal? ((cute list)) '())
     (equal? ((cute list <...>)) '())
     (equal? ((cute list 1)) '(1))
     (equal? ((cute list <>) 1) '(1))
     (equal? ((cute list <...>) 1) '(1))
     (equal? ((cute list 1 2)) '(1 2))
     (equal? ((cute list 1 <>) 2) '(1 2))
     (equal? ((cute list 1 <...>) 2) '(1 2))
     (equal? ((cute list 1 <...>) 2 3 4) '(1 2 3 4))
     (equal? ((cute list 1 <> 3 <>) 2 4) '(1 2 3 4))
     (equal? ((cute list 1 <> 3 <...>) 2 4 5 6) '(1 2 3 4 5 6))
     (equal? (let* ((x 'ok) (y (cute list x))) (set! x 'wrong) (y)) '(ok))
     (equal? 
      (let ((a 0))
	(map (cute + (begin (set! a (+ a 1)) a) <>)
	     '(1 2))
	a)
      1)))

;;;; free-identifier=? of <> and <...>

(check
 (let* ((<> 'wrong) (f (cut list <> <...>)))
   (set! <> 'ok)
   (f 1 2))
 => '(ok 1 2))
(check
 (let* ((<...> 'wrong) (f (cut list <> <...>)))
   (set! <...> 'ok)
   (f 1))
 => '(1 ok))
(check
 (let* ((<> 'ok) (f (cute list <> <...>)))
   (set! <> 'wrong)
   (f 1 2))
 => '(ok 1 2))
(check
 (let* ((<...> 'ok) (f (cute list <> <...>)))
   (set! <...> 'wrong)
   (f 1))
 => '(1 ok))

;;; ———————————————— is / isnt（SRFI 156）————————————————

(check (is 1 < 2) => #t)
(check (is 1 < 2 < 3) => #t)
(check (is 3 < 2) => #f)
(check (isnt 3 < 2) => #t)
(check ((is _ < 3) 2) => #t)
(check (filter (is _ > 2) '(1 2 3 4)) => '(3 4))
(check ((is 'x eq? _) 'x) => #t)
(check ((is _ null?) '()) => #t)

;;; ———————————————— rest-values（SRFI 51）————————————————

;; 最多两个可选参数，缺省为 1 与 3；缺省写成 (缺省值 . 谓词)
(define (f . rest) (rest-values rest 2 (cons 1 integer?) (cons 3 integer?)))
(check (call-with-values (lambda () (f)) list) => '(1 3))
(check (call-with-values (lambda () (f 10)) list) => '(10 3))
(check-raises assertion-violation? (f 1 2 3))                      ; 多于两个
;; 缺省写成表：第一个是缺省值，其余是允许的取值
(define (g . rest) (rest-values rest 1 '(red red green blue)))
(check (call-with-values (lambda () (g)) list) => '(red))
(check (call-with-values (lambda () (g 'blue)) list) => '(blue))
(check-raises assertion-violation? (g 'pink))
(check (call-with-values (lambda () (rest-values '(a b))) list) => '(a b))
;; arg-and：全部为真时返回最后一个的值，否则报错；arg-or：任一为真时报错，否则为 #f
(define x 5)
(check (arg-and x (integer? x) (> x 0)) => #t)
(check-raises assertion-violation? (let ((y -1)) (arg-and y (> y 0))))
(check (arg-or x (string? x)) => #f)
(check-raises assertion-violation? (arg-or x (integer? x)))

;;; ———————————————— 参数个数（SRFI 102 的三个过程，基于 IronScheme 的 procedure-arity）————————————————

(define (two a b) a)
(define (at-least-one a . r) a)
(define multi (case-lambda ((a) a) ((a b c) a)))
(check (procedure-arity-includes? two 2) => #t)
(check (procedure-arity-includes? two 1) => #f)
(check (procedure-arity-includes? at-least-one 5) => #t)
(check (procedure-arity-includes? at-least-one 0) => #f)
(check (procedure-arity-includes? multi 3) => #t)
(check (procedure-arity-includes? multi 2) => #f)
(check (arity-at-least? (procedure-arity at-least-one)) => #t)
(check (arity-at-least-value (procedure-arity at-least-one)) => 1)
(check (arity-at-least? 2) => #f)

(check-report "std procedures")
