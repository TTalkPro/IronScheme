;;; std 测试的公共部分（designs/08-std-library.md D8）：(check 表达式 => 期望) 用 equal? 比较；
;;; (check-report "名字") 在最后打印 "名字: all passed (n checks)" 或失败数，供 C# 测试判断。
;;; 不用 (ironscheme std testing)：被测的库不应参与测自己。
(define check-count 0)
(define check-failures 0)

(define-syntax check
  (syntax-rules (=>)
    ((_ expr => expected)
     (let ((v (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e)))) expr))
           (x expected))
       (set! check-count (+ check-count 1))
       (unless (equal? v x)
         (set! check-failures (+ check-failures 1))
         (display "FAIL: ") (write 'expr) (display " => ") (write v)
         (display ", expected ") (write x) (newline))))))

;; 表达式应当引发条件（pred 判断条件对象）
(define-syntax check-raises
  (syntax-rules ()
    ((_ pred expr)
     (check (guard (e ((pred e) 'raised) (#t (list 'wrong-condition e))) expr 'returned) => 'raised))))

(define (check-report name)
  (display name)
  (if (= check-failures 0)
      (begin (display ": all passed (") (display check-count) (display " checks)"))
      (begin (display ": ") (display check-failures) (display " of ") (display check-count) (display " checks failed")))
  (newline))
