;;; (ironscheme std time) 的测试（designs/08-std-library.md D8）。改写自 chez-srfi 的 tests/time.sps：
;;; SRFI 19 参照测试集（srfi-19-test-suite.scm，Will Fitzgerald）的 8 组测试各计一项；原测试中只打印的
;;; date->string 格式演示改为对固定日期逐个格式检查结果；另按 SRFI 19 文本补写其余导出名的测试。
(import (rnrs) (rnrs mutable-pairs) (only (ironscheme) include) (ironscheme std time))
(include "tests/std/check.ss")

;;; simple test procedures


(define s19-tests (list))

(define (define-s19-test! name thunk)
  (let ((name (if (symbol? name) name (string->symbol name)))
	(pr (assoc name s19-tests)))
    (if pr
	(set-cdr! pr thunk)
	(set! s19-tests (append s19-tests (list (cons name thunk)))))))

(define (run-s19-test name thunk verbose)
  (if verbose (begin (display ";;; Running ") (display name)))
  (let ((result (thunk)))
    (if verbose (begin (display ": ") (display (not (not result))) (newline)))
    (check (if result #t name) => #t)
    result))

(define (run-s19-tests . verbose)
  (let ((runs 0) (goods 0) (bads 0) (verbose (if (cdr verbose) (cdr verbose) #f)))
    (for-each (lambda (pr)
		(set! runs (+ runs 1))
		(if (run-s19-test (car pr) (cdr pr) verbose)
		    (set! goods (+ goods 1))
		    (set! bads (+ bads 1))))
	      s19-tests)
    (if verbose
	(begin
	  (display ";;; Results: Runs: ")
	  (display runs)
	  (display "; Goods: ")
	  (display goods)
	  (display "; Bads: ")
	  (display bads)
	  (if (> runs 0)
	      (begin
		(display "; Pass rate: ")
		(display (/ goods runs)))
	      (display "; No tests."))
	  (newline)))
    (values runs goods bads)))

(set! s19-tests (list))

(define-s19-test! "Creating time structures"
  (lambda ()
    (not (null? (list (current-time 'time-tai)
		      (current-time 'time-utc)
		      (current-time 'time-monotonic)
		      (current-time 'time-thread)
		      (current-time 'time-process))))))

(define-s19-test! "Testing time resolutions"
  (lambda ()
    (not (null? (list (time-resolution 'time-tai)
		      (time-resolution 'time-utc)
		      (time-resolution 'time-monotonic)
		      (time-resolution 'time-thread)
		      (time-resolution 'time-process))))))

(define-s19-test! "Time comparisons (time=?, etc.)"
  (lambda ()
    (let ((t1 (make-time 'time-utc 0 1))
	  (t2 (make-time 'time-utc 0 1))
	  (t3 (make-time 'time-utc 0 2))
	  (t11 (make-time 'time-utc 1001 1))
	  (t12 (make-time 'time-utc 1001 1))
	  (t13 (make-time 'time-utc 1001 2))
	  )
      (and (time=? t1 t2)
	   (time>? t3 t2)
	   (time<? t2 t3)
	   (time>=? t1 t2)
	   (time>=? t3 t2)
	   (time<=? t1 t2)
	   (time<=? t2 t3)
	   (time=? t11 t12)
	   (time>? t13 t12)
	   (time<? t12 t13)
	   (time>=? t11 t12)
	   (time>=? t13 t12)
	   (time<=? t11 t12)
	   (time<=? t12 t13)
	   ))))

(define-s19-test! "Time difference"
  (lambda ()
    (let ((t1 (make-time 'time-utc 0 3000))
	  (t2 (make-time 'time-utc 0 1000))
	  (t3 (make-time 'time-duration 0 2000))
	  (t4 (make-time 'time-duration 0 -2000)))
      (and
       (time=? t3 (time-difference t1 t2))
       (time=? t4 (time-difference t2 t1))))))


(define (test-one-utc-tai-edge utc tai-diff tai-last-diff)
  (let* (;; right on the edge they should be the same
	 (utc-basic (make-time 'time-utc 0 utc))
	 (tai-basic (make-time 'time-tai 0 (+ utc tai-diff)))
	 (utc->tai-basic (time-utc->time-tai utc-basic))
	 (tai->utc-basic (time-tai->time-utc tai-basic))
	 ;; a second before they should be the old diff
	 (utc-basic-1 (make-time 'time-utc 0 (- utc 1)))
	 (tai-basic-1 (make-time 'time-tai 0 (- (+ utc tai-last-diff) 1)))
	 (utc->tai-basic-1 (time-utc->time-tai utc-basic-1))
	 (tai->utc-basic-1 (time-tai->time-utc tai-basic-1))
	 ;; a second later they should be the new diff
	 (utc-basic+1 (make-time 'time-utc 0 (+ utc 1)))
	 (tai-basic+1 (make-time 'time-tai 0 (+ (+ utc tai-diff) 1)))
	 (utc->tai-basic+1 (time-utc->time-tai utc-basic+1))
	 (tai->utc-basic+1 (time-tai->time-utc tai-basic+1))
	 ;; ok, let's move the clock half a month or so plus half a second
	 (shy (* 15 24 60 60))
	 (hs (/ (expt 10 9) 2))
	 ;; a second later they should be the new diff
	 (utc-basic+2 (make-time 'time-utc hs (+ utc shy)))
	 (tai-basic+2 (make-time 'time-tai hs (+ (+ utc tai-diff) shy)))
	 (utc->tai-basic+2 (time-utc->time-tai utc-basic+2))
	 (tai->utc-basic+2 (time-tai->time-utc tai-basic+2))
	 )
    (and (time=? utc-basic tai->utc-basic)
	 (time=? tai-basic utc->tai-basic)
	 (time=? utc-basic-1 tai->utc-basic-1)
	 (time=? tai-basic-1 utc->tai-basic-1)
	 (time=? utc-basic+1 tai->utc-basic+1)
	 (time=? tai-basic+1 utc->tai-basic+1)
	 (time=? utc-basic+2 tai->utc-basic+2)
	 (time=? tai-basic+2 utc->tai-basic+2) 
	 )))

(define-s19-test! "TAI-UTC Conversions"
  (lambda ()
    (and
     (test-one-utc-tai-edge 915148800  32 31)
     (test-one-utc-tai-edge 867715200  31 30)
     (test-one-utc-tai-edge 820454400  30 29)
     (test-one-utc-tai-edge 773020800  29 28)
     (test-one-utc-tai-edge 741484800  28 27)
     (test-one-utc-tai-edge 709948800  27 26)
     (test-one-utc-tai-edge 662688000  26 25)
     (test-one-utc-tai-edge 631152000  25 24)
     (test-one-utc-tai-edge 567993600  24 23)
     (test-one-utc-tai-edge 489024000  23 22)
     (test-one-utc-tai-edge 425865600  22 21)
     (test-one-utc-tai-edge 394329600  21 20)
     (test-one-utc-tai-edge 362793600  20 19)
     (test-one-utc-tai-edge 315532800  19 18)
     (test-one-utc-tai-edge 283996800  18 17)
     (test-one-utc-tai-edge 252460800  17 16)
     (test-one-utc-tai-edge 220924800  16 15)
     (test-one-utc-tai-edge 189302400  15 14)
     (test-one-utc-tai-edge 157766400  14 13)
     (test-one-utc-tai-edge 126230400  13 12)
     (test-one-utc-tai-edge 94694400   12 11)
     (test-one-utc-tai-edge 78796800   11 10)
     (test-one-utc-tai-edge 63072000   10 0)
     (test-one-utc-tai-edge 0   0 0) ;; at the epoch
     (test-one-utc-tai-edge 10   0 0) ;; close to it ...
     (test-one-utc-tai-edge 1045789645 32 32) ;; about now ...
     )))

(define (tm:date= d1 d2)
  (and (= (date-year d1) (date-year d2))
       (= (date-month d1) (date-month d2))
       (= (date-day d1) (date-day d2))
       (= (date-hour d1) (date-hour d2))
       (= (date-second d1) (date-second d2))
       (= (date-nanosecond d1) (date-nanosecond d2))
       (= (date-zone-offset d1) (date-zone-offset d2))))

(define-s19-test! "TAI-Date Conversions"
  (lambda ()
    (and
     (tm:date= (time-tai->date (make-time time-tai 0 (+ 915148800 29)) 0)
	       (make-date 0 58 59 23 31 12 1998 0))
     (tm:date= (time-tai->date (make-time time-tai 0 (+ 915148800 30)) 0)
	       (make-date 0 59 59 23 31 12 1998 0))
     (tm:date= (time-tai->date (make-time time-tai 0 (+ 915148800 31)) 0)
	       (make-date 0 60 59 23 31 12 1998 0))
     (tm:date= (time-tai->date (make-time time-tai 0 (+ 915148800 32)) 0)
	       (make-date 0 0 0 0 1 1 1999 0)))))

(define-s19-test! "Date-UTC Conversions"
  (lambda ()
    (and
     (time=? (make-time time-utc 0 (- 915148800 2))
	     (date->time-utc (make-date 0 58 59 23 31 12 1998 0)))
     (time=? (make-time time-utc 0 (- 915148800 1))
	     (date->time-utc (make-date 0 59 59 23 31 12 1998 0)))
     ;; yes, I think this is acutally right.
     (time=? (make-time time-utc 0 (- 915148800 0))
	     (date->time-utc (make-date 0 60 59 23 31 12 1998 0)))
     (time=? (make-time time-utc 0 (- 915148800 0))
	     (date->time-utc (make-date 0 0 0 0 1 1 1999 0)))
     (time=? (make-time time-utc 0 (+ 915148800 1))
	     (date->time-utc (make-date 0 1 0 0 1 1 1999 0))))))

(define-s19-test! "TZ Offset conversions"
  (lambda ()
    (let ((ct-utc (make-time time-utc 6320000 1045944859))
	  (ct-tai (make-time time-tai 6320000 1045944891))
	  (cd (make-date 6320000 19 14 15 22 2 2003 -18000)))
      (and
       (time=? ct-utc (date->time-utc cd))
       (time=? ct-tai (date->time-tai cd))))))

(begin (newline) (run-s19-tests #t))

;;; ———————————————— date->string：固定日期逐个格式 ————————————————
;; 2026-10-09 星期五 11:04:09.123456789，时区 +08:00
(define d (make-date 123456789 9 4 11 9 10 2026 28800))
(for-each
  (lambda (f+r) (check (date->string d (car f+r)) => (cdr f+r)))
  '(("~~" . "~") ("~a" . "Fri") ("~A" . "Friday") ("~b" . "Oct") ("~B" . "October")
    ("~d" . "09") ("~D" . "10/09/26") ("~e" . " 9") ("~h" . "Oct") ("~H" . "11") ("~I" . "11")
    ("~j" . "282") ("~k" . "11") ("~l" . "11") ("~m" . "10") ("~M" . "04") ("~n" . "\n")
    ("~N" . "123456789") ("~p" . "AM") ("~S" . "09") ("~t" . "\t") ("~T" . "11:04:09")
    ("~w" . "5") ("~y" . "26") ("~Y" . "2026") ("~z" . "+0800")
    ("~1" . "2026-10-09") ("~2" . "11:04:09+0800") ("~3" . "11:04:09") ("~4" . "2026-10-09T11:04:09+0800")
    ("~5" . "2026-10-09T11:04:09")))
;; 其余格式（依赖区域习惯或参照实现的细节）只检查能产生字符串
(for-each
  (lambda (f) (check (string? (date->string d f)) => #t))
  '("~c" "~f" "~r" "~s" "~U" "~V" "~W" "~x" "~X" "~Z"))
(check (date->string d) => (date->string d "~c"))

;;; ———————————————— string->date ————————————————
(define d2 (string->date "2026-10-09 11:04:09" "~Y-~m-~d ~H:~M:~S"))
(check (list (date-year d2) (date-month d2) (date-day d2) (date-hour d2) (date-minute d2) (date-second d2))
       => '(2026 10 9 11 4 9))

;;; ———————————————— 时间对象 ————————————————
(define t (make-time time-utc 500 1000))
(check (time? t) => #t)
(check (time? 5) => #f)
(check (time-type t) => time-utc)
(check (list (time-second t) (time-nanosecond t)) => '(1000 500))
(define t* (copy-time t))
(check (begin (set-time-second! t* 2000) (set-time-nanosecond! t* 7) (set-time-type! t* time-tai)
              (list (time-second t) (time-second t*) (time-nanosecond t*) (time-type t*)))
       => (list 1000 2000 7 time-tai))
(check (list time-duration time-monotonic time-process time-tai time-thread time-utc)
       => '(time-duration time-monotonic time-process time-tai time-thread time-utc))
(check (time-resolution) => 100)
(check (time? (current-time)) => #t)
(check (time-type (current-time time-monotonic)) => time-monotonic)

;; 时长运算
(define dur (make-time time-duration 0 10))
(check (time-second (add-duration t dur)) => 1010)
(check (time-second (subtract-duration t dur)) => 990)
(check (let ((x (copy-time t))) (add-duration! x dur) (time-second x)) => 1010)
(check (let ((x (copy-time t))) (subtract-duration! x dur) (time-second x)) => 990)
(check (time-second (time-difference (make-time time-utc 0 30) (make-time time-utc 0 10))) => 20)
(check (let ((x (make-time time-utc 0 30))) (time-type (time-difference! x (make-time time-utc 0 10)))) => time-duration)

;;; ———————————————— 日期 ————————————————
(check (date? d) => #t)
(check (list (date-nanosecond d) (date-second d) (date-minute d) (date-hour d) (date-day d)
             (date-month d) (date-year d) (date-zone-offset d))
       => '(123456789 9 4 11 9 10 2026 28800))
(check (date-year-day d) => 282)
(check (date-week-day d) => 5)
(check (date-week-number d 0) => 39)                  ; 不计年初不满一周的部分（2026-01-04 是第一个星期日）
(check (date? (current-date)) => #t)
(check (date-zone-offset (current-date 0)) => 0)

;;; ———————————————— 儒略日与各种换算 ————————————————
;; 1970-01-01T00:00:00Z：儒略日 2440587.5，修正儒略日 40587
(define epoch (make-date 0 0 0 0 1 1 1970 0))
(check (date->julian-day epoch) => 4881175/2)
(check (date->modified-julian-day epoch) => 40587)
(check (date->julian-day (make-date 0 0 0 8 1 1 1970 28800)) => 4881175/2)   ; 同一时刻，东八区
(check (date->julian-day (make-date 0 0 0 12 1 1 1970 0)) => 2440588)
(check (time-second (date->time-utc epoch)) => 0)
(check (time-second (date->time-tai epoch)) => 0)                 ; 1972 年前 TAI-UTC 按 0 计
(check (time-type (date->time-monotonic epoch)) => time-monotonic)
(check (date-year (julian-day->date 4881175/2 0)) => 1970)
(check (time-second (julian-day->time-utc 4881175/2)) => 0)
(check (time-type (julian-day->time-tai 4881175/2)) => time-tai)
(check (time-type (julian-day->time-monotonic 4881175/2)) => time-monotonic)
(check (date-year (modified-julian-day->date 40587 0)) => 1970)
(check (time-second (modified-julian-day->time-utc 40587)) => 0)
(check (time-type (modified-julian-day->time-tai 40587)) => time-tai)
(check (time-type (modified-julian-day->time-monotonic 40587)) => time-monotonic)
(check (number? (current-julian-day)) => #t)
(check (number? (current-modified-julian-day)) => #t)

(define utc0 (make-time time-utc 0 0))
(check (time-utc->julian-day utc0) => 4881175/2)
(check (time-utc->modified-julian-day utc0) => 40587)
(check (date-year (time-utc->date utc0 0)) => 1970)
(check (time-type (time-utc->time-tai utc0)) => time-tai)
(check (time-type (time-utc->time-monotonic utc0)) => time-monotonic)
(check (let ((x (copy-time utc0))) (time-utc->time-tai! x) (time-type x)) => time-tai)
(check (let ((x (copy-time utc0))) (time-utc->time-monotonic! x) (time-type x)) => time-monotonic)

;; 2017-01-01 起 TAI-UTC = 37 秒
(define tai (make-time time-tai 0 (+ 1483228800 37)))
(check (time-second (time-tai->time-utc tai)) => 1483228800)
(check (let ((x (copy-time tai))) (time-tai->time-utc! x) (time-second x)) => 1483228800)
(check (time-type (time-tai->time-monotonic tai)) => time-monotonic)
(check (let ((x (copy-time tai))) (time-tai->time-monotonic! x) (time-type x)) => time-monotonic)
(check (date-year (time-tai->date tai 0)) => 2017)
(check (time-tai->modified-julian-day tai) => 57754)
(check (time-tai->julian-day tai) => 4915509/2)            ; 2457754.5

(define mono (time-utc->time-monotonic (make-time time-utc 0 1483228800)))
(check (time-second (time-monotonic->time-utc mono)) => 1483228800)
(check (let ((x (copy-time mono))) (time-monotonic->time-utc! x) (time-second x)) => 1483228800)
(check (time-type (time-monotonic->time-tai mono)) => time-tai)
(check (let ((x (copy-time mono))) (time-monotonic->time-tai! x) (time-type x)) => time-tai)
(check (date-year (time-monotonic->date mono 0)) => 2017)
(check (time-monotonic->modified-julian-day mono) => 57754)
(check (time-monotonic->julian-day mono) => 4915509/2)

(check-report "std time")
