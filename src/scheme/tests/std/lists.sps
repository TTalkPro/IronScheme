;;; (ironscheme std lists) 的测试（designs/08-std-library.md D8）。改写自 chez-srfi 的 tests/lists.sps
;;; （SRFI 1 测试集，lth 2003，Larceny；R6RS 版 Derick Eddington，MIT 许可）：每项 (or 表达式 (fail '记号))
;;; 改为 (expect '记号 表达式)。用到本库不导出的同名 SRFI 版本（D2）的项，改为检验文件头对照表给出的写法，
;;; 原表达式保留在注释中。
;;;
;;; Note (原注释): In Larceny, we require that the procedures designated as "linear update" variants in
;;; the spec (eg append!) side-effect their arguments, and there are tests here that check that
;;; side-effecting occurs.  For linear update we only require that the cells of the result are taken
;;; from the cells of the input.
(import (ironscheme) (ironscheme std lists))
(include "tests/std/check.ss")

;; 表达式为真即通过；失败时显示记号
(define-syntax expect
  (syntax-rules ()
    ((_ token expr) (check (if expr #t token) => #t))))

;; Test cases are ordered as in the spec.  R5RS procedures are left out.

(expect 'xcons:1
    (equal? (xcons 1 2) '(2 . 1)))

(expect 'cons*:1
    (equal? (cons* 1) 1))
(expect 'cons*:2
    (equal? (cons* 1 2 3 4 5) '(1 2 3 4 . 5)))

(expect 'make-list:1
    (equal? (make-list 5 #t) '(#t #t #t #t #t)))
(expect 'make-list:2
    (equal? (make-list 0 #f) '()))
(expect 'make-list:3
    (equal? (length (make-list 3)) 3))

(expect 'list-tabulate:1
    (equal? (list-tabulate 5 (lambda (x) x)) '(0 1 2 3 4)))
(expect 'list-tabluate:2
    (equal? (list-tabulate 0 (lambda (x) (error "FOO!"))) '()))

(expect 'list-copy:1
    (call-with-current-continuation
     (lambda (abort)
       (let* ((c  (list 1 2 3 4 5))
              (cp (list-copy c)))
         (or (equal? c cp)
             (abort #f))
         (let loop ((c c) (cp cp))
           (if (not (null? c))
               (begin
                 (or (not (eq? c cp))
                     (abort #f))
                 (loop (cdr c) (cdr cp)))))
         #t))))

(expect 'list-copy:2
    (equal? (list-copy '(1 2 3 . 4)) '(1 2 3 . 4)))

(expect 'circular-list:1
    (not (list? (circular-list 1 2 3))))
(expect 'circular-list:2
    (let* ((a (list 'a))
           (b (list 'b))
           (c (list 'c))
           (x (circular-list a b c)))
      (and (eq? a (car x))
           (eq? b (cadr x))
           (eq? c (caddr x))
           (eq? a (cadddr x)))))

(expect 'iota:1
    (equal? (iota 0) '()))
(expect 'iota:2
    (equal? (iota 5 2 3) '(2 5 8 11 14)))
(expect 'iota:3
    (equal? (iota 5 2) '(2 3 4 5 6)))

(expect 'proper-list?:1
    (proper-list? '(1 2 3 4 5)))
(expect 'proper-list?:2
    (proper-list? '()))
(expect 'proper-list?:3
    (not (proper-list? '(1 2 . 3))))
(expect 'proper-list:4
    (not (proper-list? (circular-list 1 2 3))))

(expect 'circular-list?:1
    (not (circular-list? '(1 2 3 4 5))))
(expect 'circular-list?:2
    (not (circular-list? '())))
(expect 'circular-list?:3
    (not (circular-list? '(1 2 . 3))))
(expect 'circular-list:4
    (circular-list? (circular-list 1 2 3)))

(expect 'dotted-list?:1
    (not (dotted-list? '(1 2 3 4 5))))
(expect 'dotted-list?:2
    (not (dotted-list? '())))
(expect 'dotted-list?:3
    (dotted-list? '(1 2 . 3)))
(expect 'dotted-list:4
    (not (dotted-list? (circular-list 1 2 3))))

(expect 'null-list?:1
    (null-list? '()))
(expect 'null-list?:2
    (not (null-list? '(1 2))))
(expect 'null-list?:3
    (not (null-list? (circular-list 1 2))))

(expect 'not-pair:1
    (not-pair? 1))
(expect 'not-pair:2
    (not (not-pair? (cons 1 2))))

(expect 'list=:1
    (list= = '(1 2 3) '(1 2 3) '(1 2 3)))
(expect 'list=:2
    (not (list= = '(1 2 3) '(1 2 3) '(1 4 3))))
;; Checks that l0 is not being used when testing l2, cf spec
(expect 'list=:3
    (list= (lambda (a b) (not (eq? a b))) '(#f #f #f) '(#t #t #t) '(#f #f #f)))
(expect 'list=:4
    (list= =))

(expect 'first
    (= (first '(1 2 3 4 5 6 7 8 9 10)) 1))
(expect 'second
    (= (second '(1 2 3 4 5 6 7 8 9 10)) 2))
(expect 'third
    (= (third '(1 2 3 4 5 6 7 8 9 10)) 3))
(expect 'fourth
    (= (fourth '(1 2 3 4 5 6 7 8 9 10)) 4))
(expect 'fifth
    (= (fifth '(1 2 3 4 5 6 7 8 9 10)) 5))
(expect 'sixth
    (= (sixth '(1 2 3 4 5 6 7 8 9 10)) 6))
(expect 'seventh
    (= (seventh '(1 2 3 4 5 6 7 8 9 10)) 7))
(expect 'eighth
    (= (eighth '(1 2 3 4 5 6 7 8 9 10)) 8))
(expect 'ninth
    (= (ninth '(1 2 3 4 5 6 7 8 9 10)) 9))
(expect 'tenth
    (= (tenth '(1 2 3 4 5 6 7 8 9 10)) 10))

(expect 'car+cdr:1
    (let-values (((a b) (car+cdr '(1 . 2))))
      (and (= a 1) (= b 2))))

(expect 'take:1
    (equal? '(1 2 3) (take '(1 2 3 4 5 6) 3)))
(expect 'take:2
    (equal? '(1) (take '(1) 1)))

(expect 'drop:1
    (let ((x (list 1 2 3 4 5 6)))
      (eq? (cdddr x) (drop x 3))))
(expect 'drop:2
    (let ((x (list 1 2 3)))
      (eq? x (drop x 0))))

(expect 'take-right:1
    (equal? '(4 5 6) (take-right '(1 2 3 4 5 6) 3)))
(expect 'take-right:2
    (null? (take-right '(1 2 3 4 5 6) 0)))
(expect 'take-right:3
    (equal? '(2 3 . 4) (take-right '(1 2 3 . 4) 2)))
(expect 'take-right:4
    (equal? 4 (take-right '(1 2 3 . 4) 0)))

(expect 'drop-right:1
    (equal? '(1 2 3) (drop-right '(1 2 3 4 5 6) 3)))
(expect 'drop-right:2
    (equal? '(1 2 3) (drop-right '(1 2 3) 0)))
(expect 'drop-right:3
    (equal? '(1 2 3) (drop-right '(1 2 3 . 4) 0)))

(expect 'take!:1
    (let ((x (list 1 2 3 4 5 6)))
      (let ((y (take! x 3)))
        (and (eq? x y)
             (eq? (cdr x) (cdr y))
             (eq? (cddr x) (cddr y))
             (equal? y '(1 2 3))))))

(expect 'drop-right!:1
    (let ((x (list 1 2 3 4 5 6)))
      (let ((y (drop-right! x 3)))
        (and (eq? x y)
             (eq? (cdr x) (cdr y))
             (eq? (cddr x) (cddr y))
             (equal? y '(1 2 3))))))

(expect 'split-at:1
    (let-values (((a b) (split-at '(1 2 3 4 5 6) 2)))
      (and (equal? a '(1 2))
           (equal? b '(3 4 5 6)))))

(expect 'split-at!:1
    (let* ((x (list 1 2 3 4 5 6))
           (y (cddr x)))
      (let-values (((a b) (split-at! x 2)))
        (and (equal? a '(1 2))
             (eq? a x)
             (equal? b '(3 4 5 6))
             (eq? b y)))))

(expect 'last:1
    (eqv? 37 (last '(1 2 3 37))))

(expect 'length+:1
    (not (length+ (circular-list 1 2 3))))
(expect 'length+:2
    (equal? 4 (length+ '(1 2 3 4))))

(expect 'append!:1
    (let ((x (list 1 2))
          (y (list 3 4))
          (z (list 5 6)))
      (let ((r (append! x y '() z)))
        (and (equal? r '(1 2 3 4 5 6))
             (eq? r x)
             (eq? (cdr r) (cdr x))
             (eq? (cddr r) y)
             (eq? (cdddr r) (cdr y))
             (eq? (cddddr r) z)
             (eq? (cdr (cddddr r)) (cdr z))))))

(expect 'concatenate:1
    (equal? (concatenate '((1 2 3) (4 5 6) () (7 8 9))) '(1 2 3 4 5 6 7 8 9)))

(expect 'concatenate!:1
    (equal? (concatenate! `(,(list 1 2 3) ,(list 4 5 6) () ,(list 7 8 9)))
            '(1 2 3 4 5 6 7 8 9)))

(expect 'append-reverse:1
    (equal? (append-reverse '(3 2 1) '(4 5 6)) '(1 2 3 4 5 6)))

(expect 'append-reverse!:1
    (equal? (append-reverse! (list 3 2 1) (list 4 5 6)) '(1 2 3 4 5 6)))

(expect 'zip:1
    (equal? (zip '(1 2 3) '(4 5 6)) '((1 4) (2 5) (3 6))))
(expect 'zip:2
    (equal? (zip '() '() '() '()) '()))
(expect 'zip:3
    (equal? (zip '(1) (circular-list 1 2)) '((1 1))))

(expect 'unzip1:1
    (equal? '(1 2 3 4 5) (unzip1 '((1) (2) (3) (4) (5)))))

(expect 'unzip2:1
    (let-values (((a b) (unzip2 '((10 11) (20 21) (30 31)))))
      (and (equal? a '(10 20 30))
           (equal? b '(11 21 31)))))

(expect 'unzip3:1
    (let-values (((a b c) (unzip3 '((10 11 12) (20 21 22) (30 31 32)))))
      (and (equal? a '(10 20 30))
           (equal? b '(11 21 31))
           (equal? c '(12 22 32)))))

(expect 'unzip4:1
    (let-values (((a b c d) (unzip4 '((10 11 12 13)
                                      (20 21 22 23)
                                      (30 31 32 33)))))
      (and (equal? a '(10 20 30))
           (equal? b '(11 21 31))
           (equal? c '(12 22 32))
           (equal? d '(13 23 33)))))

(expect 'unzip5:1
    (let-values (((a b c d e) (unzip5 '((10 11 12 13 14)
                                        (20 21 22 23 24)
                                        (30 31 32 33 34)))))
      (and (equal? a '(10 20 30))
           (equal? b '(11 21 31))
           (equal? c '(12 22 32))
           (equal? d '(13 23 33))
           (equal? e '(14 24 34)))))

(expect 'count:1
    (equal? 3 (count even? '(3 1 4 1 5 9 2 5 6))))
(expect 'count:2
    (equal? 3 (count < '(1 2 4 8) '(2 4 6 8 10 12 14 16))))
(expect 'count:3
    (equal? 2 (count < '(3 1 4 1) (circular-list 1 10))))

(expect 'fold:1
    (equal? '(c 3 b 2 a 1) (fold cons* '() '(a b c) '(1 2 3 4 5))))

(expect 'fold:2
    (equal? '(c 3 z b 2 y a 1 x) (fold cons* '() '(a b c) '(1 2 3 4 5) '(x y z))))

(expect 'fold-right:0
    (equal? '(a b c) (fold-right cons* '() '(a b c))))

(expect 'fold-right:1
    (equal? '(a 1 b 2 c 3) (fold-right cons* '() '(a b c) '(1 2 3 4 5))))

(expect 'fold-right:2
    (equal? '(a 1 x b 2 y c 3 z) (fold-right cons* '() '(a b c) '(1 2 3) '(x y z))))

(expect 'fold-right:3
    (equal? '(a 1 x 7 b 2 y 8 c 3 z 9) (fold-right cons* '() '(a b c) '(1 2 3) '(x y z) '(7 8 9))))

(expect 'pair-fold:1
    (let* ((x (list 1 2 3))
           (r (list x (cdr x) (cddr x)))
           (y (pair-fold (lambda (pair tail)
                           (set-cdr! pair tail) pair)
                         '()
                         x)))
      (and (equal? y '(3 2 1))
           (every (lambda (c) (memq c r)) (list y (cdr y) (cddr y))))))

(expect 'pair-fold-right:1
    (equal? '((a b c) (b c) (c)) (pair-fold-right cons '() '(a b c))))

(expect 'reduce:1
    (equal? 5 (reduce max 'illegal '(1 2 3 4 5))))
(expect 'reduce:2
    (equal? 0 (reduce max 0 '())))

(expect 'reduce-right:1
    (equal? '(1 2 3 4 5) (reduce-right append 'illegal '((1 2) () (3 4 5)))))

(expect 'unfold:1
    (equal? '(1 4 9 16 25 36 49 64 81 100)
            (unfold (lambda (x) (> x 10))
                    (lambda (x) (* x x))
                    (lambda (x) (+ x 1))
                    1)))

(expect 'unfold-right:1
    (equal? '(1 4 9 16 25 36 49 64 81 100)
            (unfold-right zero?
                          (lambda (x) (* x x))
                          (lambda (x) (- x 1))
                          10)))

;; D2：本库不导出 SRFI 1 版本，改用对照表的写法。原项：
;; (expect 'map:1
;;     (equal? '(4 1 5 1)
;;             (map + '(3 1 4 1) (circular-list 1 0))))
(expect 'map:1
    (equal? '(4 1 5 1) (map + '(3 1 4 1) (take (circular-list 1 0) 4))))

;; D2：本库不导出 SRFI 1 版本，改用对照表的写法。原项：
;; (expect 'for-each:1
;;     (equal? '(5 4 3 2 1)
;;             (let ((v 1)
;;                   (l '()))
;;               (for-each (lambda (x y)
;;                           (let ((n v))
;;                             (set! v (+ v 1))
;;                             (set! l (cons n l))))
;;                         '(0 0 0 0 0)
;;                         (circular-list 1 2))
;;               l)))
(expect 'for-each:1
    (equal? '(5 4 3 2 1)
            (let ((v 1)
                  (l '()))
              (for-each (lambda (x y)
                          (let ((n v))
                            (set! v (+ v 1))
                            (set! l (cons n l))))
                        '(0 0 0 0 0)
                        (take (circular-list 1 2) 5))
              l)))

(expect 'append-map:1
    (equal? '(1 -1 3 -3 8 -8)
            (append-map (lambda (x) (list x (- x))) '(1 3 8))))

(expect 'append-map!:1
    (equal? '(1 -1 3 -3 8 -8)
            (append-map! (lambda (x) (list x (- x))) '(1 3 8))))

(expect 'map!:1
    (let* ((l (list 1 2 3))
           (m (map! (lambda (x) (* x x)) l)))
      (and (equal? m '(1 4 9))
           (equal? l '(1 4 9)))))

(expect 'map-in-order:1
    (equal? '(1 2 3 4 5)
            (let ((v 1))
              (map-in-order (lambda (x)
                              (let ((n v))
                                (set! v (+ v 1))
                                n))
                            '(0 0 0 0 0)))))

(expect 'pair-for-each:1
    (equal? '((3) (2 3) (1 2 3))
            (let ((xs (list 1 2 3))
                  (l '()))
              (pair-for-each (lambda (x) (set! l (cons x l))) xs)
              l)))

(expect 'filter-map:1
    (equal? '(1 9 49)
            (filter-map (lambda (x y) (and (number? x) (* x x)))
                        '(a 1 b 3 c 7)
                        (circular-list 1 2))))

(expect 'filter:1
    (equal? '(0 8 8 -4) (filter even? '(0 7 8 8 43 -4))))

(expect 'partition:1
    (let-values (((a b) (partition symbol? '(one 2 3 four five 6))))
      (and (equal? a '(one four five))
           (equal? b '(2 3 6)))))

;; D2：本库不导出 SRFI 1 版本，改用对照表的写法。原项：
;; (expect 'remove:1
;;     (equal? '(7 43) (remove even? '(0 7 8 8 43 -4))))
(expect 'remove:1
    (equal? '(7 43) (remp even? '(0 7 8 8 43 -4))))
;; 对照表中的陷阱：基础库的 remove 按 equal? 删除对象，传入谓词时原样返回
(expect 'remove:base-pitfall
    (equal? '(0 7 8 8 43 -4) (remove even? '(0 7 8 8 43 -4))))

(expect 'filter!:1
    (let* ((x (list 0 7 8 8 43 -4))
           (y (pair-fold cons '() x))
           (r (filter! even? x)))
      (and (equal? '(0 8 8 -4) r)
           (every (lambda (c) (memq c y)) (pair-fold cons '() r)))))

(expect 'partition!:1
    (let* ((x (list 'one 2 3 'four 'five 6))
           (y (pair-fold cons '() x)))
      (let-values (((a b) (partition! symbol? x)))
        (and (equal? a '(one four five))
             (equal? b '(2 3 6))
             (every (lambda (c) (memq c y)) (pair-fold cons '() a))
             (every (lambda (c) (memq c y)) (pair-fold cons '() b))))))

(expect 'remove!:1
    (let* ((x (list 0 7 8 8 43 -4))
           (y (pair-fold cons '() x))
           (r (remove! even? x)))
      (and (equal? '(7 43) r)
           (every (lambda (c) (memq c y)) (pair-fold cons '() r)))))

(expect 'find:1
    (equal? 4 (find even? '(3 1 4 1 5 9 8))))

(expect 'find-tail:1
    (equal? '(4 1 5 9 8) (find-tail even? '(3 1 4 1 5 9 8))))
(expect 'find-tail:2
    (equal? '#f (find-tail even? '(1 3 5 7))))

(expect 'take-while:1
    (equal? '(2 18) (take-while even? '(2 18 3 10 22 9))))

(expect 'take-while!:1
    (let* ((x (list 2 18 3 10 22 9))
           (r (take-while! even? x)))
      (and (equal? r '(2 18))
           (eq? r x)
           (eq? (cdr r) (cdr x)))))

(expect 'drop-while:1
    (equal? '(3 10 22 9) (drop-while even? '(2 18 3 10 22 9))))

(expect 'span:1
    (let-values (((a b) (span even? '(2 18 3 10 22 9))))
      (and (equal? a '(2 18))
           (equal? b '(3 10 22 9)))))

(expect 'break:1
    (let-values (((a b) (break even? '(3 1 4 1 5 9))))
      (and (equal? a '(3 1))
           (equal? b '(4 1 5 9)))))

(expect 'span!:1
    (let* ((x     (list 2 18 3 10 22 9))
           (cells (pair-fold cons '() x)))
      (let-values (((a b) (span! even? x)))
        (and (equal? a '(2 18))
             (equal? b '(3 10 22 9))
             (every (lambda (x) (memq x cells)) (pair-fold cons '() a))
             (every (lambda (x) (memq x cells)) (pair-fold cons '() b))))))

(expect 'break!:1
    (let* ((x     (list 3 1 4 1 5 9))
           (cells (pair-fold cons '() x)))
      (let-values (((a b) (break! even? x)))
        (and (equal? a '(3 1))
             (equal? b '(4 1 5 9))
             (every (lambda (x) (memq x cells)) (pair-fold cons '() a))
             (every (lambda (x) (memq x cells)) (pair-fold cons '() b))))))

(expect 'any:1
    (any integer? '(a 3 b 2.7)))
(expect 'any:2
    (not (any integer? '(a 3.1 b 2.7))))
(expect 'any:3
    (any < '(3 1 4 1 5) (circular-list 2 7 1 8 2)))
(expect 'any:4
    (equal? 'yes (any (lambda (a b) (if (< a b) 'yes #f))
                      '(1 2 3) '(0 1 4))))

(expect 'every:1
    (every integer? '(1 2 3)))
(expect 'every:2
    (not (every integer? '(3 4 5.1))))
(expect 'every:3
    (every < '(1 2 3) (circular-list 2 3 4)))

(expect 'list-index:1
    (equal? 2 (list-index even? '(3 1 4 1 5 9))))
(expect 'list-index:2
    (equal? 1 (list-index < '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))
(expect 'list-index:3
    (not (list-index = '(3 1 4 1 5 9 2 5 6) '(2 7 1 8 2))))

;; D2：本库不导出 SRFI 1 版本，改用对照表的写法。原项：
;; (expect 'member:1
;;     (equal? '(37 48) (member 5 '(1 2 5 37 48) <)))
(expect 'member:1
    (equal? '(37 48) (memp (lambda (y) (< 5 y)) '(1 2 5 37 48))))

(expect 'delete:1
    (equal? '(1 2 5) (delete 5 '(1 48 2 5 37) <)))
(expect 'delete:2
    (equal? '(1 2 7) (delete 5 '(1 5 2 5 7))))

(expect 'delete!:1
    (let* ((x     (list 1 48 2 5 37))
           (cells (pair-fold cons '() x))
           (r     (delete! 5 x <)))
      (and (equal? r '(1 2 5))
           (every (lambda (x) (memq x cells)) (pair-fold cons '() r)))))

(expect 'delete-duplicates:1
    (equal? '((a . 3) (b . 7) (c . 1))
            (delete-duplicates '((a . 3) (b . 7) (a . 9) (c . 1))
                               (lambda (x y) (eq? (car x) (car y))))))
(expect 'delete-duplicates:2
    (equal? '(a b c z) (delete-duplicates '(a b a c a b c z) eq?)))

(expect 'delete-duplicates!:1
    (let* ((x     (list 'a 'b 'a 'c 'a 'b 'c 'z))
           (cells (pair-fold cons '() x))
           (r     (delete-duplicates! x)))
      (and (equal? '(a b c z) r)
           (every (lambda (x) (memq x cells)) (pair-fold cons '() r)))))

;; D2：本库不导出 SRFI 1 版本，改用对照表的写法。原项：
;; (expect 'assoc:1
;;     (equal? '(3 . #t) (assoc 6
;;                              '((4 . #t) (3 . #t) (5 . #t))
;;                              (lambda (x y)
;;                                (zero? (remainder x y))))))
(expect 'assoc:1
    (equal? '(3 . #t) (assp (lambda (y) (zero? (remainder 6 y)))
                            '((4 . #t) (3 . #t) (5 . #t)))))

(expect 'alist-cons:1
    (equal? '((1 . #t) (2 . #f)) (alist-cons 1 #t '((2 . #f)))))

(expect 'alist-copy:1
    (let* ((a (list (cons 1 2) (cons 3 4)))
           (b (alist-copy a)))
      (and (equal? a b)
           (every (lambda (x) (not (memq x b))) a)
           (every (lambda (x) (not (memq x a))) b))))

(expect 'alist-delete:1
    (equal? '((1 . #t) (2 . #t) (4 . #t))
            (alist-delete 5 '((1 . #t) (2 . #t) (37 . #t) (4 . #t) (48 #t)) <)))
(expect 'alist-delete:2
    (equal? '((1 . #t) (2 . #t) (4 . #t))
            (alist-delete 7 '((1 . #t) (2 . #t) (7 . #t) (4 . #t) (7 #t)))))

(expect 'alist-delete!:1
    (let* ((x (list-copy '((1 . #t) (2 . #t) (7 . #t) (4 . #t) (7 #t))))
           (y (list-copy x))
           (cells (pair-fold cons '() x))
           (r (alist-delete! 7 x)))
      (and (equal? r '((1 . #t) (2 . #t) (4 . #t)))
           (every (lambda (x) (memq x cells)) (pair-fold cons '() r))
           (every (lambda (x) (memq x y)) r))))

(expect 'lset<=:1
    (lset<= eq? '(a) '(a b a) '(a b c c)))
(expect 'lset<=:2
    (not (lset<= eq? '(a) '(a b a) '(a))))
(expect 'lset<=:3
    (lset<= eq?))
(expect 'lset<=:4
    (lset<= eq? '(a)))

(expect 'lset=:1
    (lset= eq? '(b e a) '(a e b) '(e e b a)))
(expect 'lset=:2
    (not (lset= eq? '(b e a) '(a e b) '(e e b a c))))
(expect 'lset=:3
    (lset= eq?))
(expect 'lset=:4
    (lset= eq? '(a)))

(expect 'lset-adjoin:1
    (equal? '(u o i a b c d c e)
            (lset-adjoin eq? '(a b c d c e) 'a 'e 'i 'o 'u)))

(expect 'lset-union:1
    (equal? '(u o i a b c d e)
            (lset-union eq? '(a b c d e) '(a e i o u))))
(expect 'lset-union:2
    (equal? '(x a a c) (lset-union eq? '(a a c) '(x a x))))
(expect 'lset-union:3
    (null? (lset-union eq?)))
(expect 'lset-union:4
    (equal? '(a b c) (lset-union eq? '(a b c))))

(expect 'lset-intersection:1
    (equal? '(a e) (lset-intersection eq? '(a b c d e) '(a e i o u))))
(expect 'lset-intersection:2
    (equal? '(a x a) (lset-intersection eq? '(a x y a) '(x a x z))))
(expect 'lset-intersection:3
    (equal? '(a b c) (lset-intersection eq? '(a b c))))

(expect 'lset-difference:1
    (equal? '(b c d) (lset-difference eq? '(a b c d e) '(a e i o u))))
(expect 'lset-difference:2
    (equal? '(a b c) (lset-difference eq? '(a b c))))

(expect 'lset-xor:1
    (lset= eq? '(d c b i o u) (lset-xor eq? '(a b c d e) '(a e i o u))))
(expect 'lset-xor:2
    (lset= eq? '() (lset-xor eq?)))
(expect 'lset-xor:3
    (lset= eq? '(a b c d e) (lset-xor eq? '(a b c d e))))

(expect 'lset-diff+intersection:1
    (let-values (((d i) (lset-diff+intersection eq? '(a b c d e) '(c d f))))
      (and (equal? d '(a b e))
           (equal? i '(c d)))))

                                        ; FIXME: For the following five procedures, need to check that cells
                                        ; returned are from the arguments.

(expect 'lset-union!:1
    (equal? '(u o i a b c d e)
            (lset-union! eq? (list 'a 'b 'c 'd 'e) (list 'a 'e 'i 'o 'u))))
(expect 'lset-union!:2
    (equal? '(x a a c) (lset-union! eq? (list 'a 'a 'c) (list 'x 'a 'x))))
(expect 'lset-union!:3
    (null? (lset-union! eq?)))
(expect 'lset-union!:4
    (equal? '(a b c) (lset-union! eq? (list 'a 'b 'c))))

(expect 'lset-intersection!:1
    (equal? '(a e) (lset-intersection! eq? (list 'a 'b 'c 'd 'e)
                                       (list 'a 'e 'i 'o 'u))))
(expect 'lset-intersection!:2
    (equal? '(a x a) (lset-intersection! eq? (list 'a 'x 'y 'a)
                                         (list 'x 'a 'x 'z))))
(expect 'lset-intersection!:3
    (equal? '(a b c) (lset-intersection! eq? (list 'a 'b 'c))))

(expect 'lset-difference!:1
    (equal? '(b c d) (lset-difference! eq? (list 'a 'b 'c 'd 'e)
                                       (list 'a 'e 'i 'o 'u))))
(expect 'lset-difference!:2
    (equal? '(a b c) (lset-difference! eq? (list 'a 'b 'c))))

(expect 'lset-xor!:1
    (lset= eq? '(d c b i o u) (lset-xor! eq? (list 'a 'b 'c 'd 'e)
                                         (list 'a 'e 'i 'o 'u))))
(expect 'lset-xor!:2
    (lset= eq? '() (lset-xor! eq?)))
(expect 'lset-xor!:3
    (lset= eq? '(a b c d e) (lset-xor! eq? (list 'a 'b 'c 'd 'e))))

(expect 'lset-diff+intersection!:1
    (let-values (((d i) (lset-diff+intersection! eq? (list 'a 'b 'c 'd 'e)
                                                 (list 'c 'd 'f))))
      (and (equal? d '(a b e))
           (equal? i '(c d)))))

;; 原测试没有覆盖 reverse!（线性更新：结果的序对取自输入）
(expect 'reverse!:1
    (equal? '(3 2 1) (reverse! (list 1 2 3))))
(expect 'reverse!:2
    (null? (reverse! '())))

(check-report "std lists")
