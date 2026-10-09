#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std private pfds) —— pfds 各库共用的辅助过程（惰性表、向量、关联表、位操作），不对外。
;;; 实现来自 pfds（Ian Price，new-style BSD 许可，全文见 LICENSES/pfds.txt）；各原文件的说明与版权声明保留在下面。
;;; 改动：alists 中 SRFI 1 的三参数 assoc 改为 assp（D2）。
(library (ironscheme std private pfds)
  (export
    cons* tail head empty? take drop rev append* vector-set vector-insert vector-remove
    vector-copy vector-copy! vector-fold alist-ref alist-set alist-delete alist-update
    bitwise-bit-set bitwise-bit-unset)
  (import
    (except (rnrs) cons*)
    (rnrs r5rs))

;; ———————————————— 来自 pfds 的 private/lazy-lists.sls ————————————————
;;; lazy-lists.sls --- odd lazy lists

;; Copyright (C) 2011 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

;;; Commentary:

;; If you want real lazy lists, use SRFI 41, but Okazaki uses 'odd'
;; lists, so I wrote a quick implementation.

;;; Code:

(define-syntax cons*
  (syntax-rules ()
    ((cons* a b)
     (cons a (delay b)))))

(define head car)

(define empty? null?)

(define (tail pair)
  (if (empty? pair)
      pair
      (force (cdr pair))))

(define (take n l)
  (if (zero? n)
      '()
      (cons* (head l)
             (take (- n 1) (tail l)))))

(define (drop n l)
  (if (zero? n)
      l
      (drop (- n 1) (tail l))))

(define (append* x y)
  (if (empty? x)
      y
      (cons* (head x)
             (append* (tail x) y))))

(define (rev l)
  (let loop ((l l) (a '()))
    (if (empty? l)
        a
        (loop (tail l) (cons* (head l) a)))))

;; ———————————————— 来自 pfds 的 private/vectors.sls ————————————————
;;; vectors.sls --- Vector Utilities

;; Copyright (C) 2014 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

(define (vector-set h i x)
  (let ((v* (vector-copy h)))
    (vector-set! v* i x)
    v*))

(define (vector-remove v i)
  (define len (vector-length v))
  (assert (and (<= 0 i) (< i len)))
  (let ((newvec (make-vector (- len 1))))
    (vector-copy! v 0 newvec 0 i)
    (vector-copy! v (+ i 1) newvec i (- len i 1))
    newvec))

(define (vector-insert v i x)
  (define len (vector-length v))
  (assert (<= 0 i len))
  (let* ((newvec (make-vector (+ len 1))))
    (vector-set! newvec i x)
    (vector-copy! v 0 newvec 0 i)
    (vector-copy! v i newvec (+ 1 i) (- len i))
    newvec))

(define (vector-copy! source source-start target target-start k)
  ;; TODO: assertions
  ;; guile has vector-move functions, but rnrs does not :(
  (do ((i 0 (+ 1 i)))
      ((>= i k))
    (vector-set! target
                 (+ target-start i)
                 (vector-ref source (+ source-start i)))))

(define (vector-copy vector)
  (define len (vector-length vector))
  (define v* (make-vector len))
  (vector-copy! vector 0 v* 0 len)
  v*)

;; vector-fold is left to right
(define (vector-fold combine initial vector)
  (define len (vector-length vector))
  (let loop ((index 0) (accum initial))
    (if (>= index len)
        accum
        (loop (+ index 1)
              (combine (vector-ref vector index) accum)))))

;; ———————————————— 来自 pfds 的 private/alists.sls ————————————————
;;; alists.sls --- Alist Utilities

;; Copyright (C) 2014 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

(define (alist-ref alist key default eqv?)
  ;; 原为 SRFI 1 的三参数 assoc；(ironscheme std lists) 不导出它（D2），改用 assp
  (cond ((assp (lambda (k) (eqv? key k)) alist) => cdr)
        (else default)))

(define (alist-set alist key value eqv?)
  ;; TODO: measure to see if it is even worth it
  ;; adds key value to alist if key is not in alist
  ;; if key is in a list, replaces the association
  ;; does not preserve order.
  (let loop ((new '()) (old alist))
    (cond ((null? old)
           (cons (cons key value) new))
          ((eqv? (car (car old)) key)
           (cons (cons key value)
                 (append (cdr old) new)))
          (else (loop (cons (car old) new) (cdr old))))))

;;((al (alist-delete (collision-alist node) key eqv?)))
(define (alist-delete alist key eqv?)
  ;; TODO: measure to see if it is even worth it
  (let loop ((new '()) (old alist))
    (cond ((null? old) new)
          ((eqv? (car (car old)) key)
           (append (cdr old) new))
          (else (loop (cons (car old) new) (cdr old))))))

(define (alist-update alist key update base eqv?)
  (let loop ((new '()) (old alist))
    (cond ((null? old)
           (cons (cons key (update base)) new))
          ((eqv? (car (car old)) key)
           (cons (cons key (update (cdr (car old))))
                 (append (cdr old) new)))
          (else (loop (cons (car old) new) (cdr old))))))

;; ———————————————— 来自 pfds 的 private/bitwise.sls ————————————————
;;; bitwise.sls --- Bitwise Arithmetic Utilities

;; Copyright (C) 2014 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

(define (bitwise-bit-set bits i)
  (bitwise-ior bits (bitwise-arithmetic-shift-left 1 i)))

(define (bitwise-bit-unset bits i)
  (bitwise-and bits (bitwise-not (bitwise-arithmetic-shift-left 1 i))))
)
