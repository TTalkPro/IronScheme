#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std arithmetic) —— 整数除法、fixnum 补充与位运算（designs/08-std-library.md）
;;; 词源与取舍（D3）：
;;;   SRFI 141（John Cowan，整数除法）：floor/ truncate/ … euclidean/ balanced/ 等 18 个，参照实现
;;;     Copyright (c) 2010--2011 Taylor R. Campbell（BSD 两条款，全文见下方代码）。
;;;   SRFI 143（John Cowan，fixnum）：只收基础库没有的 12 个（fx-width fx-greatest fx-least fxneg fxabs
;;;     fxsquare fxsqrt fxquotient fxremainder fxfirst-set-bit fxbit-field-rotate fxbit-field-reverse）。
;;;   SRFI 151（John Cowan，位运算）为主：34 个。
;;;   SRFI 60（Aubrey Jaffer，整数位）：只收 SRFI 151 没有的 17 个：
;;;     any-bits-set? ash bitwise-merge booleans->integer copy-bit-field integer->list list->integer log2-binary-factors logand
;;;     logbit? logcount logior lognot logtest logxor reverse-bit-field rotate-bit-field
;;;     与 SRFI 151 同名的 arithmetic-shift bit-count bit-field bit-set? copy-bit first-set-bit
;;;     integer-length 按 SRFI 151（copy-bit 的参数等与 SRFI 60 不同）。
;;; 实现：SRFI 143 / 151 / 60 的 R6RS 实现 Copyright (c) 2018 - 2020 Andrew W. Keep（chez-srfi，MIT，
;;; 见 LICENSES/chez-srfi.txt）；SRFI 151 的 bitwise-eqv 等出自 Olin Shivers 的 SRFI 33 实现（公有领域）。
;;; SRFI 60 部分在 (ironscheme std private integer-bits)。
;;;
;;; 你要的在 IronScheme 里叫什么（D2：下列名字与基础库同名，本库不导出）：
;;;   ⚠ fxbit-set? fxcopy-bit  基础库为 R6RS 版本，参数次序与 SRFI 143 相反：
;;;                          SRFI 143 的 (fxbit-set? 下标 i) → (fxbit-set? i 下标)；
;;;                          SRFI 143 的 (fxcopy-bit 下标 i 布尔) → (fxcopy-bit i 下标 (if 布尔 1 0))
;;;   bitwise-and bitwise-ior bitwise-xor bitwise-not bitwise-if、fx+ fx* fxand … → 基础库（同一绑定）
;;;
;;; 基础库的 bitwise-copy-bit 曾在下标为 31 时误走 fixnum 路径而报错，iron-043 时本库用库内版本绕开；
;;; iron-054 修正了基础库，现在直接用基础库的。
(library (ironscheme std arithmetic)
  (export
    any-bit-set? any-bits-set? arithmetic-shift ash balanced-quotient balanced-remainder
    balanced/ bit-count bit-field bit-field-any? bit-field-clear bit-field-every?
    bit-field-replace bit-field-replace-same bit-field-reverse bit-field-rotate bit-field-set
    bit-set? bit-swap bits bits->list bits->vector bitwise-andc1 bitwise-andc2 bitwise-eqv
    bitwise-fold bitwise-for-each bitwise-merge bitwise-nand bitwise-nor bitwise-orc1
    bitwise-orc2 bitwise-unfold booleans->integer ceiling-quotient ceiling-remainder ceiling/
    copy-bit copy-bit-field euclidean-quotient euclidean-remainder euclidean/ every-bit-set?
    first-set-bit floor-quotient floor-remainder floor/ fx-greatest fx-least fx-width fxabs
    fxbit-field-reverse fxbit-field-rotate fxfirst-set-bit fxneg fxquotient fxremainder
    fxsqrt fxsquare integer->list integer-length list->bits list->integer log2-binary-factors
    logand logbit? logcount logior lognot logtest logxor make-bitwise-generator
    reverse-bit-field rotate-bit-field round-quotient round-remainder round/
    truncate-quotient truncate-remainder truncate/ vector->bits)
  (import
    (except (rnrs) fxbit-set? fxcopy-bit)
    (prefix (only (rnrs) fxbit-set? fxcopy-bit) r6:)
    (rnrs r5rs)
    (only (ironscheme std private integer-bits) any-bits-set? ash bitwise-merge booleans->integer copy-bit-field integer->list list->integer log2-binary-factors logand logbit? logcount logior lognot logtest logxor reverse-bit-field rotate-bit-field))

;; ———————————————— SRFI 141 ————————————————

;;; -*- Mode: Scheme -*-

;;;; Integer Division Operators

;;; Given a QUOTIENT and REMAINDER defined for nonnegative numerators
;;; and positive denominators implementing the truncated, floored, or
;;; Euclidean integer division, this implements a number of other
;;; integer division operators.

;;; Copyright (c) 2010--2011 Taylor R. Campbell
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;; 1. Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;; 2. Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
;;; ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
;;; FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
;;; DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
;;; OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
;;; HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
;;; LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
;;; OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
;;; SUCH DAMAGE.

;;;; Shims
;;; SRFI-8
(define-syntax receive
  (syntax-rules ()
    ((receive formals expression body ...)
     (call-with-values (lambda () expression)
                       (lambda formals body ...)))))

;;; exact-integer?
(define (exact-integer? x) (and (integer? x) (exact? x)))

;;;; Integer Division

;;;; Ceiling

(define (ceiling/ n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (ceiling-/- n d))
            ((negative? n)
             (let ((n (- 0 n)))
               (values (- 0 (quotient n d)) (- 0 (remainder n d)))))
            ((negative? d)
             (let ((d (- 0 d)))
               (values (- 0 (quotient n d)) (remainder n d))))
            (else
             (ceiling+/+ n d)))
      (let ((q (ceiling (/ n d))))
        (values q (- n (* d q))))))

