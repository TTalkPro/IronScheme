;;; (ironscheme std comparators) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 128 的测试，
;;; 按 SRFI 128 的文本编写，每个导出名至少一项。
(import (rnrs) (only (ironscheme) include) (ironscheme std comparators))
(include "tests/std/check.ss")

(define (exact-integer? x) (and (integer? x) (exact? x)))
(define default (make-default-comparator))
(define int-cmp (make-comparator exact-integer? = < number-hash))

;;; ———————————————— 构造与谓词 ————————————————
(check (comparator? default) => #t)
(check (comparator? 'x) => #f)
(check (comparator-ordered? int-cmp) => #t)
(check (comparator-hashable? int-cmp) => #t)
(check (comparator-ordered? (make-comparator number? = #f #f)) => #f)
(check (comparator-hashable? (make-comparator number? = #f #f)) => #f)
(check ((comparator-type-test-predicate int-cmp) 3) => #t)
(check ((comparator-type-test-predicate int-cmp) 3.5) => #f)
(check ((comparator-equality-predicate int-cmp) 2 2) => #t)
(check ((comparator-ordering-predicate int-cmp) 1 2) => #t)
(check (procedure? (comparator-hash-function int-cmp)) => #t)
(check (comparator-test-type int-cmp 3) => #t)
(check (comparator-check-type int-cmp 3) => #t)
(check-raises (lambda (e) #t) (comparator-check-type int-cmp 'x))
(check (= (comparator-hash int-cmp 5) (comparator-hash int-cmp 5)) => #t)

;;; ———————————————— 标准比较器 ————————————————
(define pair-cmp (make-pair-comparator int-cmp int-cmp))
(check (<? pair-cmp '(1 . 2) '(1 . 3)) => #t)
(check (=? pair-cmp '(1 . 2) '(1 . 2)) => #t)
(define list-cmp (make-list-comparator int-cmp list? null? car cdr))
(check (<? list-cmp '(1 2) '(1 2 3)) => #t)
(check (<? list-cmp '(1 3) '(1 2 3)) => #f)
(define vec-cmp (make-vector-comparator int-cmp vector? vector-length vector-ref))
(check (<? vec-cmp '#(1 2) '#(0 0 0)) => #t)                 ; 先比长度
(check (=? vec-cmp '#(1 2) '#(1 2)) => #t)
(check (=? (make-eq-comparator) 'a 'a) => #t)
(check (=? (make-eqv-comparator) 1.5 1.5) => #t)
(check (=? (make-equal-comparator) '(1 "a") (list 1 "a")) => #t)

;;; ———————————————— 默认比较器 ————————————————
(check (<? default 1 2) => #t)
(check (<? default "a" "b") => #t)
(check (<? default '() '(1)) => #t)                         ; 空表排在序对之前
(check (=? default '(1 #(2 "x")) (list 1 (vector 2 "x"))) => #t)
(check (exact-integer? (default-hash '(1 2 "abc"))) => #t)
(define-record-type point (fields x y))
(define point-cmp (make-comparator point?
                                   (lambda (a b) (and (= (point-x a) (point-x b)) (= (point-y a) (point-y b))))
                                   (lambda (a b) (< (point-x a) (point-x b)))
                                   (lambda (p) (+ (point-x p) (point-y p)))))
(comparator-register-default! point-cmp)
(check (=? default (make-point 1 2) (make-point 1 2)) => #t)

;;; ———————————————— 散列过程 ————————————————
(check (exact-integer? (boolean-hash #t)) => #t)
(check (= (char-hash #\a) (char-hash #\a)) => #t)
(check (= (char-ci-hash #\a) (char-ci-hash #\A)) => #t)
(check (= (number-hash 1.5) (number-hash 1.5)) => #t)
(check (< (number-hash 12345) (hash-bound)) => #t)
(check (exact-integer? (hash-salt)) => #t)
(check (> (hash-bound) 0) => #t)

;;; ———————————————— 比较谓词 ————————————————
(check (=? default 1 1 1) => #t)
(check (<? default 1 2 3) => #t)
(check (<? default 1 3 2) => #f)
(check (>? default 3 2 1) => #t)
(check (<=? default 1 1 2) => #t)
(check (>=? default 2 2 1) => #t)
(check (comparator-if<=> 1 2 'lt 'eq 'gt) => 'lt)
(check (comparator-if<=> int-cmp 2 2 'lt 'eq 'gt) => 'eq)
(check (comparator-if<=> int-cmp 3 2 'lt 'eq 'gt) => 'gt)

(check-report "std comparators")
