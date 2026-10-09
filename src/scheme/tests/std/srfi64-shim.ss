;;; 把以 SRFI 64 写成的原测试（test-begin、test-equal、test-assert、test-error …）接到 tests/std/check.ss 的
;;; 计数上（designs/08-std-library.md D8）。在 (include "tests/std/check.ss") 之后 include 本文件。
;;; test-equal / test-eqv / test-eq / test-assert / test-approximate / test-error 各计一项，失败时显示测试名；
;;; test-begin / test-end 不做事，test-group 只是把各项包在一起；不支持 test-skip 等运行器控制。
;;; 不用 (ironscheme std testing)：被测的库不应参与测自己，测试 testing 库本身时也不 include 本文件。
;;; （iron-043、iron-044 两个分支各写过一份，iron-046 合并为本文件。）
;; 按给定的比较过程计一项
(define (check-64-record ok? name expr-form actual expected)
  (set! check-count (+ check-count 1))
  (unless ok?
    (set! check-failures (+ check-failures 1))
    (display "FAIL: ") (when name (display name) (display " ")) (write expr-form)
    (display " => ") (write actual) (display ", expected ") (write expected) (newline)))

(define-syntax check-64-compare
  (syntax-rules ()
    ((_ same? name expected expr)
     (let ((x expected)
           (v (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e)))) expr)))
       (check-64-record (same? v x) name 'expr v x)))))

(define-syntax test-begin (syntax-rules () ((_ . r) (begin))))
(define-syntax test-end (syntax-rules () ((_ . r) (begin))))

(define-syntax test-group
  (syntax-rules ()
    ((_ name body ...) (let () body ... (if #f #f)))))

(define-syntax test-equal
  (syntax-rules ()
    ((_ name expected expr) (check-64-compare equal? name expected expr))
    ((_ expected expr) (check-64-compare equal? #f expected expr))))

(define-syntax test-eqv
  (syntax-rules ()
    ((_ name expected expr) (check-64-compare eqv? name expected expr))
    ((_ expected expr) (check-64-compare eqv? #f expected expr))))

(define-syntax test-eq
  (syntax-rules ()
    ((_ name expected expr) (check-64-compare eq? name expected expr))
    ((_ expected expr) (check-64-compare eq? #f expected expr))))

(define-syntax test-assert
  (syntax-rules ()
    ((_ name expr) (check-64-compare (lambda (v x) (and v (not (and (pair? v) (eq? (car v) 'raised))))) name #t expr))
    ((_ expr) (test-assert #f expr))))

(define-syntax test-approximate
  (syntax-rules ()
    ((_ name expected expr error)
     (check-64-compare (lambda (v x) (and (number? v) (<= (abs (- v x)) error))) name expected expr))
    ((_ expected expr error) (test-approximate #f expected expr error))))

(define-syntax test-error
  (syntax-rules ()
    ((_ name type expr)
     (check-64-record (guard (e (#t #t)) expr #f) name 'expr 'returned 'raised))
    ((_ type expr) (test-error #f type expr))
    ((_ expr) (test-error #f #t expr))))
