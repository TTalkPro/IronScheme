;;; (ironscheme std persistent hash-maps) 的测试（designs/08-std-library.md D8）。改写自 pfds 的
;;; tests/hamts.sls（Ian Price，new-style BSD 许可）：trc-testing 的断言经 tests/std/trc-check.ss 计入 check.ss 的计数。
(import (rnrs) (only (ironscheme) include)
        (ironscheme std persistent hash-maps))
(include "tests/std/check.ss")
(include "tests/std/trc-check.ss")

(define (make-string-hamt)
  (make-hamt string-hash string=?))

(define (compare-string-alist l1 l2)
  (lambda (l1 l2)
    (define (compare x y) (string<? (car x) (car y)))
    (equal? (list-sort compare l1)
            (list-sort compare l2))))

(define (bad-hash x) 0)

(define-test-suite hamts
  "Tests for the Hash Array Mapped Trie implementation")

(define-test-case hamts empty-hamt ()
  (test-predicate hamt? (make-string-hamt))
  (test-eqv 0 (hamt-size (make-string-hamt))))

(define-test-case hamts hamt-ref/set ()
  ;; Referencing non-existent key
  (test-equal #f (hamt-ref (make-string-hamt) "foo" #f))
  ;; Referencing a non-existent key (exception)
  (test-exn assertion-violation? (hamt-ref (make-string-hamt) "bar"))
  ;; Referencing newly-added key
  (test-equal "bar" (hamt-ref (hamt-set (make-string-hamt) "foo" "bar") "foo" #f))
  (test-eqv 1 (hamt-size (hamt-set (make-string-hamt) "foo" "bar")))
  ;; shadowing an existing key
  (test-equal "baz" (hamt-ref (hamt-set (hamt-set (make-string-hamt) "foo" "bar") "foo" "baz") "foo" #f))
  (test-eqv 1 (hamt-size (hamt-set (hamt-set (make-string-hamt) "foo" "bar") "foo" "baz"))))

(define-test-case hamts hamt-contains ()
  (let ((h (hamt-set (make-string-hamt) "foo" 1)))
    (test-eqv #t (hamt-contains? h "foo")))
  (let ((h (hamt-set (make-string-hamt) "foo" 1)))
    (test-eqv #f (hamt-contains? h "bar"))))

(define-test-case hamts hamt-conversion ()
  ;; alist->hamt / distinct keys
  (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l string-hash string=?)))
    (test-equal (list 1 2 3)
                (map (lambda (x) (hamt-ref h x #f)) (list "a" "b" "c"))))
  ;; alist->hamt / overlapping keys (leftmost shadows)
  (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3) ("a" . 4)))
         (h (alist->hamt l string-hash string=?)))
    (test-equal (list 1 2 3)
                (map (lambda (x) (hamt-ref h x #f)) (list "a" "b" "c"))))
  ;; hamt->alist / distinct keys means left inverse
  (let ((l '(("a" . 1) ("b" . 2) ("c" . 3))))
    (test-compare compare-string-alist l
                  (hamt->alist (alist->hamt l string-hash string=?)))))

(define-test-case hamts hamt-folding ()
  ;; count size
  (let ((h (alist->hamt '(("a" . 1) ("b" . 2) ("c" . 3)) string-hash string=?))
        (increment (lambda (k v acc) (+ 1 acc))))
    (test-equal 3 (hamt-fold increment 0 h)))
  ;; copy hamt
  (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l string-hash string=?))
         (add (lambda (k v acc) (hamt-set acc k v))))
    (test-compare compare-string-alist l
                  (hamt->alist (hamt-fold add (make-string-hamt) h)))))

(define-test-case hamts hamt-removal ()
  ;; removed key exists
  (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l string-hash string=?)))
    (test-case key-exists ()
      (test-compare compare-string-alist '(("b" . 2) ("c" . 3)) (hamt-delete h "a"))
      (test-eqv (- (hamt-size h) 1) (hamt-size (hamt-delete h "a")))))
  ;; removed key does not exist
  (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l string-hash string=?)))
    (test-case key-not-exists ()
      (test-compare compare-string-alist l (hamt-delete h "d"))
      (test-eqv (hamt-size h) (hamt-size (hamt-delete h "d"))))))

(define-test-case hamts hamt-updates ()
  ;; update non-existent key
  (test-eqv 1 (hamt-ref (hamt-update (make-string-hamt) "foo" add1 0) "foo" #f))
  ;; update existing key
  (let ((h (hamt-set (make-string-hamt) "foo" 12)))
   (test-eqv 13 (hamt-ref (hamt-update h "foo" add1 0) "foo" #f))))

(define-test-case hamts hamt-collisions ()
  ;; a bad hash function does not cause problems
  (let* ((l  '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l bad-hash string=?)))
    (test-compare compare-string-alist l (hamt->alist h)))
  ;; stress test, since bigger amounts data usually finds bugs
  (let ((insert (lambda (val hamt) (hamt-set hamt val val)))
        (hash   (lambda (n) (exact (floor (/ n 2))))))
    (test-eqv 100 (hamt-size (foldl insert (make-hamt hash =) (iota 100)))))
  ;; collision removal
  (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3) ("d" . 4)))
         (h (alist->hamt l bad-hash string=?)))
    (test-compare compare-string-alist '()
                  (foldl (lambda (str hamt) (hamt-delete hamt str))
                         h
                         '("b" "notexists" "d" "a" "c" "notexists"))))
  ;; stress test removal
  (let* ((al (map (lambda (x) (cons x #t)) (iota 100)))
         (hash   (lambda (n) (exact (floor (/ n 2)))))
         (h (alist->hamt al hash =)))
    (test-eqv 94 (hamt-size (foldl (lambda (s h) (hamt-delete h s))
                                   h
                                   (list 1 93 72 6 24 48)))))
  ;; collision updates
  (let* ((l '(("a" . 1) ("b" . 2) ("c" . 3)))
         (h (alist->hamt l bad-hash string=?)))
    (test-compare compare-string-alist
                  '(("a" . 2) ("b" . 3) ("c" . 4))
                  (foldl (lambda (key hamt)
                           (hamt-update hamt key add1 0))
                         h
                         '("a" "b" "c")))))

(define-test-case hamts hamt-mapping ()
  (let* ((l '(("a" . 97) ("b" . 98) ("c" . 99)))
         (h (alist->hamt l string-hash string=?)))
    (test-compare compare-string-alist l
                  (hamt->alist (hamt-map (lambda (x) x) h))))
  (let* ((l '(("a" . 97) ("b" . 98) ("c" . 99)))
         (h (alist->hamt l string-hash string=?))
         (stringify (lambda (n) (string (integer->char n)))))
    (test-compare compare-string-alist
                  '(("a". "a") ("b" . "b") ("c" . "c"))
                  (hamt->alist (hamt-map stringify h))))
  (let ((h (alist->hamt '(("a" . 97) ("b" . 98) ("c" . 99)) string-hash string=?)))
    (test-eqv (hamt-size h) (hamt-size (hamt-map (lambda (x) x) h)))))

;;; ———————————————— 补充（iron-045）：原测试没有覆盖的导出 ————————————————
(let ((h (make-hamt string-hash string=?)))
  (check (eq? (hamt-equivalence-predicate h) string=?) => #t)
  (check (eq? (hamt-hash-function h) string-hash) => #t))

;; 负的散列值（pfds 的缺陷，iron-045 修正；基础库的 string-hash 会返回负数）
(let* ((neg-hash (lambda (s) (- -1 (* 1000 (char->integer (string-ref s 0))))))
       (h (alist->hamt '(("a" . 1) ("b" . 2) ("c" . 3) ("d" . 4)) neg-hash string=?)))
  (check (map (lambda (x) (hamt-ref h x #f)) '("a" "b" "c" "d")) => '(1 2 3 4))
  (check (hamt-size (hamt-delete h "b")) => 3)
  (check (hamt-ref (hamt-delete h "b") "c" #f) => 3))

;; 随机对照试验（iron-045：pfds 的 HAMT 有索引缺陷，见库文件头）：随机的插入、更新、删除序列，
;; 散列值取三种分布（小范围多冲突、带符号 32 位、大整数），每组结束时与关联表比较大小与全部键的值。
(define seed 987654321)
(define (rnd n)
  (set! seed (mod (+ (* seed 6364136223846793005) 1442695040888963407) 18446744073709551616))
  (mod (bitwise-arithmetic-shift-right seed 20) n))
(define (make-random-hash kind)
  (let ((t (make-eqv-hashtable)))
    (lambda (k)
      (or (hashtable-ref t k #f)
          (let ((h (case kind
                     ((small) (rnd 64))
                     ((signed) (- (rnd 4294967296) 2147483648))
                     (else (* (rnd 4294967296) (rnd 4294967296))))))
            (hashtable-set! t k h)
            h)))))
(define (random-trial kind)
  (let ((hash (make-random-hash kind)))
    (let loop ((i 0) (h (make-hamt hash eqv?)) (al '()))
      (if (< i 200)
          (let ((k (rnd 60))
                (al* (lambda (k) (remp (lambda (p) (eqv? (car p) k)) al))))
            (if (< (rnd 3) 2)
                (loop (+ i 1) (hamt-set h k i) (cons (cons k i) (al* k)))
                (loop (+ i 1) (hamt-delete h k) (al* k))))
          (and (= (hamt-size h) (length al))
               (for-all (lambda (k) (equal? (hamt-ref h k #f) (cond ((assv k al) => cdr) (else #f))))
                        (iota 60)))))))
(for-each
  (lambda (kind)
    (let trial ((n 0))
      (when (< n 20)
        (check (random-trial kind) => #t)
        (trial (+ n 1)))))
  '(small signed big))

(check-report "std persistent hash-maps")
