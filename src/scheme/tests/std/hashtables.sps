;;; (ironscheme std hashtables) 的测试（designs/08-std-library.md D8）。两部分：
;;;   SRFI 126：改写自 chez-srfi 的 tests/r6rs-hashtables.sps（Taylan Ulrich Bayırlı/Kammer），SRFI 64 形式，
;;;     经 tests/std/srfi64-shim.ss 接到 check 计数。原测试大量用到 SRFI 126 扩展参数的 make-hashtable 等
;;;     （本库因 D2 不导出），所以同时导入 (ironscheme std private hashtables-126) 测其实现。
;;;   SRFI 125：改写自 chez-srfi 的 tests/tables-test.sps（Copyright (C) William D Clinger 2015，MIT），
;;;     其 test / test-assert / test-deny 改名为 test-125 等并接到 check；deprecated:hash 等改为本库导出的
;;;     兼容名（SRFI 69 名），deprecated:string-hash / string-ci-hash 改为基础库的同名过程。
(import (except (rnrs) make-eq-hashtable make-eqv-hashtable make-hashtable hashtable-ref hashtable-update!
                hashtable-copy hashtable-clear!)
        (only (ironscheme) include)
        (only (ironscheme std lists) lset= lset-adjoin)
        (ironscheme std hashtables)
        (ironscheme std private hashtables-126)
        (except (ironscheme std comparators) hash-salt))   ; SRFI 126 的测试测的是其内部的 hash-salt
(include "tests/std/check.ss")
(include "tests/std/srfi64-shim.ss")

(define (exact-integer? obj)
  (and (integer? obj) (exact? obj)))

(define (bytevector . args)
  (u8-list->bytevector args))

(define-syntax test-125
  (syntax-rules ()
    ((_ expr expected) (check expr => expected))))
