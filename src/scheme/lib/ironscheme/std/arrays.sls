#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std arrays) —— 多维数组（designs/08-std-library.md）
;;; 词源：SRFI 25（Jussi Piitulainen）。参照实现 Jussi Piitulainen（1997 - 2001），连同其附带的扩展
;;; arlib（array-map、array->list、transpose、share-row 等 21 个过程，原为 chez-srfi 的
;;; (srfi :25 multi-dimensional-arrays arlib)）一并收入；R6RS 改写来自 chez-srfi（LICENSES/chez-srfi.txt）。
;;; 数组是记录，元素存在向量中；array:… 开头的内部过程不导出。本库所有名字都是基础库没有的（D2）。
;;; 与 SRFI 文本不同的取舍（D4）：SRFI 23 的 error 改为 &assertion，who 为出错的过程名。
(library (ironscheme std arrays)
  (export
    array array->list array->vector array-append array-end array-equal? array-for-each-index
    array-length array-map array-map! array-rank array-ref array-retabulate! array-set!
    array-shape array-size array-start array? make-array shape shape-for-each share-array
    share-array/index! share-array/origin share-array/prefix share-column share-nths
    share-row tabulate-array tabulate-array! transpose)
  (import
    (rnrs)
    (rnrs mutable-pairs)
    (rnrs r5rs)
    (only (ironscheme std private compat) SRFI-23-error->R6RS))

(define-record-type (array-type array:make array:array?)
  (fields (immutable vec array:vector)
          (immutable ind array:index)
          (immutable shp array:shape)))

(SRFI-23-error->R6RS "(library (ironscheme std arrays))"
 ;; ———— ix-ctor.scm ————
 (define (array-ref a . xs)
   (or (array:array? a)
       (error "not an array"))
   (let ((shape (array:shape a)))
     (if (null? xs)
         (array:check-indices "array-ref" xs shape)
         (let ((x (car xs)))
           (if (vector? x)
               (array:check-index-vector "array-ref" x shape)
               (if (integer? x)
                   (array:check-indices "array-ref" xs shape)
                   (if (array:array? x)
                       (array:check-index-actor "array-ref" x shape)
                       (error "not an index object"))))))
     (vector-ref
      (array:vector a)
      (if (null? xs)
          (vector-ref (array:index a) 0)
          (let ((x (car xs)))
            (if (vector? x)
                (array:index/vector
                 (quotient (vector-length shape) 2)
                 (array:index a)
                 x)
                (if (integer? x)
                    (array:vector-index (array:index a) xs)
                    (if (array:array? x)
                        (array:index/array
                         (quotient (vector-length shape) 2)
                         (array:index a)
                         (array:vector x)
                         (array:index x))
                        (error "array-ref: bad index object")))))))))

 (define (array-set! a x . xs)
   (or (array:array? a)
       (error "array-set!: not an array"))
   (let ((shape (array:shape a)))
     (if (null? xs)
         (array:check-indices "array-set!" '() shape)
         (if (vector? x)
             (array:check-index-vector "array-set!" x shape)
             (if (integer? x)
                 (array:check-indices.o "array-set!" (cons x xs) shape)
                 (if (array:array? x)
                     (array:check-index-actor "array-set!" x shape)
                     (error "not an index object")))))
     (if (null? xs)
         (vector-set! (array:vector a) (vector-ref (array:index a) 0) x)
         (if (vector? x)
             (vector-set! (array:vector a)
                          (array:index/vector
                           (quotient (vector-length shape) 2)
                           (array:index a)
                           x)
                          (car xs))
             (if (integer? x)
                 (let ((v (array:vector a))
                       (i (array:index a))
                       (r (quotient (vector-length shape) 2)))
                   (do ((sum (* (vector-ref i 0) x)
                             (+ sum (* (vector-ref i k) (car ks))))
                        (ks xs (cdr ks))
                        (k 1 (+ k 1)))
                     ((= k r)
                      (vector-set! v (+ sum (vector-ref i k)) (car ks)))))
                 (if (array:array? x)
                     (vector-set! (array:vector a)
                                  (array:index/array
                                   (quotient (vector-length shape) 2)
                                   (array:index a)
                                   (array:vector x)
                                   (array:index x))
                                  (car xs))
                     (error (string-append
                             "array-set!: bad index object: "
                             (array:thing->string x)))))))))

 ;; ———— op-ctor.scm ————
 (begin
   (define array:opt-args '(ctor (4)))
   (define (array:optimize f r)
     (case r
       ((0) (let ((n0 (f))) (array:0 n0)))
       ((1) (let ((n0 (f 0))) (array:1 n0 (- (f 1) n0))))
       ((2)
        (let ((n0 (f 0 0)))
          (array:2 n0 (- (f 1 0) n0) (- (f 0 1) n0))))
       ((3)
        (let ((n0 (f 0 0 0)))
          (array:3
            n0
            (- (f 1 0 0) n0)
            (- (f 0 1 0) n0)
            (- (f 0 0 1) n0))))
       (else
        (let ((v
               (do ((k 0 (+ k 1)) (v '() (cons 0 v)))
                   ((= k r) v))))
          (let ((n0 (apply f v)))
            (apply
             array:n
             n0
             (array:coefficients f n0 v v)))))))
   (define (array:optimize-empty r)
     (let ((x (make-vector (+ r 1) 0)))
       (vector-set! x r -1)
       x))
   (define (array:coefficients f n0 vs vp)
     (case vp
       ((()) '())
       (else
        (set-car! vp 1)
        (let ((n (- (apply f vs) n0)))
          (set-car! vp 0)
          (cons n (array:coefficients f n0 vs (cdr vp)))))))
   (define (array:vector-index x ks)
     (do ((sum 0 (+ sum (* (vector-ref x k) (car ks))))
          (ks ks (cdr ks))
          (k 0 (+ k 1)))
         ((null? ks) (+ sum (vector-ref x k)))))
   (define (array:shape-index) '#(2 1 0))
   (define (array:empty-shape-index) '#(0 0 -1))
   (define (array:shape-vector-index x r k)
     (+
      (* (vector-ref x 0) r)
      (* (vector-ref x 1) k)
      (vector-ref x 2)))
   (define (array:actor-index x k)
     (+ (* (vector-ref x 0) k) (vector-ref x 1)))
   (define (array:0 n0) (vector n0))
   (define (array:1 n0 n1) (vector n1 n0))
   (define (array:2 n0 n1 n2) (vector n1 n2 n0))
   (define (array:3 n0 n1 n2 n3) (vector n1 n2 n3 n0))
   (define (array:n n0 n1 n2 n3 n4 . ns)
     (apply vector n1 n2 n3 n4 (append ns (list n0))))
   (define (array:maker r)
     (case r
       ((0) array:0)
       ((1) array:1)
       ((2) array:2)
       ((3) array:3)
       (else array:n)))
   (define array:indexer/vector
     (let ((em
            (vector
              (lambda (x i) (+ (vector-ref x 0)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (vector-ref x 1)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (vector-ref x 2)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (vector-ref x 3)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (vector-ref x 4)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (vector-ref x 5)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (* (vector-ref x 5) (vector-ref i 5))
                 (vector-ref x 6)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (* (vector-ref x 5) (vector-ref i 5))
                 (* (vector-ref x 6) (vector-ref i 6))
                 (vector-ref x 7)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (* (vector-ref x 5) (vector-ref i 5))
                 (* (vector-ref x 6) (vector-ref i 6))
                 (* (vector-ref x 7) (vector-ref i 7))
                 (vector-ref x 8)))
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (* (vector-ref x 5) (vector-ref i 5))
                 (* (vector-ref x 6) (vector-ref i 6))
                 (* (vector-ref x 7) (vector-ref i 7))
                 (* (vector-ref x 8) (vector-ref i 8))
                 (vector-ref x 9)))))
           (it
            (lambda (w)
              (lambda (x i)
                (+
                 (* (vector-ref x 0) (vector-ref i 0))
                 (* (vector-ref x 1) (vector-ref i 1))
                 (* (vector-ref x 2) (vector-ref i 2))
                 (* (vector-ref x 3) (vector-ref i 3))
                 (* (vector-ref x 4) (vector-ref i 4))
                 (* (vector-ref x 5) (vector-ref i 5))
                 (* (vector-ref x 6) (vector-ref i 6))
                 (* (vector-ref x 7) (vector-ref i 7))
                 (* (vector-ref x 8) (vector-ref i 8))
                 (* (vector-ref x 9) (vector-ref i 9))
                 (do ((xi
                       0
                       (+
                        (* (vector-ref x u) (vector-ref i u))
                        xi))
                      (u (- w 1) (- u 1)))
                     ((< u 10) xi))
                 (vector-ref x w))))))
       (lambda (r) (if (< r 10) (vector-ref em r) (it r)))))
   (define array:indexer/array
     (let ((em
            (vector
              (lambda (x v i) (+ (vector-ref x 0)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (vector-ref x 1)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (vector-ref x 2)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (vector-ref x 3)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (vector-ref x 4)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (vector-ref x 5)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (*
                  (vector-ref x 5)
                  (vector-ref v (array:actor-index i 5)))
                 (vector-ref x 6)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (*
                  (vector-ref x 5)
                  (vector-ref v (array:actor-index i 5)))
                 (*
                  (vector-ref x 6)
                  (vector-ref v (array:actor-index i 6)))
                 (vector-ref x 7)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (*
                  (vector-ref x 5)
                  (vector-ref v (array:actor-index i 5)))
                 (*
                  (vector-ref x 6)
                  (vector-ref v (array:actor-index i 6)))
                 (*
                  (vector-ref x 7)
                  (vector-ref v (array:actor-index i 7)))
                 (vector-ref x 8)))
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (*
                  (vector-ref x 5)
                  (vector-ref v (array:actor-index i 5)))
                 (*
                  (vector-ref x 6)
                  (vector-ref v (array:actor-index i 6)))
                 (*
                  (vector-ref x 7)
                  (vector-ref v (array:actor-index i 7)))
                 (*
                  (vector-ref x 8)
                  (vector-ref v (array:actor-index i 8)))
                 (vector-ref x 9)))))
           (it
            (lambda (w)
              (lambda (x v i)
                (+
                 (*
                  (vector-ref x 0)
                  (vector-ref v (array:actor-index i 0)))
                 (*
                  (vector-ref x 1)
                  (vector-ref v (array:actor-index i 1)))
                 (*
                  (vector-ref x 2)
                  (vector-ref v (array:actor-index i 2)))
                 (*
                  (vector-ref x 3)
                  (vector-ref v (array:actor-index i 3)))
                 (*
                  (vector-ref x 4)
                  (vector-ref v (array:actor-index i 4)))
                 (*
                  (vector-ref x 5)
                  (vector-ref v (array:actor-index i 5)))
                 (*
                  (vector-ref x 6)
                  (vector-ref v (array:actor-index i 6)))
                 (*
                  (vector-ref x 7)
                  (vector-ref v (array:actor-index i 7)))
                 (*
                  (vector-ref x 8)
                  (vector-ref v (array:actor-index i 8)))
                 (*
                  (vector-ref x 9)
                  (vector-ref v (array:actor-index i 9)))
                 (do ((xi
                       0
                       (+
                        (*
                         (vector-ref x u)
                         (vector-ref
                           v
                           (array:actor-index i u)))
                        xi))
                      (u (- w 1) (- u 1)))
                     ((< u 10) xi))
                 (vector-ref x w))))))
       (lambda (r) (if (< r 10) (vector-ref em r) (it r)))))
   (define array:applier-to-vector
     (let ((em
            (vector
              (lambda (p v) (p))
              (lambda (p v) (p (vector-ref v 0)))
              (lambda (p v)
                (p (vector-ref v 0) (vector-ref v 1)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)
                 (vector-ref v 5)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)
                 (vector-ref v 5)
                 (vector-ref v 6)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)
                 (vector-ref v 5)
                 (vector-ref v 6)
                 (vector-ref v 7)))
              (lambda (p v)
                (p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)
                 (vector-ref v 5)
                 (vector-ref v 6)
                 (vector-ref v 7)
                 (vector-ref v 8)))))
           (it
            (lambda (r)
              (lambda (p v)
                (apply
                 p
                 (vector-ref v 0)
                 (vector-ref v 1)
                 (vector-ref v 2)
                 (vector-ref v 3)
                 (vector-ref v 4)
                 (vector-ref v 5)
                 (vector-ref v 6)
                 (vector-ref v 7)
                 (vector-ref v 8)
                 (vector-ref v 9)
                 (do ((k r (- k 1))
                      (r
                       '()
                       (cons (vector-ref v (- k 1)) r)))
                     ((= k 10) r)))))))
       (lambda (r) (if (< r 10) (vector-ref em r) (it r)))))
   (define array:applier-to-actor
     (let ((em
            (vector
              (lambda (p a) (p))
              (lambda (p a) (p (array-ref a 0)))
              (lambda (p a)
                (p (array-ref a 0) (array-ref a 1)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)
                 (array-ref a 5)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)
                 (array-ref a 5)
                 (array-ref a 6)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)
                 (array-ref a 5)
                 (array-ref a 6)
                 (array-ref a 7)))
              (lambda (p a)
                (p
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)
                 (array-ref a 5)
                 (array-ref a 6)
                 (array-ref a 7)
                 (array-ref a 8)))))
           (it
            (lambda (r)
              (lambda (p a)
                (apply
                 a
                 (array-ref a 0)
                 (array-ref a 1)
                 (array-ref a 2)
                 (array-ref a 3)
                 (array-ref a 4)
                 (array-ref a 5)
                 (array-ref a 6)
                 (array-ref a 7)
                 (array-ref a 8)
                 (array-ref a 9)
                 (do ((k r (- k 1))
                      (r '() (cons (array-ref a (- k 1)) r)))
                     ((= k 10) r)))))))
       (lambda (r)
         "These are high level, hiding implementation at call site."
         (if (< r 10) (vector-ref em r) (it r)))))
   (define array:applier-to-backing-vector
     (let ((em
            (vector
              (lambda (p ai av) (p))
              (lambda (p ai av)
                (p (vector-ref av (array:actor-index ai 0))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))
                 (vector-ref av (array:actor-index ai 5))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))
                 (vector-ref av (array:actor-index ai 5))
                 (vector-ref av (array:actor-index ai 6))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))
                 (vector-ref av (array:actor-index ai 5))
                 (vector-ref av (array:actor-index ai 6))
                 (vector-ref av (array:actor-index ai 7))))
              (lambda (p ai av)
                (p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))
                 (vector-ref av (array:actor-index ai 5))
                 (vector-ref av (array:actor-index ai 6))
                 (vector-ref av (array:actor-index ai 7))
                 (vector-ref av (array:actor-index ai 8))))))
           (it
            (lambda (r)
              (lambda (p ai av)
                (apply
                 p
                 (vector-ref av (array:actor-index ai 0))
                 (vector-ref av (array:actor-index ai 1))
                 (vector-ref av (array:actor-index ai 2))
                 (vector-ref av (array:actor-index ai 3))
                 (vector-ref av (array:actor-index ai 4))
                 (vector-ref av (array:actor-index ai 5))
                 (vector-ref av (array:actor-index ai 6))
                 (vector-ref av (array:actor-index ai 7))
                 (vector-ref av (array:actor-index ai 8))
                 (vector-ref av (array:actor-index ai 9))
                 (do ((k r (- k 1))
                      (r
                       '()
                       (cons
                        (vector-ref
                          av
                          (array:actor-index ai (- k 1)))
                        r)))
                     ((= k 10) r)))))))
       (lambda (r)
         "These are low level, exposing implementation at call site."
         (if (< r 10) (vector-ref em r) (it r)))))
   (define (array:index/vector r x v)
     ((array:indexer/vector r) x v))
   (define (array:index/array r x av ai)
     ((array:indexer/array r) x av ai))
   (define (array:apply-to-vector r p v)
     ((array:applier-to-vector r) p v))
   (define (array:apply-to-actor r p a)
     ((array:applier-to-actor r) p a)))

 ;; ———— array.scm ————
 ;;; array
 ;;; 1997 - 2001 Jussi Piitulainen

 ;;; --- Intro ---

 ;;; This interface to arrays is based on Alan Bawden's array.scm of
 ;;; 1993 (earlier version in the Internet Repository and another
 ;;; version in SLIB). This is a complete rewrite, to be consistent
 ;;; with the rest of Scheme and to make arrays independent of lists.

 ;;; Some modifications are due to discussion in srfi-25 mailing list.

 ;;; (array? obj)
 ;;; (make-array shape [obj])             changed arguments
 ;;; (shape bound ...)                    new
 ;;; (array shape obj ...)                new
 ;;; (array-rank array)                   changed name back
 ;;; (array-start array dimension)        new
 ;;; (array-end array dimension)          new
 ;;; (array-ref array k ...)
 ;;; (array-ref array index)              new variant
 ;;; (array-set! array k ... obj)         changed argument order
 ;;; (array-set! array index obj)         new variant
 ;;; (share-array array shape proc)       changed arguments

 ;;; All other variables in this file have names in "array:".

 ;;; Should there be a way to make arrays with initial values mapped
 ;;; from indices? Sure. The current "initial object" is lame.
 ;;;
 ;;; Removed (array-shape array) from here. There is a new version
 ;;; in arlib though.

 ;;; --- Representation type dependencies ---

 ;;; The mapping from array indices to the index to the underlying vector
 ;;; is whatever array:optimize returns. The file "opt" provides three
 ;;; representations:
 ;;; 
 ;;; mbda) mapping is a procedure that allows an optional argument
 ;;; tter) mapping is two procedures that takes exactly the indices
 ;;; ctor) mapping is a vector of a constant term and coefficients
 ;;;
 ;;; Choose one in "opt" to make the optimizer. Then choose the matching
 ;;; implementation of array-ref and array-set!.
 ;;;
 ;;; These should be made macros to inline them. Or have a good compiler
 ;;; and plant the package as a module.

 ;;; 1. Pick an optimizer.
 ;;; 2. Pick matching index representation.
 ;;; 3. Pick a record implementation; as-procedure is generic; syntax inlines.
 ;;; 3. This file is otherwise portable.

 ;;; --- Portable R5RS (R4RS and multiple values) ---

 ;;; (array? obj)
 ;;; returns #t if `obj' is an array and #t or #f otherwise.

 (define (array? obj)
    (array:array? obj))

 ;;; (make-array shape)
 ;;; (make-array shape obj)
 ;;; makes array of `shape' with each cell containing `obj' initially.

 (define (make-array shape . rest)
   (or (array:good-shape? shape)
       (error "make-array: shape is not a shape"))
   (apply array:make-array shape rest))

 (define (array:make-array shape . rest)
   (let ((size (array:size shape)))
     (array:make
      (if (pair? rest)
          (apply (lambda (o) (make-vector size o)) rest)
          (make-vector size))
      (if (= size 0)
          (array:optimize-empty
           (vector-ref (array:shape shape) 1))
          (array:optimize
           (array:make-index shape)
           (vector-ref (array:shape shape) 1)))
      (array:shape->vector shape))))

 ;;; (shape bound ...)
 ;;; makes a shape. Bounds must be an even number of exact, pairwise
 ;;; non-decreasing integers. Note that any such array can be a shape.

 (define (shape . bounds)
   (let ((v (list->vector bounds)))
     (or (even? (vector-length v))
         (error (string-append "shape: uneven number of bounds: "
                               (array:list->string bounds))))
     (let ((shp (array:make
                 v
                 (if (pair? bounds)
                     (array:shape-index)
                     (array:empty-shape-index))
                 (vector 0 (quotient (vector-length v) 2)
                         0 2))))
       (or (array:good-shape? shp)
           (error (string-append "shape: bounds are not pairwise "
                                 "non-decreasing exact integers: "
                                 (array:list->string bounds))))
       shp)))

 ;;; (array shape obj ...)
 ;;; is analogous to `vector'.

 (define (array shape . elts)
   (or (array:good-shape? shape)
       (error (string-append "array: shape " (array:thing->string shape)
                             " is not a shape")))
   (let ((size (array:size shape)))
     (let ((vector (list->vector elts)))
       (or (= (vector-length vector) size)
           (error (string-append "array: an array of shape "
                                 (array:shape-vector->string
                                  (array:vector shape))
                                 " has "
                                 (number->string size)
                                 " elements but got "
                                 (number->string (vector-length vector))
                                 " values: "
                                 (array:list->string elts))))
       (array:make
        vector
        (if (= size 0)
            (array:optimize-empty
             (vector-ref (array:shape shape) 1))
            (array:optimize
             (array:make-index shape)
             (vector-ref (array:shape shape) 1)))
        (array:shape->vector shape)))))

 ;;; (array-rank array)
 ;;; returns the number of dimensions of `array'.

 (define (array-rank array)
    (quotient (vector-length (array:shape array)) 2))

 ;;; (array-start array k)
 ;;; returns the lower bound index of array along dimension k. This is
 ;;; the least valid index along that dimension if the dimension is not
 ;;; empty.

 (define (array-start array d)
   (vector-ref (array:shape array) (+ d d)))

 ;;; (array-end array k)
 ;;; returns the upper bound index of array along dimension k. This is
 ;;; not a valid index. If the dimension is empty, this is the same as
 ;;; the lower bound along it.

 (define (array-end array d)
   (vector-ref (array:shape array) (+ d d 1)))

 ;;; (share-array array shape proc)
 ;;; makes an array that shares elements of `array' at shape `shape'.
 ;;; The arguments to `proc' are indices of the result.  The values of
 ;;; `proc' are indices of `array'.

 ;;; Todo: in the error message, should recognise the mapping and show it.

 (define (share-array array subshape f)
   (or (array:good-shape? subshape)
       (error (string-append "share-array: shape "
                             (array:thing->string subshape)
                             " is not a shape")))
   (let ((subsize (array:size subshape)))
     (or (array:good-share? subshape subsize f (array:shape array))
         (error (string-append "share-array: subshape "
                               (array:shape-vector->string
                                (array:vector subshape))
                               " does not map into supershape "
                               (array:shape-vector->string
                                (array:shape array))
                               " under mapping "
                               (array:map->string
                                f
                                (vector-ref (array:shape subshape) 1)))))    
     (let ((g (array:index array)))
       (array:make
        (array:vector array)
        (if (= subsize 0)
            (array:optimize-empty
             (vector-ref (array:shape subshape) 1))
            (array:optimize
             (lambda ks
               (call-with-values
                (lambda () (apply f ks))
                (lambda ks (array:vector-index g ks))))
             (vector-ref (array:shape subshape) 1)))
        (array:shape->vector subshape)))))

 ;;; --- Hrmph ---

 ;;; (array:share/index! ...)
 ;;; reuses a user supplied index object when recognising the
 ;;; mapping. The mind balks at the very nasty side effect that
 ;;; exposes the implementation. So this is not in the spec.
 ;;; But letting index objects in at all creates a pressure
 ;;; to go the whole hog. Arf.

 ;;; Use array:optimize-empty for an empty array to get a
 ;;; clearly invalid vector index.

 ;;; Surely it's perverse to use an actor for index here? But
 ;;; the possibility is provided for completeness.

 (define (array:share/index! array subshape proc index)
   (array:make
    (array:vector array)
    (if (= (array:size subshape) 0)
        (array:optimize-empty
         (quotient (vector-length (array:shape array)) 2))
        ((if (vector? index)
             array:optimize/vector
             array:optimize/actor)
         (lambda (subindex)
           (let ((superindex (proc subindex)))
             (if (vector? superindex)
                 (array:index/vector
                  (quotient (vector-length (array:shape array)) 2)
                  (array:index array)
                  superindex)
                 (array:index/array
                  (quotient (vector-length (array:shape array)) 2)
                  (array:index array)
                  (array:vector superindex)
                  (array:index superindex)))))
         index))
    (array:shape->vector subshape)))

 (define (array:optimize/vector f v)
   (let ((r (vector-length v)))
     (do ((k 0 (+ k 1)))
       ((= k r))
       (vector-set! v k 0))
     (let ((n0 (f v))
           (cs (make-vector (+ r 1)))
           (apply (array:applier-to-vector (+ r 1))))
       (vector-set! cs 0 n0)
       (let wok ((k 0))
         (if (< k r)
             (let ((k1 (+ k 1)))
               (vector-set! v k 1)
               (let ((nk (- (f v) n0)))
                 (vector-set! v k 0)
                 (vector-set! cs k1 nk)
                 (wok k1)))))
       (apply (array:maker r) cs))))

 (define (array:optimize/actor f a)
   (let ((r (array-end a 0))
         (v (array:vector a))
         (i (array:index a)))
     (do ((k 0 (+ k 1)))
       ((= k r))
       (vector-set! v (array:actor-index i k) 0))
     (let ((n0 (f a))
           (cs (make-vector (+ r 1)))
           (apply (array:applier-to-vector (+ r 1))))
       (vector-set! cs 0 n0)
       (let wok ((k 0))
         (if (< k r)
             (let ((k1 (+ k 1))
                   (t (array:actor-index i k)))
               (vector-set! v t 1)
               (let ((nk (- (f a) n0)))
                 (vector-set! v t 0)
                 (vector-set! cs k1 nk)
                 (wok k1)))))
       (apply (array:maker r) cs))))

 ;;; --- Internals ---

 (define (array:shape->vector shape)
   (let ((idx (array:index shape))
         (shv (array:vector shape))
         (rnk (vector-ref (array:shape shape) 1)))
     (let ((vec (make-vector (* rnk 2))))
       (do ((k 0 (+ k 1)))
         ((= k rnk)
          vec)
         (vector-set! vec (+ k k)
                      (vector-ref shv (array:shape-vector-index idx k 0)))
         (vector-set! vec (+ k k 1)
                      (vector-ref shv (array:shape-vector-index idx k 1)))))))

 ;;; (array:size shape)
 ;;; returns the number of elements in arrays of shape `shape'.

 (define (array:size shape)
    (let ((idx (array:index shape))
          (shv (array:vector shape))
          (rnk (vector-ref (array:shape shape) 1)))
      (do   ((k 0 (+ k 1))
             (s 1 (* s
                     (- (vector-ref shv (array:shape-vector-index idx k 1))
                        (vector-ref shv (array:shape-vector-index idx k 0))))))
        ((= k rnk) s))))

 ;;; (array:make-index shape)
 ;;; returns an index function for arrays of shape `shape'. This is a
 ;;; runtime composition of several variable arity procedures, to be
 ;;; passed to array:optimize for recognition as an affine function of
 ;;; as many variables as there are dimensions in arrays of this shape.

 (define (array:make-index shape)
    (let ((idx (array:index shape))
          (shv (array:vector shape))
          (rnk (vector-ref (array:shape shape) 1)))
      (do ((f (lambda () 0)
              (lambda (k . ks)
                (+ (* s (- k (vector-ref
                              shv
                              (array:shape-vector-index idx (- j 1) 0))))
                   (apply f ks))))
           (s 1 (* s (- (vector-ref
                         shv
                         (array:shape-vector-index idx (- j 1) 1))
                        (vector-ref
                         shv
                         (array:shape-vector-index idx (- j 1) 0)))))
           (j rnk (- j 1)))
        ((= j 0)
         f))))


 ;;; --- Error checking ---

 ;;; (array:good-shape? shape)
 ;;; returns true if `shape' is an array of the right shape and its
 ;;; elements are exact integers that pairwise bound intervals `[lo..hi)´.

 (define (array:good-shape? shape)
   (and (array:array? shape)
        (let ((u (array:shape shape))
              (v (array:vector shape))
              (x (array:index shape)))
          (and (= (vector-length u) 4)
               (= (vector-ref u 0) 0)
               (= (vector-ref u 2) 0)
               (= (vector-ref u 3) 2))
          (let ((p (vector-ref u 1)))
            (do ((k 0 (+ k 1))
                 (true #t (let ((lo (vector-ref
                                     v
                                     (array:shape-vector-index x k 0)))
                                (hi (vector-ref
                                     v
                                     (array:shape-vector-index x k 1))))
                            (and true
                                 (integer? lo)
                                 (exact? lo)
                                 (integer? hi)
                                 (exact? hi)
                                 (<= lo hi)))))
              ((= k p) true))))))

 ;;; (array:good-share? subv subsize mapping superv)
 ;;; returns true if the extreme indices in the subshape vector map
 ;;; into the bounds in the supershape vector.

 ;;; If some interval in `subv' is empty, then `subv' is empty and its
 ;;; image under `f' is empty and it is trivially alright.  One must
 ;;; not call `f', though.

 (define (array:good-share? subshape subsize f super)
   (or (zero? subsize)
       (letrec
           ((sub (array:vector subshape))
            (dex (array:index subshape))
            (ck (lambda (k ks)
 		 (if (zero? k)
                      (call-with-values
                       (lambda () (apply f ks))
                       (lambda qs (array:good-indices? qs super)))
                      (and (ck (- k 1)
                               (cons (vector-ref
                                      sub
                                      (array:shape-vector-index
                                       dex
                                       (- k 1)
                                       0))
                                     ks))
                           (ck (- k 1)
                               (cons (- (vector-ref
                                         sub
                                         (array:shape-vector-index
                                          dex
                                          (- k 1)
                                          1))
                                        1)
                                     ks)))))))
         (let ((rnk (vector-ref (array:shape subshape) 1)))
           (or (array:unchecked-share-depth? rnk)
               (ck rnk '()))))))

 ;;; Check good-share on 10 dimensions at most. The trouble is,
 ;;; the cost of this check is exponential in the number of dimensions.

 (define (array:unchecked-share-depth? rank)
   (if (> rank 10)
       (begin
         (display `(warning: unchecked depth in share:
                             ,rank subdimensions))
         (newline)
         #t)
       #f))

 ;;; (array:check-indices caller indices shape-vector)
 ;;; (array:check-indices.o caller indices shape-vector)
 ;;; (array:check-index-vector caller index-vector shape-vector)
 ;;; return if the index is in bounds, else signal error.
 ;;;
 ;;; Shape-vector is the internal representation, with
 ;;; b and e for dimension k at 2k and 2k + 1.

 (define (array:check-indices who ks shv)
   (or (array:good-indices? ks shv)
       (error (array:not-in who ks shv))))

 (define (array:check-indices.o who ks shv)
   (or (array:good-indices.o? ks shv)
       (error (array:not-in who (reverse (cdr (reverse ks))) shv))))

 (define (array:check-index-vector who ks shv)
   (or (array:good-index-vector? ks shv)
       (error (array:not-in who (vector->list ks) shv))))

 (define (array:check-index-actor who ks shv)
   (let ((shape (array:shape ks)))
     (or (and (= (vector-length shape) 2)
              (= (vector-ref shape 0) 0))
         (error "not an actor"))
     (or (array:good-index-actor?
          (vector-ref shape 1)
          (array:vector ks)
          (array:index ks)
          shv)
         (array:not-in who (do ((k (vector-ref shape 1) (- k 1))
                                (m '() (cons (vector-ref
                                              (array:vector ks)
                                              (array:actor-index
                                               (array:index ks)
                                               (- k 1)))
                                             m)))
                             ((= k 0) m))
                       shv))))

 (define (array:good-indices? ks shv)
    (let ((d2 (vector-length shv)))
       (do ((kp ks (if (pair? kp)
                       (cdr kp)))
            (k 0 (+ k 2))
            (true #t (and true (pair? kp)
                          (array:good-index? (car kp) shv k))))
         ((= k d2)
          (and true (null? kp))))))

 (define (array:good-indices.o? ks.o shv)
    (let ((d2 (vector-length shv)))
      (do   ((kp ks.o (if (pair? kp)
                          (cdr kp)))
             (k 0 (+ k 2))
             (true #t (and true (pair? kp)
                           (array:good-index? (car kp) shv k))))
        ((= k d2)
         (and true (pair? kp) (null? (cdr kp)))))))

 (define (array:good-index-vector? ks shv)
   (let ((r2 (vector-length shv)))
     (and (= (* 2 (vector-length ks)) r2)
          (do ((j 0 (+ j 1))
               (k 0 (+ k 2))
               (true #t (and true
                             (array:good-index? (vector-ref ks j) shv k))))
            ((= k r2) true)))))

 (define (array:good-index-actor? r v i shv)
   (and (= (* 2 r) (vector-length shv))
        (do ((j 0 (+ j 1))
             (k 0 (+ k 2))
             (true #t (and true
                           (array:good-index? (vector-ref
                                               v
                                               (array:actor-index i j))
                                              shv
                                              k))))
          ((= j r) true))))

 ;;; (array:good-index? index shape-vector 2d)
 ;;; returns true if index is within bounds for dimension 2d/2.

 (define (array:good-index? w shv k)
   (and (integer? w)
        (exact? w)
        (<= (vector-ref shv k) w)
        (< w (vector-ref shv (+ k 1)))))

 (define (array:not-in who ks shv)
   (let ((index (array:list->string ks))
         (bounds (array:shape-vector->string shv)))
     (error (string-append who
                           ": index " index
                           " not in bounds " bounds))))

 (define (array:list->string ks)
   (do ((index "" (string-append index (array:thing->string (car ks)) " "))
        (ks ks (cdr ks)))
     ((null? ks) index)))

 (define (array:shape-vector->string shv)
   (do ((bounds "" (string-append bounds
                                  "["
                                  (number->string (vector-ref shv t))
                                  ".."
                                  (number->string (vector-ref shv (+ t 1)))
                                  ")"
                                  " "))
        (t 0 (+ t 2)))
     ((= t (vector-length shv)) bounds)))

 (define (array:thing->string thing)
   (cond
     ((number? thing) (number->string thing))
     ((symbol? thing) (string-append "#<symbol>" (symbol->string thing)))
     ((char? thing) "#<char>")
     ((string? thing) "#<string>")
     ((list? thing) (string-append "#" (number->string (length thing))
                                   "<list>"))

     ((pair? thing) "#<pair>")
     ((array? thing) "#<array>")
     ((vector? thing) (string-append "#" (number->string
                                          (vector-length thing))
                                     "<vector>"))
     ((procedure? thing) "#<procedure>")
     (else
      (case thing
        ((()) "()")
        ((#t) "#t")
        ((#f) "#f")
        (else
         "#<whatsit>")))))

 ;;; And to grok an affine map, vector->vector type. Column k of arr
 ;;; will contain coefficients n0 ... nm of 1 k1 ... km for kth value.
 ;;; 
 ;;; These are for the error message when share fails.

 (define (array:index-ref ind k)
   (if (vector? ind)
       (vector-ref ind k)
       (vector-ref
        (array:vector ind)
        (array:actor-index (array:index ind) k))))

 (define (array:index-set! ind k o)
   (if (vector? ind)
       (vector-set! ind k o)
       (vector-set!
        (array:vector ind)
        (array:actor-index (array:index ind) k)
        o)))

 (define (array:index-length ind)
   (if (vector? ind)
       (vector-length ind)
       (vector-ref (array:shape ind) 1)))

 (define (array:map->string proc r)
   (let* ((m (array:grok/arguments proc r))
          (s (vector-ref (array:shape m) 3)))
     (do ((i "" (string-append i c "k" (number->string k)))
          (c "" ", ")
          (k 1 (+ k 1)))
       ((< r k)
        (do ((o "" (string-append o c (array:map-column->string m r k)))
             (c "" ", ")
             (k 0 (+ k 1)))
          ((= k s)
           (string-append i " => " o)))))))

 (define (array:map-column->string m r k)
   (let ((v (array:vector m))
         (i (array:index m)))
     (let ((n0 (vector-ref v (array:vector-index i (list 0 k)))))
       (let wok ((j 1)
                 (e (if (= n0 0) "" (number->string n0))))
         (if (<= j r)
             (let ((nj (vector-ref v (array:vector-index i (list j k)))))
               (if (= nj 0)
                   (wok (+ j 1) e)
                   (let* ((nj (if (= nj 1) ""
                                  (if (= nj -1) "-"
                                      (string-append (number->string nj)
                                                     " "))))
                          (njkj (string-append nj "k" (number->string j))))
                     (if (string=? e "")
                         (wok (+ j 1) njkj)
                         (wok (+ j 1) (string-append e " + " njkj))))))
             (if (string=? e "") "0" e))))))

 (define (array:grok/arguments proc r)
   (array:grok/index!
    (lambda (vec)
      (call-with-values
       (lambda ()
         (array:apply-to-vector r proc vec))
       vector))
    (make-vector r)))

 (define (array:grok/index! proc in)
   (let ((m (array:index-length in)))
     (do ((k 0 (+ k 1)))
       ((= k m))
       (array:index-set! in k 0))
     (let* ((n0 (proc in))
            (n (array:index-length n0)))
       (let ((arr (make-array (shape 0 (+ m 1) 0 n))))  ; (*)
         (do ((k 0 (+ k 1)))
           ((= k n))
           (array-set! arr 0 k (array:index-ref n0 k))) ; (**)
         (do ((j 0 (+ j 1)))
           ((= j m))
           (array:index-set! in j 1)
           (let ((nj (proc in)))
             (array:index-set! in j 0)
             (do ((k 0 (+ k 1)))
               ((= k n))
               (array-set! arr (+ j 1) k (- (array:index-ref nj k) ; (**)
                                            (array:index-ref n0 k))))))
         arr))))
 ;; (*)  Should not use `make-array' and `shape' here
 ;; (**) Should not use `array-set!' here
 ;; Should use something internal to the library instead: either lower
 ;; level code (preferable but complex) or alternative names to these same.

 ;; ———— arlib.scm ————
 ;;; array arlib

 ;;; 2001 Jussi Piitulainen

 ;;; This is a high level implementation of some generally useful
 ;;; array procedures. In addition to R5RS and SRFI-25, only one
 ;;; tool is used, namely array:apply-to-vector and friends. Thus
 ;;; this library serves to prove that the primitives really are
 ;;; primitives. - A lower level implementation would access some
 ;;; implementation details to bypass redundant checking and such.

 ;;; Note that these procedures are not necessarily designed with
 ;;; full care. Think of them as examples of what can be done.
 ;;; Important tools are also missing, including scans and reduces
 ;;; and many thinks that I have not even heard of yet.

 ;;; (array-shape arr) (array-length arr dim) (array-size arr)
 ;;; (array-equal? arr1 arr2)
 ;;; (shape-for-each shp proc [ind])
 ;;; (array-for-each-index arr proc [ind])
 ;;; (tabulate-array shp proc) (tabulate-array! shp proc ind)
 ;;; (array-retabulate! arr shp proc [ind])
 ;;; (array-map [shp] proc arr0 arr1 ...)
 ;;; (array-map! arr [shp] proc arr0 arr1 ...)
 ;;; (array->vector arr) (array->list arr)
 ;;; (share-array/prefix arr k ...) (share-row arr k) (share-column arr k)
 ;;; (share-array/origin arr k ...) (share-array/origin arr ind)
 ;;; (array-append dim arr0 arr1 ...)
 ;;; (transpose arr dim ...)
 ;;; (share-nths arr dim n)

 ;;; Naming problem: should all those index-object using procedures
 ;;; bang? The main argument, like shape, is not mutated.

 ;;; (array-shape arr)

 (define (array-shape arr)
   (let ((r (array-rank arr)))
     (let ((m (make-array (shape 0 r 0 2))))
       (do ((d 0 (+ d 1)))
         ((= d r)
          m)
         (array-set! m d 0 (array-start arr d))
         (array-set! m d 1 (array-end arr d))))))

 ;;; (array-length arr dim)

 (define (array-length arr dim)
   (- (array-end arr dim)
      (array-start arr dim)))

 ;;; (array-size arr)

 (define (array-size arr)
   (let ((r (array-rank arr)))
     (do ((k 0 (+ k 1))
          (p 1 (* p (array-length arr k))))
       ((= k r) p))))

 ;;; (array-equal? a b)
 ;;; compares elements with equal? so elements better not contain
 ;;; arrays.

 (define (array-equal? a b)
   (let ((r (array-rank a)))
     (and (= r (array-rank b))
          (and (do ((k 0 (+ k 1))
                    (true #t (and true
                                  (= (array-start a k)
                                     (array-start b k))
                                  (= (array-end a k)
                                     (array-end b k)))))
                 ((= k r) true))
               (let ((ks (make-vector r 0)))
                 (let wok ((d 0))
                   (if (< d r)
                       (let ((e (array-end a d)))
                         (do ((k (array-start a d) (+ k 1))
                              (true #t (and true (wok (+ d 1)))))
                           ((= k e) true)
                           (vector-set! ks d k)))
                       (equal? (array-ref a ks)
                               (array-ref b ks)))))))))

 ;;; (shape-for-each shp proc [index-object])
 ;;; passes each index in shape to proc in row-major orderd, using
 ;;; index-object if provided.

 (define (shape-for-each shp proc . o)
   (if (null? o)
       (array:arlib:shape-for-each/arguments shp proc)
       (if (vector? (car o))
           (array:arlib:shape-for-each/vector shp proc (car o))
           (array:arlib:shape-for-each/array shp proc (car o)))))

 (define (array:arlib:shape-for-each/arguments shp proc)
   (let ((r (array-end shp 0)))
     (let ((vec (make-vector r)))
       (let do-dim ((d 0))
         (if (= d r)
             (array:apply-to-vector r proc vec)
             (let ((e (array-ref shp d 1)))
               (do ((k (array-ref shp d 0) (+ k 1)))
                 ((= k e))
                 (vector-set! vec d k)
                 (do-dim (+ d 1)))))))))

 (define (array:arlib:shape-for-each/vector shp proc vec)
   (let ((r (array-end shp 0)))
     (let do-dim ((d 0))
       (if (= d r)
           (proc vec)
           (let ((e (array-ref shp d 1)))
             (do ((k (array-ref shp d 0) (+ k 1)))
               ((= k e))
               (vector-set! vec d k)
               (do-dim (+ d 1))))))))

 (define (array:arlib:shape-for-each/array shp proc arr)
   ;; arr is not vector
   (let ((r (array-end shp 0)))
     (let do-dim ((d 0))
       (if (= d r)
           (proc arr)
           (let ((e (array-ref shp d 1)))
             (do ((k (array-ref shp d 0) (+ k 1)))
               ((= k e))
               (array-set! arr d k)
               (do-dim (+ d 1))))))))

 ;;; (array-for-each-index arr proc [ind])
 ;;; is equivalent to
 ;;;
 ;;;   (shape-for-each-index (array-shape arr) proc [ind])
 ;;;
 ;;; but is implemented without allocation of the shape, to prove
 ;;; that it can be so implemented.

 (define (array-for-each-index arr proc . o)
   (if (null? o)
       (array:arlib:array-for-each-index/arguments arr proc)
       (if (vector? (car o))
           (array:arlib:array-for-each-index/vector arr proc (car o))
           (array:arlib:array-for-each-index/array arr proc (car o)))))

 (define (array:arlib:array-for-each-index/arguments arr proc)
   (let ((r (array-rank arr)))
     (let ((vec (make-vector r))
           (apply (array:applier-to-vector r)))
       (let do-dim ((d 0))
         (if (= d r)
             (apply proc vec)
             (let ((e (array-end arr d)))
               (do ((k (array-start arr d) (+ k 1)))
                 ((= k e))
                 (vector-set! vec d k)
                 (do-dim (+ d 1)))))))))

 (define (array:arlib:array-for-each-index/vector arr proc ind)
   ;; ind is a vector
   (let ((r (array-rank arr)))
     (let do-dim ((d 0))
       (if (= d r)
           (proc ind)
           (let ((e (array-end arr d)))
             (do ((k (array-start arr d) (+ k 1)))
               ((= k e))
               (vector-set! ind d k)
               (do-dim (+ d 1))))))))

 (define (array:arlib:array-for-each-index/array arr proc ind)
   ;; ind is an array but not a vector
   (let ((r (array-rank arr)))
     (let do-dim ((d 0))
       (if (= d r)
           (proc ind)
           (let ((e (array-end arr d)))
             (do ((k (array-start arr d) (+ k 1)))
               ((= k e))
               (array-set! ind d k)
               (do-dim (+ d 1))))))))

 ;;; (tabulate-array shp proc)
 ;;; (tabulate-array! shp proc ind)
 ;;; returns a newly allocated array of the given shape with initial
 ;;; contents at each index whatever proc returns given the indices.
 ;;; The latter procedure reuses ind for package of indices.

 (define (tabulate-array shp proc)
   (let ((arr (make-array shp)))
     (array:arlib:shape-for-each/vector
      shp
      (let ((apply (array:applier-to-vector (array-end shp 0))))
        (lambda (ix) (array-set! arr ix (apply proc ix))))
      (make-vector (array-end shp 0)))
     arr))

 (define (tabulate-array! shp proc ind)
   (let ((arr (make-array shp)))
     (if (vector? ind)
         (array:arlib:shape-for-each/vector
          shp
          (lambda (ix) (array-set! arr ix (proc ix)))
          ind)
         (array:arlib:shape-for-each/array
          shp
          (lambda (ix) (array-set! arr ix (proc ix)))
          ind))
     arr))

 ;;; (array-retabulate! arr shp proc [index-object])
 ;;; sets the elements of arr in shape to the value of proc at that
 ;;; index, using index-object if provided.

 (define (array-retabulate! arr shp proc . o)
   (if (null? o)
       (array:arlib:shape-for-each/vector
        shp
        (let ((apply (array:applier-to-vector (array-end shp 0))))
          (lambda (ix)
            (array-set! arr ix (apply proc ix))))
        (make-vector (array-end shp 0)))
       (if (vector? (car o))
           (array:arlib:shape-for-each/vector
            shp
            (lambda (ix)
              (array-set! arr ix (proc ix)))
            (car o))
           (array:arlib:shape-for-each/array
            shp
            (lambda (ix)
              (array-set! arr ix (proc ix)))
            (car o)))))

 ;;; (array-map! array [shape] proc array0 array1...)
 ;;; stores to the elements of array (in shape) the values of proc at
 ;;; the contents of arrayk at corresponding index.

 (define (array-map! arr x y . o)
   (if (array:array? x)
       (array:arlib:map! arr x y (apply vector o))
       (array:arlib:map! arr (array-shape arr) x (apply vector y o))))

 (define (array:arlib:map! arr shp proc args)
   (let ((rank (vector-length args)))
     (let ((argv (make-vector rank)))
       (array:arlib:shape-for-each/vector
        shp
        (let ((apply (array:applier-to-vector rank)))
          (lambda (ix)
            (do ((k 0 (+ k 1)))
              ((= k rank))
              (vector-set! argv k (array-ref (vector-ref args k) ix)))
            (array-set! arr ix (apply proc argv))))
        (make-vector (array-end shp 0))))))

 ;;; (array-map [shape] proc array0 array1 ...)
 ;;; creates a new array with elements initialized to the values of
 ;;; proc at contents of arrayk (in shape).

 (define (array-map x y . o)
   (if (array:array? x)
       (let ((arr (make-array x)))
         (array:arlib:map! arr x y (apply vector o))
         arr)
       (let ((shp (array-shape y)))
         (let ((arr (make-array shp)))
           (array:arlib:map! arr shp x (apply vector y o))
           arr))))

 ;;; SRFI-25 mailing list requested array->vector; they also requested the
 ;;; ability to use an array as an index of an element, and array->list is
 ;;; an attempt to provide for that.

 (define (array->vector arr)
   (let ((vec (make-vector (array-size arr))))
     (let ((k 0))
       (shape-for-each
        (array-shape arr)
        (lambda (index)
          (vector-set! vec k (array-ref arr index))
          (set! k (+ k 1)))
        (make-vector (array-rank arr)))
       vec)))

 ;;; It needs to be said that more efficient implementations are
 ;;; possible, even within SRFI-25.

 (define (array->list arr)
   (vector->list (array->vector arr)))

 ;;; (share-row arr k)
 ;;; shares whatever the first index is about.
 ;;; The result has one dimension less.

 (define (share-row arr k)
   (share-array
    arr
    (let ((bounds (array->list (array-shape arr))))
      (apply shape (cddr bounds)))
    (lambda ks
      (apply values k ks))))

 ;;; (share-array/prefix arr k ...)

 (define (share-array/prefix arr . js)
   (if (or (null? js)
           (integer? (car js)))
       (share-array
        arr
        (let ((bounds (array->list (array-shape arr))))
          (apply shape (list-tail bounds (* 2 (length js)))))
        (lambda ks
          (apply values (append js ks))))
       (apply (lambda (fix)
                (share-array/prefix!
                 arr
                 fix
                 (make-vector (- (array-rank arr)
                                 (if (vector? fix)
                                     (vector-length fix)
                                     (array-end fix 0))))))
              js)))

 (define (share-array/prefix! arr fix in . out)
   (let* ((out (if (pair? out)
                   ((lambda (out) out) out)
                   (make-vector (array-rank arr))))
          (fix-ref (if (vector? fix) vector-ref array-ref))
          (in-ref (if (vector? in) vector-ref array-ref))
          (out-set! (if (vector? out) vector-set! array-set!))
          (m (if (vector? fix)
                 (vector-length fix)
                 (array-end fix 0)))
          (n (if (vector? out)
                 (vector-length out)
                 (array-end out 0))))
     (do ((k 0 (+ k 1)))
       ((= k m))
       (out-set! out k (fix-ref fix k)))
     (share-array/index!
      arr
      (let ((bounds (array->list (array-shape arr))))
        (apply shape (list-tail bounds (if (vector? fix)
                                           (* 2 (vector-length fix))
                                           (* 2 (array-end fix 0))))))
      (lambda (in)
        (do ((k m (+ k 1)))
          ((= k n))
          (out-set! out k (in-ref in (- k m))))
        out)
      in)))

 ;;; (share-column arr k)
 ;;; shares whatever the second index is about.
 ;;; The result has one dimension less.

 (define (share-column arr k)
   (share-array
    arr
    (let ((bounds (array->list (array-shape arr))))
      (apply shape
             (car bounds) (cadr bounds)
             (cddddr bounds)))
    (lambda ks
      (apply values (car ks) k (cdr ks)))))

 ;;; (share-array/origin arr k ...)
 ;;; (share-array/origin arr index)
 ;;; change origin to k ..., with index a vector or zero-based
 ;;; one-dimensional array that contains k ...
 ;;;
 ;;; This is useful for writing array-append. Maybe for something
 ;;; else too - who knows.

 (define (share-array/origin arr . xs)
   (let ((new (if (or (null? xs)
                      (integer? (car xs)))
                  xs
                  (apply (lambda (x)
                           (if (vector? x)
                               (vector->list x)
                               (if (array? x)
                                   (array->list x)
                                   (error "share-array/origin: bad thing"))))
                         xs))))
     (do ((k (array-rank arr) (- k 1))
          (old '() (cons (array-start arr (- k 1)) old)))
       ((= k 0)
        (let ((ds (map - new old)))
          (share-array
           arr
           (tabulate-array
            (shape 0 (array-rank arr) 0 2)
            (lambda (r k)
              (case k
                ((0) (+ (array-start arr r) (list-ref ds r)))
                ((1) (+ (array-end arr r) (list-ref ds r))))))
           (lambda ks
             (apply values (map - ks ds)))))))))

 ;;; SRFI-25 mailing list requested making shapes their own type. Here's
 ;;; an example of how manipulating shapes as arrays can be useful. The
 ;;; example also tests that higher level libraries are indeed easy to
 ;;; write on top of this SRFI.

 ;;; (array-append arr1 arr2 dim)
 ;;; appends two arrays along a specified dimension. The arrays must
 ;;; have equally many dimensions and all other dimensions equally long.
 ;;;
 ;;; Generalize to more arrays and maybe rewrite with shape-for-each or
 ;;; what have you.

 (define (array-append dim arr . ars)
   (let* ((total (do ((m (array-length arr dim)
                         (+ m (array-length (car r) dim)))
                      (r ars (cdr r)))
                   ((null? r) m)))
          (common (array-shape arr))
          (origin (array->vector (share-column common 0)))
          (index (make-vector (array-rank arr))))
     (array-set! common dim 1 (+ (array-start arr dim) total))
     (let ((result (make-array common)))
       (array-set! common dim 1 (array-start arr dim))
       (let wok ((arr arr)
                 (ars ars))
         (vector-set! origin dim (array-ref common dim 1))
         (let ((arr1 (share-array/origin arr origin)))
           (array-set! common dim 0 (array-start arr1 dim))
           (array-set! common dim 1 (array-end arr1 dim))
           (shape-for-each
            common
            (lambda (index)
              (array-set! result index (array-ref arr1 index)))
            index))
         (if (pair? ars)
             (wok (car ars) (cdr ars))))
       result)))

 ;;; Transpose, as permutation of dimensions, is applicable to all
 ;;; arrays. The default is reversal.

 ;;; The implementation uses multiplication by permutation
 ;;; matrix but matrix multiplication is not exported.

 (define (array:arlib:matrix-times a b)
   (or (and (= (array-rank a) 2)
            (= (array-rank b) 2))
       (error "times: arrays are not matrices"))
   (let ((r0 (array-start a 0))  (rn (array-end a 0))
         (t0 (array-start a 1))  (tn (array-end a 1))
         (u0 (array-start b 0))  (un (array-end b 0)) 
         (k0 (array-start b 1))  (kn (array-end b 1)))
     (or (= (- tn t0) (- un u0))
         (error "times: matrices are not compatible"))
     (let ((ab (make-array (shape r0 rn k0 kn))))
       (do ((r r0 (+ r 1)))
         ((= r rn))
         (do ((k k0 (+ k 1)))
           ((= k kn))
           (do ((t t0 (+ t 1))
                (u u0 (+ u 1))
                (s 0 (+ s (* (array-ref a r t)
                             (array-ref b u k)))))
             ((and (= t tn)
                   (= u un))
              (array-set! ab r k s)))))
       ab)))

 ; This is a generalized transpose. It can permute the dimensions any which 
 ; way. The permutation is provided by a permutation matrix: a square matrix
 ; of zeros and ones, with exactly one one in each row and column, or a
 ; permutation of the rows of an identity matrix; the size of the matrix
 ; must match the number of dimensions of the array.
 ;
 ; The default permutation is [ 0 1 | 1 0 ] of course, but any permutation
 ; array can be specified, and the shape array of the original array is then
 ; multiplied with it, and index column vectors of the new array with its
 ; inverse, from left, to permute the rows appropriately.

 (define (array:arlib:permutation-matrix . ds)
   (let* ((n (length ds))
          (arr (make-array (shape 0 n 0 n) 0)))
     (do ((k 0 (+ k 1))
          (ds ds (cdr ds)))
       ((= k n))
       (array-set! arr k (car ds) 1))
     arr))

 ;;; (transpose arr k ...)
 ;;; shares arr with permuted dimensions. Each dimension from 0
 ;;; inclusive to rank exclusive must appear once in k ...

 (define (transpose a . p0)
   (let* ((r (array-rank a))
          (permutation (apply array:arlib:permutation-matrix
                              (if (pair? p0)
                                  p0
                                  (do ((ds '() (cons d ds))
                                       (d 0 (+ d 1)))
                                    ((= d r)
                                     ;; reverse dimensions
                                     ds)))))
          (inverse-permutation (share-array permutation
                                            (array-shape permutation)
                                            (lambda (r k)
                                              ;; transpose
                                              (values k r)))))
     (share-array
      a
      (array:arlib:matrix-times permutation (array-shape a))
      (lambda ks0
        (apply values
               (array->list
                (array:arlib:matrix-times
                 inverse-permutation
                 (apply array (shape 0 r 0 1) ks0))))))))

 ;;; (share-array/index! array subshape proc index)

 (define (share-array/index! array subshape proc index)
   (array:share/index! array subshape proc index))

 ;;; Take every nth slice along dimension d into a shared array. This
 ;;; preserves the origin.

 (define (share-nths arr d n)
   (let* ((bounds (array->vector (array-shape arr)))
          (b (vector-ref bounds (* 2 d)))
          (e (vector-ref bounds (+ (* 2 d) 1))))
     (vector-set! bounds (+ (* 2 d) 1) (+ b (quotient (+ n (- e b 1)) n)))
     (share-array
      arr
      (apply shape (vector->list bounds))
      (lambda ks
        (apply values
               (let d/nk ((u 0) (ks ks))
                 (if (= u d)
                     (cons (+ b (* n (- (car ks) b))) (cdr ks))
                     (cons (car ks) (d/nk (+ u 1) (cdr ks))))))))))
 )
)
