;;; (ironscheme std persistent sequences) 的测试（designs/08-std-library.md D8）。改写自 pfds 的
;;; tests/sequences.sls（Ian Price，new-style BSD 许可）：trc-testing 的断言经 tests/std/trc-check.ss 计入 check.ss 的计数。
(import (rnrs) (only (ironscheme) include)
        (ironscheme std persistent sequences))
(include "tests/std/check.ss")
(include "tests/std/trc-check.ss")

(define-test-suite sequences
  "Tests for the sequences implementation")
;; Note: at the moment, sequences are a trivial instantiation of
;; fingertrees, and so are pretty much covered by the fingertrees
;; tests.

(define-test-case sequences sequences-bugs
  (let ((s (sequence 'zero 'one 'two)))
    (test-case sequences-bugs ()
      (test-eqv 'zero (sequence-ref s 0))
      (test-eqv 'two (sequence-ref s 2))
      (test-exn assertion-violation? (sequence-ref s -1))
      (test-exn assertion-violation? (sequence-ref s 3)))))

;;; ———————————————— 补充（iron-045）：原测试没有覆盖的导出 ————————————————
(check (sequence? (make-sequence)) => #t)
(check (sequence? '(1 2)) => #f)
(check (sequence-empty? (make-sequence)) => #t)
(check (sequence-empty? (sequence 1)) => #f)
(check (sequence-size (sequence 1 2 3)) => 3)
(check (sequence->list (sequence-cons 0 (sequence 1 2))) => '(0 1 2))
(check (sequence->list (sequence-snoc (sequence 1 2) 3)) => '(1 2 3))
(check (call-with-values (lambda () (sequence-uncons (sequence 1 2 3)))
         (lambda (x s) (list x (sequence->list s))))
       => '(1 (2 3)))
(check (call-with-values (lambda () (sequence-unsnoc (sequence 1 2 3)))
         (lambda (s x) (list (sequence->list s) x)))
       => '((1 2) 3))
(check-raises sequence-empty-condition? (sequence-uncons (make-sequence)))
(check-raises sequence-empty-condition? (sequence-unsnoc (make-sequence)))
(check (sequence->list (sequence-append (list->sequence '(1 2)) (list->sequence '(3 4)))) => '(1 2 3 4))
(check (call-with-values (lambda () (sequence-split-at (sequence 1 2 3 4) 1))
         (lambda (a b) (list (sequence->list a) (sequence->list b))))
       => '((1) (2 3 4)))
(check (call-with-values (lambda () (sequence-split-at (sequence 1 2) -1))
         (lambda (a b) (list (sequence->list a) (sequence->list b))))
       => '(() (1 2)))
(check (sequence->list (sequence-take (sequence 1 2 3) 2)) => '(1 2))
(check (sequence->list (sequence-take (sequence 1 2 3) 10)) => '(1 2 3))
(check (sequence->list (sequence-drop (sequence 1 2 3) 2)) => '(3))
(check (sequence->list (sequence-drop (sequence 1 2 3) -1)) => '(1 2 3))
(check (sequence-ref (sequence 'a 'b 'c) 1) => 'b)
(check-raises assertion-violation? (sequence-ref (sequence 'a) 5))
(check (sequence->list (sequence-set (sequence 'a 'b 'c) 1 'x)) => '(a x c))
(check (sequence-fold cons '() (sequence 1 2 3)) => '(3 2 1))
(check (sequence-fold-right cons '() (sequence 1 2 3)) => '(1 2 3))
(check (sequence->list (sequence-reverse (sequence 1 2 3))) => '(3 2 1))
(check (sequence->list (sequence-map (lambda (x) (* x x)) (sequence 1 2 3))) => '(1 4 9))
(check (sequence->list (sequence-filter odd? (sequence 1 2 3 4 5))) => '(1 3 5))

(check-report "std persistent sequences")
