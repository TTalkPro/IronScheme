;;; (ironscheme std testing) 的测试（designs/08-std-library.md D8）。
;;;
;;; 一、SRFI 64：即 chez-srfi 的 tests/testing.sps 所用的 SRFI 64 元测试集（srfi-64-test.scm，文件中未署名，
;;;     随 SRFI 64 参照实现发布）。被测的框架不参与判定：内层（triv-runner 等运行的）测试照旧用被测的
;;;     test-assert / test-equal …，外层原用 SRFI 64 自己判定的 test-equal / test-assert / test-error
;;;     改为 tests/std/check.ss 的 check / check-raises，外层的 test-begin / test-end 去掉（留作注释）。
;;;     原测试：51 项通过、2 项预期失败（test-expect-fail）；这 2 项在这里检查"确实与期望不同"。
;;; 二、SRFI 78：改写自 chez-srfi 的 tests/lightweight-testing.sps（SRFI 78 的例子，Sebastian Egner）：
;;;     把 check 的输出捕获到字符串，用 check.ss 判定计数与报告；被测的 check 以前缀 lt: 导入。
(import (rnrs) (rnrs r5rs) (only (ironscheme) include parameterize)
        (except (ironscheme std testing) check check-report)
        (prefix (only (ironscheme std testing) check check-ec check-report check-set-mode! check-reset! check-passed?) lt:)
        (ironscheme std comprehensions))
(include "tests/std/check.ss")

;;; ———————————————— SRFI 64 元测试集 ————————————————
;; 原测试在外层 test-begin 建立的运行器中运行（有的内层用例出错后依赖它）；这里放一个不做判定的空运行器
(test-runner-current (test-runner-null))
;;;
;;;  This is a test suite written in the notation of 
;;;  SRFI-64, A Scheme API for test suites
;;;

;; （外层）(test-begin "SRFI 64 - Meta-Test Suite")

;;;
;;;  Ironically, in order to set up the meta-test environment,
;;;  we have to invoke one of the most sophisticated features:
;;;  custom test runners
;;;

;;;  The `prop-runner' invokes `thunk' in the context of a new
;;;  test runner, and returns the indicated properties of the 
;;;  last-executed test result.