(define (ceiling-/- n d)
  (let ((n (- 0 n)) (d (- 0 d)))
    (let ((q (quotient n d)) (r (remainder n d)))
      (if (zero? r)
          (values q r)
          (values (+ q 1) (- d r))))))

(define (ceiling+/+ n d)
  (let ((q (quotient n d)) (r (remainder n d)))
    (if (zero? r)
        (values q r)
        (values (+ q 1) (- r d)))))

(define (ceiling-quotient n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (receive (q r) (ceiling-/- n d) r q))
            ((negative? n) (- 0 (quotient (- 0 n) d)))
            ((negative? d) (- 0 (quotient n (- 0 d))))
            (else (receive (q r) (ceiling+/+ n d) r q)))
      (ceiling (/ n d))))

(define (ceiling-remainder n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (receive (q r) (ceiling-/- n d) q r))
            ((negative? n) (- 0 (remainder (- 0 n) d)))
            ((negative? d) (remainder n (- 0 d)))
            (else (receive (q r) (ceiling+/+ n d) q r)))
      (- n (* d (ceiling (/ n d))))))

;;;; Euclidean Division

;;; 0 <= r < |d|

(define (euclidean/ n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d)) (ceiling-/- n d))
            ((negative? n) (floor-/+ n d))
            ((negative? d)
             (let ((d (- 0 d)))
               (values (- 0 (quotient n d)) (remainder n d))))
            (else (values (quotient n d) (remainder n d))))
      (let ((q (if (negative? d) (ceiling (/ n d)) (floor (/ n d)))))
        (values q (- n (* d q))))))

(define (euclidean-quotient n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (receive (q r) (ceiling-/- n d) r q))
            ((negative? n) (receive (q r) (floor-/+ n d) r q))
            ((negative? d) (- 0 (quotient n (- 0 d))))
            (else (quotient n d)))
      (if (negative? d) (ceiling (/ n d)) (floor (/ n d)))))

(define (euclidean-remainder n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (receive (q r) (ceiling-/- n d) q r))
            ((negative? n) (receive (q r) (floor-/+ n d) q r))
            ((negative? d) (remainder n (- 0 d)))
            (else (remainder n d)))
      (- n (* d (if (negative? d) (ceiling (/ n d)) (floor (/ n d)))))))

;;;; Floor

(define (floor/ n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (let ((n (- 0 n)) (d (- 0 d)))
               (values (quotient n d) (- 0 (remainder n d)))))
            ((negative? n) (floor-/+ n d))
            ((negative? d) (floor+/- n d))
            (else (values (quotient n d) (remainder n d))))
      (let ((q (floor (/ n d))))
        (values q (- n (* d q))))))

(define (floor-/+ n d)
  (let ((n (- 0 n)))
    (let ((q (quotient n d)) (r (remainder n d)))
      (if (zero? r)
          (values (- 0 q) r)
          (values (- (- 0 q) 1) (- d r))))))

(define (floor+/- n d)
  (let ((d (- 0 d)))
    (let ((q (quotient n d)) (r (remainder n d)))
      (if (zero? r)
          (values (- 0 q) r)
          (values (- (- 0 q) 1) (- r d))))))

