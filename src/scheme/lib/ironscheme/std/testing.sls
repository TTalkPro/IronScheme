#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std testing) —— 测试框架（designs/08-std-library.md）
;;; 词源：SRFI 64（Per Bothner）为主，test-begin / test-assert / test-equal … 与测试运行器；
;;;       SRFI 78（Sebastian Egner）的轻量检查 check / check-ec / check-report / check-set-mode! /
;;;       check-reset! / check-passed?。两者没有同名的过程（D3），一并导出。
;;; 实现：SRFI 64 参照实现 Copyright (c) 2005, 2006 Per Bothner（MIT 许可，声明见下方代码）；
;;;       SRFI 78 参照实现 Sebastian Egner（MIT 许可，声明见下方代码），Derick Eddington 改进了输出；
;;;       R6RS 改写来自 chez-srfi（LICENSES/chez-srfi.txt）。check-ec 用 (ironscheme std comprehensions)。
;;;
;;; 与参照实现不同（D4）：
;;;   ① SRFI 64 参照实现为 Kawa、MzScheme、Chicken、Guile 等写的 cond-expand 分支已去掉，只保留
;;;      R6RS + SRFI 9 / 23 / 34 / 39 的分支。
;;;   ② test-log-to-file 是存取过程：(test-log-to-file) 取值，(test-log-to-file v) 设置；缺省为 #f，
;;;      不写日志文件（参照实现缺省写 测试名.log）。
;;;   ③ SRFI 78 的 check:write 用基础库的 pretty-print；check-set-mode! 的模式存放在参数中。
;;;   ④ 错误为 &assertion。
;;;   ⑤ 修正参照实现的缺陷：test-result-remove 拿表尾而不是元素与要删的属性比较，永不相等，
;;;      走到表尾时出错（iron-044）。
;;; 本库所有名字都是基础库没有的（D2）。
(library (ironscheme std testing)
  (export
    check check-ec check-passed? check-report check-reset! check-set-mode! test-apply
    test-approximate test-assert test-begin test-end test-eq test-equal test-eqv test-error
    test-expect-fail test-group test-group-with-cleanup test-log-to-file test-match-all
    test-match-any test-match-name test-match-nth test-on-bad-count-simple
    test-on-bad-end-name-simple test-on-final-simple test-on-group-begin-simple
    test-on-group-end-simple test-on-test-end-simple test-passed? test-read-eval-string
    test-result-alist test-result-alist! test-result-clear test-result-kind test-result-ref
    test-result-remove test-result-set! test-runner-aux-value test-runner-aux-value!
    test-runner-create test-runner-current test-runner-factory test-runner-fail-count
    test-runner-fail-count! test-runner-get test-runner-group-path test-runner-group-stack
    test-runner-group-stack! test-runner-null test-runner-on-bad-count
    test-runner-on-bad-count! test-runner-on-bad-end-name test-runner-on-bad-end-name!
    test-runner-on-final test-runner-on-final! test-runner-on-group-begin
    test-runner-on-group-begin! test-runner-on-group-end test-runner-on-group-end!
    test-runner-on-test-begin test-runner-on-test-begin! test-runner-on-test-end
    test-runner-on-test-end! test-runner-pass-count test-runner-pass-count! test-runner-reset
    test-runner-simple test-runner-skip-count test-runner-skip-count! test-runner-test-name
    test-runner-xfail-count test-runner-xfail-count! test-runner-xpass-count
    test-runner-xpass-count! test-runner? test-skip test-with-runner)
  (import
    (except (rnrs) define-record-type)
    (rename (rnrs eval) (eval rnrs:eval))
    (rnrs mutable-pairs)
    (only (ironscheme) make-parameter parameterize open-output-string get-output-string pretty-print)
    (only (ironscheme std lists) reverse!)
    (only (ironscheme std ports) open-input-string)
    (ironscheme std comprehensions)
    (ironscheme std private compat))

;; SRFI 9 形式的记录定义（参照实现的 test-runner 记录用）
(define-syntax define-record-type
  (syntax-rules ()
    ((_ . rest) (srfi-9:define-record-type . rest))))

;; ———————————————— SRFI 64 ————————————————
;; 参照实现中的 eval（test-read-eval-string 用）在 R6RS 环境中求值
(define (eval form)
  (rnrs:eval form (environment '(rnrs) '(rnrs eval) '(rnrs mutable-pairs) '(rnrs mutable-strings) '(rnrs r5rs))))

;; test-log-to-file：无参数时取当前设置，一个参数时设置（#f 不写日志文件；#t 写到 测试名.log；字符串为文件名）
(define test-log-to-file
  (case-lambda
    (() %test-log-to-file-value)
    ((val) (set! %test-log-to-file-value val))))

(SRFI-23-error->R6RS "(library (ironscheme std testing))"
 ;; Copyright (c) 2005, 2006 Per Bothner
 ;;
 ;; Permission is hereby granted, free of charge, to any person
 ;; obtaining a copy of this software and associated documentation
 ;; files (the "Software"), to deal in the Software without
 ;; restriction, including without limitation the rights to use, copy,
 ;; modify, merge, publish, distribute, sublicense, and/or sell copies
 ;; of the Software, and to permit persons to whom the Software is
 ;; furnished to do so, subject to the following conditions:
 ;;
 ;; The above copyright notice and this permission notice shall be
 ;; included in all copies or substantial portions of the Software.
 ;;
 ;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 ;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 ;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 ;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 ;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 ;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 ;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 ;; SOFTWARE.

 (begin)

 (begin
 (define-syntax %test-export
     (syntax-rules ()
       ((%test-export . names) (begin)))))

 ;; List of exported names
 (%test-export
  test-begin ;; must be listed first, since in Kawa (at least) it is "magic".
  test-end test-assert test-eqv test-eq test-equal
  test-approximate test-assert test-error test-apply test-with-runner
  test-match-nth test-match-all test-match-any test-match-name
  test-skip test-expect-fail test-read-eval-string
  test-runner-group-path test-group-with-cleanup
  test-result-ref test-result-set! test-result-clear test-result-remove
  test-result-kind test-passed?
  %test-log-to-file-value
  ; Misc test-runner functions
  test-runner? test-runner-reset test-runner-null
  test-runner-simple test-runner-current test-runner-factory test-runner-get
  test-runner-create test-runner-test-name
  ;; test-runner field setter and getter functions - see %test-record-define:
  test-runner-pass-count test-runner-pass-count!
  test-runner-fail-count test-runner-fail-count!
  test-runner-xpass-count test-runner-xpass-count!
  test-runner-xfail-count test-runner-xfail-count!
  test-runner-skip-count test-runner-skip-count!
  test-runner-group-stack test-runner-group-stack!
  test-runner-on-test-begin test-runner-on-test-begin!
  test-runner-on-test-end test-runner-on-test-end!
  test-runner-on-group-begin test-runner-on-group-begin!
  test-runner-on-group-end test-runner-on-group-end!
  test-runner-on-final test-runner-on-final!
  test-runner-on-bad-count test-runner-on-bad-count!
  test-runner-on-bad-end-name test-runner-on-bad-end-name!
  test-result-alist test-result-alist!
  test-runner-aux-value test-runner-aux-value!
  ;; default/simple call-back functions, used in default test-runner,
  ;; but can be called to construct more complex ones.
  test-on-group-begin-simple test-on-group-end-simple
  test-on-bad-count-simple test-on-bad-end-name-simple
  test-on-final-simple test-on-test-end-simple
  test-on-final-simple)

 (begin
 (define-syntax %test-record-define
     (syntax-rules ()
       ((%test-record-define alloc runner? (name index getter setter) ...)
        (define-record-type test-runner
 	 (alloc)
 	 runner?
 	 (name getter setter) ...)))))

 (%test-record-define
  %test-runner-alloc test-runner?
  ;; Cumulate count of all tests that have passed and were expected to.
  (pass-count 1 test-runner-pass-count test-runner-pass-count!)
  (fail-count 2 test-runner-fail-count test-runner-fail-count!)
  (xpass-count 3 test-runner-xpass-count test-runner-xpass-count!)
  (xfail-count 4 test-runner-xfail-count test-runner-xfail-count!)
  (skip-count 5 test-runner-skip-count test-runner-skip-count!)
  (skip-list 6 %test-runner-skip-list %test-runner-skip-list!)
  (fail-list 7 %test-runner-fail-list %test-runner-fail-list!)
  ;; Normally #t, except when in a test-apply.
  (run-list 8 %test-runner-run-list %test-runner-run-list!)
  (skip-save 9 %test-runner-skip-save %test-runner-skip-save!)
  (fail-save 10 %test-runner-fail-save %test-runner-fail-save!)
  (group-stack 11 test-runner-group-stack test-runner-group-stack!)
  (on-test-begin 12 test-runner-on-test-begin test-runner-on-test-begin!)
  (on-test-end 13 test-runner-on-test-end test-runner-on-test-end!)
  ;; Call-back when entering a group. Takes (runner suite-name count).
  (on-group-begin 14 test-runner-on-group-begin test-runner-on-group-begin!)
  ;; Call-back when leaving a group.
  (on-group-end 15 test-runner-on-group-end test-runner-on-group-end!)
  ;; Call-back when leaving the outermost group.
  (on-final 16 test-runner-on-final test-runner-on-final!)
  ;; Call-back when expected number of tests was wrong.
  (on-bad-count 17 test-runner-on-bad-count test-runner-on-bad-count!)
  ;; Call-back when name in test=end doesn't match test-begin.
  (on-bad-end-name 18 test-runner-on-bad-end-name test-runner-on-bad-end-name!)
  ;; Cumulate count of all tests that have been done.
  (total-count 19 %test-runner-total-count %test-runner-total-count!)
  ;; Stack (list) of (count-at-start . expected-count):
  (count-list 20 %test-runner-count-list %test-runner-count-list!)
  (result-alist 21 test-result-alist test-result-alist!)
  ;; Field can be used by test-runner for any purpose.
  ;; test-runner-simple uses it for a log file.
  (aux-value 22 test-runner-aux-value test-runner-aux-value!)
 )

 (define (test-runner-reset runner)
     (test-result-alist! runner '())
     (test-runner-pass-count! runner 0)
     (test-runner-fail-count! runner 0)
     (test-runner-xpass-count! runner 0)
     (test-runner-xfail-count! runner 0)
     (test-runner-skip-count! runner 0)
     (%test-runner-total-count! runner 0)
     (%test-runner-count-list! runner '())
     (%test-runner-run-list! runner #t)
     (%test-runner-skip-list! runner '())
     (%test-runner-fail-list! runner '())
     (%test-runner-skip-save! runner '())
     (%test-runner-fail-save! runner '())
     (test-runner-group-stack! runner '()))

 (define (test-runner-group-path runner)
   (reverse (test-runner-group-stack runner)))

 (define (%test-null-callback runner) #f)

 (define (test-runner-null)
   (let ((runner (%test-runner-alloc)))
     (test-runner-reset runner)
     (test-runner-on-group-begin! runner (lambda (runner name count) #f))
     (test-runner-on-group-end! runner %test-null-callback)
     (test-runner-on-final! runner %test-null-callback)
     (test-runner-on-test-begin! runner %test-null-callback)
     (test-runner-on-test-end! runner %test-null-callback)
     (test-runner-on-bad-count! runner (lambda (runner count expected) #f))
     (test-runner-on-bad-end-name! runner (lambda (runner begin end) #f))
     runner))

 ;; Not part of the specification.  FIXME
 ;; Controls whether a log file is generated.
 (define %test-log-to-file-value #f) ; 缺省不写日志文件（参照实现为 #t）

 (define (test-runner-simple)
   (let ((runner (%test-runner-alloc)))
     (test-runner-reset runner)
     (test-runner-on-group-begin! runner test-on-group-begin-simple)
     (test-runner-on-group-end! runner test-on-group-end-simple)
     (test-runner-on-final! runner test-on-final-simple)
     (test-runner-on-test-begin! runner test-on-test-begin-simple)
     (test-runner-on-test-end! runner test-on-test-end-simple)
     (test-runner-on-bad-count! runner test-on-bad-count-simple)
     (test-runner-on-bad-end-name! runner test-on-bad-end-name-simple)
     runner))

 (begin
 (define test-runner-current (make-parameter #f))
 (define test-runner-factory (make-parameter test-runner-simple)))

 ;; A safer wrapper to test-runner-current.
 (define (test-runner-get)
   (let ((r (test-runner-current)))
     (if (not r)
 	(begin
 (error "test-runner not initialized - test-begin missing?")))
     r))

 (define (%test-specificier-matches spec runner)
   (spec runner))

 (define (test-runner-create)
   ((test-runner-factory)))

 (define (%test-any-specifier-matches list runner)
   (let ((result #f))
     (let loop ((l list))
       (cond ((null? l) result)
 	    (else
 	     (if (%test-specificier-matches (car l) runner)
 		 (set! result #t))
 	     (loop (cdr l)))))))

 ;; Returns #f, #t, or 'xfail.
 (define (%test-should-execute runner)
   (let ((run (%test-runner-run-list runner)))
     (cond ((or
 	    (not (or (eqv? run #t)
 		     (%test-any-specifier-matches run runner)))
 	    (%test-any-specifier-matches
 	     (%test-runner-skip-list runner)
 	     runner))
 	    (test-result-set! runner 'result-kind 'skip)
 	    #f)
 	  ((%test-any-specifier-matches
 	    (%test-runner-fail-list runner)
 	    runner)
 	   (test-result-set! runner 'result-kind 'xfail)
 	   'xfail)
 	  (else #t))))

 (define (%test-begin suite-name count)
   (if (not (test-runner-current))
       (test-runner-current (test-runner-create)))
   (let ((runner (test-runner-current)))
     ((test-runner-on-group-begin runner) runner suite-name count)
     (%test-runner-skip-save! runner
 			       (cons (%test-runner-skip-list runner)
 				     (%test-runner-skip-save runner)))
     (%test-runner-fail-save! runner
 			       (cons (%test-runner-fail-list runner)
 				     (%test-runner-fail-save runner)))
     (%test-runner-count-list! runner
 			     (cons (cons (%test-runner-total-count runner)
 					 count)
 				   (%test-runner-count-list runner)))
     (test-runner-group-stack! runner (cons suite-name
 					(test-runner-group-stack runner)))))
 (begin
 (define-syntax test-begin
     (syntax-rules ()
       ((test-begin suite-name)
        (%test-begin suite-name #f))
       ((test-begin suite-name count)
        (%test-begin suite-name count)))))

 (define (test-on-group-begin-simple runner suite-name count)
   (if (null? (test-runner-group-stack runner))
       (begin
 	(display "%%%% Starting test ")
 	(display suite-name)
 	(if %test-log-to-file-value
 	    (let* ((log-file-name
 		    (if (string? %test-log-to-file-value) %test-log-to-file-value
 			(string-append suite-name ".log")))
 		   (log-file
 		    (begin
 (open-output-file log-file-name))))
 	      (display "%%%% Starting test " log-file)
 	      (display suite-name log-file)
 	      (newline log-file)
 	      (test-runner-aux-value! runner log-file)
 	      (display "  (Writing full log to \"")
 	      (display log-file-name)
 	      (display "\")")))
 	(newline)))
   (let ((log (test-runner-aux-value runner)))
     (if (output-port? log)
 	(begin
 	  (display "Group begin: " log)
 	  (display suite-name log)
 	  (newline log))))
   #f)

 (define (test-on-group-end-simple runner)
   (let ((log (test-runner-aux-value runner)))
     (if (output-port? log)
 	(begin
 	  (display "Group end: " log)
 	  (display (car (test-runner-group-stack runner)) log)
 	  (newline log))))
   #f)

 (define (%test-on-bad-count-write runner count expected-count port)
   (display "*** Total number of tests was " port)
   (display count port)
   (display " but should be " port)
   (display expected-count port)
   (display ". ***" port)
   (newline port)
   (display "*** Discrepancy indicates testsuite error or exceptions. ***" port)
   (newline port))

 (define (test-on-bad-count-simple runner count expected-count)
   (%test-on-bad-count-write runner count expected-count (current-output-port))
   (let ((log (test-runner-aux-value runner)))
     (if (output-port? log)
 	(%test-on-bad-count-write runner count expected-count log))))

 (define (test-on-bad-end-name-simple runner begin-name end-name)
   (let ((msg (string-append (%test-format-line runner) "test-end " begin-name
 			    " does not match test-begin " end-name)))
     (begin
 (error msg))))


 (define (%test-final-report1 value label port)
   (if (> value 0)
       (begin
 	(display label port)
 	(display value port)
 	(newline port))))

 (define (%test-final-report-simple runner port)
   (%test-final-report1 (test-runner-pass-count runner)
 		      "# of expected passes      " port)
   (%test-final-report1 (test-runner-xfail-count runner)
 		      "# of expected failures    " port)
   (%test-final-report1 (test-runner-xpass-count runner)
 		      "# of unexpected successes " port)
   (%test-final-report1 (test-runner-fail-count runner)
 		      "# of unexpected failures  " port)
   (%test-final-report1 (test-runner-skip-count runner)
 		      "# of skipped tests        " port))

 (define (test-on-final-simple runner)
   (%test-final-report-simple runner (current-output-port))
   (let ((log (test-runner-aux-value runner)))
     (if (output-port? log)
 	(%test-final-report-simple runner log))))

 (define (%test-format-line runner)
    (let* ((line-info (test-result-alist runner))
 	  (source-file (assq 'source-file line-info))
 	  (source-line (assq 'source-line line-info))
 	  (file (if source-file (cdr source-file) "")))
      (if source-line
 	 (string-append file ":"
 			(number->string (cdr source-line)) ": ")
 	 "")))

 (define (%test-end suite-name line-info)
   (let* ((r (test-runner-get))
 	 (groups (test-runner-group-stack r))
 	 (line (%test-format-line r)))
     (test-result-alist! r line-info)
     (if (null? groups)
 	(let ((msg (string-append line "test-end not in a group")))
 	  (begin
 (error msg))))
     (if (and suite-name (not (equal? suite-name (car groups))))
 	((test-runner-on-bad-end-name r) r suite-name (car groups)))
     (let* ((count-list (%test-runner-count-list r))
 	   (expected-count (cdar count-list))
 	   (saved-count (caar count-list))
 	   (group-count (- (%test-runner-total-count r) saved-count)))
       (if (and expected-count
 	       (not (= expected-count group-count)))
 	  ((test-runner-on-bad-count r) r group-count expected-count))
       ((test-runner-on-group-end r) r)
       (test-runner-group-stack! r (cdr (test-runner-group-stack r)))
       (%test-runner-skip-list! r (car (%test-runner-skip-save r)))
       (%test-runner-skip-save! r (cdr (%test-runner-skip-save r)))
       (%test-runner-fail-list! r (car (%test-runner-fail-save r)))
       (%test-runner-fail-save! r (cdr (%test-runner-fail-save r)))
       (%test-runner-count-list! r (cdr count-list))
       (if (null? (test-runner-group-stack r))
 	  ((test-runner-on-final r) r)))))

 (define-syntax test-group
   (syntax-rules ()
     ((test-group suite-name . body)
      (let ((r (test-runner-current)))
        ;; Ideally should also set line-number, if available.
        (test-result-alist! r (list (cons 'test-name suite-name)))
        (if (%test-should-execute r)
 	   (dynamic-wind
 	       (lambda () (test-begin suite-name))
 	       (lambda () . body)
 	       (lambda () (test-end  suite-name))))))))

 (define-syntax test-group-with-cleanup
   (syntax-rules ()
     ((test-group-with-cleanup suite-name form cleanup-form)
      (test-group suite-name
 		    (dynamic-wind
 			(lambda () #f)
 			(lambda () form)
 			(lambda () cleanup-form))))
     ((test-group-with-cleanup suite-name cleanup-form)
      (test-group-with-cleanup suite-name #f cleanup-form))
     ((test-group-with-cleanup suite-name form1 form2 form3 . rest)
      (test-group-with-cleanup suite-name (begin form1 form2) form3 . rest))))

 (define (test-on-test-begin-simple runner)
  (let ((log (test-runner-aux-value runner)))
     (if (output-port? log)
 	(let* ((results (test-result-alist runner))
 	       (source-file (assq 'source-file results))
 	       (source-line (assq 'source-line results))
 	       (source-form (assq 'source-form results))
 	       (test-name (assq 'test-name results)))
 	  (display "Test begin:" log)
 	  (newline log)
 	  (if test-name (%test-write-result1 test-name log))
 	  (if source-file (%test-write-result1 source-file log))
 	  (if source-line (%test-write-result1 source-line log))
 	  (if source-form (%test-write-result1 source-form log))))))

 (define-syntax test-result-ref
   (syntax-rules ()
     ((test-result-ref runner pname)
      (test-result-ref runner pname #f))
     ((test-result-ref runner pname default)
      (let ((p (assq pname (test-result-alist runner))))
        (if p (cdr p) default)))))

 (define (test-on-test-end-simple runner)
   (let ((log (test-runner-aux-value runner))
 	(kind (test-result-ref runner 'result-kind)))
     (if (memq kind '(fail xpass))
 	(let* ((results (test-result-alist runner))
 	       (source-file (assq 'source-file results))
 	       (source-line (assq 'source-line results))
 	       (test-name (assq 'test-name results)))
 	  (if (or source-file source-line)
 	      (begin
 		(if source-file (display (cdr source-file)))
 		(display ":")
 		(if source-line (display (cdr source-line)))
 		(display ": ")))
 	  (display (if (eq? kind 'xpass) "XPASS" "FAIL"))
 	  (if test-name
 	      (begin
 		(display " ")
 		(display (cdr test-name))))
 	  (newline)))
     (if (output-port? log)
 	(begin
 	  (display "Test end:" log)
 	  (newline log)
 	  (let loop ((list (test-result-alist runner)))
 	    (if (pair? list)
 		(let ((pair (car list)))
 		  ;; Write out properties not written out by on-test-begin.
 		  (if (not (memq (car pair)
 				 '(test-name source-file source-line source-form)))
 		      (%test-write-result1 pair log))
 		  (loop (cdr list)))))))))

 (define (%test-write-result1 pair port)
   (display "  " port)
   (display (car pair) port)
   (display ": " port)
   (write (cdr pair) port)
   (newline port))

 (define (test-result-set! runner pname value)
   (let* ((alist (test-result-alist runner))
 	 (p (assq pname alist)))
     (if p
 	(set-cdr! p value)
 	(test-result-alist! runner (cons (cons pname value) alist)))))

 (define (test-result-clear runner)
   (test-result-alist! runner '()))

 (define (test-result-remove runner pname)
   (let* ((alist (test-result-alist runner))
 	 (p (assq pname alist)))
     (if p
 	(test-result-alist! runner
 				   (let loop ((r alist))
 				     (if (eq? (car r) p) (cdr r) ; 参照实现为 (eq? r p)，见文件头 ⑤
 					 (cons (car r) (loop (cdr r)))))))))

 (define (test-result-kind . rest)
   (let ((runner (if (pair? rest) (car rest) (test-runner-current))))
     (test-result-ref runner 'result-kind)))

 (define (test-passed? . rest)
   (let ((runner (if (pair? rest) (car rest) (test-runner-get))))
     (memq (test-result-ref runner 'result-kind) '(pass xpass))))

 (define (%test-report-result)
   (let* ((r (test-runner-get))
 	 (result-kind (test-result-kind r)))
     (case result-kind
       ((pass)
        (test-runner-pass-count! r (+ 1 (test-runner-pass-count r))))
       ((fail)
        (test-runner-fail-count!	r (+ 1 (test-runner-fail-count r))))
       ((xpass)
        (test-runner-xpass-count! r (+ 1 (test-runner-xpass-count r))))
       ((xfail)
        (test-runner-xfail-count! r (+ 1 (test-runner-xfail-count r))))
       (else
        (test-runner-skip-count! r (+ 1 (test-runner-skip-count r)))))
     (%test-runner-total-count! r (+ 1 (%test-runner-total-count r)))
     ((test-runner-on-test-end r) r)))

 (begin
 (define-syntax %test-evaluate-with-catch
     (syntax-rules ()
       ((%test-evaluate-with-catch test-expression)
        (guard (ex (else #F)) test-expression)))))

 (begin
 (define (%test-source-line2 form)
     '()))

 (define (%test-on-test-begin r)
   (%test-should-execute r)
   ((test-runner-on-test-begin r) r)
   (not (eq? 'skip (test-result-ref r 'result-kind))))

 (define (%test-on-test-end r result)
     (test-result-set! r 'result-kind
 		      (if (eq? (test-result-ref r 'result-kind) 'xfail)
 			  (if result 'xpass 'xfail)
 			  (if result 'pass 'fail))))

 (define (test-runner-test-name runner)
   (test-result-ref runner 'test-name ""))

 (define-syntax %test-comp2body
   (syntax-rules ()
 		((%test-comp2body r comp expected expr)
 		 (let ()
 		   (if (%test-on-test-begin r)
 		       (let ((exp expected))
 			 (test-result-set! r 'expected-value exp)
 			 (let ((res (%test-evaluate-with-catch expr)))
 			   (test-result-set! r 'actual-value res)
 			   (%test-on-test-end r (comp exp res)))))
 		   (%test-report-result)))))

 (define (%test-approximimate= error)
   (lambda (value expected)
     (and (>= value (- expected error))
          (<= value (+ expected error)))))

 (define-syntax %test-comp1body
   (syntax-rules ()
     ((%test-comp1body r expr)
      (let ()
        (if (%test-on-test-begin r)
 	   (let ()
 	     (let ((res (%test-evaluate-with-catch expr)))
 	       (test-result-set! r 'actual-value res)
 	       (%test-on-test-end r res))))
        (%test-report-result)))))

 (begin
 (define-syntax test-end
     (syntax-rules ()
       ((test-end)
        (%test-end #f '()))
       ((test-end suite-name)
        (%test-end suite-name '()))))
 (define-syntax test-assert
     (syntax-rules ()
       ((test-assert tname test-expression)
        (let ((r (test-runner-get)))
 	 (test-result-alist! r `((test-name . ,tname)
                                  (source-form . test-expression)))
 	 (%test-comp1body r test-expression)))
       ((test-assert test-expression)
        (let ((r (test-runner-get)))
 	 (test-result-alist! r '((source-form . test-expression)))
 	 (%test-comp1body r test-expression)))))
 (define-syntax %test-comp2
     (syntax-rules ()
       ((%test-comp2 comp tname expected expr)
        (let ((r (test-runner-get)))
 	 (test-result-alist! r `((test-name . ,tname)
                                  (source-form . expr)))
 	 (%test-comp2body r comp expected expr)))
       ((%test-comp2 comp expected expr)
        (let ((r (test-runner-get)))
 	 (test-result-alist! r '((source-form . expr)))
 	 (%test-comp2body r comp expected expr)))))
 (define-syntax test-equal
     (syntax-rules ()
       ((test-equal . rest)
        (%test-comp2 equal? . rest))))
 (define-syntax test-eqv
     (syntax-rules ()
       ((test-eqv . rest)
        (%test-comp2 eqv? . rest))))
 (define-syntax test-eq
     (syntax-rules ()
       ((test-eq . rest)
        (%test-comp2 eq? . rest))))
 (define-syntax test-approximate
     (syntax-rules ()
       ((test-approximate tname expected expr error)
        (%test-comp2 (%test-approximimate= error) tname expected expr))
       ((test-approximate expected expr error)
        (%test-comp2 (%test-approximimate= error) expected expr)))))

 (begin
 (define-syntax %test-error
     (syntax-rules ()
       ((%test-error etype expr)
        (let ((t etype))
          (when (procedure? t)
            (test-result-set! (test-runner-get) 'expected-error t))
          (guard (ex (else
                      (test-result-set! (test-runner-get) 'actual-error ex)
                      (if (procedure? t) (t ex) #T)))
            expr
            #F))))))

 (begin
 (define-syntax test-error
     (syntax-rules ()
       ((test-error name etype expr)
        (test-assert name (%test-error etype expr)))
       ((test-error etype expr)
        (test-assert (%test-error etype expr)))
       ((test-error expr)
        (test-assert (%test-error #t expr))))))

 (define (test-apply first . rest)
   (if (test-runner? first)
       (test-with-runner first (apply test-apply rest))
       (let ((r (test-runner-current)))
 	(if r
 	    (let ((run-list (%test-runner-run-list r)))
 	      (cond ((null? rest)
 		     (%test-runner-run-list! r (reverse! run-list))
 		     (first)) ;; actually apply procedure thunk
 		    (else
 		     (%test-runner-run-list!
 		      r
 		      (if (eq? run-list #t) (list first) (cons first run-list)))
 		     (apply test-apply rest)
 		     (%test-runner-run-list! r run-list))))
 	    (let ((r (test-runner-create)))
 	      (test-with-runner r (apply test-apply first rest))
 	      ((test-runner-on-final r) r))))))

 (define-syntax test-with-runner
   (syntax-rules ()
     ((test-with-runner runner form ...)
      (let ((saved-runner (test-runner-current)))
        (dynamic-wind
            (lambda () (test-runner-current runner))
            (lambda () form ...)
            (lambda () (test-runner-current saved-runner)))))))

 ;;; Predicates

 (define (%test-match-nth n count)
   (let ((i 0))
     (lambda (runner)
       (set! i (+ i 1))
       (and (>= i n) (< i (+ n count))))))

 (define-syntax test-match-nth
   (syntax-rules ()
     ((test-match-nth n)
      (test-match-nth n 1))
     ((test-match-nth n count)
      (%test-match-nth n count))))

 (define (%test-match-all . pred-list)
   (lambda (runner)
     (let ((result #t))
       (let loop ((l pred-list))
 	(if (null? l)
 	    result
 	    (begin
 	      (if (not ((car l) runner))
 		  (set! result #f))
 	      (loop (cdr l))))))))

 (define-syntax test-match-all
   (syntax-rules ()
     ((test-match-all pred ...)
      (%test-match-all (%test-as-specifier pred) ...))))

 (define (%test-match-any . pred-list)
   (lambda (runner)
     (let ((result #f))
       (let loop ((l pred-list))
 	(if (null? l)
 	    result
 	    (begin
 	      (if ((car l) runner)
 		  (set! result #t))
 	      (loop (cdr l))))))))

 (define-syntax test-match-any
   (syntax-rules ()
     ((test-match-any pred ...)
      (%test-match-any (%test-as-specifier pred) ...))))

 ;; Coerce to a predicate function:
 (define (%test-as-specifier specifier)
   (cond ((procedure? specifier) specifier)
 	((integer? specifier) (test-match-nth 1 specifier))
 	((string? specifier) (test-match-name specifier))
 	(else
 	 (error "not a valid test specifier"))))

 (define-syntax test-skip
   (syntax-rules ()
     ((test-skip pred ...)
      (let ((runner (test-runner-get)))
        (%test-runner-skip-list! runner
 				  (cons (test-match-all (%test-as-specifier pred)  ...)
 					(%test-runner-skip-list runner)))))))

 (define-syntax test-expect-fail
   (syntax-rules ()
     ((test-expect-fail pred ...)
      (let ((runner (test-runner-get)))
        (%test-runner-fail-list! runner
 				  (cons (test-match-all (%test-as-specifier pred)  ...)
 					(%test-runner-fail-list runner)))))))

 (define (test-match-name name)
   (lambda (runner)
     (equal? name (test-runner-test-name runner))))

 (define (test-read-eval-string string)
   (let* ((port (open-input-string string))
 	 (form (read port)))
     (if (eof-object? (read-char port))
 	(eval form)
 	(begin
 (error "(not at eof)")))))
 )

;; ———————————————— SRFI 78 ————————————————
;; check:mode 是参数（同 chez-srfi）；check:write 用基础库的 pretty-print
(define-syntax check:mode
  (identifier-syntax
    (_ (check:mode-param))
    ((set! _ expr) (check:mode-param expr))))

(define check:mode-param (make-parameter #f))

(define check:write pretty-print)

(let-syntax ((define (vanish-define define (check:write check:mode))))
  (SRFI-23-error->R6RS "(library (ironscheme std testing))"
  ;; Modified by Derick Eddington to improve the print-outs.  All lines of printed
  ;; expected results (for failed checks) are commented-out so they don't break
  ;; syntactic-datum delimiting, so a print-out can be programmatically read and
  ;; processed.  When a non-default equality predicate is used, (=> <expr>) is
  ;; printed.

  ; <PLAINTEXT>
  ; Copyright (c) 2005-2006 Sebastian Egner.
  ; 
  ; Permission is hereby granted, free of charge, to any person obtaining
  ; a copy of this software and associated documentation files (the
  ; ``Software''), to deal in the Software without restriction, including
  ; without limitation the rights to use, copy, modify, merge, publish,
  ; distribute, sublicense, and/or sell copies of the Software, and to
  ; permit persons to whom the Software is furnished to do so, subject to
  ; the following conditions:
  ; 
  ; The above copyright notice and this permission notice shall be
  ; included in all copies or substantial portions of the Software.
  ; 
  ; THE SOFTWARE IS PROVIDED ``AS IS'', WITHOUT WARRANTY OF ANY KIND,
  ; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  ; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  ; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
  ; LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  ; OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  ; WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ; 
  ; -----------------------------------------------------------------------
  ; 
  ; Lightweight testing (reference implementation)
  ; ==============================================
  ;
  ; Sebastian.Egner@philips.com
  ; in R5RS + SRFI 23 (error) + SRFI 42 (comprehensions)
  ;
  ; history of this file:
  ;   SE, 25-Oct-2004: first version based on code used in SRFIs 42 and 67
  ;   SE, 19-Jan-2006: (arg ...) made optional in check-ec
  ;
  ; Naming convention "check:<identifier>" is used only internally.

  ; -- portability --

  ; PLT:      (require (lib "23.ss" "srfi") (lib "42.ss" "srfi"))
  ; Scheme48: ,open srfi-23 srfi-42 

  ; -- utilities --

  (define check:write write)

  (define (print/header/padded x header padding)
    (define (print/lines)
      (let* ((str (call-with-string-output-port
                    (lambda (sop) (check:write x sop))))
             (sip (open-string-input-port str)))
        (let loop ((lines '()))
          (let ((l (get-line sip)))
            (if (eof-object? l)
              (reverse lines)
              (loop (cons l lines)))))))
    (let ((lines (print/lines)))
      (display header)
      (display (car lines))
      (let loop ((lines (cdr lines)))
        (unless (null? lines)
          (newline)
          (display padding)
          (display (car lines))
          (loop (cdr lines))))))

  ; You can also use a pretty printer if you have one.
  ; However, the output might not improve for most cases
  ; because the pretty printers usually output a trailing
  ; newline.

  ; PLT:      (require (lib "pretty.ss")) (define check:write pretty-print)
  ; Scheme48: ,open pp (define check:write p)

  ; -- mode --

  (define check:mode #f)

  (define (check-set-mode! mode)
    (set! check:mode
          (case mode
            ((off)           0)
            ((summary)       1)
            ((report-failed) 10)
            ((report)        100)
            (else (error "unrecognized mode" mode)))))

  ; -- state --

  (define check:correct #f)
  (define check:failed   #f)

  (define (check-reset!)
    (set! check:correct 0)
    (set! check:failed   '()))

  (define (check:add-correct!)
    (set! check:correct (+ check:correct 1)))

  (define (check:add-failed! expression actual-result expected-result pred)
    (set! check:failed
          (cons (list expression actual-result expected-result pred)
                check:failed)))

  ; -- reporting --

  (define (check:report-expression expression pred)
    (newline)
    (check:write expression)
    (if pred
      (begin (print/header/padded pred "(=> " "    ")
             (display ")"))
      (display "=>"))
    (newline))

  (define (check:report-actual-result actual-result)
    (check:write actual-result)
    (display ";; "))

  (define (check:report-correct cases)
    (display "correct")
    (if (not (= cases 1))
        (begin (display " (")
               (display cases)
               (display " cases checked)")))
    (newline))

  (define (check:report-failed expected-result)
    (display "*** failed ***")
    (newline)
    (print/header/padded expected-result ";; expected result: "
                                         ";;                  ")
    (newline))

  (define (check-report)
    (if (>= check:mode 1)
        (begin
          (newline)
          (display ";; *** checks *** : ")
          (display check:correct)
          (display " correct, ")
          (display (length check:failed))
          (display " failed.")
          (if (or (null? check:failed) (<= check:mode 1))
              (newline)
              (let* ((w (car (reverse check:failed)))
                     (expression (car w))
                     (actual-result (cadr w))
                     (expected-result (caddr w))
                     (pred (cadddr w)))                  
                (display " First failed example:")
                (newline)
                (check:report-expression expression pred)
                (check:report-actual-result actual-result)
                (check:report-failed expected-result))))))

  (define (check-passed? expected-total-count)
    (and (= (length check:failed) 0)
         (= check:correct expected-total-count)))

  ; -- simple checks --

  (define (check:proc expression thunk equal equal-expr expected-result)
    (define equal-expr*
      (and (not (eq? equal? equal))
           equal-expr))
    (case check:mode
      ((0) #f)
      ((1)
       (let ((actual-result (thunk)))
         (if (equal actual-result expected-result)
             (check:add-correct!)
             (check:add-failed!
              expression actual-result expected-result equal-expr*))))
      ((10)
       (let ((actual-result (thunk)))
         (if (equal actual-result expected-result)
             (check:add-correct!)
             (begin
               (check:report-expression expression equal-expr*)
               (check:report-actual-result actual-result)
               (check:report-failed expected-result)
               (check:add-failed!
                expression actual-result expected-result equal-expr*)))))
      ((100)
       (check:report-expression expression equal-expr*)
       (let ((actual-result (thunk)))
         (check:report-actual-result actual-result)
         (if (equal actual-result expected-result)
             (begin (check:report-correct 1)
                    (check:add-correct!))
             (begin (check:report-failed expected-result)
                    (check:add-failed!
                     expression actual-result expected-result equal-expr*)))))
      (else (error "unrecognized check:mode" check:mode)))
    (if #f #f))

  (define-syntax check
    (syntax-rules (=>)
      ((check expr => expected)
       (check expr (=> equal?) expected))
      ((check expr (=> equal) expected)
       (if (>= check:mode 1)
  	 (check:proc 'expr (lambda () #F expr) equal 'equal expected)))))

  ; -- parametric checks --

  (define (check:proc-ec w)
    (let ((correct? (car w))
          (expression (cadr w))
          (actual-result (caddr w))
          (expected-result (cadddr w))
  	(cases (car (cddddr w)))
          (equal-expr (cadr (cddddr w))))
      (if correct?
          (begin (if (>= check:mode 100)
                     (begin (check:report-expression expression equal-expr)
                            (check:report-actual-result actual-result)
                            (check:report-correct cases)))
                 (check:add-correct!))
          (begin (if (>= check:mode 10)
                     (begin (check:report-expression expression equal-expr)
                            (check:report-actual-result actual-result)
                            (check:report-failed expected-result)))
                 (check:add-failed!
                  expression actual-result expected-result equal-expr)))))

  (define-syntax check-ec:make
    (syntax-rules (=>)
      ((check-ec:make qualifiers expr (=> equal) expected (arg ...))
       (if (>= check:mode 1)
           (check:proc-ec
  	  (let* ((cases 0)
                   (eq-p equal)
                   (equal-expr (and (not (eq? equal? eq-p))
                                    'equal)))
  	    (let ((w (first-ec 
  		      #f
  		      qualifiers
  		      (:let equal-pred eq-p)
  		      (:let expected-result expected)
  		      (:let actual-result
                              (let ((arg arg) ...) ; (*)
                                expr))
  		      (begin (set! cases (+ cases 1)))
  		      (if (not (equal-pred actual-result expected-result)))
  		      (list (list 'let (list (list 'arg arg) ...) 'expr)
  			    actual-result
  			    expected-result
  			    cases
                              equal-expr))))
  	      (if w
  		  (cons #f w)
  		  (list #t 
  			'(check-ec qualifiers 
  				   expr (=> equal) 
  				   expected (arg ...))
  			(if #f #f)
  		        (if #f #f)
  			cases
                          equal-expr)))))))))

  ; (*) is a compile-time check that (arg ...) is a list
  ; of pairwise disjoint bound variables at this point.

  (define-syntax check-ec
    (syntax-rules (nested =>)
      ((check-ec expr => expected)
       (check-ec:make (nested) expr (=> equal?) expected ()))
      ((check-ec expr (=> equal) expected)
       (check-ec:make (nested) expr (=> equal) expected ()))
      ((check-ec expr => expected (arg ...))
       (check-ec:make (nested) expr (=> equal?) expected (arg ...)))
      ((check-ec expr (=> equal) expected (arg ...))
       (check-ec:make (nested) expr (=> equal) expected (arg ...)))

      ((check-ec qualifiers expr => expected)
       (check-ec:make qualifiers expr (=> equal?) expected ()))
      ((check-ec qualifiers expr (=> equal) expected)
       (check-ec:make qualifiers expr (=> equal) expected ()))
      ((check-ec qualifiers expr => expected (arg ...))
       (check-ec:make qualifiers expr (=> equal?) expected (arg ...)))
      ((check-ec qualifiers expr (=> equal) expected (arg ...))
       (check-ec:make qualifiers expr (=> equal) expected (arg ...)))

      ((check-ec (nested q1 ...) q etc ...)
       (check-ec (nested q1 ... q) etc ...))
      ((check-ec q1 q2             etc ...)
       (check-ec (nested q1 q2)    etc ...))))


  (check-set-mode! 'report)
  (check-reset!)
  ))
)
