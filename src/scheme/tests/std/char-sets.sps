;;; (ironscheme std char-sets) 的测试（designs/08-std-library.md D8）。改写自 chez-srfi 的 tests/char-sets.sps：
;;; 测试用例来自 Scheme 48 1.9（Mike Sperber，许可证见 lib/ironscheme/std/LICENSES/scheme48.txt），
;;; 包括反转表（(ironscheme std private inversion-list)）与 SRFI 14 两部分。
;;; Scheme 48 的 check / check-that 改为计入 tests/std/check.ss 的计数（check 改名为 s48-check）。
(import (rnrs) (only (ironscheme) include)
        (ironscheme std private inversion-list)
        (ironscheme std char-sets))
(include "tests/std/check.ss")

(define-syntax define-test-suite
  (syntax-rules ()
    ((_ suite) (define dummy 'suite))))

(define-syntax define-test-case
  (syntax-rules ()
    ((_ test-case suite checks ...)
     (begin checks ...))))

(define (is-true) (lambda (x) x))
(define (is-false) not)

(define-syntax check-that
  (syntax-rules ()
    ((_ expr ok?)
     (check (let ((v expr)) (if (ok? v) #t (list 'failed v))) => #t))))

(define-syntax s48-check
  (syntax-rules (=>)
    ((_ expr) (check-that expr (is-true)))
    ((_ expr => expect) (check-that expr (lambda (x) (equal? x expect))))
    ((_ expr (=> equal?) expect) (check-that expr (lambda (x) (equal? x expect))))))

(define is
  (case-lambda
    ((= x) (lambda (y) (= x y)))
    ((x) (if (procedure? x) x (lambda (y) (equal? x y))))))

(define (opposite f) (lambda (x) (not (f x))))

(define (all-of . fs)
  (lambda (x) (for-all (lambda (f) (f x)) fs)))

(define x->char-set ->char-set)
(define char->scalar-value char->integer)
(define scalar-value->char integer->char)

;;; ———————————————— 反转表（inversion-list-check.scm）————————————————
; Part of Scheme 48 1.9.  See file COPYING for notices and license.

; Authors: Mike Sperber

(define-test-suite inversion-lists-tests)

(define-test-case creation/membership inversion-lists-tests
  (check-that (inversion-list-member? 5 (make-empty-inversion-list 0 1000)) (is-false))
  (s48-check (inversion-list-member? 5 (number->inversion-list 0 1000 5)))
  (check-that (inversion-list-member? 4 (number->inversion-list 0 1000 5)) (is-false))
  (check-that (inversion-list-member? 6 (number->inversion-list 0 1000 5)) (is-false))
  (check-that (inversion-list-member? 6 (range->inversion-list 0 1000 500 1000)) (is-false))
  (check-that (inversion-list-member? 499 (range->inversion-list 0 1000 500 1000)) (is-false))
  (s48-check (inversion-list-member? 500 (range->inversion-list 0 1000 500 1000)))
  (s48-check (inversion-list-member? 1000 (range->inversion-list 0 1000 500 1000))))

(define-test-case complement/1 inversion-lists-tests
  (check-that
   (inversion-list-complement
    (inversion-list-complement
     (range->inversion-list 0 1000 5 10)))
   (is inversion-list=?
       (range->inversion-list 0 1000 5 10))))

(define-test-case complement/2 inversion-lists-tests
  (check-that
   (inversion-list-complement
    (inversion-list-complement
     (range->inversion-list 0 1000 0 1000)))
   (is inversion-list=?
       (range->inversion-list 0 1000 0 1000))))

(define-test-case union/1 inversion-lists-tests
  (check-that
   (inversion-list-union (range->inversion-list 0 1000 5 10)
			 (range->inversion-list 0 1000 20 30))
   (is inversion-list=?
       (ranges->inversion-list 0 1000 '(5 . 10) '(20 . 30)))))

(define-test-case union/2 inversion-lists-tests
  (check-that
   (inversion-list-union (range->inversion-list 0 1000 5 10)
			 (range->inversion-list 0 1000 7 8))
   (is inversion-list=?
       (range->inversion-list 0 1000 5 10))))
  
(define-test-case union/3 inversion-lists-tests
  (check-that
   (inversion-list-union (range->inversion-list 0 1000 5 10)
			 (range->inversion-list 0 1000 7 15))
   (is inversion-list=?
       (range->inversion-list 0 1000 5 15))))

(define-test-case union/4 inversion-lists-tests
  (check-that
   (inversion-list-union (range->inversion-list 0 1000 500 1000)
			 (range->inversion-list 0 1000 0 500))
   (is inversion-list=?
       (range->inversion-list 0 1000 0 1000))))

(define-test-case intersection/1 inversion-lists-tests
  (check-that
   (inversion-list-intersection (range->inversion-list 0 1000 5 10)
				(range->inversion-list 0 1000 20 30))
   (is inversion-list=?
       (make-empty-inversion-list 0 1000))))
  
(define-test-case intersection/2 inversion-lists-tests
  (check-that
   (inversion-list-intersection (range->inversion-list 0 1000 5 10)
				(range->inversion-list 0 1000 7 8))
   (is inversion-list=?
       (range->inversion-list 0 1000 7 8))))

(define-test-case intersection/3 inversion-lists-tests
  (check-that
   (inversion-list-intersection (range->inversion-list 0 1000 5 10)
				(range->inversion-list 0 1000 7 15))
   (is inversion-list=?
       (range->inversion-list 0 1000 7 10))))

(define-test-case intersection/4 inversion-lists-tests
  (check-that
   (inversion-list-intersection (range->inversion-list 0 1000 500 1000)
				(range->inversion-list 0 1000 0 501))
   (is inversion-list=?
       (range->inversion-list 0 1000 500 501))))

(define-test-case intersection/5 inversion-lists-tests
  (check-that
   (inversion-list-intersection (range->inversion-list 0 1000 500 1000)
				(range->inversion-list 0 1000 501 505))
   (is inversion-list=?
       (range->inversion-list 0 1000 501 505))))

(define-test-case adjoin inversion-lists-tests
  (check-that
   (inversion-list-adjoin (range->inversion-list 0 1000 0 999) 999)
   (is inversion-list=?
       (range->inversion-list 0 1000 0 1000))))

(define-test-case remove inversion-lists-tests
  (check-that
   (inversion-list-remove (range->inversion-list 0 1000 0 1000) 999)
   (is inversion-list=?
       (range->inversion-list 0 1000 0 999))))

(define-test-case size inversion-lists-tests
  (s48-check
   (inversion-list-size
    (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)))
   => 510))

(define-test-case copy inversion-lists-tests
  (check-that
   (inversion-list-copy
    (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)))
   (is inversion-list=?
       (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)))))

(define-test-case fold/done? inversion-lists-tests
  (s48-check
   (inversion-list-fold/done?
    (lambda (n sum)
      (+ n sum))
    0
    (lambda (sum)
      (> sum 250000))
    (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)))
   =>
   250781))

(define (i-list-sum i-list)
  (let loop ((cursor (inversion-list-cursor i-list))
	     (sum 0))
    (if (inversion-list-cursor-at-end? cursor)
	sum
	(loop (inversion-list-cursor-next i-list cursor)
	      (+ (inversion-list-cursor-ref cursor)
		 sum)))))
    
(define-test-case cursor inversion-lists-tests
  (s48-check
   (i-list-sum (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)))
   => 374870))

(define-test-case hash inversion-lists-tests 
  (check-that
   (inversion-list-hash (ranges->inversion-list 0 1000 '(5 . 10) '(15 . 20) '(500 . 1000)) 1031)
   (opposite (is =
		 (inversion-list-hash (ranges->inversion-list 0 1000 '(5 . 10) '(500 . 1000)) 1031)))))

;;; ———————————————— SRFI 14（srfi-14-check.scm）————————————————
; Part of Scheme 48 1.9.  See file COPYING for notices and license.

; Authors: Mike Sperber, Olin Shivers

; SRFI 14 test suite

;; adapted from Olin's test suite
(define (vowel? c)
  (member c '(#\a #\e #\i #\o #\u)))

(define-test-suite srfi-14-tests)

(define-test-case char-set? srfi-14-tests
  (s48-check (not (char-set? 5)))
  (s48-check (char-set? (char-set #\a #\e #\i #\o #\u))))

(define-test-case char-set= srfi-14-tests
  (s48-check (char-set=))
  (s48-check (char-set= (char-set)))
  (s48-check (string->char-set "ioeauaiii")
	 (=> char-set=)
	 (char-set #\a #\e #\i #\o #\u))
  (s48-check (not (char-set= (string->char-set "ioeauaiii")
			 (char-set #\e #\i #\o #\u)))))

(define-test-case char-set<= srfi-14-tests
  (s48-check (char-set<=))
  (s48-check (char-set<= (char-set)))
  (s48-check (char-set<= (char-set #\a #\e #\i #\o #\u)
		     (string->char-set "ioeauaiii")))
  (s48-check (char-set<= (char-set #\e #\i #\o #\u)
		     (string->char-set "ioeauaiii"))))

(define-test-case char-set-hash srfi-14-tests
  (check-that (char-set-hash char-set:graphic 100)
	      (all-of (is (lambda (x) (>= x 0)))
		      (is (lambda (x) (<= x 99))))))

(define-test-case char-set-fold srfi-14-tests
  (s48-check (char-set-fold (lambda (c i) (+ i 1)) 0
			(char-set #\e #\i #\o #\u #\e #\e))
	 => 4))

; The following test is ASCII/Latin-1 only, and fails with Unicode
; (char-set= (string->char-set "eiaou2468013579999")
;            (char-set-unfold null? car cdr '(#\a #\e #\i #\o #\u #\u #\u)
;                             char-set:digit))

(define-test-case char-set-unfold srfi-14-tests
  (check-that (char-set-unfold null? car cdr '(#\a #\e #\i #\o #\u)
			  (string->char-set "0123456789"))
	      (is char-set=
		  (string->char-set "eiaou246801357999"))))

(define-test-case char-set-unfold! srfi-14-tests
  (check-that (char-set-unfold! null? car cdr '(#\a #\e #\i #\o #\u)
				(string->char-set "0123456789"))
	      (opposite (is char-set= 
			    (string->char-set "eiaou246801357")))))

(define-test-case char-set-for-each srfi-14-tests
  (let ((cs (string->char-set "0123456789")))
    (char-set-for-each (lambda (c) (set! cs (char-set-delete cs c)))
		       (string->char-set "02468000"))
    (check-that cs (is char-set= (string->char-set "97531"))))

  (let ((cs (string->char-set "0123456789")))
    (char-set-for-each (lambda (c) (set! cs (char-set-delete cs c)))
		       (string->char-set "02468"))
    (check-that cs (opposite (is char-set= (string->char-set "7531"))))))

(define-test-case char-set-map srfi-14-tests
  (check-that (char-set-map char-upcase (string->char-set "aeiou"))
	      (is char-set=
		  (string->char-set "IOUAEEEE")))
  (check-that (char-set-map char-upcase (string->char-set "aeiou"))
	      (opposite (is char-set= 
			    (string->char-set "OUAEEEE")))))

(define-test-case char-set-copy srfi-14-tests
  (check-that (char-set-copy (string->char-set "aeiou"))
	      (is char-set= (string->char-set "aeiou"))))

(define-test-case char-set srfi-14-tests
  (check-that (char-set #\x #\y) (is char-set= (string->char-set "xy")))
  (check-that (char-set #\x #\y #\z) (opposite (is char-set= (string->char-set "xy")))))

(define-test-case list->char-set srfi-14-tests
  (check-that (list->char-set '(#\x #\y)) (is char-set= (string->char-set "xy")))
  (check-that (list->char-set '(#\x #\y)) (opposite (is char-set= (string->char-set "axy"))))
  (check-that (list->char-set '(#\x #\y) (string->char-set "12345"))
	      (is char-set= (string->char-set "xy12345")))
  (check-that (list->char-set '(#\x #\y) (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "y12345")))))

(define-test-case list->char-set! srfi-14-tests
  (check-that (list->char-set! '(#\x #\y) (string->char-set "12345"))
	      (is char-set= (string->char-set "xy12345")))
  (check-that (list->char-set! '(#\x #\y) (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "y12345")))))

(define-test-case char-set-filter srfi-14-tests
  (check-that (char-set-filter vowel? char-set:ascii (string->char-set "12345"))
	      (is char-set= (string->char-set "aeiou12345")))
  (check-that (char-set-filter vowel? char-set:ascii (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "aeou12345")))))

(define-test-case char-set-filter! srfi-14-tests
  (check-that (char-set-filter! vowel? char-set:ascii (string->char-set "12345"))
	      (is char-set= (string->char-set "aeiou12345")))
  (check-that (char-set-filter! vowel? char-set:ascii (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "aeou12345")))))

(define-test-case ucs-range->char-set srfi-14-tests
  (check-that (ucs-range->char-set 97 103 #t (string->char-set "12345"))
	      (is char-set= (string->char-set "abcdef12345")))
  (check-that (ucs-range->char-set 97 103 #t (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "abcef12345")))))

(define-test-case ucs-range_>char-set! srfi-14-tests
  (check-that (ucs-range->char-set! 97 103 #t (string->char-set "12345"))
	      (is char-set= (string->char-set "abcdef12345")))
  (check-that (ucs-range->char-set! 97 103 #t (string->char-set "12345"))
	      (opposite (is char-set= (string->char-set "abcef12345")))))

(define-test-case x->char-set srfi-14-tests
  (check-that (x->char-set #\x) (is char-set= (x->char-set "x")))
  (check-that (x->char-set #\x) (is char-set= (x->char-set (char-set #\x))))
  (check-that (x->char-set "y")
	      (opposite (is char-set= (x->char-set #\x)))))

(define-test-case char-set-size srfi-14-tests
  (s48-check (char-set-size (char-set-intersection char-set:ascii char-set:digit))
	 => 10))

(define-test-case char-set-count srfi-14-tests
  (s48-check (char-set-count vowel? char-set:ascii)
	 => 5))

(define-test-case char-set->list srfi-14-tests
  (s48-check (char-set->list (char-set #\x)) => '(#\x))
  (check-that (char-set->list (char-set #\x)) (opposite (is '(#\X)))))

(define-test-case char-set->string srfi-14-tests
  (s48-check (char-set->string (char-set #\x)) => "x")
  (check-that (char-set->string (char-set #\x)) (opposite (is "X" ))))

(define-test-case char-set-contains? srfi-14-tests
  (s48-check (char-set-contains? (x->char-set "xyz") #\x))
  (s48-check (not (char-set-contains? (x->char-set "xyz") #\a))))

(define-test-case char-set-every srfi-14-tests
  (s48-check (char-set-every char-lower-case? (x->char-set "abcd")))
  (check-that (char-set-every char-lower-case? (x->char-set "abcD")) (is-false)))

(define-test-case char-set-any srfi-14-tests
  (s48-check (char-set-any char-lower-case? (x->char-set "abcd")))
  (check-that (char-set-any char-lower-case? (x->char-set "ABCD")) (is-false)))

(define-test-case cursors srfi-14-tests
  (check-that
   (let ((cs (x->char-set "abcd")))
     (let lp ((cur (char-set-cursor cs)) (ans '()))
       (if (end-of-char-set? cur) (list->char-set ans)
	   (lp (char-set-cursor-next cs cur)
	       (cons (char-upcase (char-set-ref cs cur)) ans)))))
   (is char-set=
       (x->char-set "ABCD"))))

(define-test-case char-set-adjoin srfi-14-tests
  (check-that (char-set-adjoin (x->char-set "123") #\x #\a)
	      (is char-set= (x->char-set "123xa")))
  (check-that (x->char-set "123x")
	      (opposite (is char-set= (char-set-adjoin (x->char-set "123") #\x #\a)))))

(define-test-case char-set-adjoin! srfi-14-tests
  (check-that (char-set-adjoin! (x->char-set "123") #\x #\a)
	      (is char-set= (x->char-set "123xa")))
  (check-that (x->char-set "123x")
	      (opposite (is char-set= (char-set-adjoin! (x->char-set "123") #\x #\a)))))

(define-test-case char-set-delete srfi-14-tests
  (check-that (char-set-delete (x->char-set "123") #\2 #\a #\2)
	      (is char-set= (x->char-set "13")))
  (check-that (char-set-delete (x->char-set "123") #\2 #\a #\2)
	      (opposite (is char-set= (x->char-set "13a")))))

(define-test-case char-set-delete! srfi-14-tests
  (check-that (char-set-delete! (x->char-set "123") #\2 #\a #\2)
	      (is char-set= (x->char-set "13")))
  (check-that (char-set-delete! (x->char-set "123") #\2 #\a #\2)
	      (opposite (is char-set= (x->char-set "13a")))))

(define-test-case char-set-intersection srfi-14-tests
  (check-that
   (char-set-intersection char-set:hex-digit (char-set-complement char-set:digit))
   (is char-set=
       (x->char-set "abcdefABCDEF"))))

(define-test-case char-set-intersection! srfi-14-tests
  (check-that
   (char-set-intersection! (char-set-complement! (x->char-set "0123456789"))
			   char-set:hex-digit)
   (is char-set=
       (x->char-set "abcdefABCDEF"))))

(define-test-case char-set-union srfi-14-tests
  (check-that
   (char-set-union char-set:hex-digit
		   (x->char-set "abcdefghijkl"))
   (is char-set=
       (x->char-set "abcdefABCDEFghijkl0123456789"))))

(define-test-case char-set-union! srfi-14-tests
  (check-that
   (char-set-union! (x->char-set "abcdefghijkl")
		    char-set:hex-digit)
   (is char-set=
       (x->char-set "abcdefABCDEFghijkl0123456789"))))

(define-test-case char-set-difference srfi-14-tests
  (check-that
   (char-set-difference (x->char-set "abcdefghijklmn")
			char-set:hex-digit)
   (is char-set=
       (x->char-set "ghijklmn"))))

(define-test-case char-set-difference! srfi-14-tests
  (check-that
   (char-set-difference! (x->char-set "abcdefghijklmn")
			 char-set:hex-digit)
   (is char-set=
       (x->char-set "ghijklmn"))))

(define-test-case char-set-xor srfi-14-tests
  (check-that
   (char-set-xor (x->char-set "0123456789")
		 char-set:hex-digit)
   (is char-set=
       (x->char-set "abcdefABCDEF"))))

(define-test-case char-set-xor! srfi-14-tests char-set=
  (check-that (char-set-xor! (x->char-set "0123456789")
			     char-set:hex-digit)
	      (is char-set= (x->char-set "abcdefABCDEF"))))

(define-test-case char-set-diff+intersection srfi-14-tests
  (call-with-values (lambda ()
		      (char-set-diff+intersection char-set:hex-digit
						  char-set:letter))
    (lambda (d i)
      (check-that d (is char-set= (x->char-set "0123456789")))
      (check-that i (is char-set= (x->char-set "abcdefABCDEF")))))
  (call-with-values (lambda ()
		      (char-set-diff+intersection (char-set-union char-set:letter
								  char-set:digit)
						  char-set:letter))
    (lambda (d i)
      (check-that d (is char-set= char-set:digit))
      (check-that i (is char-set= char-set:letter)))))

(define-test-case char-set-diff+intersection! srfi-14-tests
  (call-with-values (lambda ()
		      (char-set-diff+intersection! (char-set-copy char-set:hex-digit)
						   (char-set-copy char-set:letter)))
    (lambda (d i)
      (check-that d (is char-set= (x->char-set "0123456789")))
      (check-that i (is char-set= (x->char-set "abcdefABCDEF")))))
  (call-with-values (lambda ()
		      (char-set-diff+intersection! (char-set-union char-set:letter
								   char-set:digit)
						   (char-set-copy char-set:letter)))
    (lambda (d i)
      (check-that d (is char-set= char-set:digit))
      (check-that i (is char-set= char-set:letter)))))

; The following stuff was adapted from the suite Matthew Flatt wrote
; for PLT Scheme

(define-test-case char-set:lower-case srfi-14-tests
  (s48-check (char-set-contains? char-set:lower-case #\a))
  (s48-check (not (char-set-contains? char-set:lower-case #\A)))
  (s48-check (char-set-contains? char-set:lower-case (scalar-value->char #x00E0)))
  (s48-check (not (char-set-contains? char-set:lower-case (scalar-value->char #x00C2))))
  (s48-check (char-set-contains? char-set:lower-case (scalar-value->char #x00B5))))

(define-test-case char-set:upper-case srfi-14-tests
  (s48-check (char-set-contains? char-set:upper-case #\A))
  (s48-check (not (char-set-contains? char-set:upper-case #\a)))
  (s48-check (char-set-contains? char-set:upper-case (scalar-value->char #x00C2)))
  (s48-check (not (char-set-contains? char-set:upper-case (scalar-value->char #x00E0)))))

(define-test-case char-set:title-case srfi-14-tests
  (s48-check (char-set-contains? char-set:title-case (scalar-value->char #x01C5)))
  (s48-check (char-set-contains? char-set:title-case (scalar-value->char #x1FA8)))
  (s48-check (not (char-set-contains? char-set:title-case #\a)))
  (s48-check (not (char-set-contains? char-set:title-case #\A))))

(define-test-case char-set:letter srfi-14-tests
  (s48-check (char-set-contains? char-set:letter #\a))
  (s48-check (char-set-contains? char-set:letter #\A))
  (s48-check (not (char-set-contains? char-set:letter #\1)))
  (s48-check (char-set-contains? char-set:letter (scalar-value->char #x00AA)))
  (s48-check (char-set-contains? char-set:letter (scalar-value->char #x00BA))))

(define-test-case char-set:lower-case/2 srfi-14-tests
  (s48-check (not (char-set-every (lambda (c) (char-set-contains? char-set:lower-case c)) char-set:letter)))
  (s48-check (char-set-any (lambda (c) (char-set-contains? char-set:lower-case c)) char-set:letter)))

(define-test-case char-set:upper-case/2 srfi-14-tests
  (s48-check (not (char-set-every (lambda (c) (char-set-contains? char-set:upper-case c)) char-set:letter)))
  (s48-check (char-set-any (lambda (c) (char-set-contains? char-set:upper-case c)) char-set:letter)))

;; Not true?
;; (test #t char-set<= char-set:letter (char-set-union char-set:lower-case char-set:upper-case char-set:title-case))

(define-test-case char-set:digit srfi-14-tests
  (s48-check (char-set-contains? char-set:digit #\1))
  (s48-check (not (char-set-contains? char-set:digit #\a))))

(define-test-case char-set:hex-digit srfi-14-tests
  (s48-check (char-set-contains? char-set:hex-digit #\1))
  (s48-check (char-set-contains? char-set:hex-digit #\a))
  (s48-check (char-set-contains? char-set:hex-digit #\A))
  (s48-check (not (char-set-contains? char-set:hex-digit #\g))))

(define-test-case char-set:letter+digit srfi-14-tests equal?
  (s48-check (char-set-contains? char-set:letter+digit #\1))
  (s48-check (char-set-contains? char-set:letter+digit #\a))
  (s48-check (char-set-contains? char-set:letter+digit #\z))
  (s48-check (char-set-contains? char-set:letter+digit #\A))
  (s48-check (char-set-contains? char-set:letter+digit #\Z)))

;; 原期望 92496 是 Unicode 5.x 的字母数。iron-054 起字符集数据取自 .NET 的 Unicode 数据，
;; 改为与基础库 char-general-category 现场统计的结果比较（同时检查二者 Unicode 版本一致）。
(define (count-category cats)
  (let loop ((cp 0) (n 0))
    (cond ((> cp #x10FFFF) n)
          ((<= #xD800 cp #xDFFF) (loop (+ cp 1) n))
          ((memq (char-general-category (integer->char cp)) cats) (loop (+ cp 1) (+ n 1)))
          (else (loop (+ cp 1) n)))))

(define-test-case char-set:letter/size srfi-14-tests 
  (s48-check (char-set-size char-set:letter) => (count-category '(Lu Ll Lt Lm Lo))))

(define-test-case char-set:letter/2 srfi-14-tests
  (check-that (char-set-union char-set:letter char-set:digit) 
	      (is char-set=
		  char-set:letter+digit))
  (s48-check (not (char-set-every (lambda (c) (char-set-contains? char-set:letter c)) char-set:letter+digit)))
  (s48-check (not (char-set-every (lambda (c) (char-set-contains? char-set:digit c)) char-set:letter+digit)))
  (s48-check (char-set-any (lambda (c) (char-set-contains? char-set:letter c)) char-set:letter+digit)))

(define-test-case char-set:letter+digit/2 srfi-14-tests
  (s48-check (char-set-every (lambda (c) (char-set-contains? char-set:letter+digit c)) char-set:letter))
  (s48-check (char-set-every (lambda (c) (char-set-contains? char-set:letter+digit c)) char-set:digit)))

(define char-set:latin-1 (ucs-range->char-set 0 256))

(define-test-case char-set:latin-1 srfi-14-tests 
  (check-that
   (char-set-intersection (char-set-union char-set:letter char-set:digit char-set:punctuation char-set:symbol)
			  char-set:latin-1)
   (is char-set=
       (char-set-intersection char-set:graphic char-set:latin-1))))

(define-test-case char-set:printing srfi-14-tests
  (check-that (char-set-union char-set:graphic char-set:whitespace)
	      (is char-set= char-set:printing)))

(define-test-case char-set:whitespace srfi-14-tests
  (s48-check (char-set-contains? char-set:whitespace (scalar-value->char #x0009)))
  (s48-check (char-set-contains? char-set:whitespace (scalar-value->char #x000D)))
  (s48-check (not (char-set-contains? char-set:whitespace #\a))))

(define-test-case char-set:iso-control srfi-14-tests
  (check-that (char-set-union (ucs-range->char-set #x0000 #x0020)
			      (ucs-range->char-set #x007F #x00A0)) 
	      (is char-set=
		  char-set:iso-control)))

(define-test-case char-set:punctuation srfi-14-tests 
  (s48-check (char-set-contains? char-set:punctuation #\!))
  (s48-check (char-set-contains? char-set:punctuation (scalar-value->char #x00A1)))
  (s48-check (not (char-set-contains? char-set:punctuation #\a))))

(define-test-case char-set:symbol srfi-14-tests
  (s48-check (char-set-contains? char-set:symbol #\$))
  (s48-check (char-set-contains? char-set:symbol (scalar-value->char #x00A2)))
  (s48-check (not (char-set-contains? char-set:symbol #\a))))

(define-test-case char-set:blank srfi-14-tests
  (s48-check (char-set-contains?  char-set:blank #\space))
  (s48-check (char-set-contains?  char-set:blank (scalar-value->char #x3000)))
  (s48-check (not (char-set-contains?  char-set:blank #\a))))

;; General procedures ----------------------------------------

(define-test-case char-set=/2 srfi-14-tests
  (s48-check (char-set= char-set:letter char-set:letter char-set:letter))
  (s48-check (not (char-set= char-set:letter char-set:digit)))
  (s48-check (not (char-set= char-set:letter char-set:letter char-set:digit)))
  (s48-check (not (char-set= char-set:letter char-set:digit char-set:letter))))

(define-test-case char-set<=/2 srfi-14-tests
  (s48-check (char-set<= char-set:graphic char-set:printing))
  (s48-check (not (char-set<= char-set:printing char-set:graphic)))
  (s48-check (char-set<= char-set:graphic char-set:printing char-set:full))
  (s48-check (not (char-set<= char-set:graphic char-set:full char-set:printing))))

(define-test-case char-set-hash/2 srfi-14-tests
  (s48-check (char-set-hash char-set:graphic)
	 =>
	 (char-set-hash char-set:graphic)))

;; Iterating over character sets ----------------------------------------

;; 原期望 290 来自 "grep Nd UnicodeData.txt | wc -l"（Unicode 5.x）；同上改为现场统计 Nd 的个数。
(define-test-case char-set-size/2 srfi-14-tests
  (s48-check (char-set-size char-set:digit)
	 => (count-category '(Nd))))

(define-test-case cursors/2 srfi-14-tests
  (check-that (list->char-set
	       (let loop ((c (char-set-cursor char-set:digit)) (l '()))
		 (if (end-of-char-set? c)
		     l
		     (loop (char-set-cursor-next char-set:digit c)
			   (cons (char-set-ref char-set:digit c)
				 l)))))
	      (is char-set= char-set:digit)))

(define (add1 x) (+ 1 x))

(define-test-case char-set-unfold/2 srfi-14-tests
  (check-that
   (char-set-unfold (lambda (x) (= x 20)) scalar-value->char add1 10)
   (is char-set= (ucs-range->char-set 10 20)))
  (check-that
   (char-set-unfold (lambda (x) (= x 20)) scalar-value->char add1 10 (char-set (scalar-value->char #x14)))
   (is char-set=
       (ucs-range->char-set 10 21))))

(define-test-case char-set-unfold!/2 srfi-14-tests
  (check-that
   (char-set-unfold! (lambda (x) (= x 20)) scalar-value->char add1 10
		     (char-set-copy char-set:empty))
   (is char-set= (ucs-range->char-set 10 20))))

(define-test-case char-set-for-each/2 srfi-14-tests
  (check-that
   (let ((cs char-set:empty))
     (char-set-for-each 
      (lambda (c) 
	(set! cs (char-set-adjoin cs c)))
      char-set:digit)
     cs)
   (is char-set= char-set:digit)))

(define-test-case char-set-map/2 srfi-14-tests equal?
  (check-that (char-set-map
	       (lambda (c) c)
	       char-set:digit)
	      (is char-set= char-set:digit))
  (check-that (char-set-map
	       (lambda (c) c)
	       char-set:digit)
	      (is char-set= char-set:digit))
  (check-that (char-set-union
	       (char-set-map
		(lambda (c) c)
		char-set:digit)
	       (char-set #\A))
	      (is char-set= (char-set-adjoin char-set:digit #\A))))

;; Creating character sets ----------------------------------------

(define-test-case char-set-copy/2 srfi-14-tests
  (check-that (char-set-copy char-set:digit)
	      (is char-set= char-set:digit)))

(define-test-case abc srfi-14-tests
  (let ((abc (char-set #\a #\b #\c)))
    (check-that (char-set #\c #\a #\b)
		(is char-set=
		    abc))
    (check-that (string->char-set "cba") (is char-set= abc))
    (check-that (string->char-set! "cba" (char-set-copy char-set:empty)) (is char-set= abc))
    (check-that (string->char-set "cb" (char-set #\a)) (is char-set= abc))
    (check-that (char-set-filter (lambda (c) (char=? c #\b)) abc) (is char-set= (char-set #\b)))
    (check-that (char-set-filter (lambda (c) (char=? c #\b)) abc char-set:empty) (is char-set= (char-set #\b)))
    (check-that (char-set-filter! (lambda (c) (char=? c #\b)) (char-set-copy abc) (char-set-copy char-set:empty))
		(is char-set= (char-set #\b)))

    (check-that (x->char-set "abc") (is char-set= abc))
    (check-that (x->char-set abc) (is char-set= abc))
    (check-that (x->char-set #\a) (is char-set= (char-set #\a)))))

(define-test-case ucs-range->char/2 srfi-14-tests
  (check-that
   (char-set-union (ucs-range->char-set 0 #xD800)
		   (ucs-range->char-set #xE000 #x20000))
   (is char-set= (ucs-range->char-set 0 #x20000)))
  (check-that
   (ucs-range->char-set 0 #xD800)
   (is char-set= (ucs-range->char-set 0 #xD801)))
  (check-that
   (ucs-range->char-set 0 #xD800)
   (is char-set= (ucs-range->char-set 0 #xDFFF)))
  (check-that
   char-set:empty
   (is char-set= (ucs-range->char-set #xD800 #xD810)))
  (check-that
   char-set:empty
   (is char-set= (ucs-range->char-set #xD810 #xE000)))
  (check-that
   (ucs-range->char-set #xD810 #xE001)
   (is char-set= (ucs-range->char-set #xE000 #xE001)))
  (check-that
   (char-set (scalar-value->char #xD7FF) (scalar-value->char #xE000))
   (is char-set= (ucs-range->char-set #xD7FF #xE001))))

;; Querying character sets ------------------------------

(define-test-case char-set-count/2 srfi-14-tests
  (s48-check
   (char-set-count (lambda (x)
		     (and (char<=? #\0 x)
			  (char<=? x #\2)))
		   char-set:digit)
   => 3))

(define-test-case list->char-set/2 srfi-14-tests
  (check-that (list->char-set (char-set->list char-set:digit))
	      (is char-set= char-set:digit))
  (check-that (list->char-set (char-set->list char-set:digit) char-set:empty)
	      (is char-set= char-set:digit))
  (check-that (list->char-set! (char-set->list char-set:digit) (char-set-copy char-set:empty))
	      (is char-set= char-set:digit))
;; iron-042 时字符串为 UTF-16，BMP 之外的数字往返后变成代理对，曾只比较 BMP 部分；
  ;; iron-055 起字符串按码点，恢复原项。
  (check-that (string->char-set (char-set->string char-set:digit))
	      (is char-set= char-set:digit)))



(check-report "std char-sets")