(define (floor-quotient n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d)) (quotient (- 0 n) (- 0 d)))
            ((negative? n) (receive (q r) (floor-/+ n d) r q))
            ((negative? d) (receive (q r) (floor+/- n d) r q))
            (else (quotient n d)))
      (floor (/ n d))))

(define (floor-remainder n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (- 0 (remainder (- 0 n) (- 0 d))))
            ((negative? n) (receive (q r) (floor-/+ n d) q r))
            ((negative? d) (receive (q r) (floor+/- n d) q r))
            (else (remainder n d)))
      (- n (* d (floor (/ n d))))))

;;;; Round Ties to Even

(define (round/ n d)
  (define (divide n d adjust leave)
    (let ((q (quotient n d)) (r (remainder n d)))
      (if (and (not (zero? r))
               (or (and (odd? q) (even? d) (divisible? n (quotient d 2)))
                   (< d (* 2 r))))
          (adjust (+ q 1) (- r d))
          (leave q r))))
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (divide (- 0 n) (- 0 d)
               (lambda (q r) (values q (- 0 r)))
               (lambda (q r) (values q (- 0 r)))))
            ((negative? n)
             (divide (- 0 n) d
               (lambda (q r) (values (- 0 q) (- 0 r)))
               (lambda (q r) (values (- 0 q) (- 0 r)))))
            ((negative? d)
             (divide n (- 0 d)
               (lambda (q r) (values (- 0 q) r))
               (lambda (q r) (values (- 0 q) r))))
            (else
             (let ((return (lambda (q r) (values q r))))
               (divide n d return return))))
      (let ((q (round (/ n d))))
        (values q (- n (* d q))))))

(define (divisible? n d)
  ;; This operation admits a faster implementation than the one given
  ;; here.
  (zero? (remainder n d)))

(define (round-quotient n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (receive (q r) (round/ n d)
        r                               ;ignore
        q)
      (round (/ n d))))

(define (round-remainder n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (receive (q r) (round/ n d)
        q                               ;ignore
        r)
      (- n (* d (round (/ n d))))))

;;;; Truncate

(define (truncate/ n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (let ((n (- 0 n)) (d (- 0 d)))
               (values (quotient n d) (- 0 (remainder n d)))))
            ((negative? n)
             (let ((n (- 0 n)))
               (values (- 0 (quotient n d)) (- 0 (remainder n d)))))
            ((negative? d)
             (let ((d (- 0 d)))
               (values (- 0 (quotient n d)) (remainder n d))))
            (else
             (values (quotient n d) (remainder n d))))
      (let ((q (truncate (/ n d))))
        (values q (- n (* d q))))))

(define (truncate-quotient n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d)) (quotient (- 0 n) (- 0 d)))
            ((negative? n) (- 0 (quotient (- 0 n) d)))
            ((negative? d) (- 0 (quotient n (- 0 d))))
            (else (quotient n d)))
      (truncate (/ n d))))

(define (truncate-remainder n d)
  (if (and (exact-integer? n) (exact-integer? d))
      (cond ((and (negative? n) (negative? d))
             (- 0 (remainder (- 0 n) (- 0 d))))
            ((negative? n) (- 0 (remainder (- 0 n) d)))
            ((negative? d) (remainder n (- 0 d)))
            (else (remainder n d)))
      (- n (* d (truncate (/ n d))))))

;;; Copyright 2015 William D Clinger.
;;;
;;; Permission to copy this software, in whole or in part, to use this
;;; software for any lawful purpose, and to redistribute this software
;;; is granted subject to the restriction that all copies made of this
;;; software must include this copyright and permission notice in full.
;;;
;;; I also request that you send me a copy of any improvements that you
;;; make to this software so that they may be incorporated within it to
;;; the benefit of the Scheme community.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (balanced/ x y)
  (call-with-values
   (lambda () (euclidean/ x y))
   (lambda (q r)
     (cond ((< r (abs (/ y 2)))
            (values q r))
           ((> y 0)
            (values (+ q 1) (- x (* (+ q 1) y))))
           (else
            (values (- q 1) (- x (* (- q 1) y))))))))

(define (balanced-quotient x y)
  (call-with-values
   (lambda () (balanced/ x y))
   (lambda (q r) q)))

(define (balanced-remainder x y)
  (call-with-values
   (lambda () (balanced/ x y))
   (lambda (q r) r)))

;; ———————————————— SRFI 143（helpers 与 fixnums）————————————————
(define fxabs (lambda (i) (if (fx<? i 0) (fx- i) i)))

