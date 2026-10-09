;;; pfds 测试所用 trc-testing 接口的模拟（designs/08-std-library.md D8），每个断言计入 tests/std/check.ss 的计数。
;;; 需先 (include "tests/std/check.ss")。另含 pfds 测试的 (pfds tests utils)：test test-not test-exn test-no-exn add1 foldl iota。
;;; 原 pfds 测试 Copyright (C) 2011-2014 Ian Price，new-style BSD 许可（lib/ironscheme/std/LICENSES/pfds.txt）。

(define-syntax define-test-suite
  (syntax-rules ()
    ((_ name doc) (begin))))

(define-syntax define-test-case
  (syntax-rules ()
    ((_ suite name () body ...) (let () body ... (values)))
    ((_ suite name body ...) (let () body ... (values)))))

(define-syntax test-case
  (syntax-rules ()
    ((_ name () body ...) (let () body ... (values)))))

(define-syntax test-eqv
  (syntax-rules ()
    ((_ expected actual)
     (check (let ((e expected) (a actual)) (if (eqv? e a) #t (list 'got a))) => #t))))

(define-syntax test-equal
  (syntax-rules ()
    ((_ expected actual) (check actual => expected))))

(define-syntax test-predicate
  (syntax-rules ()
    ((_ pred expr) (check (let ((v expr)) (if (pred v) #t (list 'failed v))) => #t))))

(define-syntax test-compare
  (syntax-rules ()
    ((_ cmp expected actual)
     (check (let ((e expected) (a actual)) (if (cmp e a) #t (list 'got a))) => #t))))

;; (pfds tests utils)
(define-syntax test
  (syntax-rules ()
    ((_ body) (test-eqv #t (and body #t)))))

(define-syntax test-not
  (syntax-rules ()
    ((_ body) (test-eqv #f body))))

(define-syntax test-exn
  (syntax-rules ()
    ((_ exception-pred? body)
     (test-eqv #t (guard (exn ((exception-pred? exn) #t) (else #f)) body #f)))))

(define-syntax test-no-exn
  (syntax-rules ()
    ((_ body)
     (test-eqv #t (guard (exn (else #f)) body #t)))))

(define (add1 x) (+ x 1))

(define (foldl kons knil list)
  (if (null? list)
      knil
      (foldl kons (kons (car list) knil) (cdr list))))

(define (iota n)
  (define (recur x)
    (if (< x n) (cons x (recur (+ x 1))) '()))
  (assert (integer? n))
  (recur 0))