(define (prop-runner props thunk)
  (let ((r (test-runner-null))
        (plist '()))
    ;;
    (test-runner-on-test-end!
     r
     (lambda (runner)
       (set! plist (test-result-alist runner))))
    ;;
    (test-with-runner r (thunk))
    ;; reorder the properties so they are in the order
    ;; given by `props'.  Note that any property listed in `props'
    ;; that is not in the property alist will occur as #f
    (map (lambda (k)
           (assq k plist))
         props)))

;;;  `on-test-runner' creates a null test runner and then
;;;  arranged for `visit' to be called with the runner
;;;  whenever a test is run.  The results of the calls to
;;;  `visit' are returned in a list

(define (on-test-runner thunk visit)
  (let ((r (test-runner-null))
        (results '()))
    ;;
    (test-runner-on-test-end!
     r
     (lambda (runner)
       (set! results (cons (visit r) results))))
    ;;
    (test-with-runner r (thunk))
    (reverse results)))

;;;
;;;  The `triv-runner' invokes `thunk'
;;;  and returns a list of 6 lists, the first 5 of which
;;;  are a list of the names of the tests that, respectively,
;;;  PASS, FAIL, XFAIL, XPASS, and SKIP.
;;;  The last item is a list of counts.
;;;

(define (triv-runner thunk)
  (let ((r (test-runner-null))
        (accum-pass '())
        (accum-fail '())
        (accum-xfail '())
        (accum-xpass '())
        (accum-skip '()))
    ;;
    (test-runner-on-bad-count!
     r
     (lambda (runner count expected-count)
       (error (string-append "bad count " (number->string count)
			     " but expected "
			     (number->string expected-count)))))
    (test-runner-on-bad-end-name!
     r
     (lambda (runner begin end)
       (error (string-append "bad end grojup name " end
			     " but expected " begin))))
    (test-runner-on-test-end! 
     r 
     (lambda (runner)
       (let ((n (test-runner-test-name runner)))
         (case (test-result-kind runner)
           ((pass) (set! accum-pass (cons n accum-pass)))
           ((fail) (set! accum-fail (cons n accum-fail)))
           ((xpass) (set! accum-xpass (cons n accum-xpass)))
           ((xfail) (set! accum-xfail (cons n accum-xfail)))
           ((skip) (set! accum-skip (cons n accum-skip)))))))
    ;;
    (test-with-runner r (thunk))
    (list (reverse accum-pass)    ; passed as expected
          (reverse accum-fail)    ; failed, but was expected to pass
          (reverse accum-xfail)   ; failed as expected
          (reverse accum-xpass)   ; passed, but was expected to fail
          (reverse accum-skip)    ; was not executed
          (list (test-runner-pass-count r)
                (test-runner-fail-count r)
                (test-runner-xfail-count r)
                (test-runner-xpass-count r)
                (test-runner-skip-count r)))))

(define (path-revealing-runner thunk)
  (let ((r (test-runner-null))
        (seq '()))
    ;;
    (test-runner-on-test-end! 
     r 
     (lambda (runner)
       (set! seq (cons (list (test-runner-group-path runner)
                             (test-runner-test-name runner))
                       seq))))
    (test-with-runner r (thunk))
    (reverse seq)))

;;;
;;;  Now we can start testing compliance with SRFI-64
;;;

;; （外层）(test-begin "1. Simple test-cases")

;; （外层）(test-begin "1.1. test-assert")

(define (t)
  (triv-runner
   (lambda ()
     (test-assert "a" #t)
     (test-assert "b" #f))))

;; "1.1.1. Very simple"
(check (t)
       => '(("a") ("b") () () () (1 1 0 0 0)))

;; "1.1.2. A test with no name"
(check (triv-runner (lambda () (test-assert "a" #t) (test-assert #f)))
       => '(("a") ("") () () () (1 1 0 0 0)))

;; "1.1.3. Tests can have the same name"
(check (triv-runner (lambda () (test-assert "a" #t) (test-assert "a" #t)))
       => '(("a" "a") () () () () (2 0 0 0 0)))

(define (choke)
  (vector-ref '#(1 2) 3))

;; "1.1.4. One way to FAIL is to throw an error"
(check (triv-runner (lambda () (test-assert "a" (choke))))
       => '(() ("a") () () () (0 1 0 0 0)))

;; （外层）(test-end);1.1

;; （外层）(test-begin "1.2. test-eqv")

(define (mean x y)
  (/ (+ x y) 2.0))

;; "1.2.1.  Simple numerical equivalence"
(check (triv-runner
  (lambda ()
    (test-eqv "a" (mean 3 5) 4)
    (test-eqv "b" (mean 3 5) 4.5)
    (test-eqv "c" (mean 3 5) 4.0)))
       => '(("c") ("a" "b") () () () (1 2 0 0 0)))

;; （外层）(test-end);1.2

;; （外层）(test-end "1. Simple test-cases")

;;;
;;;
;;;

;; （外层）(test-begin "2. Tests for catching errors")

;; （外层）(test-begin "2.1. test-error")

;; "2.1.1. Baseline test; PASS with no optional args"
(check (triv-runner
  (lambda ()
    ;; PASS
    (test-error (vector-ref '#(1 2) 9))))
       => '(("") () () () () (1 0 0 0 0)))

;; "2.1.2. Baseline test; FAIL with no optional args"
(check (triv-runner
  (lambda ()
    ;; FAIL: the expr does not raise an error and `test-error' is
    ;;       claiming that it will, so this test should FAIL
    (test-error (vector-ref '#(1 2) 0))))
       => '(() ("") () () () (0 1 0 0 0)))

;; "2.1.3. PASS with a test name and error type"
(check (triv-runner
  (lambda ()
    ;; PASS
    (test-error "a" #t (vector-ref '#(1 2) 9))))
       => '(("a") () () () () (1 0 0 0 0)))

;; （外层）(test-end "2.1. test-error")

;; （外层）(test-end "2. Tests for catching errors")

;;;
;;;
;;;

;; （外层）(test-begin "3. Test groups and paths")

;; "3.1. test-begin with unspecific test-end"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-assert "b" #t)
    (test-end)))
       => '(("b") () () () () (1 0 0 0 0)))

;; "3.2. test-begin with name-matching test-end"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-assert "b" #t)
    (test-end "a")))
       => '(("b") () () () () (1 0 0 0 0)))

;;; since the error raised by `test-end' on a mismatch is not a test
;;; error, we actually expect the triv-runner itself to fail

;; "3.3. test-begin with mismatched test-end"
(check-raises (lambda (e) #t) (triv-runner
  (lambda ()
    (test-begin "a")
    (test-assert "b" #t)
    (test-end "x"))))

;; "3.4. test-begin with name and count"
(check (triv-runner
  (lambda ()
    (test-begin "a" 2)
    (test-assert "b" #t)
    (test-assert "c" #t)
    (test-end "a")))
       => '(("b" "c") () () () () (2 0 0 0 0)))

;; similarly here, a mismatched count is a lexical error
;; and not a test failure...

;; "3.5. test-begin with mismatched count"
(check-raises (lambda (e) #t) (triv-runner
  (lambda ()
    (test-begin "a" 99)
    (test-assert "b" #t)
    (test-end "a"))))

;; "3.6. introspecting on the group path"
(check (path-revealing-runner
  (lambda ()
    (test-assert "w" #t)
    (test-begin "a")
    (test-begin "b")
    (test-assert "x" #t)
    (test-assert "y" #t)
    (test-end)
    (test-assert "z" #t)))
       => '((() "w")
   (("a" "b") "x")
   (("a" "b") "y")
   (("a") "z")))


;; （外层）(test-end "3. Test groups and paths")

;;;
;;;
;;;

;; （外层）(test-begin "4. Handling set-up and cleanup")

;; "4.1. Normal exit path"
(check (let ((ex '()))
               (define (do s)
                 (set! ex (cons s ex)))
               ;;
               (triv-runner
                (lambda ()
                  (test-group-with-cleanup
                   "foo"
                   (do 'in)
                   (do 1)
                   (do 2)
                   (do 'out))))
               (reverse ex))
       => '(in 1 2 out))
               
;; "4.2. Exception exit path"
(check (let ((ex '()))
               (define (do s)
                 (set! ex (cons s ex)))
               ;;
               ;; the outer runner is to run the `test-error' in, to
               ;; catch the exception raised in the inner runner,
               ;; since we don't want to depend on any other
               ;; exception-catching support
               ;;
               (triv-runner
                (lambda ()
                  (test-error
                   (triv-runner
                    (lambda ()
                      (test-group-with-cleanup
                       "foo"
                       (do 'in) (test-assert #t)
                       (do 1)   (test-assert #t)
                       (choke)  (test-assert #t)
                       (do 2)   (test-assert #t)
                       (do 'out)))))))
               (reverse ex))
       => '(in 1 out))

;; （外层）(test-end "4. Handling set-up and cleanup")

;;;
;;;
;;;

;; （外层）(test-begin "5. Test specifiers")

;; （外层）(test-begin "5.1. test-match-named")

;; "5.1.1. match test names"
(check (triv-runner
             (lambda ()
               (test-skip (test-match-name "x"))
               (test-assert "x" #t)
               (test-assert "y" #t)))
       => '(("y") () () () ("x") (1 0 0 0 1)))

;; "5.1.2. but not group names"
(check (triv-runner
             (lambda ()
               (test-skip (test-match-name "x"))
               (test-begin "x")
               (test-assert "z" #t)
               (test-end)))
       => '(("z") () () () () (1 0 0 0 0)))

;; （外层）(test-end)

;; （外层）(test-begin "5.2. test-match-nth")
;; See also: [6.4. Short-circuit evaluation]

;; "5.2.1. skip the nth one after"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-nth 2))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP
               (test-assert "y" #t)             ; 3
               (test-assert "z" #t)))
       => '(("v" "w" "y" "z") () () () ("x") (4 0 0 0 1)))          ; 4

;; "5.2.2. skip m, starting at n"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-nth 2 2))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP
               (test-assert "y" #t)             ; 3 SKIP
               (test-assert "z" #t)))
       => '(("v" "w" "z") () () () ("x" "y") (3 0 0 0 2)))          ; 4

;; （外层）(test-end)

;; （外层）(test-begin "5.3. test-match-any")
;; "5.3.1. basic disjunction"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-any (test-match-nth 3)
                                          (test-match-name "x")))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP(NAME)
               (test-assert "y" #t)             ; 3 SKIP(COUNT)
               (test-assert "z" #t)))
       => '(("v" "w" "z") () () () ("x" "y") (3 0 0 0 2)))          ; 4

;; "5.3.2. disjunction is commutative"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-any (test-match-name "x")
                                          (test-match-nth 3)))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP(NAME)
               (test-assert "y" #t)             ; 3 SKIP(COUNT)
               (test-assert "z" #t)))
       => '(("v" "w" "z") () () () ("x" "y") (3 0 0 0 2)))          ; 4

;; （外层）(test-end)

;; （外层）(test-begin "5.4. test-match-all")
;; "5.4.1. basic conjunction"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-all (test-match-nth 2 2)
                                          (test-match-name "x")))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP(NAME) & SKIP(COUNT)
               (test-assert "y" #t)             ; 3 SKIP(COUNT)
               (test-assert "z" #t)))
       => '(("v" "w" "y" "z") () () () ("x") (4 0 0 0 1)))          ; 4

;; "5.4.2. conjunction is commutative"
(check (triv-runner
             (lambda ()
               (test-assert "v" #t)
               (test-skip (test-match-all (test-match-name "x")
                                          (test-match-nth 2 2)))
               (test-assert "w" #t)             ; 1
               (test-assert "x" #t)             ; 2 SKIP(NAME) & SKIP(COUNT)
               (test-assert "y" #t)             ; 3 SKIP(COUNT)
               (test-assert "z" #t)))
       => '(("v" "w" "y" "z") () () () ("x") (4 0 0 0 1)))          ; 4

;; （外层）(test-end)

;; （外层）(test-end "5. Test specifiers")

;;;
;;;
;;;

;; （外层）(test-begin "6. Skipping selected tests")

;; "6.1. Skip by specifier - match-name"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip (test-match-name "y"))
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; SKIP
    (test-end)))
       => '(("x") () () () ("y") (1 0 0 0 1)))

;; "6.2. Shorthand specifiers"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "y")
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; SKIP
    (test-end)))
       => '(("x") () () () ("y") (1 0 0 0 1)))

;; （外层）(test-begin "6.3. Specifier Stack")

;; "6.3.1. Clearing the Specifier Stack"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "y")
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; SKIP
    (test-end)
    (test-begin "b")
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; FAIL
    (test-end)))
       => '(("x" "x") ("y") () () ("y") (2 1 0 0 1)))

;; "6.3.2. Inheriting the Specifier Stack"
(check (triv-runner
  (lambda ()
    (test-skip "y")
    (test-begin "a")
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; SKIP
    (test-end)
    (test-begin "b")
    (test-assert "x" #t)      ; PASS
    (test-assert "y" #f)      ; SKIP
    (test-end)))
       => '(("x" "x") () () () ("y" "y") (2 0 0 0 2)))

;; （外层）(test-end);6.3

;; （外层）(test-begin "6.4. Short-circuit evaluation")

;; "6.4.1. In test-match-all"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip (test-match-all "y" (test-match-nth 2)))
    ;; let's label the substructure forms so we can
    ;; see which one `test-match-nth' is going to skip
    ;;                        ; #   "y"  2   result
    (test-assert "x" #t)      ; 1 - #f   #f  PASS   
    (test-assert "y" #f)      ; 2 - #t   #t  SKIP 
    (test-assert "y" #f)      ; 3 - #t   #f  FAIL
    (test-assert "x" #f)      ; 4 - #f   #f  FAIL
    (test-assert "z" #f)      ; 5 - #f   #f  FAIL
    (test-end)))
       => '(("x") ("y" "x" "z") () () ("y") (1 3 0 0 1)))

;; "6.4.2. In separate skip-list entries"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "y")
    (test-skip (test-match-nth 2))
    ;; let's label the substructure forms so we can
    ;; see which one `test-match-nth' is going to skip
    ;;                        ; #   "y"  2   result
    (test-assert "x" #t)      ; 1 - #f   #f  PASS   
    (test-assert "y" #f)      ; 2 - #t   #t  SKIP 
    (test-assert "y" #f)      ; 3 - #t   #f  SKIP
    (test-assert "x" #f)      ; 4 - #f   #f  FAIL
    (test-assert "z" #f)      ; 5 - #f   #f  FAIL
    (test-end)))
       => '(("x") ("x" "z") () () ("y" "y") (1 2 0 0 2)))

;; （外层）(test-begin "6.4.3. Skipping test suites")

;; "6.4.3.1. Introduced using 'test-begin'"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "b")
    (test-begin "b")            ; not skipped
    (test-assert "x" #t)
    (test-end "b")
    (test-end "a")))
       => '(("x") () () () () (1 0 0 0 0)))

;; （外层）(test-expect-fail 1)：下一项是参照实现的已知不符，见下 ;; ???
;; "6.4.3.2. Introduced using 'test-group'"
;; 原测试以 test-expect-fail 标注：参照实现的结果与期望不同。这里检查确实不同（结果改变时应复核）。
(check (equal? '(() () () () () (0 0 0 0 1))
               (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "b")
    (test-group 
     "b"            ; skipped
     (test-assert "x" #t))
    (test-end "a"))))
       => #f)

;; "6.4.3.3. Non-skipped 'test-group'"
(check (triv-runner
  (lambda ()
    (test-begin "a")
    (test-skip "c")
    (test-group "b" (test-assert "x" #t))
    (test-end "a")))
       => '(("x") () () () () (1 0 0 0 0)))

;; （外层）(test-end) ; 6.4.3
 
;; （外层）(test-end);6.4

;; （外层）(test-end "6. Skipping selected tests")

;;;
;;;
;;;

;; （外层）(test-begin "7. Expected failures")

;; "7.1. Simple example"
(check (triv-runner
             (lambda ()
               (test-assert "x" #f)
               (test-expect-fail "z")
               (test-assert "z" #f)))
       => '(() ("x") ("z") () () (0 1 1 0 0)))

;; "7.2. Expected exception"
(check (triv-runner
             (lambda ()
               (test-assert "x" #f)
               (test-expect-fail "z")
               (test-assert "z" (choke))))
       => '(() ("x") ("z") () () (0 1 1 0 0)))

;; "7.3. Unexpectedly PASS"
(check (triv-runner
             (lambda ()
               (test-expect-fail "x")
               (test-expect-fail "y")
               (test-assert "x" #t)
               (test-assert "y" #f)))
       => '(() () ("y") ("x") () (0 0 1 1 0)))
               


;; （外层）(test-end "7. Expected failures")

;;;
;;;
;;;

;; （外层）(test-begin "8. Test-runner")

;;;
;;;  Because we want this test suite to be accurate even
;;;  when the underlying implementation chooses to use, e.g.,
;;;  a global variable to implement what could be thread variables
;;;  or SRFI-39 parameter objects, we really need to save and restore
;;;  their state ourselves
;;;
(define (with-factory-saved thunk)
  (let* ((saved (test-runner-factory))
         (result (thunk)))
    (test-runner-factory saved)
    result))

;; （外层）(test-begin "8.1. test-runner-current")
;; "8.1.1. automatically restored"
(check (if (let ((a 0)
                   (b 1)
                   (c 2))
               ;
               (triv-runner
                (lambda ()
                  (set! a (test-runner-current))
                  ;;
                  (triv-runner
                   (lambda ()
                     (set! b (test-runner-current))))
                  ;;
                  (set! c (test-runner-current))))
               ;;
               (and (eq? a c)
                    (not (eq? a b)))) #t #f) => #t)
              
;; （外层）(test-end)

;; （外层）(test-begin "8.2. test-runner-simple")
;; "8.2.1. default on-test hook"
(check (if (eq? (test-runner-on-test-end (test-runner-simple))
                  test-on-test-end-simple) #t #f) => #t)
;; "8.2.2. default on-final hook"
(check (if (eq? (test-runner-on-final (test-runner-simple))
                  test-on-final-simple) #t #f) => #t)
;; （外层）(test-end)

;; （外层）(test-begin "8.3. test-runner-factory")

;; "8.3.1. default factory"
(check (if (eq? (test-runner-factory) test-runner-simple) #t #f) => #t)

;; "8.3.2. settable factory"
(check (if (with-factory-saved
              (lambda ()
                (test-runner-factory test-runner-null)
                ;; we have no way, without bringing in other SRFIs,
                ;; to make sure the following doesn't print anything,
                ;; but it shouldn't:
                (test-with-runner
                 (test-runner-create)
                 (lambda ()
                   (test-begin "a")
                   (test-assert #t)             ; pass
                   (test-assert #f)             ; fail
                   (test-assert (vector-ref '#(3) 10))  ; fail with error
                   (test-end "a")))
                (eq? (test-runner-factory) test-runner-null))) #t #f) => #t)
                
;; （外层）(test-end)

;;; This got tested about as well as it could in 8.3.2

;; （外层）(test-begin "8.4. test-runner-create")
;; （外层）(test-end)

;;; This got tested about as well as it could in 8.3.2 

;; （外层）(test-begin "8.5. test-runner-factory")
;; （外层）(test-end)

;; （外层）(test-begin "8.6. test-apply")
;; "8.6.1. Simple (form 1) test-apply"
(check (triv-runner
             (lambda ()
               (test-begin "a")
               (test-assert "w" #t)
               (test-apply
                (test-match-name "p")
                (lambda ()
                  (test-begin "p")
                  (test-assert "x" #t)
                  (test-end)
                  (test-begin "z")
                  (test-assert "p" #t)  ; only this one should execute in here
                  (test-end)))
               (test-assert "v" #t)))
       => '(("w" "p" "v") () () () ("x") (3 0 0 0 1)))

;; "8.6.2. Simple (form 2) test-apply"
(check (triv-runner
             (lambda ()
               (test-begin "a")
               (test-assert "w" #t)
               (test-apply
                (test-runner-current)
                (test-match-name "p")
                (lambda ()
                  (test-begin "p")
                  (test-assert "x" #t)
                  (test-end)
                  (test-begin "z")
                  (test-assert "p" #t)  ; only this one should execute in here
                  (test-end)))
               (test-assert "v" #t)))
       => '(("w" "p" "v") () () () ("x") (3 0 0 0 1)))

;; （外层）(test-expect-fail 1)：下一项是参照实现的已知不符，见下 ;; depends on all test-match-nth being called.
;; "8.6.3. test-apply with skips"
;; 原测试以 test-expect-fail 标注：参照实现的结果与期望不同。这里检查确实不同（结果改变时应复核）。
(check (equal? '(("w" "q" "v") () () () ("x" "p" "x") (3 0 0 0 3))
               (triv-runner
             (lambda ()
               (test-begin "a")
               (test-assert "w" #t)
               (test-skip (test-match-nth 2))
               (test-skip (test-match-nth 4))
               (test-apply
                (test-runner-current)
                (test-match-name "p")
                (test-match-name "q")
                (lambda ()
                                        ; only execute if SKIP=no and APPLY=yes
                  (test-assert "x" #t)  ; # 1 SKIP=no  APPLY=no
                  (test-assert "p" #t)  ; # 2 SKIP=yes APPLY=yes
                  (test-assert "q" #t)  ; # 3 SKIP=no  APPLY=yes
                  (test-assert "x" #f)  ; # 4 SKIP=yes APPLY=no
                  0))
               (test-assert "v" #t))))
       => #f)

;;;  Unfortunately, since there is no way to UNBIND the current test runner,
;;;  there is no way to test the behavior of `test-apply' in the absence
;;;  of a current runner within our little meta-test framework.
;;;
;;;  To test the behavior manually, you should be able to invoke:
;;;
;;;     (test-apply "a" (lambda () (test-assert "a" #t)))
;;;
;;;  from the top level (with SRFI 64 available) and it should create a
;;;  new, default (simple) test runner.

;; （外层）(test-end)

;;;  This entire suite depends heavily on 'test-with-runner'.  If it didn't
;;;  work, this suite would probably go down in flames
;; （外层）(test-begin "8.7. test-with-runner")
;; （外层）(test-end)

;;;  Again, this suite depends heavily on many of the test-runner
;;;  components.  We'll just test those that aren't being exercised
;;;  by the meta-test framework
;; （外层）(test-begin "8.8. test-runner components")

(define (auxtrack-runner thunk)
  (let ((r (test-runner-null)))
    (test-runner-aux-value! r '())
    (test-runner-on-test-end! r (lambda (r)
                              (test-runner-aux-value!
                               r
                               (cons (test-runner-test-name r)
                                     (test-runner-aux-value r)))))
    (test-with-runner r (thunk))
    (reverse (test-runner-aux-value r))))

;; "8.8.1. test-runner-aux-value"
(check (auxtrack-runner
             (lambda ()
               (test-assert "x" #t)
               (test-begin "a")
               (test-assert #t)
               (test-end)
               (test-assert "y" #f)))
       => '("x" "" "y"))

;; （外层）(test-end) ; 8.8

;; （外层）(test-end "8. Test-runner")

;; （外层）(test-begin "9. Test Result Properties")

;; （外层）(test-begin "9.1. test-result-alist")

(define (symbol-alist? l)
  (if (null? l)
      #t
      (and (pair? l)
           (pair? (car l))
           (symbol? (caar l))
           (symbol-alist? (cdr l)))))

;;; check the various syntactic forms

(check (if (symbol-alist?
              (car (on-test-runner
                    (lambda ()
                      (test-assert #t))
                    (lambda (r)
                      (test-result-alist r))))) #t #f) => #t)

(check (if (symbol-alist?
              (car (on-test-runner
                    (lambda ()
                      (test-assert #t))
                    (lambda (r)
                      (test-result-alist r))))) #t #f) => #t)

;;; check to make sure the required properties are returned

(check (prop-runner
             '(result-kind)
             (lambda ()
               (test-assert #t)))
       => '((result-kind . pass)))

(check (prop-runner
             '(result-kind expected-value actual-value)
             (lambda ()
               (test-equal 2 (+ 1 2))))
       => '((result-kind . fail)
              (expected-value . 2)
              (actual-value . 3)))

;; （外层）(test-end "9.1. test-result-alist")

;; （外层）(test-begin "9.2. test-result-ref")

(check (on-test-runner
             (lambda ()
               (test-assert #t))
             (lambda (r)
               (test-result-ref r 'result-kind)))
       => '(pass))

(check (on-test-runner
             (lambda ()
               (test-assert #t))
             (lambda (r)
               (test-result-ref r 'result-kind)))
       => '(pass))

(check (on-test-runner
             (lambda ()
               (test-assert (= 1 2))
               (test-assert (= 1 1)))
             (lambda (r)
               (test-result-ref r 'result-kind)))
       => '(fail pass))

;; （外层）(test-end "9.2. test-result-ref")

;; （外层）(test-begin "9.3. test-result-set!")

(check (on-test-runner
             (lambda ()
               (test-assert (= 1 2))
               (test-assert (= 1 1)))
             (lambda (r)
               (test-result-set! r 'foo 100)
               (test-result-ref r 'foo)))
       => '(100 100))

;; （外层）(test-end "9.3. test-result-set!")

;; （外层）(test-end "9. Test Result Properties")

;;;
;;;
;;;

#|  Time to stop having fun...

(test-begin "9. For fun, some meta-test errors")

(test-equal
 "9.1. Really PASSes, but test like it should FAIL"
 '(() ("b") () () ())
 (triv-runner
  (lambda ()
    (test-assert "b" #t))))

(test-expect-fail "9.2. Expect to FAIL and do so")
(test-expect-fail "9.3. Expect to FAIL but PASS")
(test-skip "9.4. SKIP this one")

(test-assert "9.2. Expect to FAIL and do so" #f)
(test-assert "9.3. Expect to FAIL but PASS" #t)
(test-assert "9.4. SKIP this one" #t)

(test-end)
 |#

;; （外层）(test-end "SRFI 64 - Meta-Test Suite")

;;;

;;; ———————————————— SRFI 64 补充（原元测试集未覆盖的导出名，按 SRFI 64 文本） ————————————————
;; 用空运行器运行 thunk，返回 (通过 失败 预期失败 意外通过 跳过)
(define (counts-of thunk)
  (let ((r (test-runner-null)))
    (test-with-runner r (thunk))
    (list (test-runner-pass-count r) (test-runner-fail-count r) (test-runner-xfail-count r)
          (test-runner-xpass-count r) (test-runner-skip-count r))))

(check (counts-of (lambda () (test-eq 'a 'a) (test-eq "a" (string #\b)))) => '(1 1 0 0 0))
(check (counts-of (lambda () (test-approximate 1.0 1.05 0.1) (test-approximate 1.0 1.5 0.1))) => '(1 1 0 0 0))
(check (test-runner? (test-runner-null)) => #t)
(check (test-runner? 'x) => #f)
(check (let ((r (test-runner-null)) (got #f))
         (test-with-runner r (set! got (test-runner-get)))
         (eq? got r))
       => #t)
;; 计数的设置与 reset
(check (let ((r (test-runner-null)))
         (test-runner-pass-count! r 3) (test-runner-fail-count! r 4) (test-runner-xfail-count! r 5)
         (test-runner-xpass-count! r 6) (test-runner-skip-count! r 7)
         (let ((before (list (test-runner-pass-count r) (test-runner-fail-count r) (test-runner-xfail-count r)
                             (test-runner-xpass-count r) (test-runner-skip-count r))))
           (test-runner-reset r)
           (list before (test-runner-pass-count r) (test-runner-skip-count r))))
       => '((3 4 5 6 7) 0 0))
;; 组栈
(check (let ((r (test-runner-null)) (stack #f))
         (test-with-runner r
           (begin (test-begin "a") (test-begin "b")
                  (set! stack (test-runner-group-stack r))
                  (test-end "b") (test-end "a")))
         stack)
       => '("b" "a"))
(check (let ((r (test-runner-null)))
         (test-runner-group-stack! r '("x"))
         (test-runner-group-stack r))
       => '("x"))
;; 回调：设置与读取，并确认被调用
(check (let ((r (test-runner-null)) (log '()))
         (define (note x) (set! log (cons x log)))
         (test-runner-on-test-begin! r (lambda (r) (note 'test-begin)))
         (test-runner-on-group-begin! r (lambda (r name count) (note (list 'group-begin name count))))
         (test-runner-on-group-end! r (lambda (r) (note 'group-end)))
         (test-runner-on-final! r (lambda (r) (note 'final)))
         (test-with-runner r
           (begin (test-begin "g" 1) (test-assert #t) (test-end "g")))
         (list (procedure? (test-runner-on-test-begin r)) (procedure? (test-runner-on-group-begin r))
               (procedure? (test-runner-on-group-end r)) (reverse log)))
       => '(#t #t #t ((group-begin "g" 1) test-begin group-end final)))
(check (let ((r (test-runner-simple)))
         (list (eq? (test-runner-on-group-begin r) test-on-group-begin-simple)
               (eq? (test-runner-on-group-end r) test-on-group-end-simple)
               (eq? (test-runner-on-bad-count r) test-on-bad-count-simple)
               (eq? (test-runner-on-bad-end-name r) test-on-bad-end-name-simple)))
       => '(#t #t #t #t))
;; test-passed? 与结果属性（test-result-remove 验证了文件头 ⑤ 的修正）
(check (let ((r (test-runner-null)) (seen '()))
         (test-runner-on-test-end! r
           (lambda (r)
             (set! seen (cons (list (and (test-passed? r) #t) (test-result-kind r)) seen))))   ; test-passed? 返回真值
         (test-with-runner r (begin (test-assert "p" #t) (test-assert "f" #f)))
         (reverse seen))
       => '((#t pass) (#f fail)))
(check (let ((r (test-runner-null)))
         (test-result-alist! r '((a . 1) (b . 2)))
         (test-result-remove r 'a)
         (let ((after-remove (test-result-alist r)))
           (test-result-clear r)
           (list after-remove (test-result-alist r))))
       => '(((b . 2)) ()))
;; 其他
(check (test-read-eval-string "(+ 1 2)") => 3)
(check (test-log-to-file) => #f)                      ; 缺省不写日志文件
(test-log-to-file "x.log")
(check (test-log-to-file) => "x.log")
(test-log-to-file #f)

;;; ———————————————— SRFI 78 ————————————————
;; SRFI 78 的例子（examples.scm，Sebastian Egner）：9 项正确、4 项故意失败（与原测试的结果相同）。
;; 被测的 check 把结果打印到当前输出端口，这里捕获下来再判定。
(define (fib n)
  (if (<= n 2) 1 (+ (fib (- n 1)) (fib (- n 2)))))

(define (capture thunk)
  (call-with-string-output-port
    (lambda (p) (parameterize ((current-output-port p)) (thunk)))))

(define (contains? s sub)
  (let ((n (string-length s)) (m (string-length sub)))
    (let loop ((i 0))
      (and (<= (+ i m) n)
           (or (string=? (substring s i (+ i m)) sub)
               (loop (+ i 1)))))))

(define examples-output
  (capture
    (lambda ()
      (lt:check-reset!)
      (lt:check (+ 1 1) => 2)
      (lt:check (+ 1 1) => 3)                                   ; fails
      (lt:check (vector 1) => (vector 1))
      (lt:check (vector 1) (=> eq?) (vector 1))                 ; fails
      (lt:check-ec (+ 1 1) => 2)
      (lt:check-ec (: x 10) (+ x 1) => (+ x 1) (x))
      (lt:check-ec (: e 100) (positive? (expt 2 e)) => #t (e))  ; 原注释 fails on fixnums：IronScheme 有大整数，通过
      (lt:check-ec (: e 100) (:let x (expt 2.0 e)) (= (+ x 1) x) => #f (x))   ; fails
      (lt:check-ec (: e 100) (:let x (expt 2.0 e)) (= (+ x 1) x) => #f)       ; fails
      (lt:check-ec (: x 10) (: y 10) (: z 10)
                   (* x (+ y z)) => (+ (* x y) (* x z))
                   (x y z))                                     ; 10^3 cases
      (lt:check (fib 1) => 1)
      (lt:check (fib 2) => 1)
      (lt:check-ec (: n 1 31) (even? (fib n)) => (= (modulo n 3) 0) (n))
      (lt:check-report))))

(check (contains? examples-output ";; *** checks *** : 9 correct, 4 failed.") => #t)
(check (contains? examples-output ";; correct (1000 cases checked)") => #t)
(check (lt:check-passed? 9) => #f)                       ; 有失败
;; check-reset! 与 check-passed?
(define reset-output
  (capture
    (lambda ()
      (lt:check-reset!)
      (lt:check (+ 1 2) => 3)
      (lt:check-ec (: i 5) i => i)
      (lt:check-report))))
(check (lt:check-passed? 2) => #t)
(check (lt:check-passed? 3) => #f)
(check (contains? reset-output ";; *** checks *** : 2 correct, 0 failed.") => #t)
;; check-set-mode!：off 时不检查也不计数；summary 时只在报告中给出计数
(lt:check-reset!)
(lt:check-set-mode! 'off)
(lt:check (+ 1 1) => 3)
(check (lt:check-passed? 0) => #t)
(lt:check-set-mode! 'summary)
(check (capture (lambda () (lt:check (+ 1 1) => 2))) => "")
(check (lt:check-passed? 1) => #t)
(lt:check-set-mode! 'report)
(check-raises assertion-violation? (lt:check-set-mode! 'loud))

(check-report "std testing")