(define fxremainder (lambda (n d) (remainder n d)))

(define fxquotient (lambda (n d) (quotient n d)))

(define fx-width (fixnum-width))
(define fx-greatest (greatest-fixnum))
(define fx-least (least-fixnum))

(define (fxbit-set? index b)
  (r6:fxbit-set? b index))

(define (fxcopy-bit index i c)
  (if (fxnegative? index)
      (r6:fxcopy-bit i (fx+ fx-width index) (if c 1 0))
      (r6:fxcopy-bit i index (if c 1 0))))

(define fxneg (lambda (i) (fx- i)))

(define fxsquare (lambda (i) (fx* i i)))

(define fxsqrt (lambda (i) (exact-integer-sqrt i)))

(define fxfirst-set-bit (lambda (i) (fxfirst-bit-set i)))

(define (fxbit-field-rotate i count start end)
  (if (fxnegative? count)
    (fxrotate-bit-field i start end (+ count (- end start)))
    (fxrotate-bit-field i start end count)))

(define fxbit-field-reverse (lambda (i s e) (fxreverse-bit-field i s e)))

;; ———————————————— SRFI 151 ————————————————
;;; The bitwise-eqv implmentation is based on the one in the SRFI-151
;;; implementation, which extracted it from the SRFI-33 implementation which
;;; carried the following copyright information:
;;;
;;; Olin Shivers is the sole author of this code, and he has placed it in
;;; the public domain.
;;;
;;; A good implementation might choose to provide direct compiler/interpreter
;;; support for these derived functions, or might simply define them to be
;;; integrable -- i.e., inline-expanded.
;;;
;;; This is a general definition, but less than efficient.  It should also
;;; receive primitive compiler/interpreter support so that the expensive
;;; n-ary mechanism is not invoked in the standard cases -- that is,
;;; an application of BITWISE-EQV should be rewritten into an equivalent
;;; tree applying some two-argument primitive to the arguments, in the
;;; same manner that statically-known n-ary applications of associative
;;; operations such as + and * are handled efficiently:
;;;   (bitwise-eqv)         => -1
;;;   (bitwise-eqv i)       => i
;;;   (bitwise-eqv i j)     => (%bitwise-eqv i j)
;;;   (bitwise-eqv i j k)   => (%bitwise-eqv (%bitwise-eqv i j) k)
;;;   (bitwise-eqv i j k l) => (%bitwise-eqv (%bitwise-eqv (%bitwise-eqv i j) k) l)
;;;
;;; Note: this implementation takes the advice of the comment avove and
;;; implemets this using case lambade, though Chez Scheme's source optimizer
;;; is relied upon to produce the constants.
(define bitwise-eqv
  (case-lambda
    [() (bitwise-not (bitwise-xor))]
    [(i) (bitwise-not (bitwise-xor i))]
    [(i j) (bitwise-not (bitwise-xor i j))]
    [(i . more)
     (let loop ([i i] [more more])
       (if (null? more)
           i
           (loop (bitwise-not (bitwise-xor i (car more))) (cdr more))))]))

(define bitwise-nand  (lambda (i j) (bitwise-not (bitwise-and i j))))
(define bitwise-nor   (lambda (i j) (bitwise-not (bitwise-ior i j))))
(define bitwise-andc1 (lambda (i j) (bitwise-and (bitwise-not i) j)))
(define bitwise-andc2 (lambda (i j) (bitwise-and i (bitwise-not j))))
(define bitwise-orc1  (lambda (i j) (bitwise-ior (bitwise-not i) j)))
(define bitwise-orc2  (lambda (i j) (bitwise-ior i (bitwise-not j))))

(define arithmetic-shift (lambda (i c) (bitwise-arithmetic-shift i c)))

(define bit-count
  (lambda (i)
    (if (< i 0)
        (bitwise-bit-count (bitwise-not i))
        (bitwise-bit-count i))))

(define integer-length (lambda (i) (bitwise-length i)))

(define bit-set? (lambda (index i) (bitwise-bit-set? i index)))

(define copy-bit
  (lambda (index i bool)
    (bitwise-copy-bit i index (if bool 1 0))))

(define bit-swap
  (lambda (idx1 idx2 i)
    (if (bitwise-bit-set? i idx1)
        (if (bitwise-bit-set? i idx2)
            i
            (bitwise-copy-bit (bitwise-copy-bit i idx2 1) idx1 0))
        (if (bitwise-bit-set? i idx2)
            (bitwise-copy-bit (bitwise-copy-bit i idx2 0) idx1 1)
            i))))

