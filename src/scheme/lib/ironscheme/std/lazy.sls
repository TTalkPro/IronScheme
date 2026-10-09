#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std lazy) —— 空间安全的惰性求值（designs/08-std-library.md D7）
;;; 词源：SRFI 45（André van Tonder）；R7RS 的 delay-force。
;;;
;;; 基础库的 delay / force 已改为 SRFI 45 / R7RS 的迭代强制（boot/r5rs.sls），本库只补上构造器：
;;;   (lazy e) 与 (delay-force e)：e 求值得到一个 promise，强制时不增长栈；
;;;   (eager v)：已完成的 promise。
;;; 你要的在 IronScheme 里叫什么（D2）：delay、force、make-promise、promise? → 基础库。
(library (ironscheme std lazy)
  (export
    lazy delay-force eager)
  (import
    (rnrs)
    (only (ironscheme core) make-lazy-promise make-eager-promise))

(define-syntax lazy
  (syntax-rules ()
    ((_ expression) (make-lazy-promise (lambda () expression)))))

(define-syntax delay-force
  (syntax-rules ()
    ((_ expression) (make-lazy-promise (lambda () expression)))))

(define (eager value) (make-eager-promise value))
)
