#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std numeric-vectors) —— 同质数值向量（designs/08-std-library.md）
;;; 词源：SRFI 4（Marc Feeley）。实现 Andrew W. Keep（Copyright (c) 2018 - 2020，chez-srfi，MIT 许可，
;;; 见 LICENSES/chez-srfi.txt）：每种向量是包着字节向量的记录，s8/u8 … s64/u64、f32/f64 各有
;;; ?、make-、构造、-length、-ref、-set!、->list、list-> 八个过程。
;;; 字节序为本机字节序（native-endianness）。本库所有名字都是基础库没有的（D2）。
;;; 与参照实现不同（D4）：生成名字用的 format 取基础库的（原为 SRFI 28）。
(library (ironscheme std numeric-vectors)
  (export
    f32vector f32vector->list f32vector-length f32vector-ref f32vector-set! f32vector?
    f64vector f64vector->list f64vector-length f64vector-ref f64vector-set! f64vector?
    list->f32vector list->f64vector list->s16vector list->s32vector list->s64vector
    list->s8vector list->u16vector list->u32vector list->u64vector list->u8vector
    make-f32vector make-f64vector make-s16vector make-s32vector make-s64vector make-s8vector
    make-u16vector make-u32vector make-u64vector make-u8vector s16vector s16vector->list
    s16vector-length s16vector-ref s16vector-set! s16vector? s32vector s32vector->list
    s32vector-length s32vector-ref s32vector-set! s32vector? s64vector s64vector->list
    s64vector-length s64vector-ref s64vector-set! s64vector? s8vector s8vector->list
    s8vector-length s8vector-ref s8vector-set! s8vector? u16vector u16vector->list
    u16vector-length u16vector-ref u16vector-set! u16vector? u32vector u32vector->list
    u32vector-length u32vector-ref u32vector-set! u32vector? u64vector u64vector->list
    u64vector-length u64vector-ref u64vector-set! u64vector? u8vector u8vector->list
    u8vector-length u8vector-ref u8vector-set! u8vector?)
  (import
    (rnrs)
    (only (ironscheme) format))

(define-syntax define-integer-vector
  (lambda (x)
    (define format-id
      (lambda (tid fmt . args)
        (datum->syntax tid
          (string->symbol
            (apply format fmt args)))))
    (syntax-case x ()
      [(k signed? bit-size)
       (and (boolean? (syntax->datum #'signed?))
            (let ([bit-size (syntax->datum #'bit-size)])
              (and (integer? bit-size) (exact? bit-size))))
       (let ([signed? (syntax->datum #'signed?)]
             [bit-size (syntax->datum #'bit-size)])
         (let ([base-name (format "~a~svector" (if signed? #\s #\u) bit-size)])
           (with-syntax ([name (format-id #'k "$~a" base-name)]
                         [bv-accessor (format-id #'k "$~a-bv" base-name)]
                         [maker (format-id #'k "make-~a" base-name)]
                         [pred (format-id #'k "~a?" base-name)]
                         [litmaker (format-id #'k "~a" base-name)]
                         [len (format-id #'k "~a-length" base-name)]
                         [ref (format-id #'k "~a-ref" base-name)]
                         [set (format-id #'k "~a-set!" base-name)]
                         [->list (format-id #'k "~a->list" base-name)]
                         [list-> (format-id #'k "list->~a" base-name)]
                         [bytes (fxdiv bit-size 8)]
                         [min (if signed? (- (expt 2 (- bit-size 1))) 0)]
                         [max (if signed?
                                  (- (expt 2 (- bit-size 1)) 1)
                                  (- (expt 2 bit-size) 1))]
                         [(bytevector-ref bytevector-set!)
                          (let ([signed-char (if signed? #\s #\u)])
                            (if (fx=? bit-size 8)
                                (list
                                  (format-id #'k "bytevector-~a~s-ref" signed-char bit-size)
                                  (format-id #'k "bytevector-~a~s-set!" signed-char bit-size))
                                (list
                                  (format-id #'k "bytevector-~a~s-native-ref" signed-char bit-size)
                                  (format-id #'k "bytevector-~a~s-native-set!" signed-char bit-size))))])
             #'(begin
                 (define check-val
                   (lambda (who value)
                     (unless (and (and (integer? value)
                                       (exact? value))
                                  (<= min value max))
                       (error who (format "expected integer value in range ~s to ~s, but got ~s" min max value)))))
                 (define-record-type (name maker pred)
                   (nongenerative)
                   (sealed #t)
                   (opaque #t)
                   (fields (immutable bv bv-accessor))
                   (protocol
                     (lambda (new)
                       (case-lambda
                         [(size) (new (make-bytevector (fx* size bytes)))]
                         [(size value)
                          (check-val 'maker value)
                          (let ([bv-size (fx* size bytes)])
                            (let ([bv (make-bytevector bv-size)])
                              (do ([i 0 (fx+ i bytes)])
                                ((fx=? i bv-size) (new bv))
                                (bytevector-set! bv i value))))]))))
                 (define len
                   (lambda (v)
                     (fxdiv (bytevector-length (bv-accessor v)) bytes)))
                 (define ref
                   (lambda (v i)
                     (bytevector-ref (bv-accessor v) (fx* i bytes))))
                 (define set
                   (lambda (v i value)
                     (check-val 'set! value)
                     (bytevector-set! (bv-accessor v) (fx* i bytes) value)))
                 (define ->list
                   (lambda (v)
                     (let ([bv (bv-accessor v)])
                       (let loop ([n (bytevector-length bv)] [ls '()])
                         (if (fx=? n 0)
                             ls
                             (let ([n (fx- n bytes)])
                               (loop n (cons (bytevector-ref bv n) ls))))))))
                 (define $list->
                   (lambda (who ls)
                     (let f ([ls ls] [bv-bytes 0])
                       (if (null? ls)
                           (maker (fxdiv bv-bytes bytes))
                           (let ([v (f (cdr ls) (fx+ bv-bytes bytes))] [val (car ls)])
                             (check-val who val)
                             (bytevector-set! (bv-accessor v) bv-bytes val)
                             v)))))
                 (define list-> (lambda (ls) ($list-> 'list-> ls)))
                 (define litmaker (lambda args ($list-> 'litmaker args)))))))])))

(define-integer-vector #t 8)
(define-integer-vector #t 16)
(define-integer-vector #t 32)
(define-integer-vector #t 64)

(define-integer-vector #f 8)
(define-integer-vector #f 16)
(define-integer-vector #f 32)
(define-integer-vector #f 64)

(define-syntax define-float-vector
  (lambda (x)
    (define format-id
      (lambda (tid fmt . args)
        (datum->syntax tid
          (string->symbol
            (apply format fmt args)))))
    (syntax-case x ()
      [(k bit-size)
       (let ([bit-size (syntax->datum #'bit-size)])
         (and (integer? bit-size) (exact? bit-size)))
       (let ([bit-size (syntax->datum #'bit-size)])
         (let ([base-name (format "f~svector" bit-size)])
           (with-syntax ([name (format-id #'k "$~a" base-name)]
                         [bv-accessor (format-id #'k "$~a-bv" base-name)]
                         [maker (format-id #'k "make-~a" base-name)]
                         [pred (format-id #'k "~a?" base-name)]
                         [litmaker (format-id #'k "~a" base-name)]
                         [len (format-id #'k "~a-length" base-name)]
                         [ref (format-id #'k "~a-ref" base-name)]
                         [set (format-id #'k "~a-set!" base-name)]
                         [->list (format-id #'k "~a->list" base-name)]
                         [list-> (format-id #'k "list->~a" base-name)]
                         [bytes (fxdiv bit-size 8)]
                         [(bytevector-ref bytevector-set!)
                          (case bit-size
                            [(32)
                             (list #'bytevector-ieee-single-native-ref
                                   #'bytevector-ieee-single-native-set!)]
                            [(64)
                             (list #'bytevector-ieee-double-native-ref
                                   #'bytevector-ieee-double-native-set!)])])
             #'(begin
                 (define check-val
                   (lambda (who value)
                     (unless (flonum? value)
                       (error who (format "expected floating point value, but got ~s" value)))))
                 (define-record-type (name maker pred)
                   (nongenerative)
                   (sealed #t)
                   (opaque #t)
                   (fields (immutable bv bv-accessor))
                   (protocol
                     (lambda (new)
                       (case-lambda
                         [(size) (new (make-bytevector (fx* size bytes)))]
                         [(size value)
                          (check-val 'maker value)
                          (let ([bv-size (fx* size bytes)])
                            (let ([bv (make-bytevector bv-size)])
                              (do ([i 0 (fx+ i bytes)])
                                ((fx=? i bv-size) (new bv))
                                (bytevector-set! bv i value))))]))))
                 (define len
                   (lambda (v)
                     (fxdiv (bytevector-length (bv-accessor v)) bytes)))
                 (define ref
                   (lambda (v i)
                     (bytevector-ref (bv-accessor v) (fx* i bytes))))
                 (define set
                   (lambda (v i value)
                     (check-val 'set! value)
                     (bytevector-set! (bv-accessor v) (fx* i bytes) value)))
                 (define ->list
                   (lambda (v)
                     (let ([bv (bv-accessor v)])
                       (let loop ([n (bytevector-length bv)] [ls '()])
                         (if (fx=? n 0)
                             ls
                             (let ([n (fx- n bytes)])
                               (loop n (cons (bytevector-ref bv n) ls))))))))
                 (define $list->
                   (lambda (who ls)
                     (let f ([ls ls] [bv-bytes 0])
                       (if (null? ls)
                           (maker (fxdiv bv-bytes bytes))
                           (let ([v (f (cdr ls) (fx+ bv-bytes bytes))] [val (car ls)])
                             (check-val who val)
                             (bytevector-set! (bv-accessor v) bv-bytes val)
                             v)))))
                 (define list-> (lambda (ls) ($list-> 'list-> ls)))
                 (define litmaker (lambda args ($list-> 'litmaker args)))))))])))

(define-float-vector 32)
(define-float-vector 64)
)