(define any-bit-set?  (lambda (bits i) (not (zero? (bitwise-and bits i)))))
(define every-bit-set?  (lambda (bits i) (= (bitwise-and bits i) bits)))

(define first-set-bit (lambda (i) (bitwise-first-bit-set i)))

(define bit-field (lambda (i s e) (bitwise-bit-field i s e)))

(define bit-field-any?
  (lambda (i s e)
    (not (zero? (bitwise-bit-field i s e)))))

(define bit-field-every?
  (lambda (i s e)
    (= (bitwise-bit-field i s e) (- (expt 2 (- e s)) 1))))

(define bit-field-clear
  (lambda (i s e)
    (bitwise-copy-bit-field i s e 0)))

(define bit-field-set
  (lambda (i s e)
    (bitwise-copy-bit-field i s e -1)))

(define bit-field-replace
  (lambda (dest src s e)
    (bitwise-copy-bit-field dest s e src)))

(define bit-field-replace-same
  (lambda (dest src s e)
    (bitwise-copy-bit-field dest s e (bitwise-bit-field src s e))))

(define bit-field-rotate
  (lambda (i count start end)
    (if (negative? count)
        (bitwise-rotate-bit-field i start end (fx+ count (fx- end start)))
        (bitwise-rotate-bit-field i start end count))))

(define bit-field-reverse
  (lambda (i start end)
    (bitwise-reverse-bit-field i start end)))

(define bits->list
  (case-lambda
    [(i)
     (if (< i 0)
         (bits->list i (integer-length i))
         (let f ([i i])
           (if (zero? i)
               '()
               (cons (odd? i) (f (bitwise-arithmetic-shift-right i 1))))))]
    [(i n)
     (let loop ([n n] [ls '()])
       (if (fx=? n 0)
           ls
           (let ([n (fx- n 1)])
             (loop n (cons (bitwise-bit-set? i n) ls)))))]))

(define bits->vector
  (case-lambda
    [(i)
     (if (< i 0)
         (bits->vector i (integer-length i))
         (let f ([i i] [c 0])
           (if (fx=? i 0)
               (make-vector c)
               (let ([v (f (bitwise-arithmetic-shift-right i 1) (fx+ c 1))])
                 (vector-set! v c (odd? i))))))]
    [(i n)
     (let ([v (make-vector n)])
       (let loop ([n n])
         (unless (fx=? n 0)
           (let ([n (fx- n 1)])
             (vector-set! v n (bitwise-bit-set? i n))
             (loop n))))
       v)]))

(define list->bits
  (lambda (ls)
    (let loop ([ls ls] [idx 0] [i 0])
      (if (null? ls)
          i
          (loop (cdr ls) (fx+ idx 1)
            (bitwise-copy-bit i idx (if (car ls) 1 0)))))))

(define vector->bits
  (lambda (v)
    (let loop ([n (vector-length v)] [i 0])
      (if (fx=? n 0)
          i
          (let ([n (fx- n 1)])
            (loop n (bitwise-copy-bit i n (if (vector-ref v n) 1 0))))))))

(define bits (lambda args (list->bits args)))

;; ---- from SRFI-151 other ---
;; The following functions: bitwise-fold, bitwise-for-each, bitwise-unfold,
;; and make-bitwise-generator are taken from John Cowan's implemtation
;; functions from the SRFI-151.
;;
;; Copyright John Cowan 2017
;;
(define bitwise-fold
  (lambda (proc seed i)
    (let ([n (integer-length i)])
      (let loop ([idx 0] [r seed])
        (if (fx=? idx n)
            r
            (loop (fx+ idx 1) (proc (bitwise-bit-set? i idx) r)))))))

(define bitwise-for-each
  (lambda (proc i)
    (let ([n (integer-length i)])
      (let loop ([idx 0])
        (unless (fx=? idx n)
          (proc (bitwise-bit-set? i idx))
          (loop (fx+ idx 1)))))))

(define bitwise-unfold
  (lambda (stop? mapper successor seed)
    (do ([state seed (successor state)]
         [idx 0 (fx+ idx 1)]
         [i 0 (bitwise-copy-bit i idx (if (mapper state) 1 0))])
      ((stop? state) i))))

(define make-bitwise-generator
  (lambda (i)
    (let ([idx 0])
      (lambda ()
        (let ([r (bitwise-bit-set? i idx)])
          (set! idx (fx+ idx 1))
          r)))))
;; ---- END from SRFI-151 other ---
)
