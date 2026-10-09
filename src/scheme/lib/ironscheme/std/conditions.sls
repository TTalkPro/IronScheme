#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std conditions) —— SRFI 35 的条件类型过程（designs/08-std-library.md）
;;; 词源：SRFI 35（Richard Kelsey、Michael Sperber）。
;;;
;;; 与参照实现不同（D4）：参照实现自带一套与 R6RS 并行的条件系统（自己的 &condition、condition? …）。
;;; 那些名字与基础库同名（D2 不导出），只导出 7 个新名字时用户拿不到它的根类型，过程无法使用。
;;; 这里按 SRFI 35 的文本在 R6RS 条件之上重写（参照代码未保留）：
;;;   条件类型 = &condition 的子类型的 R6RS 记录类型描述符，如 (record-type-descriptor &message)；
;;;   make-condition-type 创建的类型可与 R6RS 的条件、raise、guard、condition-message 等一起使用；
;;;   make-condition 必须给出类型（含祖先）的全部字段；extract-condition 返回复合条件中属于该类型的
;;;   第一个简单条件。
;;;
;;; 你要的在 IronScheme 里叫什么（D2：SRFI 35 中下列名字与基础库同名，本库不导出，用 R6RS 的）：
;;;   &condition &message &serious &error  条件类型名（语法关键字；取描述符用 record-type-descriptor）
;;;   condition?  error?  message-condition?  serious-condition?  condition-message
;;;   condition            R6RS 的 condition 是过程（合并条件）；SRFI 35 的同名语法用 make-condition +
;;;                        make-compound-condition
;;;   define-condition-type R6RS 版本还要给出构造器名：(define-condition-type &x &error make-x x? (f x-f))
(library (ironscheme std conditions)
  (export
    condition-has-type? condition-ref condition-type? extract-condition
    make-compound-condition make-condition make-condition-type)
  (import
    (rnrs))

;; 条件类型：&condition 的子类型（R6RS 记录类型描述符）
(define condition-rtd (record-type-descriptor &condition))

(define (condition-type? obj)
  (and (record-type-descriptor? obj)
       (let loop ((rtd obj))
         (cond ((not rtd) #f)
               ((eq? rtd condition-rtd) #t)
               (else (loop (record-type-parent rtd)))))))

(define (check-condition-type who type)
  (unless (condition-type? type)
    (assertion-violation who "not a condition type" type)))

;; 类型及其祖先的全部字段名，祖先在前（R6RS 默认构造器的参数次序）
(define (all-field-names type)
  (let loop ((rtd type) (acc '()))
    (if rtd
        (loop (record-type-parent rtd)
              (append (vector->list (record-type-field-names rtd)) acc))
        acc)))

(define (make-condition-type name supertype fields)
  (unless (symbol? name)
    (assertion-violation 'make-condition-type "name is not a symbol" name))
  (check-condition-type 'make-condition-type supertype)
  (unless (and (list? fields) (for-all symbol? fields))
    (assertion-violation 'make-condition-type "fields is not a list of symbols" fields))
  (let ((inherited (all-field-names supertype)))
    (for-each (lambda (f)
                (when (memq f inherited)
                  (assertion-violation 'make-condition-type "duplicate field name" f)))
              fields))
  (make-record-type-descriptor name supertype #f #f #f
    (list->vector (map (lambda (f) (list 'immutable f)) fields))))

;; (make-condition 类型 字段名 值 …)：必须给出类型（含祖先）的全部字段
(define (make-condition type . field-plist)
  (check-condition-type 'make-condition type)
  (let ((alist (let loop ((plist field-plist))
                 (cond ((null? plist) '())
                       ((and (pair? (cdr plist)) (symbol? (car plist)))
                        (cons (cons (car plist) (cadr plist)) (loop (cddr plist))))
                       (else (assertion-violation 'make-condition "malformed field list" field-plist)))))
        (names (all-field-names type)))
    (unless (and (= (length alist) (length names))
                 (for-all (lambda (n) (assq n alist)) names))
      (assertion-violation 'make-condition "condition fields don't match condition type" type field-plist))
    (apply (record-constructor (make-record-constructor-descriptor type #f #f))
           (map (lambda (n) (cdr (assq n alist))) names))))

(define (condition-has-type? condition type)
  (check-condition-type 'condition-has-type? type)
  (let ((pred (record-predicate type)))
    (exists pred (simple-conditions condition))))

;; 在简单条件 c 的类型链上按字段名找访问器
(define (field-accessor rtd field)
  (let loop ((rtd rtd))
    (and rtd
         (let ((names (vector->list (record-type-field-names rtd))))
           (cond ((memq field names)
                  => (lambda (tail) (record-accessor rtd (- (length names) (length tail)))))
                 (else (loop (record-type-parent rtd))))))))

(define (condition-ref condition field)
  (let loop ((cs (simple-conditions condition)))
    (if (null? cs)
        (assertion-violation 'condition-ref "field not found" condition field)
        (let ((get (field-accessor (record-rtd (car cs)) field)))
          (if get (get (car cs)) (loop (cdr cs)))))))

(define (make-compound-condition condition-1 . conditions)
  (apply condition condition-1 conditions))

;; 取出复合条件中属于 type 的第一个简单条件（它本身就是一个 type 类型的条件）
(define (extract-condition condition type)
  (check-condition-type 'extract-condition type)
  (let ((pred (record-predicate type)))
    (or (find pred (simple-conditions condition))
        (assertion-violation 'extract-condition "invalid condition type" condition type))))
)
