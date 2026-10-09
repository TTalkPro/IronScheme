#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std private integer-bits) —— SRFI 60 的 R6RS 实现（Copyright (c) 2018 - 2020 Andrew W. Keep，
;;; chez-srfi，MIT 许可，见 LICENSES/chez-srfi.txt），不对外。(ironscheme std arithmetic) 只取其中 SRFI 151
;;; 没有的名字（D3）；与 SRFI 151 同名的（copy-bit bit-set? 等）语义不同，按 SRFI 151。
;;; 与参照实现不同（D4）：integer->list / list->integer（及 booleans->integer）按 SRFI 60 参照实现（SLIB）
;;; 为高位在前，原实现写成了低位在前（那是 SRFI 151 bits->list 的次序）。
(library (ironscheme std private integer-bits)
  (export
    logand bitwise-and logior bitwise-ior logxor bitwise-xor lognot bitwise-not bitwise-if
    bitwise-merge logtest any-bits-set? logcount bit-count integer-length log2-binary-factors
    first-set-bit logbit? bit-set? copy-bit bit-field copy-bit-field ash arithmetic-shift
    rotate-bit-field reverse-bit-field integer->list list->integer booleans->integer)
  (import
    (rnrs))

(define logand
  (case-lambda
    [() (bitwise-and)]
    [(i) i]
    [(i j) (bitwise-and i j)]
    [(i j k) (bitwise-and i j k)]
    [args (apply bitwise-and args)]))

(define logior
  (case-lambda
    [() (bitwise-ior)]
    [(i) i]
    [(i j) (bitwise-ior i j)]
    [(i j k) (bitwise-ior i j k)]
    [args (apply bitwise-ior args)]))

(define logxor
  (case-lambda
    [() (bitwise-xor)]
    [(i) i]
    [(i j) (bitwise-xor i j)]
    [(i j k) (bitwise-xor i j k)]
    [args (apply bitwise-xor args)]))

(define lognot (lambda (n) (bitwise-not n)))

(define bitwise-merge (lambda (m n0 n1) (bitwise-if m n0 n1)))

(define logtest (lambda (j k) (not (zero? (logand j k)))))
(define any-bits-set? (lambda (j k) (not (zero? (logand j k)))))

(define logcount
  (lambda (n)
    (if (< n 0)
        (bitwise-bit-count (bitwise-not n))
        (bitwise-bit-count n))))

(define bit-count
  (lambda (n)
    (if (< n 0)
        (bitwise-bit-count (bitwise-not n))
        (bitwise-bit-count n))))

(define integer-length (lambda (n) (bitwise-length n)))

(define log2-binary-factors (lambda (n) (bitwise-first-bit-set n)))
(define first-set-bit (lambda (n) (bitwise-first-bit-set n)))

(define logbit? (lambda (i n) (bitwise-bit-set? n i)))
(define bit-set? (lambda (i n) (bitwise-bit-set? n i))) 

(define copy-bit (lambda (i n b) (bitwise-copy-bit n i (if b 1 0))))

(define bit-field (lambda (n s e) (bitwise-bit-field n s e)))

(define copy-bit-field
  (lambda (to from s e)
    (bitwise-copy-bit-field to s e from)))

(define ash (lambda (n count) (bitwise-arithmetic-shift n count)))
(define arithmetic-shift
  (lambda (n count)
    (bitwise-arithmetic-shift n count)))

(define rotate-bit-field
  (lambda (n count start end)
    (bitwise-rotate-bit-field n start end count)))

(define reverse-bit-field
  (lambda (n start end)
    (bitwise-reverse-bit-field n start end)))

;; 高位在前（SRFI 60 / SLIB）
(define integer->list
  (case-lambda
    [(k len) (let loop ([i 0] [ls '()])
               (if (fx=? i len)
                   ls
                   (loop (fx+ i 1) (cons (bitwise-bit-set? k i) ls))))]
    [(k) (integer->list k (bitwise-length k))]))

(define list->integer
  (lambda (ls)
    (let loop ([ls ls] [i 0] [n 0])
      (if (null? ls)
          n
          (loop (cdr ls) (fx+ i 1) (+ n n (if (car ls) 1 0)))))))   ; 高位在前

(define booleans->integer
  (lambda args
    (list->integer args)))
)
