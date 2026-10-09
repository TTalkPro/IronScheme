;;; (ironscheme std sorting) 的测试（designs/08-std-library.md D8）。chez-srfi 没有可运行的 SRFI 132 测试
;;; （%3a132/sorting-test.scm 测的是参照实现的内部过程），按 SRFI 132 的文本编写：每个导出名至少一项，
;;; 另用随机数据与基础库的 list-sort 对照。
(import (rnrs) (only (ironscheme) include) (ironscheme random) (ironscheme std sorting))
(include "tests/std/check.ss")

(define rng (make-random 42))
(define (list-copy l) (map (lambda (x) x) l))
(define (random-list n) (let loop ((i 0) (l '())) (if (= i n) l (loop (+ i 1) (cons (next-fixnum rng 100) l)))))

;;; ———————————————— 有序判断 ————————————————
(check (list-sorted? < '(1 2 3)) => #t)
(check (list-sorted? < '(1 3 2)) => #f)
(check (list-sorted? < '()) => #t)
(check (vector-sorted? < '#(1 2 3)) => #t)
(check (vector-sorted? < '#(3 1 2 4) 1) => #t)               ; start
(check (vector-sorted? < '#(3 1 2 0) 1 3) => #t)             ; start end

;;; ———————————————— 稳定排序：按第一个分量排序，相同的保持原次序 ————————————————
(define pairs '((2 . a) (1 . b) (2 . c) (1 . d) (0 . e)))
(define (car<? x y) (< (car x) (car y)))
(check (list-stable-sort car<? pairs) => '((0 . e) (1 . b) (1 . d) (2 . a) (2 . c)))
(check (list-stable-sort! car<? (list-copy pairs)) => '((0 . e) (1 . b) (1 . d) (2 . a) (2 . c)))
(check (vector-stable-sort car<? (list->vector pairs)) => '#((0 . e) (1 . b) (1 . d) (2 . a) (2 . c)))
(check (let ((v (list->vector pairs))) (vector-stable-sort! car<? v) v)
       => '#((0 . e) (1 . b) (1 . d) (2 . a) (2 . c)))
(check (vector-stable-sort < '#(9 3 2 1 8) 1 4) => '#(1 2 3))           ; 只排 [1, 4)，返回新向量
(check (let ((v (vector 9 3 2 1 8))) (vector-stable-sort! < v 1 4) v) => '#(9 1 2 3 8))
(check (list-sort! < (list 3 1 2)) => '(1 2 3))

;;; ———————————————— 随机数据与基础库的 list-sort 对照 ————————————————
(do ((i 0 (+ i 1))) ((= i 20))
  (let* ((l (random-list (* i 7))) (expected (list-sort < l)))
    (check (list-stable-sort < l) => expected)
    (check (list-sort! < (list-copy l)) => expected)
    (check (vector->list (vector-stable-sort < (list->vector l))) => expected)
    (check (let ((v (list->vector l))) (vector-stable-sort! < v) (vector->list v)) => expected)))

;;; ———————————————— 归并 ————————————————
(check (list-merge < '(1 3 5) '(2 4 6)) => '(1 2 3 4 5 6))
(check (list-merge car<? '((1 . a) (2 . a)) '((1 . b))) => '((1 . a) (1 . b) (2 . a)))   ; 相同时左表在前
(check (list-merge! < (list 1 4) (list 2 3)) => '(1 2 3 4))
(check (vector-merge < '#(1 3 5) '#(2 4 6)) => '#(1 2 3 4 5 6))
(check (vector-merge < '#(0 1 3 9) '#(2 4) 1 3) => '#(1 2 3 4))         ; v1 的 [1, 3)
(check (let ((to (make-vector 5 0))) (vector-merge! < to '#(1 3) '#(2 4) 1) to) => '#(0 1 2 3 4))

;;; ———————————————— 删除相邻重复 ————————————————
(check (list-delete-neighbor-dups = '(1 1 2 3 3 3 1)) => '(1 2 3 1))
(check (list-delete-neighbor-dups! = (list 1 1 2 2)) => '(1 2))
(check (vector-delete-neighbor-dups = '#(1 1 2 3 3 3 1)) => '#(1 2 3 1))
(check (vector-delete-neighbor-dups = '#(1 1 2 3 3 3 1) 2) => '#(2 3 1))
(check (let* ((v (vector 1 1 2 2 3)) (end (vector-delete-neighbor-dups! = v)))
         (list end (vector-ref v 0) (vector-ref v 1) (vector-ref v 2)))
       => '(3 1 2 3))

;;; ———————————————— 中位数 ————————————————
(check (vector-find-median < '#() 'knil) => 'knil)
(check (vector-find-median < '#(78 61 19 38 51) 'knil) => 51)
(check (vector-find-median < '#(78 61 19 38 51 52) 'knil) => 103/2)    ; 偶数个时取中间两个的平均
(check (vector-find-median < '#(78 61 19 38 51 52) 'knil list) => '(51 52))
(check (let ((v (vector 78 61 19 38 51))) (vector-find-median! < v 'knil) (vector-sorted? < v)) => #t)

(check-report "std sorting")