(define-syntax test-assert-125
  (syntax-rules ()
    ((_ expr) (check (and expr #t) => #t))))
(define-syntax test-deny-125
  (syntax-rules ()
    ((_ expr) (check (and expr #t) => #f))))

;;; ———————————————— SRFI 126（r6rs-hashtables.sps）————————————————
(test-begin "SRFI-126")

(test-group "constructors & inspection"
  (test-group "eq"
    (let ((tables (list (make-eq-hashtable)
                        (make-eq-hashtable 10)
                        (make-eq-hashtable #f #f)
                        (make-hashtable #f eq?)
                        (alist->eq-hashtable '((a . b) (c . d)))
                        (alist->eq-hashtable 10 '((a . b) (c . d)))
                        (alist->eq-hashtable #f #f '((a . b) (c . d))))))
      (do ((tables tables (cdr tables))
           (i 0 (+ i 1)))
          ((null? tables))
        (let ((table (car tables))
              (label (number->string i)))
          (test-assert label (hashtable? table))
          (test-eq label #f (hashtable-hash-function table))
          (test-eq label eq? (hashtable-equivalence-function table))
          (test-eq label #f (hashtable-weakness table))
          (test-assert label (hashtable-mutable? table))))))
  (test-group "eqv"
    (let ((tables (list (make-eqv-hashtable)
                        (make-eqv-hashtable 10)
                        (make-eqv-hashtable #f #f)
                        (make-hashtable #f eqv?)
                        (alist->eqv-hashtable '((a . b) (c . d)))
                        (alist->eqv-hashtable 10 '((a . b) (c . d)))
                        (alist->eqv-hashtable #f #f '((a . b) (c . d))))))
      (do ((tables tables (cdr tables))
           (i 0 (+ i 1)))
          ((null? tables))
        (let ((table (car tables))
              (label (number->string i)))
          (test-assert label (hashtable? table))
          ;; iron-054 修正了基础库（eqv 表此前返回 eqv-hash），恢复原项
          (test-eq label #f (hashtable-hash-function table))
          (test-eq label eqv? (hashtable-equivalence-function table))
          (test-eq label #f (hashtable-weakness table))
          (test-assert label (hashtable-mutable? table))))))
  (test-group "equal"
    (let ((tables (list (make-hashtable equal-hash equal?)
                        (make-hashtable equal-hash equal? 10)
                        (make-hashtable equal-hash equal? #f #f)
                        (alist->hashtable equal-hash equal?
                                          '((a . b) (c . d)))
                        (alist->hashtable equal-hash equal? 10
                                          '((a . b) (c . d)))
                        (alist->hashtable equal-hash equal? #f #f
                                          '((a . b) (c . d))))))
      (do ((tables tables (cdr tables))
           (i 0 (+ i 1)))
          ((null? tables))
        (let ((table (car tables))
              (label (number->string i)))
          (test-assert label (hashtable? table))
          (test-eq label equal-hash (hashtable-hash-function table))
          (test-eq label equal? (hashtable-equivalence-function table))
          (test-eq label #f (hashtable-weakness table))
          (test-assert label (hashtable-mutable? table))))
      (let ((table (make-hashtable (cons equal-hash equal-hash) equal?)))
        (let ((hash (hashtable-hash-function table)))
          (test-assert (or (eq? equal-hash hash)
                           (and (eq? equal-hash (car hash))
                                (eq? equal-hash (cdr hash)))))))))
  (test-group "alist"
    (let ((tables (list (alist->eq-hashtable '((a . b) (a . c)))
                        (alist->eqv-hashtable '((a . b) (a . c)))
                        (alist->hashtable equal-hash equal?
                                          '((a . b) (a . c))))))
      (do ((tables tables (cdr tables))
           (i 0 (+ i 1)))
          ((null? tables))
        (let ((table (car tables))
              (label (number->string i)))
          (test-eq label 'b (hashtable-ref table 'a)))))))

(test-group "procedures"
  (test-group "basics"
    (let ((table (make-eq-hashtable)))
      (test-group "ref"
        (test-error (hashtable-ref table 'a))
        (test-eq 'b (hashtable-ref table 'a 'b))
        (test-assert (not (hashtable-contains? table 'a)))
        (test-eqv 0 (hashtable-size table)))
      (test-group "set"
        (hashtable-set! table 'a 'c)
        (test-eq 'c (hashtable-ref table 'a))
        (test-eq 'c (hashtable-ref table 'a 'b))
        (test-assert (hashtable-contains? table 'a))
        (test-eqv 1 (hashtable-size table)))
      (test-group "delete"
        (hashtable-delete! table 'a)
        (test-error (hashtable-ref table 'a))
        (test-eq 'b (hashtable-ref table 'a 'b))
        (test-assert (not (hashtable-contains? table 'a)))
        (test-eqv 0 (hashtable-size table)))))
  (test-group "advanced"
    (let ((table (make-eq-hashtable)))
      (test-group "lookup"
        (let-values (((x found?) (hashtable-lookup table 'a)))
          (test-assert (not found?))))
      (test-group "update"
        (test-error (hashtable-update! table 'a (lambda (x) (+ x 1))))
        (hashtable-update! table 'a (lambda (x) (+ x 1)) 0)
        (let-values (((x found?) (hashtable-lookup table 'a)))
          (test-eqv 1 x)
          (test-assert found?))
        (hashtable-update! table 'a (lambda (x) (+ x 1)))
        (let-values (((x found?) (hashtable-lookup table 'a)))
          (test-eqv x 2)
          (test-assert found?))
        (hashtable-update! table 'a (lambda (x) (+ x 1)) 0)
        (let-values (((x found?) (hashtable-lookup table 'a)))
          (test-eqv x 3)
          (test-assert found?)))
      (test-group "intern"
        (test-eqv 0 (hashtable-intern! table 'b (lambda () 0)))
        (test-eqv 0 (hashtable-intern! table 'b (lambda () 1))))))
  (test-group "copy/clear"
    (let ((table (alist->hashtable equal-hash equal? '((a . b)))))
      (test-group "copy"
        (let ((table2 (hashtable-copy table)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eq 'b (hashtable-ref table2 'a))
          (test-error (hashtable-set! table2 'a 'c)))
        (let ((table2 (hashtable-copy table #f)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eq 'b (hashtable-ref table2 'a))
          (test-error (hashtable-set! table2 'a 'c)))
        (let ((table2 (hashtable-copy table #t)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eq 'b (hashtable-ref table2 'a))
          (hashtable-set! table2 'a 'c)
          (test-eq 'c (hashtable-ref table2 'a)))
        (let ((table2 (hashtable-copy table #f #f)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eq #f (hashtable-weakness table2))))
      (test-group "clear"
        (let ((table2 (hashtable-copy table #t)))
          (hashtable-clear! table2)
          (test-eqv 0 (hashtable-size table2)))
        (let ((table2 (hashtable-copy table #t)))
          (hashtable-clear! table2 10)
          (test-eqv 0 (hashtable-size table2))))
      (test-group "empty-copy"
        (let ((table2 (hashtable-empty-copy table)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eqv 0 (hashtable-size table2)))
        (let ((table2 (hashtable-empty-copy table 10)))
          (test-eq equal-hash (hashtable-hash-function table2))
          (test-eq equal? (hashtable-equivalence-function table2))
          (test-eqv 0 (hashtable-size table2))))))
  (test-group "keys/values"
    (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
      (test-assert (lset= eq? '(a c) (vector->list (hashtable-keys table))))
      (test-assert (lset= eq? '(b d) (vector->list (hashtable-values table))))
      (let-values (((keys values) (hashtable-entries table)))
        (test-assert (lset= eq? '(a c) (vector->list keys)))
        (test-assert (lset= eq? '(b d) (vector->list values))))
      (test-assert (lset= eq? '(a c) (hashtable-key-list table)))
      (test-assert (lset= eq? '(b d) (hashtable-value-list table)))
      (let-values (((keys values) (hashtable-entry-lists table)))
        (test-assert (lset= eq? '(a c) keys))
        (test-assert (lset= eq? '(b d) values)))))
  (test-group "iteration"
    (test-group "walk"
      (let ((keys '())
            (values '()))
        (hashtable-walk (alist->eq-hashtable '((a . b) (c . d)))
          (lambda (k v)
            (set! keys (cons k keys))
            (set! values (cons v values))))
        (test-assert (lset= eq? '(a c) keys))
        (test-assert (lset= eq? '(b d) values))))
    (test-group "update-all"
      (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
        (hashtable-update-all! table
          (lambda (k v)
            (string->symbol (string-append (symbol->string v) "x"))))
        (test-assert (lset= eq? '(a c) (hashtable-key-list table)))
        (test-assert (lset= eq? '(bx dx) (hashtable-value-list table)))))
    (test-group "prune"
      (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
        (hashtable-prune! table (lambda (k v) (eq? k 'a)))
        (test-assert (not (hashtable-contains? table 'a)))
        (test-assert (hashtable-contains? table 'c))))
    (test-group "merge"
      (let ((table (alist->eq-hashtable '((a . b) (c . d))))
            (table2 (alist->eq-hashtable '((a . x) (e . f)))))
        (hashtable-merge! table table2)
        (test-assert (lset= eq? '(a c e) (hashtable-key-list table)))
        (test-assert (lset= eq? '(x d f) (hashtable-value-list table)))))
    (test-group "sum"
      (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
        (test-assert (lset= eq? '(a b c d)
                            (hashtable-sum table '()
                              (lambda (k v acc)
                                (lset-adjoin eq? acc k v)))))))
    (test-group "map->lset"
      (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
        (test-assert (lset= equal? '((a . b) (c . d))
                            (hashtable-map->lset table cons)))))
    (test-group "find"
      (let ((table (alist->eq-hashtable '((a . b) (c . d)))))
        (let-values (((k v f?) (hashtable-find table
                                 (lambda (k v)
                                   (eq? k 'a)))))
          (test-assert (and f? (eq? k 'a) (eq? v 'b))))
        (let-values (((k v f?) (hashtable-find table (lambda (k v) #f))))
          (test-assert (not f?)))))
    (test-group "misc"
      (test-group "empty?"
        (test-assert (hashtable-empty? (alist->eq-hashtable '())))
        (test-assert (not (hashtable-empty? (alist->eq-hashtable '((a . b)))))))
      (test-group "pop!"
        (test-error (hashtable-pop! (make-eq-hashtable)))
        (let ((table (alist->eq-hashtable '((a . b)))))
          (let-values (((k v) (hashtable-pop! table)))
            (test-eq 'a k)
            (test-eq 'b v)
            (test-assert (hashtable-empty? table)))))
      (test-group "inc!"
        (let ((table (alist->eq-hashtable '((a . 0)))))
          (hashtable-inc! table 'a)
          (test-eqv 1 (hashtable-ref table 'a))
          (hashtable-inc! table 'a 2)
          (test-eqv 3 (hashtable-ref table 'a))))
      (test-group "dec!"
        (let ((table (alist->eq-hashtable '((a . 0)))))
          (hashtable-dec! table 'a)
          (test-eqv -1 (hashtable-ref table 'a))
          (hashtable-dec! table 'a 2)
          (test-eqv -3 (hashtable-ref table 'a)))))))

(test-group "hashing"
  (test-assert (exact-integer? (hash-salt)))
  (test-assert (not (negative? (hash-salt))))
  (test-assert (= (hash-salt) (hash-salt)))
  (test-assert (= (equal-hash (list "foo" 'bar 42))
                  (equal-hash (list "foo" 'bar 42))))
  (test-assert (= (string-hash (string-copy "foo"))
                  (string-hash (string-copy "foo"))))
  (test-assert (= (string-ci-hash (string-copy "foo"))
                  (string-ci-hash (string-copy "FOO"))))
  (test-assert (= (symbol-hash (string->symbol "foo"))
                  (symbol-hash (string->symbol "foo")))))

(test-end "SRFI-126")

;; 原测试在此打印一段关于 Larceny 的说明（其中含 "XFAIL" 字样，会被 C# 端"输出不得含 FAIL"的判定误认），已删去。

;; Local Variables:
;; eval: (put (quote test-group) (quote scheme-indent-function) 1)
;; End:


;;; ———————————————— SRFI 125（tables-test.sps）————————————————
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Transition from SRFI 114 to SRFI 128.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define default-comparator (make-default-comparator))

;;; SRFI 128 says the following definition will work, but that's
;;; an error in SRFI 128; the hash function produce non-integers.

#;
(define number-comparator
  (make-comparator real? = < (lambda (x) (exact (abs x)))))

(define number-comparator
  (make-comparator real? = < (lambda (x) (exact (abs (round x))))))

(define string-comparator
  (make-comparator string? string=? string<? string-hash))

(define string-ci-comparator
  (make-comparator string? string-ci=? string-ci<? string-ci-hash))

(define eq-comparator (make-eq-comparator))

(define eqv-comparator (make-eqv-comparator))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Transition from earlier draft of SRFI 125 to this draft.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Returns an immutable hash table.

(define (hash-table-tabulate comparator n proc)
  (let ((ht (make-hash-table comparator)))
    (do ((i 0 (+ i 1)))
        ((= i n)
         (hash-table-copy ht))
      (call-with-values
       (lambda ()
         (proc i))
       (lambda (key val)
         (hash-table-set! ht key val))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Constructors.

(define ht-default (make-hash-table default-comparator))

(define ht-eq (make-hash-table eq-comparator 'random-argument "another"))

(define ht-eqv (make-hash-table eqv-comparator))

(define ht-eq2 (make-hash-table eq?))

(define ht-eqv2 (make-hash-table eqv?))

(define ht-equal (make-hash-table equal?))

(define ht-string (make-hash-table string=?))

(define ht-string-ci (make-hash-table string-ci=?))

(define ht-symbol (make-hash-table symbol=?))    ; FIXME: glass-box

(define ht-fixnum (make-hash-table = abs))

(define ht-default2
  (hash-table default-comparator 'foo 'bar 101.3 "fever" '(x y z) '#()))

(define ht-fixnum2
  (hash-table-tabulate number-comparator
                       10
                       (lambda (i) (values (* i i) i))))

(define ht-string2
  (hash-table-unfold (lambda (s) (= 0 (string-length s)))
                     (lambda (s) (values s (string-length s)))
                     (lambda (s) (substring s 0 (- (string-length s) 1)))
                     "prefixes"
                     string-comparator
                     'ignored1 'ignored2 "ignored3" '#(ignored 4 5)))

(define ht-string-ci2
  (alist->hash-table '(("" . 0) ("Mary" . 4) ("Paul" . 4) ("Peter" . 5))
                     string-ci-comparator
                     "ignored1" 'ignored2))

(define ht-symbol2
  (alist->hash-table '((mary . travers) (noel . stookey) (peter . yarrow))
                     eq?))

(define ht-equal2
  (alist->hash-table '(((edward) . abbey)
                       ((dashiell) . hammett)
                       ((edward) . teach)
                       ((mark) . twain))
                     equal?
                     (comparator-hash-function default-comparator)))

(define test-tables
  (list ht-default   ht-default2   ; initial keys: foo, 101.3, (x y z)
        ht-eq        ht-eq2        ; initially empty
        ht-eqv       ht-eqv2       ; initially empty
        ht-equal     ht-equal2     ; initial keys: (edward), (dashiell), (mark)
        ht-string    ht-string2    ; initial keys: "p, "pr", ..., "prefixes"
        ht-string-ci ht-string-ci2 ; initial keys: "", "Mary", "Paul", "Peter"
        ht-symbol    ht-symbol2    ; initial keys: mary, noel, peter
        ht-fixnum    ht-fixnum2))  ; initial keys: 0, 1, 4, 9, ..., 81

;;; Predicates

(test-125 (map hash-table?
           (cons '#()
                 (cons default-comparator
                       test-tables)))
      (append '(#f #f) (map (lambda (x) #t) test-tables)))

(test-125 (map hash-table-contains?
           test-tables
           '(foo 101.3
             x "y"
             (14 15) #\newline
             (edward) (mark)
             "p" "pref"
             "mike" "PAUL"
             jane noel
             0 4))
      '(#f #t #f #f #f #f #f #t #f #t #f #t #f #t #f #t))

(test-125 (map hash-table-contains?
           test-tables
           `(,(bytevector) 47.9
             '#() '()
             foo bar
             19 (henry)
             "p" "perp"
             "mike" "Noel"
             jane paul
             0 5))
      (map (lambda (x) #f) test-tables))

(test-125 (map hash-table-empty? test-tables)
      '(#t #f #t #t #t #t #t #f #t #f #t #f #t #f #t #f))

(test-125 (map (lambda (ht1 ht2) (hash-table=? default-comparator ht1 ht2))
           test-tables
           test-tables)
      (map (lambda (x) #t) test-tables))

(test-125 (map (lambda (ht1 ht2) (hash-table=? default-comparator ht1 ht2))
           test-tables
           (do ((tables (reverse test-tables) (cddr tables))
                (rev '() (cons (car tables) (cons (cadr tables) rev))))
               ((null? tables)
                rev)))
      '(#f #f #t #t #t #t #f #f #f #f #f #f #f #f #f #f))

(test-125 (map hash-table-mutable? test-tables)
      '(#t #f #t #t #t #t #t #t #t #t #t #t #t #t #t #f))

;;; FIXME: glass-box

(test-125 (map hash-table-mutable? (map hash-table-copy test-tables))
      (map (lambda (x) #f) test-tables))

(test-125 (hash-table-mutable? (hash-table-copy ht-fixnum2 #t))
      #t)

;;; Accessors.

;;; FIXME: glass-box (implementations not required to raise an exception here)

(test-125 (map (lambda (ht)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht 'not-a-key)))
           test-tables)
      (map (lambda (ht) 'err) test-tables))

;;; FIXME: glass-box (implementations not required to raise an exception here)

(test-125 (map (lambda (ht)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht 'not-a-key (lambda () 'err))))
           test-tables)
      (map (lambda (ht) 'err) test-tables))

;;; FIXME: glass-box (implementations not required to raise an exception here)

(test-125 (map (lambda (ht)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht 'not-a-key (lambda () 'err) values)))
           test-tables)
      (map (lambda (ht) 'err) test-tables))

(test-125 (map (lambda (ht key)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht key)))
           test-tables
           '(foo 101.3
             x "y"
             (14 15) #\newline
             (edward) (mark)
             "p" "pref"
             "mike" "PAUL"
             jane noel
             0 4))
      '(err "fever" err err err err err twain err 4 err 4 err stookey err 2))

(test-125 (map (lambda (ht key)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht key (lambda () 'eh))))
           test-tables
           '(foo 101.3
             x "y"
             (14 15) #\newline
             (edward) (mark)
             "p" "pref"
             "mike" "PAUL"
             jane noel
             0 4))
      '(eh "fever" eh eh eh eh eh twain eh 4 eh 4 eh stookey eh 2))

(test-125 (map (lambda (ht key)
             (guard (exn
                     (else 'err))
              (hash-table-ref ht key (lambda () 'eh) list)))
           test-tables
           '(foo 101.3
             x "y"
             (14 15) #\newline
             (edward) (mark)
             "p" "pref"
             "mike" "PAUL"
             jane noel
             0 4))
      '(eh ("fever") eh eh eh eh eh (twain) eh (4) eh (4) eh (stookey) eh (2)))

;;; FIXME: glass-box (implementations not required to raise an exception here)

(test-125 (map (lambda (ht)
             (guard (exn
                     (else 'eh))
              (hash-table-ref/default ht 'not-a-key 'eh)))
           test-tables)
      (map (lambda (ht) 'eh) test-tables))

(test-125 (map (lambda (ht key)
             (guard (exn
                     (else 'err))
              (hash-table-ref/default ht key 'eh)))
           test-tables
           '(foo 101.3
             x "y"
             (14 15) #\newline
             (edward) (mark)
             "p" "pref"
             "mike" "PAUL"
             jane noel
             0 4))
      '(eh "fever" eh eh eh eh eh twain eh 4 eh 4 eh stookey eh 2))

(test-125 (begin (hash-table-set! ht-fixnum)
             (list-sort < (hash-table-keys ht-fixnum)))
      '())

(test-125 (begin (hash-table-set! ht-fixnum 121 11 144 12 169 13)
             (list-sort < (hash-table-keys ht-fixnum)))
      '(121 144 169))

(test-125 (begin (hash-table-set! ht-fixnum
                              0 0 1 1 4 2 9 3 16 4 25 5 36 6 49 7 64 8 81 9)
             (list-sort < (hash-table-keys ht-fixnum)))
      '(0 1 4 9 16 25 36 49 64 81 121 144 169))

(test-125 (map (lambda (i) (hash-table-ref/default ht-fixnum i 'error))
           '(169 144 121 0 1 4 9 16 25 36 49 64 81))
      '(13 12 11 0 1 2 3 4 5 6 7 8 9))

(test-125 (begin (hash-table-delete! ht-fixnum)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i 'error))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 5 6 7 8 9))

(test-125 (begin (hash-table-delete! ht-fixnum 1 9 25 49 81 200 121 169 81 1)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(-1 12 -1 0 -1 2 -1 4 -1 6 -1 8 -1))

(test-125 (begin (hash-table-delete! ht-fixnum 200 100 0 81 36)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(-1 12 -1 -1 -1 2 -1 4 -1 -1 -1 8 -1))

(test-125 (begin (hash-table-intern! ht-fixnum 169 (lambda () 13))
             (hash-table-intern! ht-fixnum 121 (lambda () 11))
             (hash-table-intern! ht-fixnum   0 (lambda ()  0))
             (hash-table-intern! ht-fixnum   1 (lambda ()  1))
             (hash-table-intern! ht-fixnum   1 (lambda () 99))
             (hash-table-intern! ht-fixnum 121 (lambda () 66))
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 -1 4 -1 -1 -1 8 -1))

(test-125 (list-sort (lambda (v1 v2) (< (vector-ref v1 0) (vector-ref v2 0)))
                 (hash-table-map->list vector ht-fixnum))
      '(#(0 0) #(1 1) #(4 2) #(16 4) #(64 8) #(121 11) #(144 12) #(169 13)))

(test-125 (begin (hash-table-prune! (lambda (key val)
                                  (and (odd? key) (> val 10)))
                                ht-fixnum)
             (list-sort (lambda (l1 l2)
                          (< (car l1) (car l2)))
                        (hash-table-map->list list ht-fixnum)))
      '((0 0) (1 1) (4 2) (16 4) (64 8) #;(121 11) (144 12) #;(169 13)))

(test-125 (begin (hash-table-intern! ht-fixnum 169 (lambda () 13))
             (hash-table-intern! ht-fixnum 144 (lambda () 9999))
             (hash-table-intern! ht-fixnum 121 (lambda () 11))
             (list-sort (lambda (l1 l2)
                          (< (car l1) (car l2)))
                        (hash-table-map->list list ht-fixnum)))
      '((0 0) (1 1) (4 2) (16 4) (64 8) (121 11) (144 12) (169 13)))

(test-125 (begin (hash-table-update! ht-fixnum 9 length (lambda () '(a b c)))
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 -1 -1 -1 8 -1))

(test-125 (begin (hash-table-update! ht-fixnum 16 -)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 -4 -1 -1 -1 8 -1))

(test-125 (begin (hash-table-update! ht-fixnum 16 - abs)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 -1 -1 -1 8 -1))

(test-125 (begin (hash-table-update!/default ht-fixnum 25 - 5)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 -5 -1 -1 8 -1))

(test-125 (begin (hash-table-update!/default ht-fixnum 25 - 999)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 5 -1 -1 8 -1))

(test-125 (let* ((n0 (hash-table-size ht-fixnum))
             (ht (hash-table-copy ht-fixnum #t)))
        (call-with-values
         (lambda () (hash-table-pop! ht))
         (lambda (key val)
           (list (= key (* val val))
                 (= (- n0 1) (hash-table-size ht))))))
      '(#t #t))

(test-125 (begin (hash-table-delete! ht-fixnum 75)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 75 81)))
      '(13 12 11 0 1 2 3 4 5 -1 -1 8 -1 -1))

#;(let ((ht-eg (hash-table number-comparator 1 1 4 2 9 3 16 4 25 5 64 8)))
  (test-125 (hash-table-delete! ht-eg)
        0)
  (test-125 (hash-table-delete! ht-eg 2 7 2000)
        0)
  (test-125 (hash-table-delete! ht-eg 1 2 4 7 64 2000)
        3)
  (test-assert-125 (= 3 (length (hash-table-keys ht-eg)))))

(test-125 (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
           '(169 144 121 0 1 4 9 16 25 36 49 64 81))
      '(13 12 11 0 1 2 3 4 5 -1 -1 8 -1))

(test-125 (begin (hash-table-set! ht-fixnum 36 6)
             (hash-table-set! ht-fixnum 81 9)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(169 144 121 0 1 4 9 16 25 36 49 64 81)))
      '(13 12 11 0 1 2 3 4 5 6 -1 8 9))

(test-125 (begin (hash-table-clear! ht-eq)
             (hash-table-size ht-eq))
      0)

;;; The whole hash table.

(test-125 (begin (hash-table-set! ht-eq 'foo 13 'bar 14 'baz 18)
             (hash-table-size ht-eq))
      3)

(test-125 (let* ((ht (hash-table-empty-copy ht-eq))
             (n0 (hash-table-size ht))
             (ignored (hash-table-set! ht 'foo 13 'bar 14 'baz 18))
             (n1 (hash-table-size ht)))
        (list n0 n1 (hash-table=? default-comparator ht ht-eq)))
      '(0 3 #t))

(test-125 (begin (hash-table-clear! ht-eq)
             (hash-table-size ht-eq))
      0)

(test-125 (hash-table-find (lambda (key val)
                         (if (= 144 key (* val val))
                             (list key val)
                             #f))
                       ht-fixnum
                       (lambda () 99))
      '(144 12))

(test-125 (hash-table-find (lambda (key val)
                         (if (= 144 key val)
                             (list key val)
                             #f))
                       ht-fixnum
                       (lambda () 99))
      99)

(test-125 (hash-table-count <= ht-fixnum)
      2)

;;; Mapping and folding.

(test-125 (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
           '(0 1 4 9 16 25 36 49 64 81 100 121 144 169 196))
      '(0 1 2 3 4 5 6 -1 8 9 -1 11 12 13 -1))

(test-125 (let ((ht (hash-table-map (lambda (val) (* val val))
                                eqv-comparator
                                ht-fixnum)))
        (map (lambda (i) (hash-table-ref/default ht i -1))
             '(0 1 4 9 16 25 36 49 64 81 100 121 144 169 196)))
      '(0 1 4 9 16 25 36 -1 64 81 -1 121 144 169 -1))

(test-125 (let ((keys (make-vector 15 -1))
            (vals (make-vector 15 -1)))
        (hash-table-for-each (lambda (key val)
                               (vector-set! keys val key)
                               (vector-set! vals val val))
                             ht-fixnum)
        (list keys vals))
      '(#(0 1 4 9 16 25 36 -1 64 81 -1 121 144 169 -1)
        #(0 1 2 3  4  5  6 -1  8  9 -1  11  12  13 -1)))

(test-125 (begin (hash-table-map! (lambda (key val)
                                (if (<= 10 key)
                                    (- val)
                                    val))
                              ht-fixnum)
             (map (lambda (i) (hash-table-ref/default ht-fixnum i -1))
                  '(0 1 4 9 16 25 36 49 64 81 100 121 144 169 196)))
      '(0 1 2 3 -4 -5 -6 -1 -8 -9 -1 -11 -12 -13 -1))

(test-125 (hash-table-fold (lambda (key val acc)
                         (+ val acc))
                       0
                       ht-string-ci2)
      13)

(test-125 (list-sort < (hash-table-fold (lambda (key val acc)
                                      (cons key acc))
                                    '()
                                    ht-fixnum))
      '(0 1 4 9 16 25 36 64 81 121 144 169))

;;; Copying and conversion.

(test-125 (hash-table=? number-comparator ht-fixnum (hash-table-copy ht-fixnum))
      #t)

(test-125 (hash-table=? number-comparator ht-fixnum (hash-table-copy ht-fixnum #f))
      #t)

(test-125 (hash-table=? number-comparator ht-fixnum (hash-table-copy ht-fixnum #t))
      #t)

(test-125 (hash-table-mutable? (hash-table-copy ht-fixnum))
      #f)

(test-125 (hash-table-mutable? (hash-table-copy ht-fixnum #f))
      #f)

(test-125 (hash-table-mutable? (hash-table-copy ht-fixnum #t))
      #t)

(test-125 (hash-table->alist ht-eq)
      '())

(test-125 (list-sort (lambda (x y) (< (car x) (car y)))
                 (hash-table->alist ht-fixnum))
      '((0 . 0)
        (1 . 1)
        (4 . 2)
        (9 . 3)
        (16 . -4)
        (25 . -5)
        (36 . -6)
        (64 . -8)
        (81 . -9)
        (121 . -11)
        (144 . -12)
        (169 . -13)))

;;; Hash tables as sets.

(test-125 (begin (hash-table-union! ht-fixnum ht-fixnum2)
             (list-sort (lambda (x y) (< (car x) (car y)))
                        (hash-table->alist ht-fixnum)))
      '((0 . 0)
        (1 . 1)
        (4 . 2)
        (9 . 3)
        (16 . -4)
        (25 . -5)
        (36 . -6)
        (49 . 7)
        (64 . -8)
        (81 . -9)
        (121 . -11)
        (144 . -12)
        (169 . -13)))

(test-125 (let ((ht (hash-table-copy ht-fixnum2 #t)))
        (hash-table-union! ht ht-fixnum)
        (list-sort (lambda (x y) (< (car x) (car y)))
                   (hash-table->alist ht)))
      '((0 . 0)
        (1 . 1)
        (4 . 2)
        (9 . 3)
        (16 . 4)
        (25 . 5)
        (36 . 6)
        (49 . 7)
        (64 . 8)
        (81 . 9)
        (121 . -11)
        (144 . -12)
        (169 . -13)))

(test-125 (begin (hash-table-union! ht-eqv2 ht-fixnum)
             (hash-table=? default-comparator ht-eqv2 ht-fixnum))
      #f)

(test-125 (begin (hash-table-intersection! ht-eqv2 ht-fixnum)
             (hash-table=? default-comparator ht-eqv2 ht-fixnum))
      #f)

(test-125 (begin (hash-table-intersection! ht-eqv2 ht-eqv)
             (hash-table-empty? ht-eqv2))
      #t)

(test-125 (begin (hash-table-intersection! ht-fixnum ht-fixnum2)
             (list-sort (lambda (x y) (< (car x) (car y)))
                        (hash-table->alist ht-fixnum)))
      '((0 . 0)
        (1 . 1)
        (4 . 2)
        (9 . 3)
        (16 . -4)
        (25 . -5)
        (36 . -6)
        (49 . 7)
        (64 . -8)
        (81 . -9)))

(test-125 (begin (hash-table-intersection!
              ht-fixnum
              (alist->hash-table '((-1 . -1) (4 . 202) (25 . 205) (100 . 10))
                                 number-comparator))
             (list-sort (lambda (x y) (< (car x) (car y)))
                        (hash-table->alist ht-fixnum)))
      '((4 . 2)
        (25 . -5)))

(test-125 (let ((ht (hash-table-copy ht-fixnum2 #t)))
        (hash-table-difference!
         ht
         (alist->hash-table '((-1 . -1) (4 . 202) (25 . 205) (100 . 10))
                            number-comparator))
        (list-sort (lambda (x y) (< (car x) (car y)))
                   (hash-table->alist ht)))
      '((0 . 0)
        (1 . 1)
        (9 . 3)
        (16 . 4)
        (36 . 6)
        (49 . 7)
        (64 . 8)
        (81 . 9)))

(test-125 (let ((ht (hash-table-copy ht-fixnum2 #t)))
        (hash-table-xor!
         ht
         (alist->hash-table '((-1 . -1) (4 . 202) (25 . 205) (100 . 10))
                            number-comparator))
        (list-sort (lambda (x y) (< (car x) (car y)))
                   (hash-table->alist ht)))
      '((-1 . -1)
        (0 . 0)
        (1 . 1)
        (9 . 3)
        (16 . 4)
        (36 . 6)
        (49 . 7)
        (64 . 8)
        (81 . 9)
        (100 . 10)))

(test-125 (guard (exn
              (else 'key-not-found))
       (hash-table-ref ht-default "this key won't be present"))
      'key-not-found)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Desultory tests of deprecated procedures and usages.
;;; Deprecated usage of make-hash-table and alist->hash-table
;;; has already been tested above.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(test-125 (let* ((x (list 1 2 3))
             (y (cons 1 (cdr x)))
             (h1 (hash x))
             (h2 (hash y)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x "abcd")
             (y (string-append "ab" "cd"))
             (h1 (string-hash x))
             (h2 (string-hash y)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x "Hello There!")
             (y "hello THERE!")
             (h1 (string-ci-hash x))
             (h2 (string-ci-hash y)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x (vector 'a "bcD" #\c '(d 2.718) -42 (bytevector) '#() (bytevector 9 20)))
             (y x)
             (h1 (hash-by-identity x))
             (h2 (hash-by-identity y)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x (list 1 2 3))
             (y (cons 1 (cdr x)))
             (h1 (hash x 60))
             (h2 (hash y 60)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x "abcd")
             (y (string-append "ab" "cd"))
;; D2：SRFI 69 风格的 (string-hash s bound) 不导出，基础库的 string-hash 不收 bound，取模代替
             (h1 (mod (string-hash x) 97))
             (h2 (mod (string-hash y) 97)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x "Hello There!")
             (y "hello THERE!")
;; D2：同上
             (h1 (mod (string-ci-hash x) 101))
             (h2 (mod (string-ci-hash y) 101)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let* ((x (vector 'a "bcD" #\c '(d 2.718) -42 (bytevector) '#() (bytevector 19 20)))
             (y x)
             (h1 (hash-by-identity x 102))
             (h2 (hash-by-identity y 102)))
        (list (exact-integer? h1)
              (exact-integer? h2)
              (= h1 h2)))
      '(#t #t #t))

(test-125 (let ((f (hash-table-equivalence-function ht-fixnum)))
        (if (procedure? f)
            (f 34 34)
            #t))
      #t)

(test-125 (let ((f (hash-table-hash-function ht-fixnum)))
        (if (procedure? f)
            (= (f 34) (f 34))
            #t))
      #t)

(test-125 (map (lambda (key) (hash-table-exists? ht-fixnum2 key))
           '(0 1 2 3 4 5 6 7 8 9 10))
      '(#t #t #f #f #t #f #f #f #f #t #f))

(test-125 (let ((n 0))
        (hash-table-walk ht-fixnum2
                                    (lambda (key val) (set! n (+ n key))))
        n)
      (apply +
             (map (lambda (x) (* x x))
                  '(0 1 2 3 4 5 6 7 8 9))))

(test-125 (list-sort < (hash-table-fold ht-fixnum2
                                    (lambda (key val acc)
                                      (cons key acc))
                                    '()))
      '(0 1 4 9 16 25 36 49 64 81))

(test-125 (let ((ht (hash-table-copy ht-fixnum2 #t))
            (ht2 (hash-table number-comparator
                             .25 .5 64 9999 81 9998 121 -11 144 -12)))
        (hash-table-merge! ht ht2)
        (list-sort (lambda (x y) (< (car x) (car y)))
                   (hash-table->alist ht)))
      '((0 . 0)
        (.25 . .5)
        (1 . 1)
        (4 . 2)
        (9 . 3)
        (16 . 4)
        (25 . 5)
        (36 . 6)
        (49 . 7)
        (64 . 8)
        (81 . 9)
        (121 . -11)
        (144 . -12)))


;;; ———————————————— 原测试未覆盖的名字 ————————————————
(let ((ht (alist->hash-table '((a . 1) (b . 2)) (make-eq-comparator))))
  (check (list-sort < (hash-table-values ht)) => '(1 2))
  (check (call-with-values (lambda () (hash-table-entries ht))
           (lambda (ks vs) (list-sort < vs)))
         => '(1 2)))
(check (weakness weak-key) => 'weak-key)

(check-report "std hashtables")
