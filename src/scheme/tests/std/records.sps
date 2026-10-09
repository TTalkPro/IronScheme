;;; (ironscheme std records) 的测试（designs/08-std-library.md D8）。chez-srfi 的 tests/records.sps 测的是
;;; SRFI 9（R6RS define-record-type 已代替），没有 SRFI 99 的测试；按 SRFI 99 的文本编写，每个导出名至少一项。
(import (rnrs) (only (ironscheme) include) (ironscheme std records))
(include "tests/std/check.ss")

;;; ———————————————— make-rtd 与构造、访问 ————————————————
(define point (make-rtd 'point '#((mutable x) (immutable y))))
(define make-point (rtd-constructor point))
(define point? (rtd-predicate point))
(define point-x (rtd-accessor point 'x))
(define point-y (rtd-accessor point 'y))
(define set-point-x! (rtd-mutator point 'x))
(define p (make-point 1 2))
(check (rtd? point) => #t)
(check (rtd? 'point) => #f)
(check (point? p) => #t)
(check (point? 5) => #f)
(check (list (point-x p) (point-y p)) => '(1 2))
(check (begin (set-point-x! p 10) (point-x p)) => 10)
(check (rtd-name point) => 'point)
(check (rtd-parent point) => #f)
(check (rtd-field-names point) => '#(x y))
(check (rtd-field-mutable? point 'x) => #t)
(check (rtd-field-mutable? point 'y) => #f)
(check-raises assertion-violation? (rtd-mutator point 'z))

;; 字段说明可以只写符号（可变字段），也可以用表
(define cell (make-rtd 'cell '(content)))
(check (rtd-field-mutable? cell 'content) => #t)

;;; ———————————————— 继承 ————————————————
(define point3 (make-rtd 'point3 '#((mutable z)) point))
(check (rtd-parent point3) => point)
(check (rtd-field-names point3) => '#(z))
(check (rtd-all-field-names point3) => '#(x y z))
(define make-point3 (rtd-constructor point3))
(define q (make-point3 1 2 3))
(check (list (point? q) ((rtd-predicate point3) q) (point-x q) ((rtd-accessor point3 'z) q)) => '(#t #t 1 3))
;; 按字段名访问父类字段
(check ((rtd-accessor point3 'y) q) => 2)
(check (rtd-field-mutable? point3 'x) => #t)

;;; ———————————————— 按字段名子集构造 ————————————————
;; 未给出的字段的值未指定，这里只检查给出的
(define make-point3-zx (rtd-constructor point3 '#(z x)))
(define r (make-point3-zx 30 10))
(check (list (point-x r) ((rtd-accessor point3 'z) r)) => '(10 30))

;;; ———————————————— 选项：sealed、opaque、uid ————————————————
(define sealed-rtd (make-rtd 'sealed '#(a) #f 'sealed))
(check (record-type-sealed? sealed-rtd) => #t)
(define opaque-rtd (make-rtd 'opaque '#(a) #f 'opaque))
(check (record? ((rtd-constructor opaque-rtd) 1)) => #f)            ; 不透明：record? 为 #f
(define u1 (make-rtd 'u '#(a) #f 'uid 'std-records-test-uid))
(define u2 (make-rtd 'u '#(a) #f 'uid 'std-records-test-uid))
(check (eq? u1 u2) => #t)                                       ; 同一 uid：非生成的同一类型

;;; ———————————————— 与 R6RS 记录互通 ————————————————
(define-record-type thing (fields (mutable name)))
(check (rtd? (record-type-descriptor thing)) => #t)
(check ((rtd-accessor (record-type-descriptor thing) 'name) (make-thing 'n)) => 'n)
(check (rtd-name (record-rtd (make-thing 'n))) => 'thing)
(check (point-y ((record-constructor (make-record-constructor-descriptor point #f #f)) 5 6)) => 6)

(check-report "std records")
