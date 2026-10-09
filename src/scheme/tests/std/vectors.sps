;;; (ironscheme std vectors) 的测试（designs/08-std-library.md D8）。改写自 chez-srfi 的 tests/vectors.sps
;;; （SRFI 43 测试集，Larceny；Will Clinger）：每项 (or 表达式 (fail '记号)) 改为 (expect '记号 表达式)。
;;; 原测试针对 SRFI 43；本库按 SRFI 133，语义不同的项按 SRFI 133 改写，原项保留在注释中；
;;; 用到本库不导出的基础库同名过程（D2）的项改用基础库或对照表的写法。
(import (ironscheme) (ironscheme std vectors))
(include "tests/std/check.ss")

(define-syntax expect
  (syntax-rules ()
    ((_ token expr) (check (if expr #t token) => #t))))

(expect 'make-vector:0
    (vector? (make-vector 0)))

(expect 'vector-length:basic
    (= 10 (vector-length (make-vector 10))))

(expect 'vector-ref:basic
    (= 97 (vector-ref (make-vector 500 97) 499)))

(expect 'vector:0
    (equal? (vector) '#()))

(expect 'vector
    (equal? (vector 'a 'b 97) '#(a b 97)))

(expect 'vector-unfold:1
    (equal? (vector-unfold (lambda (i x) (values x (- x 1)))
                           10 0)
            '#(0 -1 -2 -3 -4 -5 -6 -7 -8 -9)) ; but SRFI 43 says -8 -8 at end
    )

(expect 'vector-unfold:2
    (equal? (vector-unfold values 10) '#(0 1 2 3 4 5 6 7 8 9)))

(expect 'vector-unfold:3
    (let ((vector '#(a b 97)))
      (equal? (vector-unfold (lambda (i) (vector-ref vector i))
                             (vector-length vector))
              vector)))

(expect 'vector-unfold-right:1
    (equal? (vector-unfold-right (lambda (i x) (values x (+ x 1))) 8 0)
            '#(7 6 5 4 3 2 1 0)))

(expect 'vector-unfold-right:2
    (let ((vector '#(3 1 4 5 9)))
      (equal? (vector-unfold-right (lambda (i x)
                                     (values (vector-ref vector x) (+ x 1)))
                                   (vector-length vector)
                                   0)
              '#(9 5 4 1 3))))

(expect 'vector-copy:1
    (equal? (vector-copy '#(a b c d e f g h i))
            '#(a b c d e f g h i)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-copy:2
;;     (equal? (vector-copy '#(a b c d e f g h i) 6)
;;             '#(g h i)))
(expect 'vector-copy:2
    (equal? (let ((r (make-vector 3))) (vector-copy! r 0 '#(a b c d e f g h i) 6) r) '#(g h i)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-copy:3
;;     (equal? (vector-copy '#(a b c d e f g h i) 3 6)
;;             '#(d e f)))
(expect 'vector-copy:3
    (equal? (let ((r (make-vector 3))) (vector-copy! r 0 '#(a b c d e f g h i) 3 6) r) '#(d e f)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-copy:4
;;     (equal? (vector-copy '#(a b c d e f g h i) 6 12 'x)
;;             '#(g h i x x x)))
(expect 'vector-copy:4
    (equal? (let ((r (make-vector 6 'x))) (vector-copy! r 0 '#(a b c d e f g h i) 6) r) '#(g h i x x x)))

(expect 'vector-reverse-copy
    (equal? (vector-reverse-copy '#(5 4 3 2 1 0) 1 5)
            '#(1 2 3 4)))

(expect 'vector-append:1
    (equal? (vector-append '#(x) '#(y))
            '#(x y)))

(expect 'vector-append:2
    (equal? (vector-append '#(a) '#(b c d))
            '#(a b c d)))

(expect 'vector-append:3
    (equal? (vector-append '#(a #(b)) '#(#(c)))
            '#(a #(b) #(c))))

(expect 'vector-concatenate
    (equal? (vector-concatenate '(#(a b) #(c d)))
            '#(a b c d)))

(expect 'vector?
    (and (eq? (vector? '#(a b c)) #t)
         (eq? (vector? '(a b c)) #f)
         (eq? (vector? #t) #f)
         (eq? (vector? '#()) #t)
         (eq? (vector? '()) #f)))

(expect 'vector-empty?
    (and (eq? (vector-empty? '#(a)) #f)
         (eq? (vector-empty? '#(())) #f)
         (eq? (vector-empty? '#(#())) #f)
         (eq? (vector-empty? '#()) #t)))

(expect 'vector=
    (and (eq? (vector= eq? '#(a b c d) '#(a b c d)) #t)
         (eq? (vector= eq? '#(a b c d) '#(a b d c)) #f)
         (eq? (vector= = '#(1 2 3 4 5) '#(1 2 3 4)) #f)
         (eq? (vector= = '#(1 2 3 4) '#(1 2 3 4))   #t)
         (eq? (vector= eq?) #t)
         (eq? (vector= eq? '#(a)) #t)
         (eq? (vector= eq? (vector (vector 'a)) (vector (vector 'a))) #f)
         (eq? (vector= equal? (vector (vector 'a)) (vector (vector 'a))) #t)))

(expect 'vector-ref
    (eq? (vector-ref '#(a b c d) 2) 'c))

(expect 'vector-length
    (eqv? (vector-length '#(a b c)) 3))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-fold:1
;;     (equal? (vector-fold (lambda (index len str) (max (string-length str) len))
;;                          0 '#("a" "b" "" "dd" "e"))
;;             2))
(expect 'vector-fold:1
    (equal? (vector-fold (lambda (len str) (max (string-length str) len))
                         0 '#("a" "b" "" "dd" "e"))
            2))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-fold:2
;;     (equal? (vector-fold (lambda (index tail elt) (cons elt tail))
;;                          '() '#(0 1 2 3 4))
;;             '(4 3 2 1 0)))
(expect 'vector-fold:2
    (equal? (vector-fold (lambda (tail elt) (cons elt tail))
                         '() '#(0 1 2 3 4))
            '(4 3 2 1 0)))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-fold:3
;;     (equal? (vector-fold (lambda (index counter n)
;;                            (if (even? n) (+ counter 1) counter))
;;                          0 '#(0 1 2 3 4 4 4 5 6 7))
;;             6))
(expect 'vector-fold:3
    (equal? (vector-fold (lambda (counter n)
                           (if (even? n) (+ counter 1) counter))
                         0 '#(0 1 2 3 4 4 4 5 6 7))
            6))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-fold-right
;;     (equal? (vector-fold-right (lambda (index tail elt) (cons elt tail))
;;                                '() '#(a b c d))
;;             '(a b c d)))
(expect 'vector-fold-right
    (equal? (vector-fold-right (lambda (tail elt) (cons elt tail))
                               '() '#(a b c d))
            '(a b c d)))


;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-map:1
;;     (equal? (vector-map (lambda (i x) (* x x))
;;                         (vector-unfold (lambda (i x) (values x (+ x 1))) 4 1))
;;             '#(1 4 9 16)))
(expect 'vector-map:1
    (equal? (vector-map (lambda (x) (* x x))
                        (vector-unfold (lambda (i x) (values x (+ x 1))) 4 1))
            '#(1 4 9 16)))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-map:2
;;     (equal? (vector-map (lambda (i x y) (* x y))
;;                         (vector-unfold (lambda (i x) (values x (+ x 1))) 5 1)
;;                         (vector-unfold (lambda (i x) (values x (- x 1))) 5 5))
;;             '#(5 8 9 8 5)))
(expect 'vector-map:2
    (equal? (vector-map (lambda (x y) (* x y))
                        (vector-unfold (lambda (i x) (values x (+ x 1))) 5 1)
                        (vector-unfold (lambda (i x) (values x (- x 1))) 5 5))
            '#(5 8 9 8 5)))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-map:3
;;     (member (let ((count 0))
;;               (vector-map (lambda (ignored-index ignored-elt)
;;                             (set! count (+ count 1))
;;                             count)
;;                           '#(a b)))
;;             '(#(1 2) #(2 1))))
(expect 'vector-map:3
    (member (let ((count 0))
              (vector-map (lambda (ignored-elt)
                            (set! count (+ count 1))
                            count)
                          '#(a b)))
            '(#(1 2) #(2 1))))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-map!
;;     (equal? (let ((v (vector 1 2 3 4)))
;;               (vector-map! (lambda (i elt) (+ i elt)) v)
;;               v)
;;             '#(1 3 5 7)))
(expect 'vector-map!
    (equal? (let ((v (vector 1 2 3 4)))
              (vector-map! + v (vector 0 1 2 3))
              v)
            '#(1 3 5 7)))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-for-each
;;     (equal? (let ((p (open-output-string)))
;;               (vector-for-each (lambda (i x) (display x p) (newline p))
;;                                '#("foo" "bar" "baz" "quux" "zot"))
;;               (get-output-string p))
;;             "foo\nbar\nbaz\nquux\nzot\n"))
(expect 'vector-for-each
    (equal? (let ((p (open-output-string)))
              (vector-for-each (lambda (x)
                                 (display x p)
                                 (newline p))
                               '#("foo" "bar" "baz" "quux" "zot"))
              (get-output-string p))
            "foo\nbar\nbaz\nquux\nzot\n"))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-count:1
;;     (equal? (vector-count (lambda (i elt) (even? elt)) '#(3 1 4 1 5 9 2 5 6))
;;             3))
(expect 'vector-count:1
    (equal? (vector-count (lambda (elt) (even? elt))
                          '#(3 1 4 1 5 9 2 5 6))
            3))

;; SRFI 133：过程不再收下标参数（SRFI 43 的 kons / f 第一个参数是下标）。原项：
;; (expect 'vector-count:2
;;     (equal? (vector-count (lambda (i x y) (< x y))
;;                           '#(1 3 6 9)
;;                           '#(2 4 6 8 10 12))
;;             2))
(expect 'vector-count:2
    (equal? (vector-count (lambda (x y) (< x y))
                          '#(1 3 6 9) '#(2 4 6 8 10 12))
            2))

(expect 'vector-index:1
    (equal? (vector-index even? '#(3 1 4 1 5 9))
            2))

(expect 'vector-index:2
    (equal? (vector-index < '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))
            1))

(expect 'vector-index:3
    (equal? (vector-index = '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))
            #f))

(expect 'vector-index-right:1
    (equal? (vector-index-right even? '#(3 1 4 1 5 9))
            2))

(expect 'vector-index-right:2
    (equal? (vector-index-right < '#(3 1 4 1 5) '#(2 7 1 8 2))
            3))

(expect 'vector-index-right:3
    (equal? (vector-index-right = '#(3 1 4 1 5) '#(2 7 1 8 2))
            #f))

(expect 'vector-skip:1
    (equal? (vector-skip even? '#(3 1 4 1 5 9))
            0))

(expect 'vector-skip:2
    (equal? (vector-skip < '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))
            0))

(expect 'vector-skip:3
    (equal? (vector-skip = '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))
            0))

(expect 'vector-skip:4
    (equal? (vector-skip > '#(3 1 4 1 5 9 2 5 6) '#(2 7 1 8 2))
            1))

(expect 'vector-skip-right:1
    (equal? (vector-skip-right even? '#(3 1 4 1 5 9))
            5))

(expect 'vector-skip-right:2
    (equal? (vector-skip-right < '#(3 1 4 1 5) '#(2 7 1 8 2))
            4))

(expect 'vector-skip-right:3
    (equal? (vector-skip-right = '#(3 1 4 1 5) '#(2 7 1 8 2))
            4))

(expect 'vector-skip-right:4
    (equal? (vector-skip-right > '#(3 1 4 1 5) '#(2 7 1 8 2))
            3))

(define (string-comparator s1 s2)
  (cond ((< (string-length s1) (string-length s2))
         -1)
        ((> (string-length s1) (string-length s2))
         +1)
        ((string<? s1 s2)
         -1)
        ((string>? s1 s2)
         +1)
        (else
         0)))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:0
    (equal? (vector-binary-search '#()
                                  "bad"
                                  string-comparator)
            #f))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:1
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  "bad"
                                  string-comparator)
            #f))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:2
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  ""
                                  string-comparator)
            #f))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:3
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  "hello"
                                  string-comparator)
            #f))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:4
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  "ab"
                                  string-comparator)
            0))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:5
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  "aaaa"
                                  string-comparator)
            5))

;; iron-054 起基础库的 vector-binary-search 即 SRFI 133 的接口，恢复原项。
(expect 'vector-binary-search:6
    (equal? (vector-binary-search '#("ab" "cd" "ef" "bcd" "cde" "aaaa")
                                  "bcd"
                                  string-comparator)
            3))

(expect 'vector-any:0
    (equal? (vector-any list '#() '#(a b c))
            #f))

(expect 'vector-any:1
    (equal? (vector-any list '#(a b c) '#())
            #f))

(expect 'vector-any:2
    (equal? (vector-any list '#(a b c) '#(d))
            '(a d)))

(expect 'vector-any:3
    (equal? (vector-any memq '#(a b c) '#(() (c d e) (b c 97)))
            '(c 97)))

(expect 'vector-every:0
    (equal? (vector-every list '#() '#(a b c))
            #t))

(expect 'vector-every:1
    (equal? (vector-every list '#(a b c) '#())
            #t))

(expect 'vector-every:2
    (equal? (vector-every list '#(a b c) '#(d))
            '(a d)))

(expect 'vector-every:3
    (equal? (vector-every memq '#(a b c) '#(() (c d e) (b c 97)))
            #f))

(expect 'vector-set!
    (equal? (let ((v (vector 0 1 2 3)))
              (vector-set! v 1 11)
              v)
            '#(0 11 2 3)))

(expect 'vector-swap!
    (equal? (let ((v (vector 0 1 2 3)))
              (vector-swap! v 1 3)
              v)
            '#(0 3 2 1)))

(expect 'vector-fill!:0
    (equal? (let ((v (vector)))
              (vector-fill! v 97)
              v)
            '#()))

(expect 'vector-fill!:1
    (equal? (let ((v (vector 0 1 2 3)))
              (vector-fill! v 97)
              v)
            '#(97 97 97 97)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-fill!:2
;;     (equal? (let ((v (vector 0 1 2 3)))
;;               (vector-fill! v 97 1)
;;               v)
;;             '#(0 97 97 97)))
(expect 'vector-fill!:2
    (equal? (let ((v (vector 0 1 2 3))) (vector-copy! v 1 (make-vector 3 97)) v) '#(0 97 97 97)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-fill!:3
;;     (equal? (let ((v (vector 0 1 2 3)))
;;               (vector-fill! v 97 1 2)
;;               v)
;;             '#(0 97 2 3)))
(expect 'vector-fill!:3
    (equal? (let ((v (vector 0 1 2 3))) (vector-copy! v 1 (make-vector 1 97)) v) '#(0 97 2 3)))

(expect 'vector-reverse!:0
    (equal? (let ((v (vector)))
              (vector-reverse! v)
              v)
            '#()))

(expect 'vector-reverse!:1
    (equal? (let ((v (vector 0 1 2 3)))
              (vector-reverse! v)
              v)
            '#(3 2 1 0)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-reverse!:2
;;     (equal? (let ((v (vector 0 1 2 3)))
;;               (vector-reverse! v 1)
;;               v)
;;             '#(0 3 2 1)))
(expect 'vector-reverse!:2
    (equal? (let ((v (vector 0 1 2 3))) (vector-reverse-copy! v 1 (vector-copy v) 1) v) '#(0 3 2 1)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector-reverse!:3
;;     (equal? (let ((v (vector 0 1 2 3)))
;;               (vector-reverse! v 1 3)
;;               v)
;;             '#(0 2 1 3)))
(expect 'vector-reverse!:3
    (equal? (let ((v (vector 0 1 2 3))) (vector-reverse-copy! v 1 (vector-copy v) 1 3) v) '#(0 2 1 3)))

(expect 'vector-copy!:0
    (equal? (let ((v (vector))
                  (src '#(100 101 102 103 104 105)))
              (vector-copy! v 0 v)
              v)
            '#()))

(expect 'vector-copy!:1
    (equal? (let ((v (vector 0 1 2 3 4 5))
                  (src '#(100 101 102 103 104 105)))
              (vector-copy! v 0 src)
              v)
            '#(100 101 102 103 104 105)))

(expect 'vector-copy!:2
    (equal? (let ((v (vector 0 1 2 3))
                  (src '#(100 101 102 103 104 105)))
              (vector-copy! v 1 src 4)
              v)
            '#(0 104 105 3)))

(expect 'vector-copy!:3
    (equal? (let ((v (vector 0 1 2 3))
                  (src '#(100 101 102 103 104 105)))
              (vector-copy! v 1 src 2 4)
              v)
            '#(0 102 103 3)))

(expect 'vector-reverse-copy!:0
    (equal? (let ((v (vector))
                  (src '#(100 101 102 103 104 105)))
              (vector-reverse-copy! v 0 v)
              v)
            '#()))

(expect 'vector-reverse-copy!:1
    (equal? (let ((v (vector 0 1 2 3 4 5))
                  (src '#(100 101 102 103 104 105)))
              (vector-reverse-copy! v 0 src)
              v)
            '#(105 104 103 102 101 100)))

(expect 'vector-reverse-copy!:2
    (equal? (let ((v (vector 0 1 2 3))
                  (src '#(100 101 102 103 104 105)))
              (vector-reverse-copy! v 1 src 4)
              v)
            '#(0 105 104 3)))

(expect 'vector-reverse-copy!:3
    (equal? (let ((v (vector 0 1 2 3))
                  (src '#(100 101 102 103 104 105)))
              (vector-reverse-copy! v 1 src 2 4)
              v)
            '#(0 103 102 3)))

(expect 'vector->list:0
    (equal? (vector->list '#())
            '()))

(expect 'vector->list:1
    (equal? (vector->list '#(a b c))
            '(a b c)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector->list:2
;;     (equal? (vector->list '#(a b c d e) 1)
;;             '(b c d e)))
(expect 'vector->list:2
    (equal? (reverse (reverse-vector->list '#(a b c d e) 1)) '(b c d e)))

;; D2：本库不导出该名字（基础库的版本不收 start / end 或比较过程），改用对照表的写法。原项：
;; (expect 'vector->list:3
;;     (equal? (vector->list '#(a b c d e) 1 4)
;;             '(b c d)))
(expect 'vector->list:3
    (equal? (reverse (reverse-vector->list '#(a b c d e) 1 4)) '(b c d)))

(expect 'reverse-vector->list:0
    (equal? (reverse-vector->list '#())
            '()))

(expect 'reverse-vector->list:1
    (equal? (reverse-vector->list '#(a b c))
            '(c b a)))

(expect 'reverse-vector->list:2
    (equal? (reverse-vector->list '#(a b c d e) 1)
            '(e d c b)))

(expect 'reverse-vector->list:3
    (equal? (reverse-vector->list '#(a b c d e) 1 3)
            '(c b)))

(expect 'list->vector:0
    (equal? (list->vector '())
            '#()))

(expect 'list->vector:1
    (equal? (list->vector '(a b c))
            '#(a b c)))

(expect 'reverse-list->vector:0
    (equal? (reverse-list->vector '())
            '#()))

(expect 'reverse-list->vector:1
    (equal? (reverse-list->vector '(a b c))
            '#(c b a)))


;;; ———————————————— SRFI 133 新增（原 SRFI 43 测试没有） ————————————————
(check (vector-append-subvectors '#(a b c d e) 0 2 '#(f g h i j) 2 4) => '#(a b h i))
(check (vector-cumulate + 0 '#(3 1 4 1 5 9 2 5 6)) => '#(3 4 8 9 14 23 25 30 36))
(check (call-with-values (lambda () (vector-partition symbol? '#(a 1 b 2 c))) list) => '(#(a b c 1 2) 3))
(check (let ((v (vector 1 2 3 4 5))) (vector-unfold! (lambda (i) (* i 10)) v 1 3) v) => '#(1 10 20 4 5))
(check (let ((v (vector 1 2 3 4 5))) (vector-unfold-right! (lambda (i x) (values x (+ x 1))) v 1 4 0) v) => '#(1 2 1 0 5))
(check (vector->string '#(#\a #\b #\c) 1) => "bc")
(check (string->vector "abc" 0 2) => '#(#\a #\b))

(check-report "std vectors")
