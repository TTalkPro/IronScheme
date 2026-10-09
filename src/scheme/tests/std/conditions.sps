;;; (ironscheme std conditions) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 35 的测试；
;;; 按 SRFI 35 的文本（例子改用 R6RS 条件类型）编写，每个导出名至少一项。
(import (rnrs) (only (ironscheme) include) (ironscheme std conditions))
(include "tests/std/check.ss")

(define &c (record-type-descriptor &condition))
(define &msg (record-type-descriptor &message))
(define &err (record-type-descriptor &error))

;;; ———————————————— 条件类型 ————————————————
(check (condition-type? &c) => #t)
(check (condition-type? &msg) => #t)
(check (condition-type? (record-type-descriptor &i/o)) => #t)
(check (condition-type? 'foo) => #f)
(define-record-type plain (fields a))
(check (condition-type? (record-type-descriptor plain)) => #f)

;; SRFI 35 的例子：c 类型带 b 字段，c1、c2 是它的子类型
(define &c-type (make-condition-type 'c &c '(b)))
(define &c1 (make-condition-type 'c1 &c-type '(b1)))
(define &c2 (make-condition-type 'c2 &c-type '(b2)))
(check (condition-type? &c1) => #t)
(check-raises assertion-violation? (make-condition-type 'bad &c-type '(b)))   ; 与祖先字段重名
(check-raises assertion-violation? (make-condition-type "c" &c '()))
(check-raises assertion-violation? (make-condition-type 'x 'not-a-type '()))

;;; ———————————————— 构造与访问 ————————————————
(define v1 (make-condition &c1 'b "b-v1" 'b1 "b1"))
(check (condition? v1) => #t)
(check (condition-has-type? v1 &c1) => #t)
(check (condition-has-type? v1 &c-type) => #t)        ; 子类型
(check (condition-has-type? v1 &c2) => #f)
(check (condition-ref v1 'b) => "b-v1")
(check (condition-ref v1 'b1) => "b1")
(check-raises assertion-violation? (condition-ref v1 'zzz))
(check-raises assertion-violation? (make-condition &c1 'b 1))          ; 缺字段

(define v2 (make-condition &c2 'b "b-v2" 'b2 "b2"))
(define v3 (make-compound-condition v1 v2))
(check (condition-has-type? v3 &c1) => #t)
(check (condition-has-type? v3 &c2) => #t)
(check (condition-ref v3 'b) => "b-v1")               ; 第一个有该字段的成员
(check (condition-ref v3 'b2) => "b2")
(check (condition-ref (extract-condition v3 &c2) 'b) => "b-v2")
(check (condition-has-type? (extract-condition v3 &c2) &c1) => #f)
(check-raises assertion-violation? (extract-condition v1 &c2))

;;; ———————————————— 与 R6RS 条件互通 ————————————————
(define m (make-condition &msg 'message "hello"))
(check (message-condition? m) => #t)
(check (condition-message m) => "hello")
(define r6 (condition (make-error) (make-message-condition "boom")))
(check (condition-has-type? r6 &err) => #t)
(check (condition-ref r6 'message) => "boom")
(check (error? (extract-condition r6 &err)) => #t)
(check (guard (e ((condition-has-type? e &c1) (condition-ref e 'b1)))
         (raise (make-compound-condition (make-error) v1)))
       => "b1")

(check-report "std conditions")
