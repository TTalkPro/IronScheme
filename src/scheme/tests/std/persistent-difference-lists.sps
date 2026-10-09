;;; (ironscheme std persistent difference-lists) 的测试（designs/08-std-library.md D8）。
;;; pfds 没有 dlists 的测试，按 pfds 的说明（doc/dlists.scm，含其中 reverse 的例子）编写。
(import (rnrs) (only (ironscheme) include) (ironscheme std persistent difference-lists))
(include "tests/std/check.ss")

(check (dlist? (dlist)) => #t)
(check (dlist? '()) => #f)
(check (dlist->list (dlist)) => '())
(check (dlist->list (dlist 1 2 3)) => '(1 2 3))
(check (dlist->list (list->dlist '(a b))) => '(a b))
(check (dlist->list (dlist-cons 0 (dlist 1 2))) => '(0 1 2))
(check (dlist->list (dlist-snoc (dlist 1 2) 3)) => '(1 2 3))
(check (dlist->list (dlist-append (dlist 1) (dlist 2 3))) => '(1 2 3))
(check (dlist->list (dlist-append (dlist) (dlist 2))) => '(2))

;; doc/dlists.scm 的例子：以 dlist-append 写的 reverse 是线性的
(define (reverse* l)
  (if (null? l)
      (dlist)
      (dlist-append (reverse* (cdr l)) (dlist (car l)))))
(check (dlist->list (reverse* '(1 2 3 4))) => '(4 3 2 1))
(check (length (dlist->list (reverse* (let loop ((i 0) (acc '())) (if (= i 10000) acc (loop (+ i 1) (cons i acc))))))) => 10000)

(check-report "std persistent difference-lists")
