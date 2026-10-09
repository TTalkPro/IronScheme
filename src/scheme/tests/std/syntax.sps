;;; (ironscheme std syntax) 的测试（designs/08-std-library.md D8）。and-let* 部分改写自
;;; chez-srfi 的 tests/and-let*.sps（Derick Eddington，MIT 许可，见 lib/ironscheme/std/LICENSES/chez-srfi.txt）。
(import (rnrs) (rnrs eval) (rnrs r5rs) (only (ironscheme) include) (ironscheme std syntax))
(include "tests/std/check.ss")

(define-syntax expect
  (syntax-rules ()
    ((_ expr result) (check expr => result))))

(define-syntax must-be-a-syntax-error
  (syntax-rules ()
    ((_ expr)
     (check
       (guard (ex (#t (syntax-violation? ex)))
         (eval 'expr (environment '(rnrs) '(ironscheme std syntax)))
         'unexpected-return)
       => #t))))

;;; ———————————————— and-let*（SRFI 2）————————————————
;; Taken from the reference implementation tests

(expect  (and-let* () 1) 1)
(expect  (and-let* () 1 2) 2)
(expect  (and-let* () ) #T)

(expect (let ((x #F)) (and-let* (x))) #F)
(expect (let ((x 1)) (and-let* (x))) 1)
(expect (and-let* ((x #F)) ) #F)
(expect (and-let* ((x 1)) ) 1)
(must-be-a-syntax-error (and-let* ( #F (x 1))) )
(expect (and-let* ( (#F) (x 1)) ) #F)
(must-be-a-syntax-error (and-let* (2 (x 1))) )
(expect (and-let* ( (2) (x 1)) ) 1)
(expect (and-let* ( (x 1) (2)) ) 2)
(expect (let ((x #F)) (and-let* (x) x)) #F)
(expect (let ((x "")) (and-let* (x) x)) "")
(expect (let ((x "")) (and-let* (x)  )) "")
(expect (let ((x 1)) (and-let* (x) (+ x 1))) 2)
(expect (let ((x #F)) (and-let* (x) (+ x 1))) #F)
(expect (let ((x 1)) (and-let* (((positive? x))) (+ x 1))) 2)
(expect (let ((x 1)) (and-let* (((positive? x))) )) #T)
(expect (let ((x 0)) (and-let* (((positive? x))) (+ x 1))) #F)
(expect (let ((x 1)) (and-let* (((positive? x)) (x (+ x 1))) (+ x 1)))  3)
;; Derick thinks variable shadowing should be allowed, because it's a "let*".
#;(must-be-a-syntax-error
  (let ((x 1)) (and-let* (((positive? x)) (x (+ x 1)) (x (+ x 1))) (+ x 1))))

(expect (let ((x 1)) (and-let* (x ((positive? x))) (+ x 1))) 2)
(expect (let ((x 1)) (and-let* ( ((begin x)) ((positive? x))) (+ x 1))) 2)
(expect (let ((x 0)) (and-let* (x ((positive? x))) (+ x 1))) #F)
(expect (let ((x #F)) (and-let* (x ((positive? x))) (+ x 1))) #F)
(expect (let ((x #F)) (and-let* ( ((begin x)) ((positive? x))) (+ x 1))) #F)

(expect  (let ((x 1)) (and-let* (x (y (- x 1)) ((positive? y))) (/ x y))) #F)
(expect  (let ((x 0)) (and-let* (x (y (- x 1)) ((positive? y))) (/ x y))) #F)
(expect  (let ((x #F)) (and-let* (x (y (- x 1)) ((positive? y))) (/ x y))) #F)
(expect  (let ((x 3)) (and-let* (x (y (- x 1)) ((positive? y))) (/ x y))) 3/2)

;; Derick's additional tests

(must-be-a-syntax-error (and-let* (("oops" 1))))
(must-be-a-syntax-error (and-let* ((x 1 2))))
(must-be-a-syntax-error (and-let* ((x 1) . oops)))
(expect (let ((x 1))
          (and-let* ((x (+ x 1))
                     (x (+ x 1))
                     (x (+ x 1)))
            (+ x 1)))
        5)
(expect (and-let* () (define x 1) (- x)) -1)
(expect (and-let* ((x 2) (y (+ 1 x))) (define z (* x y)) (/ z)) 1/6)


;;; ———————————————— cond-expand（SRFI 0）————————————————

(check (cond-expand (ironscheme 'yes) (else 'no)) => 'yes)
(check (cond-expand (r6rs 'yes) (else 'no)) => 'yes)
(check (cond-expand ((and ironscheme r6rs) 'both) (else 'no)) => 'both)
(check (cond-expand ((or no-such-feature ironscheme) 'one) (else 'no)) => 'one)
(check (cond-expand ((not no-such-feature) 'yes) (else 'no)) => 'yes)
(check (cond-expand (no-such-feature 'no) (else 'fallback)) => 'fallback)
(check (cond-expand ((or windows posix) 'os) (else 'no)) => 'os)
(check (cond-expand (srfi-1 'srfi) (else 'none)) => 'none)   ; D5：不声明 srfi-N
(must-be-a-syntax-error (cond-expand (no-such-feature 1)))

;;; ———————————————— receive（SRFI 8）————————————————

(check (receive (a b . rest) (values 1 2 3 4) (list a b rest)) => '(1 2 (3 4)))
(check (receive all (values 1 2) all) => '(1 2))
(check (receive (x) (values 'one) x) => 'one)

;;; ———————————————— fluid-let（SRFI 15）————————————————

(define depth 0)
(define (current-depth) depth)
(check (fluid-let ((depth 5)) (current-depth)) => 5)
(check depth => 0)
(check (guard (e (#t depth)) (fluid-let ((depth 7)) (raise 'oops))) => 0)   ; 非正常退出也恢复

;;; ———————————————— rec（SRFI 31）————————————————

(check ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5) => 120)
(check (let ((s (rec xs (cons 1 (delay xs))))) (car (force (cdr s)))) => 1)

;;; ———————————————— assume（SRFI 145）————————————————

(check (assume (+ 1 2) "never") => 3)
(check-raises assertion-violation? (assume (= 1 2) "one is not two"))

(check-report "std syntax")
