#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std char-sets) —— 字符集（designs/08-std-library.md）
;;; 词源：SRFI 14（Olin Shivers）。实现来自 Scheme 48（Mike Sperber，许可证见 LICENSES/scheme48.txt），
;;; 经 chez-srfi 改写为 R6RS（Derick Eddington，MIT 许可，见 LICENSES/chez-srfi.txt）。
;;; 字符集表示：Latin-1 部分为字节向量，其余为反转表（(ironscheme std private inversion-list)）。
;;;
;;; 与 SRFI 文本不同的取舍（D4）：
;;;   ① 标准字符集（char-set:letter 等）的数据按 .NET 的 Unicode 数据生成（iron-054；Scheme 48 原数据为
;;;      Unicode 5.x），与 char-alphabetic? 等基础库谓词所用的 Unicode 版本一致。
;;;   ② （iron-042 时字符串以 UTF-16 存储，BMP 之外的字符往返会变成代理对；iron-055 起字符串按码点，已无此问题。）
;;;   ③ 参数检查按 Scheme 48 的做法；错误为 &assertion。
;;; 本库所有名字都是基础库没有的（D2）。
(library (ironscheme std char-sets)
  (export
    ->char-set char-set char-set->list char-set->string char-set-adjoin char-set-adjoin!
    char-set-any char-set-complement char-set-complement! char-set-contains? char-set-copy
    char-set-count char-set-cursor char-set-cursor-next char-set-delete char-set-delete!
    char-set-diff+intersection char-set-diff+intersection! char-set-difference
    char-set-difference! char-set-every char-set-filter char-set-filter! char-set-fold
    char-set-for-each char-set-hash char-set-intersection char-set-intersection! char-set-map
    char-set-ref char-set-size char-set-unfold char-set-unfold! char-set-union
    char-set-union! char-set-xor char-set-xor! char-set:ascii char-set:blank char-set:digit
    char-set:empty char-set:full char-set:graphic char-set:hex-digit char-set:iso-control
    char-set:letter char-set:letter+digit char-set:lower-case char-set:printing
    char-set:punctuation char-set:symbol char-set:title-case char-set:upper-case
    char-set:whitespace char-set<= char-set= char-set? end-of-char-set? list->char-set
    list->char-set! string->char-set string->char-set! ucs-range->char-set
    ucs-range->char-set!)
  (import
    (except (rnrs) define-record-type)
    (rnrs mutable-strings)
    (rnrs r5rs)
    (rename (only (rnrs) partition) (partition partition-list))
    (only (ironscheme std private compat) srfi-9:define-record-type let-optionals*)
    (ironscheme std private inversion-list))

(define-syntax define-record-type
  (syntax-rules ()
    ((_ . rest) (srfi-9:define-record-type . rest))))

(define-syntax define-record-discloser
  (syntax-rules ()
    ((_ type discloser)
     (define dummy #f))))

(define (make-immutable! obj)
  #f)

(define char->scalar-value char->integer)
(define scalar-value->char integer->char)

(define make-byte-vector make-bytevector)
(define byte-vector-ref bytevector-u8-ref)
(define byte-vector-set! bytevector-u8-set!)
(define byte-vector=? bytevector=?)
(define copy-bytes! bytevector-copy!)
(define byte-vector-length bytevector-length)

(define (unspecific) (if #f #f))

(define-syntax opt-lambda
  (lambda (x)
    (define (split-args args)
      (syntax-case args ()
        [(name . rest)
         (identifier? #'name)
         (let-values (((names opt-args) (split-args #'rest)))
           (values (cons #'name names) opt-args))]
        [(opt-args ...)
         (values '() #'(opt-args ...))]))
    (syntax-case x ()
      [(_ (args ...) body ...)
       (let-values (((fixed-args opt-args) (split-args #'(args ...))))
         (with-syntax (((fixed-args ...) fixed-args)
                       ((opt-args ...) opt-args))
           #'(lambda (fixed-args ... . rest)
               (let-optionals* rest (opt-args ...) body ...))))])))

;; SRFI 14 的名字是 ->char-set，Scheme 48 的实现叫 x->char-set
(define (->char-set x) (x->char-set x))

;; ———————————————— 改写自 srfi/%3a14/srfi-14.scm ————————————————

; Part of Scheme 48 1.9.  See file COPYING for notices and license.

; Authors: Mike Sperber, Robert Tansom

; Copyright (c) 2005-2006 by Basis Technology Corporation. 

; This is basically a complete re-implementation, suitable for Unicode.

; Some bits and pieces from Olin's reference implementation remain,
; but none from the MIT Scheme code.  For whatever remains, the
; following copyright holds:

; Copyright (c) 1994-2003 by Olin Shivers
; 
; All rights reserved.
; 
; Redistribution and use in source and binary forms, with or without
; modification, are permitted provided that the following conditions
; are met:
; 1. Redistributions of source code must retain the above copyright
;    notice, this list of conditions and the following disclaimer.
; 2. Redistributions in binary form must reproduce the above copyright
;    notice, this list of conditions and the following disclaimer in the
;    documentation and/or other materials provided with the distribution.
; 3. The name of the authors may not be used to endorse or promote products
;    derived from this software without specific prior written permission.
; 
; THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR
; IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
; OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
; IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT,
; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
; NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
; THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

(define-record-type :char-set
  (make-char-set simple i-list)
  char-set?
  ;; byte vector for the Latin-1 part
  (simple char-set-simple
	  set-char-set-simple!)
  ;; inversion list for the rest
  (i-list char-set-i-list
	  set-char-set-i-list!))

(define-record-discloser :char-set
  (lambda (cs)
    (list 'char-set
	  (char-set-size cs))))

(define (make-char-set-immutable! char-set)
  (make-immutable! char-set)
  (make-immutable! (char-set-simple char-set)))
  ; inversion lists are always immutable

;;; "Simple Csets"---we use mutable byte vectors for the Latin-1 part

(define *simple-cset-boundary* 256)

(define (simple-char? c)
  (< (char->scalar-value c) *simple-cset-boundary*))

(define (make-empty-simple-cset)
  (make-byte-vector *simple-cset-boundary* 0))

(define (make-full-simple-cset)
  (make-byte-vector *simple-cset-boundary* 1))

(define (copy-simple-cset s)
  (byte-vector-copy s))

; don't mistake these for abstractions
(define (simple-cset-code-not-member? s i) (zero? (byte-vector-ref s i)))
(define (simple-cset-code-member? s i) (not (simple-cset-code-not-member? s i)))
(define (simple-cset-ref s i) (byte-vector-ref s i))
(define (simple-cset-set! s i v) (byte-vector-set! s i v))
(define (simple-cset-remove-code! s i) (byte-vector-set! s i 0))
(define (simple-cset-adjoin-code! s i) (byte-vector-set! s i 1))

(define (simple-cset-contains? s char)
  (simple-cset-code-member? s (char->scalar-value char)))

(define (simple-cset=? s1 s2)
  (byte-vector=? s1 s2))

(define (simple-cset<=? s1 s2)
  (or (eq? s1 s2)
      (let loop ((i 0))
	(if (>= i *simple-cset-boundary*)
	    #t
	    (and (<= (simple-cset-ref s1 i) (simple-cset-ref s2 i))
		 (loop (+ 1 i)))))))

(define (simple-cset-size s)
  (let loop ((i 0) (size 0))
    (if (>= i *simple-cset-boundary*)
	size
	(loop (+ 1 i) (+ size (simple-cset-ref s i))))))

(define (simple-cset-count pred s)
  (let loop ((i 0) (count 0))
    (if (>= i *simple-cset-boundary*)
	count
	(loop (+ 1 i)
	      (if (and (simple-cset-code-member? s i) (pred (scalar-value->char i)))
		  (+ count 1)
		  count)))))

(define (simple-cset-modify! set s chars)
  (for-each (lambda (c) (set s (char->scalar-value c)))
	    chars)
  s)

(define (simple-cset-modify set s chars)
  (simple-cset-modify! set (copy-simple-cset s) chars))

(define (simple-cset-adjoin s . chars)
  (simple-cset-modify simple-cset-adjoin-code! s chars))
(define (simple-cset-adjoin! s . chars)
  (simple-cset-modify! simple-cset-adjoin-code! s chars))
(define (simple-cset-delete s . chars)
  (simple-cset-modify simple-cset-remove-code! s chars))
(define (simple-cset-delete! s . chars)
  (simple-cset-modify! simple-cset-remove-code! s chars))

;;; If we represented char sets as a bit set, we could do the following
;;; trick to pick the lowest bit out of the set: 
;;;   (count-bits (xor (- cset 1) cset))
;;; (But first mask out the bits already scanned by the cursor first.)

(define (simple-cset-cursor-next s cursor)
  (let loop ((cur cursor))
    (let ((cur (- cur 1)))
      (if (or (< cur 0) (simple-cset-code-member? s cur))
	  cur
	  (loop cur)))))

(define (end-of-simple-cset? cursor)
  (negative? cursor))

(define (simple-cset-cursor-ref cursor)
  (scalar-value->char cursor))

(define (simple-cset-for-each proc s)
  (let loop ((i 0))
    (if (< i *simple-cset-boundary*)
	(begin
	  (if (simple-cset-code-member? s i)
	      (proc (scalar-value->char i)))
	  (loop (+ 1 i))))))

(define (simple-cset-fold kons knil s)
  (let loop ((i 0) (ans knil))
    (if (>= i *simple-cset-boundary*)
	ans
	(loop (+ 1 i)
	      (if (simple-cset-code-not-member? s i)
		  ans
		  (kons (scalar-value->char i) ans))))))

(define (simple-cset-every? pred s)
  (let loop ((i 0))
    (cond
     ((>= i *simple-cset-boundary*)
      #t)
     ((or (simple-cset-code-not-member? s i)
	  (pred (scalar-value->char i)))
      (loop (+ 1 i)))
     (else
      #f))))

(define (simple-cset-any pred s)
  (let loop ((i 0))
    (cond
     ((>= i *simple-cset-boundary*) #f)
     ((and (simple-cset-code-member? s i)
	   (pred (scalar-value->char i))))
     (else
      (loop (+ 1 i))))))

(define (ucs-range->simple-cset lower upper)
  (let ((s (make-empty-simple-cset)))
    (let loop ((i lower))
      (if (< i upper)
	  (begin
	    (simple-cset-adjoin-code! s i)
	    (loop (+ 1 i)))))
    s))

; Algebra

; These do various "s[i] := s[i] op val" operations

(define (simple-cset-invert-code! s i v)
  (simple-cset-set! s i (- 1 v)))

(define (simple-cset-and-code! s i v)
  (if (zero? v)
      (simple-cset-remove-code! s i)))
(define (simple-cset-or-code! s i v)
  (if (not (zero? v))
      (simple-cset-adjoin-code! s i)))
(define (simple-cset-minus-code! s i v)
  (if (not (zero? v))
      (simple-cset-remove-code! s i)))
(define (simple-cset-xor-code! s i v)
  (if (not (zero? v))
      (simple-cset-set! s i (- 1 (simple-cset-ref s i)))))

(define (simple-cset-complement s)
  (simple-cset-complement! (copy-simple-cset s)))

(define (simple-cset-complement! s)
  (byte-vector-iter (lambda (i v) (simple-cset-invert-code! s i v)) s)
  s)

(define (simple-cset-op! s simple-csets code-op!)
  (for-each (lambda (s2)
	      (let loop ((i 0))
		(if (< i *simple-cset-boundary*)
		    (begin
		      (code-op! s i (simple-cset-ref s2 i))
		      (loop (+ 1 i))))))
	    simple-csets)
  s)

(define (simple-cset-union! s1 . ss)
  (simple-cset-op! s1 ss simple-cset-or-code!))

(define (simple-cset-union . ss)
  (if (pair? ss)
      (apply simple-cset-union!
	     (byte-vector-copy (car ss))
	     (cdr ss))
      (make-empty-simple-cset)))

(define (simple-cset-intersection! s1 . ss)
  (simple-cset-op! s1 ss simple-cset-and-code!))

(define (simple-cset-intersection . ss)
  (if (pair? ss)
      (apply simple-cset-intersection!
	     (byte-vector-copy (car ss))
	     (cdr ss))
      (make-full-simple-cset)))

(define (simple-cset-difference! s1 . ss)
  (simple-cset-op! s1 ss simple-cset-minus-code!))

(define (simple-cset-difference s1 . ss)
  (if (pair? ss)
      (apply simple-cset-difference! (copy-simple-cset s1) ss)
      (copy-simple-cset s1)))

(define (simple-cset-xor! s1 . ss)
  (simple-cset-op! s1 ss simple-cset-xor-code!))

(define (simple-cset-xor . ss)
  (if (pair? ss)
      (apply simple-cset-xor!
	     (byte-vector-copy (car ss))
	     (cdr ss))
      (make-empty-simple-cset)))

(define (simple-cset-diff+intersection! s1 s2 . ss)
  (byte-vector-iter (lambda (i v)
		       (cond
			((zero? v)
			 (simple-cset-remove-code! s2 i))
			((simple-cset-code-member? s2 i)
			 (simple-cset-remove-code! s1 i))))
		     s1)

  (for-each (lambda (s)
	      (byte-vector-iter (lambda (i v)
				  (if (and (not (zero? v))
					   (simple-cset-code-member? s1 i))
				      (begin
					(simple-cset-remove-code! s1 i)
					(simple-cset-adjoin-code! s2 i))))
				 s))
	    ss)

  (values s1 s2))



; Compute (c + 37 c + 37^2 c + ...) modulo BOUND, with sleaze thrown
; in to keep the intermediate values small. (We do the calculation
; with just enough bits to represent BOUND, masking off high bits at
; each step in calculation. If this screws up any important properties
; of the hash function I'd like to hear about it. -Olin)

(define (simple-cset-hash s bound)
  ;; The mask that will cover BOUND-1:
  (let ((mask (let loop ((i #x10000)) ; Let's skip first 16 iterations, eh?
		(if (>= i bound) (- i 1) (loop (+ i i))))))
    (let loop ((i (- *simple-cset-boundary* 1)) (ans 0))
      (if (< i 0)
	  (modulo ans bound)
	  (loop (- i 1)
	      (if (simple-cset-code-not-member? s i)
		  ans
		  (bitwise-and mask (+ (* 37 ans) i))))))))

;;; Now for the real character sets

(define (make-empty-char-set)
  (make-char-set (make-empty-simple-cset)
		 (make-empty-inversion-list *simple-cset-boundary* (+ 1 #x10ffff))))
(define (make-full-char-set)
  (make-char-set (make-full-simple-cset)
		 (range->inversion-list *simple-cset-boundary* (+ 1 #x10ffff)
					*simple-cset-boundary* (+ 1 #x10ffff))))

(define (char-set-copy cs)
  (make-char-set (copy-simple-cset (char-set-simple cs))
		 (inversion-list-copy (char-set-i-list cs))))

; n-ary version
(define (char-set= . rest)
  (or (null? rest)
      (let ((cs1  (car rest))
	    (rest (cdr rest)))
	(let loop ((rest rest))
	  (or (not (pair? rest))
	      (and (char-set=/2 cs1 (car rest))
		   (loop (cdr rest))))))))

; binary version
(define (char-set=/2 cs-1 cs-2)
  (and (simple-cset=? (char-set-simple cs-1) (char-set-simple cs-2))
       (inversion-list=? (char-set-i-list cs-1)
			 (char-set-i-list cs-2))))

; n-ary
(define (char-set<= . rest)
  (or (null? rest)
      (let ((cs1  (car rest))
	    (rest (cdr rest)))
	(let loop ((cs1 cs1)  (rest rest))
	  (or (not (pair? rest))
	      (and (char-set<=/2 cs1 (car rest))
		   (loop (car rest) (cdr rest))))))))

; binary
(define (char-set<=/2 cs-1 cs-2)
  (and (simple-cset<=? (char-set-simple cs-1) (char-set-simple cs-2))
       (inversion-list<=? (char-set-i-list cs-1)
			  (char-set-i-list cs-2))))

(define (inversion-list<=? i-list-1 i-list-2)
  (inversion-list=? i-list-1
		    (inversion-list-intersection i-list-1 i-list-2)))

;;; Hash

; We follow Olin's reference implementation:
;
; If you keep BOUND small enough, the intermediate calculations will 
; always be fixnums. How small is dependent on the underlying Scheme system; 
; we use a default BOUND of 2^22 = 4194304, which should hack it in
; Schemes that give you at least 29 signed bits for fixnums. The core 
; calculation that you don't want to overflow is, worst case,
;     (+ 65535 (* 37 (- bound 1)))
; where 65535 is the max character code. Choose the default BOUND to be the
; biggest power of two that won't cause this expression to fixnum overflow, 
; and everything will be copacetic.

(define char-set-hash
  (opt-lambda (cs (bound 4194304))
    (if (not (and (integer? bound)
		  (exact? bound)
		  (<= 0 bound)))
	(assertion-violation 'char-set-hash "invalid bound" bound))
    (let ((bound (if (zero? bound) 4194304 bound)))
      (modulo (+ (simple-cset-hash (char-set-simple cs) bound)
		 (* 37 (inversion-list-hash (char-set-i-list cs) bound)))
	      bound))))

(define (char-set-contains? cs char)
  (if (simple-char? char)
      (simple-cset-contains? (char-set-simple cs) char)
      (inversion-list-member? (char->scalar-value char)
			      (char-set-i-list cs))))

(define (char-set-size cs)
  (+ (simple-cset-size (char-set-simple cs))
     (inversion-list-size (char-set-i-list cs))))

(define (char-set-count pred cset)
  (+ (simple-cset-count pred (char-set-simple cset))
     (inversion-list-count pred (char-set-i-list cset))))

(define (inversion-list-count pred i-list)
  (inversion-list-fold/done? (lambda (v count)
			       (if (pred (scalar-value->char v))
				   (+ 1 count)
				   count))
			     0
			     (lambda (v) #f)
			     i-list))

(define (make-char-set-char-op simple-cset-op inversion-list-op)
  (lambda (cs . chars)
    (call-with-values
	(lambda () (partition-list simple-char? chars))
      (lambda (simple-chars non-simple-chars)
	(make-char-set (apply simple-cset-op (char-set-simple cs) simple-chars)
		       (apply inversion-list-op (char-set-i-list cs)
			      (map char->scalar-value non-simple-chars)))))))

(define (make-char-set-char-op! simple-cset-op! simple-cset-op
				inversion-list-op)
  (lambda (cs . chars)
    (call-with-values
	(lambda () (partition-list simple-char? chars))
      (lambda (simple-chars non-simple-chars)
	(if (null? non-simple-chars)
	    (apply simple-cset-op! (char-set-simple cs) simple-chars)
	    (begin
	      (set-char-set-simple! cs
				    (apply simple-cset-op (char-set-simple cs)
					   simple-chars))
	      (set-char-set-i-list! cs
				    (apply inversion-list-op (char-set-i-list cs)
					   (map char->scalar-value non-simple-chars)))))))
    cs))

(define char-set-adjoin
  (make-char-set-char-op simple-cset-adjoin inversion-list-adjoin))
(define char-set-adjoin!
  (make-char-set-char-op! simple-cset-adjoin! simple-cset-adjoin
			  inversion-list-adjoin))
(define char-set-delete
  (make-char-set-char-op simple-cset-delete inversion-list-remove))
(define char-set-delete!
  (make-char-set-char-op! simple-cset-delete! simple-cset-delete
			  inversion-list-remove))

;;; Cursors

; A cursor is either an integer index into the mark vector (-1 for the
; end-of-char-set cursor) as in the reference implementation, and an
; inversion-list cursor otherwise.

(define (char-set-cursor cset)
  (let ((simple-cursor
	 (simple-cset-cursor-next (char-set-simple cset) 
				  *simple-cset-boundary*)))
    (if (end-of-simple-cset? simple-cursor)
	(inversion-list-cursor (char-set-i-list cset))
	simple-cursor)))
  
(define (end-of-char-set? cursor)
  (and (inversion-list-cursor? cursor)
       (inversion-list-cursor-at-end? cursor)))

(define (char-set-ref cset cursor)
  (if (number? cursor)
      (simple-cset-cursor-ref cursor)
      (scalar-value->char (inversion-list-cursor-ref cursor))))

(define (char-set-cursor-next cset cursor)
  (cond
   ((number? cursor)
    (let ((next (simple-cset-cursor-next (char-set-simple cset) cursor)))
      (if (end-of-simple-cset? next)
	  (inversion-list-cursor (char-set-i-list cset))
	  next)))
   (else
    (inversion-list-cursor-next (char-set-i-list cset) cursor))))

(define (char-set-for-each proc cs)
  (simple-cset-for-each proc (char-set-simple cs))
  (inversion-list-fold/done? (lambda (n _)
			       (proc (scalar-value->char n))
			       (unspecific))
			     #f
			     (lambda (_) #f)
			     (char-set-i-list cs)))

; this is pretty inefficent
(define (char-set-map proc cs)
  (let ((simple-cset (make-empty-simple-cset))
	(other-scalar-values '()))
    
    (define (adjoin! c)
      (let ((c (proc c)))
	(if (simple-char? c)
	    (simple-cset-adjoin! simple-cset c)
	    (set! other-scalar-values
		  (cons (char->scalar-value c) other-scalar-values)))))

    (char-set-for-each adjoin! cs)

    (make-char-set simple-cset
		   (apply numbers->inversion-list
			  *simple-cset-boundary* (+ 1 #x10ffff)
			  other-scalar-values))))

(define (char-set-fold kons knil cs)
  (inversion-list-fold/done? (lambda (n v)
			       (kons (scalar-value->char n) v))
			     (simple-cset-fold kons knil (char-set-simple cs))
			     (lambda (_) #f)
			     (char-set-i-list cs)))

(define (char-set-every pred cs)
  (and (simple-cset-every? pred (char-set-simple cs))
       (inversion-list-fold/done? (lambda (n v)
				    (and v
					 (pred (scalar-value->char n))))
				  #t
				  not
				  (char-set-i-list cs))))

(define (char-set-any pred cs)
  (or (simple-cset-any pred (char-set-simple cs))
      (inversion-list-fold/done? (lambda (n v)
				   (or v
				       (pred (scalar-value->char n))))
				 #f
				 values
				 (char-set-i-list cs))))

(define (base-char-set maybe-base-cs)
  (if maybe-base-cs
      (char-set-copy maybe-base-cs)
      (make-empty-char-set)))

(define char-set-unfold
  (opt-lambda (p f g seed (maybe-base-cs #f))
    (char-set-unfold! p f g seed
		      (base-char-set maybe-base-cs))))

(define (char-set-unfold! p f g seed base-cs)
  (let loop ((seed seed) (cs base-cs))
    (if (p seed) cs			; P says we are done.
	(loop (g seed)			; Loop on (G SEED).
	      (char-set-adjoin! cs (f seed)))))) ; Add (F SEED) to set.

; converting from and to lists

(define (char-set . chars)
  (list->char-set chars))

(define list->char-set
  (opt-lambda (chars (maybe-base-cs #f))
    (list->char-set! chars
		     (base-char-set maybe-base-cs))))

(define (list->char-set! chars cs)
  (for-each (lambda (c)
	      (char-set-adjoin! cs c))
	    chars)
  cs)

(define (char-set->list cs)
  (char-set-fold cons '() cs))

; converting to and from strings

(define string->char-set
  (opt-lambda (str (maybe-base-cs #f))
    (string->char-set! str
		       (base-char-set maybe-base-cs))))

(define (string->char-set! str cs)
  (do ((i (- (string-length str) 1) (- i 1)))
      ((< i 0))
    (char-set-adjoin! cs (string-ref str i)))
  cs)

(define (char-set->string cs)
  (let ((ans (make-string (char-set-size cs))))
    (char-set-fold (lambda (ch i)
		     (string-set! ans i ch)
		     (+ i 1))
		   0
		   cs)
    ans))

(define ucs-range->char-set
  (opt-lambda (lower upper (error? #f) (maybe-base-cs #f))
    (ucs-range->char-set! lower upper error?
			  (base-char-set maybe-base-cs))))

(define (ucs-range->char-set! lower upper error? base-cs)
  (if (negative? lower)
      (assertion-violation 'ucs-range->char-set! "negative lower bound" lower))
  (if (> lower #x10ffff)
      (assertion-violation 'ucs-range->char-set! "invalid lower bound" lower))
  (if (negative? upper)
      (assertion-violation 'ucs-range->char-set! "negative upper bound" upper))
  (if (> upper #x110000)
      (assertion-violation 'ucs-range->char-set! "invalid lower bound" upper))
  (if (not (<= lower upper))
      (assertion-violation 'ucs-range->char-set! "decreasing bounds" lower upper))

  (let ((create-inversion-list
	 (lambda (lower upper)
	   (cond
	    ((and (>= lower #xD800)
		  (>= #xe000 upper))
	     (make-empty-inversion-list *simple-cset-boundary* (+ 1 #x10ffff)))
	    ((<= upper #xe000)
	     (range->inversion-list *simple-cset-boundary* (+ 1 #x10ffff)
				    lower (min #xd800 upper)))
	    ((>= lower #xd800)
	     (range->inversion-list *simple-cset-boundary* (+ 1 #x10ffff)
				    (max #xe000 lower) upper))
	    (else
	     ;; hole
	     (ranges->inversion-list *simple-cset-boundary* (+ 1 #x10ffff)
				     (cons lower #xd800)
				     (cons #xe000 upper)))))))
    (char-set-union!
     base-cs
     (cond
      ((>= lower *simple-cset-boundary*)
       (make-char-set (make-empty-simple-cset)
		      (create-inversion-list lower upper)))
      ((< upper *simple-cset-boundary*)
       (make-char-set (ucs-range->simple-cset lower upper)
		      (make-empty-inversion-list *simple-cset-boundary* (+ 1 #x10ffff))))
      (else
       (make-char-set (ucs-range->simple-cset lower *simple-cset-boundary*)
		      (create-inversion-list *simple-cset-boundary* upper)))))))

(define char-set-filter
  (opt-lambda (predicate domain (maybe-base-cs #f))
    (char-set-filter! predicate
		      domain
		      (base-char-set maybe-base-cs))))

(define (char-set-filter! predicate domain base-cs)
  (char-set-fold (lambda (ch _)
		   (if (predicate ch)
		       (char-set-adjoin! base-cs ch)))
		 (unspecific)
		 domain)
  base-cs)

; {string, char, char-set, char predicate} -> char-set

; This is called ->CHAR-SET in the SRFI, but that's not a valid R5RS
; identifier.

(define (x->char-set x)
  (cond ((char-set? x) x)
	((string? x) (string->char-set x))
	((char? x) (char-set x))
	(else (assertion-violation 'x->char-set "Not a charset, string or char."))))


; Set algebra

(define *surrogate-complement-i-list*
  (inversion-list-complement
   (range->inversion-list *simple-cset-boundary* (+ 1 #x10ffff)
			  #xd800 #xe000)))

(define (char-set-complement cs)
  (make-char-set (simple-cset-complement (char-set-simple cs))
		 (inversion-list-intersection
		  (inversion-list-complement (char-set-i-list cs))
		  *surrogate-complement-i-list*)))

(define (char-set-complement! cs)
  (set-char-set-simple! cs
			(simple-cset-complement! (char-set-simple cs)))
  (set-char-set-i-list! cs
			(inversion-list-intersection
			 (inversion-list-complement (char-set-i-list cs))
			 *surrogate-complement-i-list*))
  cs)

(define (make-char-set-op! simple-cset-op! inversion-list-op)
  (lambda (cset1 . csets)
    (set-char-set-simple! cset1
			  (apply simple-cset-op!
				 (char-set-simple cset1)
				 (map char-set-simple csets)))
    (set-char-set-i-list! cset1
			  (apply inversion-list-op
				 (char-set-i-list cset1)
				 (map char-set-i-list csets)))
    cset1))

(define (make-char-set-op char-set-op! make-neutral)
  (lambda csets
    (if (pair? csets)
	(apply char-set-op! (char-set-copy (car csets)) (cdr csets))
	(make-neutral))))

(define char-set-union!
  (make-char-set-op! simple-cset-union! inversion-list-union))
(define char-set-union
  (make-char-set-op char-set-union! make-empty-char-set))

(define char-set-intersection!
  (make-char-set-op! simple-cset-intersection! inversion-list-intersection))
(define char-set-intersection
  (make-char-set-op char-set-intersection! make-full-char-set))

(define char-set-difference!
  (make-char-set-op! simple-cset-difference! inversion-list-difference))

(define (char-set-difference cset1 . csets)
  (apply char-set-difference! (char-set-copy cset1) csets))

; copied from inversion-list.scm
(define (binary->n-ary proc/2)
  (lambda (arg-1 . args)
    (if (and (pair? args)
	     (null? (cdr args)))
	(proc/2 arg-1 (car args))
	(let loop ((args args)
		   (result arg-1))
	  (if (null? args)
	      result
	      (loop (cdr args) (proc/2 result (car args))))))))

(define inversion-list-xor
  (binary->n-ary
   (lambda (i-list-1 i-list-2)
     (inversion-list-union (inversion-list-intersection
			    (inversion-list-complement i-list-1)
			    i-list-2)
			   (inversion-list-intersection
			    i-list-1
			    (inversion-list-complement i-list-2))))))

; Really inefficient for things outside Latin-1
; WHO NEEDS THIS NONSENSE, ANYWAY?
(define char-set-xor!
  (make-char-set-op! simple-cset-xor! inversion-list-xor))

(define char-set-xor
  (make-char-set-op char-set-xor! make-empty-char-set))

(define (char-set-diff+intersection! cs1 cs2 . csets)
  (call-with-values
      (lambda () (apply simple-cset-diff+intersection!
			(char-set-simple cs1) (char-set-simple cs2)
			(map char-set-simple csets)))
    (lambda (simple-diff simple-intersection)
      (set-char-set-simple! cs1 simple-diff)
      (set-char-set-simple! cs2 simple-intersection)
      (let ((i-list-1 (char-set-i-list cs1))
	    (i-list-2 (char-set-i-list cs2))
	    (i-list-rest (map char-set-i-list csets)))
	(set-char-set-i-list! cs1
			      (apply inversion-list-difference
				     i-list-1 i-list-2
				     i-list-rest))
	(set-char-set-i-list! cs2
			      (inversion-list-intersection
			       i-list-1
			       (apply inversion-list-union
				      i-list-2
				      i-list-rest)))
	(values cs1 cs2)))))

(define (char-set-diff+intersection cs1 . csets)
  (apply char-set-diff+intersection!
	 (char-set-copy cs1)
	 (make-empty-char-set)
	 csets))

;; Byte vector utilities

(define (byte-vector-copy b)
  (let* ((size (byte-vector-length b))
	 (result (make-byte-vector size 0)))
    (copy-bytes! b 0 result 0 size)
    result))

;;; Apply P to each index and its char code in S: (P I VAL).
;;; Used by the set-algebra ops.

(define (byte-vector-iter p s)
  (let loop ((i (- (byte-vector-length s) 1)))
    (if (>= i 0)
	(begin
	  (p i (byte-vector-ref s i))
	  (loop (- i 1))))))

;; Utility for srfi-14-base-char-sets.scm, which follows

; The range vector is an even-sized vector with [lower, upper)
; pairs.

(define (range-vector->char-set range-vector)
  (let ((size (vector-length range-vector))
	(simple-cset (make-empty-simple-cset)))

    (let loop ((index 0) (ranges '()))
      (if (>= index size)
	  (make-char-set simple-cset
			 (apply ranges->inversion-list
				*simple-cset-boundary* (+ 1 #x10ffff)
				ranges))
	  (let ((lower (vector-ref range-vector index))
		(upper (vector-ref range-vector (+ 1 index))))
	    
	    (define (fill-simple-cset! lower upper)
	      (let loop ((scalar-value lower))
		(if (< scalar-value upper)
		    (begin
		      (simple-cset-adjoin-code! simple-cset scalar-value)
		      (loop (+ 1 scalar-value))))))

	    
	    (cond
	     ((>= lower *simple-cset-boundary*)
	      (loop (+ 2 index) (cons (cons lower upper) ranges)))
	     ((< upper *simple-cset-boundary*)
	      (fill-simple-cset! lower upper)
	      (loop (+ 2 index) ranges))
	     (else
	      (fill-simple-cset! lower *simple-cset-boundary*)
	      (loop (+ 2 index)
		    (cons (cons *simple-cset-boundary* upper) ranges)))))))))

;; ———————————————— 基础字符集（iron-054：按 .NET 的 Unicode 数据重新生成，取代 Scheme 48 的 Unicode 5.x 数据） ————————————————
;; 各集合即 Unicode 一般类别：lower-case Ll、upper-case Lu、title-case Lt、letter L*、digit Nd、mark M*、
;; separator Z*、punctuation P*、symbol S*、space-separator Zs（与 Scheme 48 生成原数据的规则相同）。
; Generated from the Unicode data of .NET 10.0.12 (System.Globalization.CharUnicodeInfo) by iron-054; do not edit.

(define char-set:lower-case (range-vector->char-set '#(97 123 181 182 223 247 248 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303 304 305 306 307 308 309 310 311 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 330 331 332 333 334 335 336 337 338 339 340 341 342 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 378 379 380 381 382 385 387 388 389 390 392 393 396 398 402 403 405 406 409 412 414 415 417 418 419 420 421 422 424 425 426 428 429 430 432 433 436 437 438 439 441 443 445 448 454 455 457 458 460 461 462 463 464 465 466 467 468 469 470 471 472 473 474 475 476 478 479 480 481 482 483 484 485 486 487 488 489 490 491 492 493 494 495 497 499 500 501 502 505 506 507 508 509 510 511 512 513 514 515 516 517 518 519 520 521 522 523 524 525 526 527 528 529 530 531 532 533 534 535 536 537 538 539 540 541 542 543 544 545 546 547 548 549 550 551 552 553 554 555 556 557 558 559 560 561 562 563 570 572 573 575 577 578 579 583 584 585 586 587 588 589 590 591 660 661 688 881 882 883 884 887 888 891 894 912 913 940 975 976 978 981 984 985 986 987 988 989 990 991 992 993 994 995 996 997 998 999 1000 1001 1002 1003 1004 1005 1006 1007 1012 1013 1014 1016 1017 1019 1021 1072 1120 1121 1122 1123 1124 1125 1126 1127 1128 1129 1130 1131 1132 1133 1134 1135 1136 1137 1138 1139 1140 1141 1142 1143 1144 1145 1146 1147 1148 1149 1150 1151 1152 1153 1154 1163 1164 1165 1166 1167 1168 1169 1170 1171 1172 1173 1174 1175 1176 1177 1178 1179 1180 1181 1182 1183 1184 1185 1186 1187 1188 1189 1190 1191 1192 1193 1194 1195 1196 1197 1198 1199 1200 1201 1202 1203 1204 1205 1206 1207 1208 1209 1210 1211 1212 1213 1214 1215 1216 1218 1219 1220 1221 1222 1223 1224 1225 1226 1227 1228 1229 1230 1232 1233 1234 1235 1236 1237 1238 1239 1240 1241 1242 1243 1244 1245 1246 1247 1248 1249 1250 1251 1252 1253 1254 1255 1256 1257 1258 1259 1260 1261 1262 1263 1264 1265 1266 1267 1268 1269 1270 1271 1272 1273 1274 1275 1276 1277 1278 1279 1280 1281 1282 1283 1284 1285 1286 1287 1288 1289 1290 1291 1292 1293 1294 1295 1296 1297 1298 1299 1300 1301 1302 1303 1304 1305 1306 1307 1308 1309 1310 1311 1312 1313 1314 1315 1316 1317 1318 1319 1320 1321 1322 1323 1324 1325 1326 1327 1328 1376 1417 4304 4347 4349 4352 5112 5118 7296 7305 7306 7307 7424 7468 7531 7544 7545 7579 7681 7682 7683 7684 7685 7686 7687 7688 7689 7690 7691 7692 7693 7694 7695 7696 7697 7698 7699 7700 7701 7702 7703 7704 7705 7706 7707 7708 7709 7710 7711 7712 7713 7714 7715 7716 7717 7718 7719 7720 7721 7722 7723 7724 7725 7726 7727 7728 7729 7730 7731 7732 7733 7734 7735 7736 7737 7738 7739 7740 7741 7742 7743 7744 7745 7746 7747 7748 7749 7750 7751 7752 7753 7754 7755 7756 7757 7758 7759 7760 7761 7762 7763 7764 7765 7766 7767 7768 7769 7770 7771 7772 7773 7774 7775 7776 7777 7778 7779 7780 7781 7782 7783 7784 7785 7786 7787 7788 7789 7790 7791 7792 7793 7794 7795 7796 7797 7798 7799 7800 7801 7802 7803 7804 7805 7806 7807 7808 7809 7810 7811 7812 7813 7814 7815 7816 7817 7818 7819 7820 7821 7822 7823 7824 7825 7826 7827 7828 7829 7838 7839 7840 7841 7842 7843 7844 7845 7846 7847 7848 7849 7850 7851 7852 7853 7854 7855 7856 7857 7858 7859 7860 7861 7862 7863 7864 7865 7866 7867 7868 7869 7870 7871 7872 7873 7874 7875 7876 7877 7878 7879 7880 7881 7882 7883 7884 7885 7886 7887 7888 7889 7890 7891 7892 7893 7894 7895 7896 7897 7898 7899 7900 7901 7902 7903 7904 7905 7906 7907 7908 7909 7910 7911 7912 7913 7914 7915 7916 7917 7918 7919 7920 7921 7922 7923 7924 7925 7926 7927 7928 7929 7930 7931 7932 7933 7934 7935 7944 7952 7958 7968 7976 7984 7992 8000 8006 8016 8024 8032 8040 8048 8062 8064 8072 8080 8088 8096 8104 8112 8117 8118 8120 8126 8127 8130 8133 8134 8136 8144 8148 8150 8152 8160 8168 8178 8181 8182 8184 8458 8459 8462 8464 8467 8468 8495 8496 8500 8501 8505 8506 8508 8510 8518 8522 8526 8527 8580 8581 11312 11360 11361 11362 11365 11367 11368 11369 11370 11371 11372 11373 11377 11378 11379 11381 11382 11388 11393 11394 11395 11396 11397 11398 11399 11400 11401 11402 11403 11404 11405 11406 11407 11408 11409 11410 11411 11412 11413 11414 11415 11416 11417 11418 11419 11420 11421 11422 11423 11424 11425 11426 11427 11428 11429 11430 11431 11432 11433 11434 11435 11436 11437 11438 11439 11440 11441 11442 11443 11444 11445 11446 11447 11448 11449 11450 11451 11452 11453 11454 11455 11456 11457 11458 11459 11460 11461 11462 11463 11464 11465 11466 11467 11468 11469 11470 11471 11472 11473 11474 11475 11476 11477 11478 11479 11480 11481 11482 11483 11484 11485 11486 11487 11488 11489 11490 11491 11493 11500 11501 11502 11503 11507 11508 11520 11558 11559 11560 11565 11566 42561 42562 42563 42564 42565 42566 42567 42568 42569 42570 42571 42572 42573 42574 42575 42576 42577 42578 42579 42580 42581 42582 42583 42584 42585 42586 42587 42588 42589 42590 42591 42592 42593 42594 42595 42596 42597 42598 42599 42600 42601 42602 42603 42604 42605 42606 42625 42626 42627 42628 42629 42630 42631 42632 42633 42634 42635 42636 42637 42638 42639 42640 42641 42642 42643 42644 42645 42646 42647 42648 42649 42650 42651 42652 42787 42788 42789 42790 42791 42792 42793 42794 42795 42796 42797 42798 42799 42802 42803 42804 42805 42806 42807 42808 42809 42810 42811 42812 42813 42814 42815 42816 42817 42818 42819 42820 42821 42822 42823 42824 42825 42826 42827 42828 42829 42830 42831 42832 42833 42834 42835 42836 42837 42838 42839 42840 42841 42842 42843 42844 42845 42846 42847 42848 42849 42850 42851 42852 42853 42854 42855 42856 42857 42858 42859 42860 42861 42862 42863 42864 42865 42873 42874 42875 42876 42877 42879 42880 42881 42882 42883 42884 42885 42886 42887 42888 42892 42893 42894 42895 42897 42898 42899 42902 42903 42904 42905 42906 42907 42908 42909 42910 42911 42912 42913 42914 42915 42916 42917 42918 42919 42920 42921 42922 42927 42928 42933 42934 42935 42936 42937 42938 42939 42940 42941 42942 42943 42944 42945 42946 42947 42948 42952 42953 42954 42955 42957 42958 42961 42962 42963 42964 42965 42966 42967 42968 42969 42970 42971 42972 42998 42999 43002 43003 43824 43867 43872 43881 43888 43968 64256 64263 64275 64280 65345 65371 66600 66640 66776 66812 66967 66978 66979 66994 66995 67002 67003 67005 68800 68851 68976 68998 71872 71904 93792 93824 119834 119860 119886 119893 119894 119912 119938 119964 119990 119994 119995 119996 119997 120004 120005 120016 120042 120068 120094 120120 120146 120172 120198 120224 120250 120276 120302 120328 120354 120380 120406 120432 120458 120486 120514 120539 120540 120546 120572 120597 120598 120604 120630 120655 120656 120662 120688 120713 120714 120720 120746 120771 120772 120778 120779 120780 122624 122634 122635 122655 122661 122667 125218 125252)))
(define char-set:upper-case (range-vector->char-set '#(65 91 192 215 216 223 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303 304 305 306 307 308 309 310 311 313 314 315 316 317 318 319 320 321 322 323 324 325 326 327 328 330 331 332 333 334 335 336 337 338 339 340 341 342 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 378 379 380 381 382 385 387 388 389 390 392 393 396 398 402 403 405 406 409 412 414 415 417 418 419 420 421 422 424 425 426 428 429 430 432 433 436 437 438 439 441 444 445 452 453 455 456 458 459 461 462 463 464 465 466 467 468 469 470 471 472 473 474 475 476 478 479 480 481 482 483 484 485 486 487 488 489 490 491 492 493 494 495 497 498 500 501 502 505 506 507 508 509 510 511 512 513 514 515 516 517 518 519 520 521 522 523 524 525 526 527 528 529 530 531 532 533 534 535 536 537 538 539 540 541 542 543 544 545 546 547 548 549 550 551 552 553 554 555 556 557 558 559 560 561 562 563 570 572 573 575 577 578 579 583 584 585 586 587 588 589 590 591 880 881 882 883 886 887 895 896 902 903 904 907 908 909 910 912 913 930 931 940 975 976 978 981 984 985 986 987 988 989 990 991 992 993 994 995 996 997 998 999 1000 1001 1002 1003 1004 1005 1006 1007 1012 1013 1015 1016 1017 1019 1021 1072 1120 1121 1122 1123 1124 1125 1126 1127 1128 1129 1130 1131 1132 1133 1134 1135 1136 1137 1138 1139 1140 1141 1142 1143 1144 1145 1146 1147 1148 1149 1150 1151 1152 1153 1162 1163 1164 1165 1166 1167 1168 1169 1170 1171 1172 1173 1174 1175 1176 1177 1178 1179 1180 1181 1182 1183 1184 1185 1186 1187 1188 1189 1190 1191 1192 1193 1194 1195 1196 1197 1198 1199 1200 1201 1202 1203 1204 1205 1206 1207 1208 1209 1210 1211 1212 1213 1214 1215 1216 1218 1219 1220 1221 1222 1223 1224 1225 1226 1227 1228 1229 1230 1232 1233 1234 1235 1236 1237 1238 1239 1240 1241 1242 1243 1244 1245 1246 1247 1248 1249 1250 1251 1252 1253 1254 1255 1256 1257 1258 1259 1260 1261 1262 1263 1264 1265 1266 1267 1268 1269 1270 1271 1272 1273 1274 1275 1276 1277 1278 1279 1280 1281 1282 1283 1284 1285 1286 1287 1288 1289 1290 1291 1292 1293 1294 1295 1296 1297 1298 1299 1300 1301 1302 1303 1304 1305 1306 1307 1308 1309 1310 1311 1312 1313 1314 1315 1316 1317 1318 1319 1320 1321 1322 1323 1324 1325 1326 1327 1329 1367 4256 4294 4295 4296 4301 4302 5024 5110 7305 7306 7312 7355 7357 7360 7680 7681 7682 7683 7684 7685 7686 7687 7688 7689 7690 7691 7692 7693 7694 7695 7696 7697 7698 7699 7700 7701 7702 7703 7704 7705 7706 7707 7708 7709 7710 7711 7712 7713 7714 7715 7716 7717 7718 7719 7720 7721 7722 7723 7724 7725 7726 7727 7728 7729 7730 7731 7732 7733 7734 7735 7736 7737 7738 7739 7740 7741 7742 7743 7744 7745 7746 7747 7748 7749 7750 7751 7752 7753 7754 7755 7756 7757 7758 7759 7760 7761 7762 7763 7764 7765 7766 7767 7768 7769 7770 7771 7772 7773 7774 7775 7776 7777 7778 7779 7780 7781 7782 7783 7784 7785 7786 7787 7788 7789 7790 7791 7792 7793 7794 7795 7796 7797 7798 7799 7800 7801 7802 7803 7804 7805 7806 7807 7808 7809 7810 7811 7812 7813 7814 7815 7816 7817 7818 7819 7820 7821 7822 7823 7824 7825 7826 7827 7828 7829 7838 7839 7840 7841 7842 7843 7844 7845 7846 7847 7848 7849 7850 7851 7852 7853 7854 7855 7856 7857 7858 7859 7860 7861 7862 7863 7864 7865 7866 7867 7868 7869 7870 7871 7872 7873 7874 7875 7876 7877 7878 7879 7880 7881 7882 7883 7884 7885 7886 7887 7888 7889 7890 7891 7892 7893 7894 7895 7896 7897 7898 7899 7900 7901 7902 7903 7904 7905 7906 7907 7908 7909 7910 7911 7912 7913 7914 7915 7916 7917 7918 7919 7920 7921 7922 7923 7924 7925 7926 7927 7928 7929 7930 7931 7932 7933 7934 7935 7944 7952 7960 7966 7976 7984 7992 8000 8008 8014 8025 8026 8027 8028 8029 8030 8031 8032 8040 8048 8120 8124 8136 8140 8152 8156 8168 8173 8184 8188 8450 8451 8455 8456 8459 8462 8464 8467 8469 8470 8473 8478 8484 8485 8486 8487 8488 8489 8490 8494 8496 8500 8510 8512 8517 8518 8579 8580 11264 11312 11360 11361 11362 11365 11367 11368 11369 11370 11371 11372 11373 11377 11378 11379 11381 11382 11390 11393 11394 11395 11396 11397 11398 11399 11400 11401 11402 11403 11404 11405 11406 11407 11408 11409 11410 11411 11412 11413 11414 11415 11416 11417 11418 11419 11420 11421 11422 11423 11424 11425 11426 11427 11428 11429 11430 11431 11432 11433 11434 11435 11436 11437 11438 11439 11440 11441 11442 11443 11444 11445 11446 11447 11448 11449 11450 11451 11452 11453 11454 11455 11456 11457 11458 11459 11460 11461 11462 11463 11464 11465 11466 11467 11468 11469 11470 11471 11472 11473 11474 11475 11476 11477 11478 11479 11480 11481 11482 11483 11484 11485 11486 11487 11488 11489 11490 11491 11499 11500 11501 11502 11506 11507 42560 42561 42562 42563 42564 42565 42566 42567 42568 42569 42570 42571 42572 42573 42574 42575 42576 42577 42578 42579 42580 42581 42582 42583 42584 42585 42586 42587 42588 42589 42590 42591 42592 42593 42594 42595 42596 42597 42598 42599 42600 42601 42602 42603 42604 42605 42624 42625 42626 42627 42628 42629 42630 42631 42632 42633 42634 42635 42636 42637 42638 42639 42640 42641 42642 42643 42644 42645 42646 42647 42648 42649 42650 42651 42786 42787 42788 42789 42790 42791 42792 42793 42794 42795 42796 42797 42798 42799 42802 42803 42804 42805 42806 42807 42808 42809 42810 42811 42812 42813 42814 42815 42816 42817 42818 42819 42820 42821 42822 42823 42824 42825 42826 42827 42828 42829 42830 42831 42832 42833 42834 42835 42836 42837 42838 42839 42840 42841 42842 42843 42844 42845 42846 42847 42848 42849 42850 42851 42852 42853 42854 42855 42856 42857 42858 42859 42860 42861 42862 42863 42873 42874 42875 42876 42877 42879 42880 42881 42882 42883 42884 42885 42886 42887 42891 42892 42893 42894 42896 42897 42898 42899 42902 42903 42904 42905 42906 42907 42908 42909 42910 42911 42912 42913 42914 42915 42916 42917 42918 42919 42920 42921 42922 42927 42928 42933 42934 42935 42936 42937 42938 42939 42940 42941 42942 42943 42944 42945 42946 42947 42948 42952 42953 42954 42955 42957 42960 42961 42966 42967 42968 42969 42970 42971 42972 42973 42997 42998 65313 65339 66560 66600 66736 66772 66928 66939 66940 66955 66956 66963 66964 66966 68736 68787 68944 68966 71840 71872 93760 93792 119808 119834 119860 119886 119912 119938 119964 119965 119966 119968 119970 119971 119973 119975 119977 119981 119982 119990 120016 120042 120068 120070 120071 120075 120077 120085 120086 120093 120120 120122 120123 120127 120128 120133 120134 120135 120138 120145 120172 120198 120224 120250 120276 120302 120328 120354 120380 120406 120432 120458 120488 120513 120546 120571 120604 120629 120662 120687 120720 120745 120778 120779 125184 125218)))
(define char-set:title-case (range-vector->char-set '#(453 454 456 457 459 460 498 499 8072 8080 8088 8096 8104 8112 8124 8125 8140 8141 8188 8189)))
(define char-set:letter (range-vector->char-set '#(65 91 97 123 170 171 181 182 186 187 192 215 216 247 248 706 710 722 736 741 748 749 750 751 880 885 886 888 890 894 895 896 902 903 904 907 908 909 910 930 931 1014 1015 1154 1162 1328 1329 1367 1369 1370 1376 1417 1488 1515 1519 1523 1568 1611 1646 1648 1649 1748 1749 1750 1765 1767 1774 1776 1786 1789 1791 1792 1808 1809 1810 1840 1869 1958 1969 1970 1994 2027 2036 2038 2042 2043 2048 2070 2074 2075 2084 2085 2088 2089 2112 2137 2144 2155 2160 2184 2185 2191 2208 2250 2308 2362 2365 2366 2384 2385 2392 2402 2417 2433 2437 2445 2447 2449 2451 2473 2474 2481 2482 2483 2486 2490 2493 2494 2510 2511 2524 2526 2527 2530 2544 2546 2556 2557 2565 2571 2575 2577 2579 2601 2602 2609 2610 2612 2613 2615 2616 2618 2649 2653 2654 2655 2674 2677 2693 2702 2703 2706 2707 2729 2730 2737 2738 2740 2741 2746 2749 2750 2768 2769 2784 2786 2809 2810 2821 2829 2831 2833 2835 2857 2858 2865 2866 2868 2869 2874 2877 2878 2908 2910 2911 2914 2929 2930 2947 2948 2949 2955 2958 2961 2962 2966 2969 2971 2972 2973 2974 2976 2979 2981 2984 2987 2990 3002 3024 3025 3077 3085 3086 3089 3090 3113 3114 3130 3133 3134 3160 3163 3165 3166 3168 3170 3200 3201 3205 3213 3214 3217 3218 3241 3242 3252 3253 3258 3261 3262 3293 3295 3296 3298 3313 3315 3332 3341 3342 3345 3346 3387 3389 3390 3406 3407 3412 3415 3423 3426 3450 3456 3461 3479 3482 3506 3507 3516 3517 3518 3520 3527 3585 3633 3634 3636 3648 3655 3713 3715 3716 3717 3718 3723 3724 3748 3749 3750 3751 3761 3762 3764 3773 3774 3776 3781 3782 3783 3804 3808 3840 3841 3904 3912 3913 3949 3976 3981 4096 4139 4159 4160 4176 4182 4186 4190 4193 4194 4197 4199 4206 4209 4213 4226 4238 4239 4256 4294 4295 4296 4301 4302 4304 4347 4348 4681 4682 4686 4688 4695 4696 4697 4698 4702 4704 4745 4746 4750 4752 4785 4786 4790 4792 4799 4800 4801 4802 4806 4808 4823 4824 4881 4882 4886 4888 4955 4992 5008 5024 5110 5112 5118 5121 5741 5743 5760 5761 5787 5792 5867 5873 5881 5888 5906 5919 5938 5952 5970 5984 5997 5998 6001 6016 6068 6103 6104 6108 6109 6176 6265 6272 6277 6279 6313 6314 6315 6320 6390 6400 6431 6480 6510 6512 6517 6528 6572 6576 6602 6656 6679 6688 6741 6823 6824 6917 6964 6981 6989 7043 7073 7086 7088 7098 7142 7168 7204 7245 7248 7258 7294 7296 7307 7312 7355 7357 7360 7401 7405 7406 7412 7413 7415 7418 7419 7424 7616 7680 7958 7960 7966 7968 8006 8008 8014 8016 8024 8025 8026 8027 8028 8029 8030 8031 8062 8064 8117 8118 8125 8126 8127 8130 8133 8134 8141 8144 8148 8150 8156 8160 8173 8178 8181 8182 8189 8305 8306 8319 8320 8336 8349 8450 8451 8455 8456 8458 8468 8469 8470 8473 8478 8484 8485 8486 8487 8488 8489 8490 8494 8495 8506 8508 8512 8517 8522 8526 8527 8579 8581 11264 11493 11499 11503 11506 11508 11520 11558 11559 11560 11565 11566 11568 11624 11631 11632 11648 11671 11680 11687 11688 11695 11696 11703 11704 11711 11712 11719 11720 11727 11728 11735 11736 11743 11823 11824 12293 12295 12337 12342 12347 12349 12353 12439 12445 12448 12449 12539 12540 12544 12549 12592 12593 12687 12704 12736 12784 12800 13312 19904 19968 42125 42192 42238 42240 42509 42512 42528 42538 42540 42560 42607 42623 42654 42656 42726 42775 42784 42786 42889 42891 42958 42960 42962 42963 42964 42965 42973 42994 43010 43011 43014 43015 43019 43020 43043 43072 43124 43138 43188 43250 43256 43259 43260 43261 43263 43274 43302 43312 43335 43360 43389 43396 43443 43471 43472 43488 43493 43494 43504 43514 43519 43520 43561 43584 43587 43588 43596 43616 43639 43642 43643 43646 43696 43697 43698 43701 43703 43705 43710 43712 43713 43714 43715 43739 43742 43744 43755 43762 43765 43777 43783 43785 43791 43793 43799 43808 43815 43816 43823 43824 43867 43868 43882 43888 44003 44032 55204 55216 55239 55243 55292 63744 64110 64112 64218 64256 64263 64275 64280 64285 64286 64287 64297 64298 64311 64312 64317 64318 64319 64320 64322 64323 64325 64326 64434 64467 64830 64848 64912 64914 64968 65008 65020 65136 65141 65142 65277 65313 65339 65345 65371 65382 65471 65474 65480 65482 65488 65490 65496 65498 65501 65536 65548 65549 65575 65576 65595 65596 65598 65599 65614 65616 65630 65664 65787 66176 66205 66208 66257 66304 66336 66349 66369 66370 66378 66384 66422 66432 66462 66464 66500 66504 66512 66560 66718 66736 66772 66776 66812 66816 66856 66864 66916 66928 66939 66940 66955 66956 66963 66964 66966 66967 66978 66979 66994 66995 67002 67003 67005 67008 67060 67072 67383 67392 67414 67424 67432 67456 67462 67463 67505 67506 67515 67584 67590 67592 67593 67594 67638 67639 67641 67644 67645 67647 67670 67680 67703 67712 67743 67808 67827 67828 67830 67840 67862 67872 67898 67968 68024 68030 68032 68096 68097 68112 68116 68117 68120 68121 68150 68192 68221 68224 68253 68288 68296 68297 68325 68352 68406 68416 68438 68448 68467 68480 68498 68608 68681 68736 68787 68800 68851 68864 68900 68938 68966 68975 68998 69248 69290 69296 69298 69314 69317 69376 69405 69415 69416 69424 69446 69488 69506 69552 69573 69600 69623 69635 69688 69745 69747 69749 69750 69763 69808 69840 69865 69891 69927 69956 69957 69959 69960 69968 70003 70006 70007 70019 70067 70081 70085 70106 70107 70108 70109 70144 70162 70163 70188 70207 70209 70272 70279 70280 70281 70282 70286 70287 70302 70303 70313 70320 70367 70405 70413 70415 70417 70419 70441 70442 70449 70450 70452 70453 70458 70461 70462 70480 70481 70493 70498 70528 70538 70539 70540 70542 70543 70544 70582 70583 70584 70609 70610 70611 70612 70656 70709 70727 70731 70751 70754 70784 70832 70852 70854 70855 70856 71040 71087 71128 71132 71168 71216 71236 71237 71296 71339 71352 71353 71424 71451 71488 71495 71680 71724 71840 71904 71935 71943 71945 71946 71948 71956 71957 71959 71960 71984 71999 72000 72001 72002 72096 72104 72106 72145 72161 72162 72163 72164 72192 72193 72203 72243 72250 72251 72272 72273 72284 72330 72349 72350 72368 72441 72640 72673 72704 72713 72714 72751 72768 72769 72818 72848 72960 72967 72968 72970 72971 73009 73030 73031 73056 73062 73063 73065 73066 73098 73112 73113 73440 73459 73474 73475 73476 73489 73490 73524 73648 73649 73728 74650 74880 75076 77712 77809 77824 78896 78913 78919 78944 82939 82944 83527 90368 90398 92160 92729 92736 92767 92784 92863 92880 92910 92928 92976 92992 92996 93027 93048 93053 93072 93504 93549 93760 93824 93952 94027 94032 94033 94099 94112 94176 94178 94179 94180 94208 100344 100352 101590 101631 101641 110576 110580 110581 110588 110589 110591 110592 110883 110898 110899 110928 110931 110933 110934 110948 110952 110960 111356 113664 113771 113776 113789 113792 113801 113808 113818 119808 119893 119894 119965 119966 119968 119970 119971 119973 119975 119977 119981 119982 119994 119995 119996 119997 120004 120005 120070 120071 120075 120077 120085 120086 120093 120094 120122 120123 120127 120128 120133 120134 120135 120138 120145 120146 120486 120488 120513 120514 120539 120540 120571 120572 120597 120598 120629 120630 120655 120656 120687 120688 120713 120714 120745 120746 120771 120772 120780 122624 122655 122661 122667 122928 122990 123136 123181 123191 123198 123214 123215 123536 123566 123584 123628 124112 124140 124368 124398 124400 124401 124896 124903 124904 124908 124909 124911 124912 124927 124928 125125 125184 125252 125259 125260 126464 126468 126469 126496 126497 126499 126500 126501 126503 126504 126505 126515 126516 126520 126521 126522 126523 126524 126530 126531 126535 126536 126537 126538 126539 126540 126541 126544 126545 126547 126548 126549 126551 126552 126553 126554 126555 126556 126557 126558 126559 126560 126561 126563 126564 126565 126567 126571 126572 126579 126580 126584 126585 126589 126590 126591 126592 126602 126603 126620 126625 126628 126629 126634 126635 126652 131072 173792 173824 177978 177984 178206 178208 183970 183984 191457 191472 192094 194560 195102 196608 201547 201552 205744)))
(define char-set:digit (range-vector->char-set '#(48 58 1632 1642 1776 1786 1984 1994 2406 2416 2534 2544 2662 2672 2790 2800 2918 2928 3046 3056 3174 3184 3302 3312 3430 3440 3558 3568 3664 3674 3792 3802 3872 3882 4160 4170 4240 4250 6112 6122 6160 6170 6470 6480 6608 6618 6784 6794 6800 6810 6992 7002 7088 7098 7232 7242 7248 7258 42528 42538 43216 43226 43264 43274 43472 43482 43504 43514 43600 43610 44016 44026 65296 65306 66720 66730 68912 68922 68928 68938 69734 69744 69872 69882 69942 69952 70096 70106 70384 70394 70736 70746 70864 70874 71248 71258 71360 71370 71376 71396 71472 71482 71904 71914 72016 72026 72688 72698 72784 72794 73040 73050 73120 73130 73552 73562 90416 90426 92768 92778 92864 92874 93008 93018 93552 93562 118000 118010 120782 120832 123200 123210 123632 123642 124144 124154 124401 124411 125264 125274 130032 130042)))
(define char-set:mark (range-vector->char-set '#(768 880 1155 1162 1425 1470 1471 1472 1473 1475 1476 1478 1479 1480 1552 1563 1611 1632 1648 1649 1750 1757 1759 1765 1767 1769 1770 1774 1809 1810 1840 1867 1958 1969 2027 2036 2045 2046 2070 2074 2075 2084 2085 2088 2089 2094 2137 2140 2199 2208 2250 2274 2275 2308 2362 2365 2366 2384 2385 2392 2402 2404 2433 2436 2492 2493 2494 2501 2503 2505 2507 2510 2519 2520 2530 2532 2558 2559 2561 2564 2620 2621 2622 2627 2631 2633 2635 2638 2641 2642 2672 2674 2677 2678 2689 2692 2748 2749 2750 2758 2759 2762 2763 2766 2786 2788 2810 2816 2817 2820 2876 2877 2878 2885 2887 2889 2891 2894 2901 2904 2914 2916 2946 2947 3006 3011 3014 3017 3018 3022 3031 3032 3072 3077 3132 3133 3134 3141 3142 3145 3146 3150 3157 3159 3170 3172 3201 3204 3260 3261 3262 3269 3270 3273 3274 3278 3285 3287 3298 3300 3315 3316 3328 3332 3387 3389 3390 3397 3398 3401 3402 3406 3415 3416 3426 3428 3457 3460 3530 3531 3535 3541 3542 3543 3544 3552 3570 3572 3633 3634 3636 3643 3655 3663 3761 3762 3764 3773 3784 3791 3864 3866 3893 3894 3895 3896 3897 3898 3902 3904 3953 3973 3974 3976 3981 3992 3993 4029 4038 4039 4139 4159 4182 4186 4190 4193 4194 4197 4199 4206 4209 4213 4226 4238 4239 4240 4250 4254 4957 4960 5906 5910 5938 5941 5970 5972 6002 6004 6068 6100 6109 6110 6155 6158 6159 6160 6277 6279 6313 6314 6432 6444 6448 6460 6679 6684 6741 6751 6752 6781 6783 6784 6832 6863 6912 6917 6964 6981 7019 7028 7040 7043 7073 7086 7142 7156 7204 7224 7376 7379 7380 7401 7405 7406 7412 7413 7415 7418 7616 7680 8400 8433 11503 11506 11647 11648 11744 11776 12330 12336 12441 12443 42607 42611 42612 42622 42654 42656 42736 42738 43010 43011 43014 43015 43019 43020 43043 43048 43052 43053 43136 43138 43188 43206 43232 43250 43263 43264 43302 43310 43335 43348 43392 43396 43443 43457 43493 43494 43561 43575 43587 43588 43596 43598 43643 43646 43696 43697 43698 43701 43703 43705 43710 43712 43713 43714 43755 43760 43765 43767 44003 44011 44012 44014 64286 64287 65024 65040 65056 65072 66045 66046 66272 66273 66422 66427 68097 68100 68101 68103 68108 68112 68152 68155 68159 68160 68325 68327 68900 68904 68969 68974 69291 69293 69372 69376 69446 69457 69506 69510 69632 69635 69688 69703 69744 69745 69747 69749 69759 69763 69808 69819 69826 69827 69888 69891 69927 69941 69957 69959 70003 70004 70016 70019 70067 70081 70089 70093 70094 70096 70188 70200 70206 70207 70209 70210 70367 70379 70400 70404 70459 70461 70462 70469 70471 70473 70475 70478 70487 70488 70498 70500 70502 70509 70512 70517 70584 70593 70594 70595 70597 70598 70599 70603 70604 70609 70610 70611 70625 70627 70709 70727 70750 70751 70832 70852 71087 71094 71096 71105 71132 71134 71216 71233 71339 71352 71453 71468 71724 71739 71984 71990 71991 71993 71995 71999 72000 72001 72002 72004 72145 72152 72154 72161 72164 72165 72193 72203 72243 72250 72251 72255 72263 72264 72273 72284 72330 72346 72751 72759 72760 72768 72850 72872 72873 72887 73009 73015 73018 73019 73020 73022 73023 73030 73031 73032 73098 73103 73104 73106 73107 73112 73459 73463 73472 73474 73475 73476 73524 73531 73534 73539 73562 73563 78912 78913 78919 78934 90398 90416 92912 92917 92976 92983 94031 94032 94033 94088 94095 94099 94180 94181 94192 94194 113821 113823 118528 118574 118576 118599 119141 119146 119149 119155 119163 119171 119173 119180 119210 119214 119362 119365 121344 121399 121403 121453 121461 121462 121476 121477 121499 121504 121505 121520 122880 122887 122888 122905 122907 122914 122915 122917 122918 122923 123023 123024 123184 123191 123566 123567 123628 123632 124140 124144 124398 124400 125136 125143 125252 125259 917760 918000)))
(define char-set:separator (range-vector->char-set '#(32 33 160 161 5760 5761 8192 8203 8232 8234 8239 8240 8287 8288 12288 12289)))
(define char-set:punctuation (range-vector->char-set '#(33 36 37 43 44 48 58 60 63 65 91 94 95 96 123 124 125 126 161 162 167 168 171 172 182 184 187 188 191 192 894 895 903 904 1370 1376 1417 1419 1470 1471 1472 1473 1475 1476 1478 1479 1523 1525 1545 1547 1548 1550 1563 1564 1565 1568 1642 1646 1748 1749 1792 1806 2039 2042 2096 2111 2142 2143 2404 2406 2416 2417 2557 2558 2678 2679 2800 2801 3191 3192 3204 3205 3572 3573 3663 3664 3674 3676 3844 3859 3860 3861 3898 3902 3973 3974 4048 4053 4057 4059 4170 4176 4347 4348 4960 4969 5120 5121 5742 5743 5787 5789 5867 5870 5941 5943 6100 6103 6104 6107 6144 6155 6468 6470 6686 6688 6816 6823 6824 6830 6990 6992 7002 7009 7037 7040 7164 7168 7227 7232 7294 7296 7360 7368 7379 7380 8208 8232 8240 8260 8261 8274 8275 8287 8317 8319 8333 8335 8968 8972 9001 9003 10088 10102 10181 10183 10214 10224 10627 10649 10712 10716 10748 10750 11513 11517 11518 11520 11632 11633 11776 11823 11824 11856 11858 11870 12289 12292 12296 12306 12308 12320 12336 12337 12349 12350 12448 12449 12539 12540 42238 42240 42509 42512 42611 42612 42622 42623 42738 42744 43124 43128 43214 43216 43256 43259 43260 43261 43310 43312 43359 43360 43457 43470 43486 43488 43612 43616 43742 43744 43760 43762 44011 44012 64830 64832 65040 65050 65072 65107 65108 65122 65123 65124 65128 65129 65130 65132 65281 65284 65285 65291 65292 65296 65306 65308 65311 65313 65339 65342 65343 65344 65371 65372 65373 65374 65375 65382 65792 65795 66463 66464 66512 66513 66927 66928 67671 67672 67871 67872 67903 67904 68176 68185 68223 68224 68336 68343 68409 68416 68505 68509 68974 68975 69293 69294 69461 69466 69510 69514 69703 69710 69819 69821 69822 69826 69952 69956 70004 70006 70085 70089 70093 70094 70107 70108 70109 70112 70200 70206 70313 70314 70612 70614 70615 70617 70731 70736 70746 70748 70749 70750 70854 70855 71105 71128 71233 71236 71264 71277 71353 71354 71484 71487 71739 71740 72004 72007 72162 72163 72255 72263 72346 72349 72350 72355 72448 72458 72673 72674 72769 72774 72816 72818 73463 73465 73539 73552 73727 73728 74864 74869 77809 77811 92782 92784 92917 92918 92983 92988 92996 92997 93549 93552 93847 93851 94178 94179 113823 113824 121479 121484 124415 124416 125278 125280)))
(define char-set:symbol (range-vector->char-set '#(36 37 43 44 60 63 94 95 96 97 124 125 126 127 162 167 168 170 172 173 174 178 180 181 184 185 215 216 247 248 706 710 722 736 741 748 749 750 751 768 885 886 900 902 1014 1015 1154 1155 1421 1424 1542 1545 1547 1548 1550 1552 1758 1759 1769 1770 1789 1791 2038 2039 2046 2048 2184 2185 2546 2548 2554 2556 2801 2802 2928 2929 3059 3067 3199 3200 3407 3408 3449 3450 3647 3648 3841 3844 3859 3860 3861 3864 3866 3872 3892 3893 3894 3895 3896 3897 4030 4038 4039 4045 4046 4048 4053 4057 4254 4256 5008 5018 5741 5742 6107 6108 6464 6465 6622 6656 7009 7019 7028 7037 8125 8126 8127 8130 8141 8144 8157 8160 8173 8176 8189 8191 8260 8261 8274 8275 8314 8317 8330 8333 8352 8385 8448 8450 8451 8455 8456 8458 8468 8469 8470 8473 8478 8484 8485 8486 8487 8488 8489 8490 8494 8495 8506 8508 8512 8517 8522 8526 8527 8528 8586 8588 8592 8968 8972 9001 9003 9258 9280 9291 9372 9450 9472 10088 10132 10181 10183 10214 10224 10627 10649 10712 10716 10748 10750 11124 11126 11158 11159 11264 11493 11499 11856 11858 11904 11930 11931 12020 12032 12246 12272 12288 12292 12293 12306 12308 12320 12321 12342 12344 12350 12352 12443 12445 12688 12690 12694 12704 12736 12774 12783 12784 12800 12831 12842 12872 12880 12881 12896 12928 12938 12977 12992 13312 19904 19968 42128 42183 42752 42775 42784 42786 42889 42891 43048 43052 43062 43066 43639 43642 43867 43868 43882 43884 64297 64298 64434 64451 64832 64848 64975 64976 65020 65024 65122 65123 65124 65127 65129 65130 65284 65285 65291 65292 65308 65311 65342 65343 65344 65345 65372 65373 65374 65375 65504 65511 65512 65519 65532 65534 65847 65856 65913 65930 65932 65935 65936 65949 65952 65953 66000 66045 67703 67705 68296 68297 69006 69008 71487 71488 73685 73714 92988 92992 92997 92998 113820 113821 117760 118000 118016 118452 118608 118724 118784 119030 119040 119079 119081 119141 119146 119149 119171 119173 119180 119210 119214 119275 119296 119362 119365 119366 119552 119639 120513 120514 120539 120540 120571 120572 120597 120598 120629 120630 120655 120656 120687 120688 120713 120714 120745 120746 120771 120772 120832 121344 121399 121403 121453 121461 121462 121476 121477 121479 123215 123216 123647 123648 126124 126125 126128 126129 126254 126255 126704 126706 126976 127020 127024 127124 127136 127151 127153 127168 127169 127184 127185 127222 127245 127406 127462 127491 127504 127548 127552 127561 127568 127570 127584 127590 127744 128728 128732 128749 128752 128765 128768 128887 128891 128986 128992 129004 129008 129009 129024 129036 129040 129096 129104 129114 129120 129160 129168 129198 129200 129212 129216 129218 129280 129620 129632 129646 129648 129661 129664 129674 129679 129735 129742 129757 129759 129770 129776 129785 129792 129939 129940 130032)))
(define char-set:space-separator (range-vector->char-set '#(32 33 160 161 5760 5761 8192 8203 8239 8240 8287 8288 12288 12289)))

;; ———————————————— 改写自 srfi/%3a14/srfi-14-char-sets.scm ————————————————

; Part of Scheme 48 1.9.  See file COPYING for notices and license.

; Authors: Mike Sperber

; This constructs the SRFI 14 char sets from thin air and what's defined in
; srfi-14-base-char-sets.scm.

; Defined there:
; lower-case, upper-case, title-case, letter, digit, punctuation, symbol

(define char-set:empty (char-set))
(define char-set:full (char-set-complement char-set:empty))

(define char-set:letter+digit
  (char-set-union char-set:letter char-set:digit))

(define char-set:graphic
  (char-set-union char-set:mark
		  char-set:letter
		  char-set:digit
		  char-set:symbol
		  char-set:punctuation))

(define char-set:whitespace
  (char-set-union char-set:separator
		  (list->char-set (map scalar-value->char
				       '(9 ; tab
					 10 ; newline
					 11 ; vtab
					 12 ; page
					 13 ; return
					 )))))


(define char-set:printing
  (char-set-union char-set:whitespace char-set:graphic))

(define char-set:iso-control
  (char-set-union (ucs-range->char-set 0 #x20)
		  (ucs-range->char-set #x7f #xa0)))

(define char-set:blank
  (char-set-union char-set:space-separator
		  (char-set (scalar-value->char 9)))) ; tab

(define char-set:ascii (ucs-range->char-set 0 128))
(define char-set:hex-digit (string->char-set "0123456789abcdefABCDEF"))
  
(make-char-set-immutable! char-set:empty)
(make-char-set-immutable! char-set:full)
(make-char-set-immutable! char-set:lower-case)
(make-char-set-immutable! char-set:upper-case)
(make-char-set-immutable! char-set:letter)
(make-char-set-immutable! char-set:digit)
(make-char-set-immutable! char-set:hex-digit)
(make-char-set-immutable! char-set:letter+digit)
(make-char-set-immutable! char-set:punctuation)
(make-char-set-immutable! char-set:symbol)
(make-char-set-immutable! char-set:graphic)
(make-char-set-immutable! char-set:whitespace)
(make-char-set-immutable! char-set:printing)
(make-char-set-immutable! char-set:blank)
(make-char-set-immutable! char-set:iso-control)
(make-char-set-immutable! char-set:ascii)
)
