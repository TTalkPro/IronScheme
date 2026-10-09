#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std boxes) —— 盒子（designs/08-std-library.md）
;;; 词源：SRFI 111（John Cowan）。实现即 R6RS 记录。
(library (ironscheme std boxes)
  (export
    box box? unbox set-box!)
  (import
    (rnrs))

(define-record-type (box-type box box?)
  (fields (mutable value unbox set-box!)))
)
