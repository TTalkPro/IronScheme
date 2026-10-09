#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std procedures) —— 过程的构造与组合（designs/08-std-library.md）
;;;
;;; 词源：cut / cute / <> / <...>  SRFI 26（Sebastian Egner）
;;;       is / isnt                SRFI 156（Panicz Maciej Godek）
;;;       rest-values 与 arg-and … SRFI 51（Joo ChurlSoo）
;;;       arity-at-least? arity-at-least-value procedure-arity-includes?  SRFI 102（David Van Horn）
;;; 实现改写自 chez-srfi 中的参照实现（见 LICENSES/chez-srfi.txt）。
;;;
;;; 取舍（D4）：
;;;   ① SRFI 51 的参照实现用 SRFI 23 的 error（第一个参数是消息）；这里以同样的参数调用本库的 error，
;;;      它抛 &assertion（who 为 #f），消息是第一个参数。
;;;   ② SRFI 102 的 procedure-arity 不在这里（D2）：用 IronScheme 的 procedure-arity，
;;;      其结果与 SRFI 102 同构（固定 n、至少 n 为 n.0、多种为列表），本库的三个过程按它工作。
(library (ironscheme std procedures)
  (export
    cut cute <> <...> is isnt rest-values arg-and arg-ands err-and err-ands arg-or arg-ors
    err-or err-ors arity-at-least? arity-at-least-value procedure-arity-includes?)
  (import
    (except (rnrs) error)
    (only (ironscheme) procedure-arity))

;; SRFI 23 风格的 error（SRFI 51 的参照实现使用）
(define (error reason . irritants)
  (apply assertion-violation #f
         (if (string? reason) reason (call-with-string-output-port (lambda (p) (display reason p))))
         irritants))

(define (every pred lst) (for-all pred lst))

(define (append-reverse rev tail)
  (fold-left (lambda (acc x) (cons x acc)) tail rev))

;; ———————————————— 改写自 srfi/%3a26/cut-impl.scm ————————————————

; REFERENCE IMPLEMENTATION FOR SRFI-26 "CUT"
; ==========================================
;
; Sebastian.Egner@philips.com, 5-Jun-2002.
; adapted from the posting by Al Petrofsky <al@petrofsky.org>
; placed in the public domain
;
; The code to handle the variable argument case was originally
; proposed by Michael Sperber and has been adapted to the new
; syntax of the macro using an explicit rest-slot symbol. The
; code to evaluate the non-slots for cute has been proposed by
; Dale Jordan. The code to allow a slot for the procedure position
; and to process the macro using an internal macro is based on 
; a suggestion by Al Petrofsky. The code found below is, with
; exception of this header and some changes in variable names,
; entirely written by Al Petrofsky.
;
; compliance:
;   Scheme R5RS (including macros).
;
; loading this file into Scheme 48 0.57:
;   ,load cut.scm
;
; history of this file:
;   SE,  6-Feb-2002: initial version as 'curry' with ". <>" notation
;   SE, 14-Feb-2002: revised for <...>
;   SE, 27-Feb-2002: revised for 'cut'
;   SE, 03-Jun-2002: revised for proc-slot, cute
;   SE, 04-Jun-2002: rewritten with internal transformer (no "loop" pattern)
;   SE, 05-Jun-2002: replace my code by Al's; substituted "constant" etc.
;     to match the convention in the SRFI-document

; (srfi-26-internal-cut slot-names combination . se)
;   transformer used internally
;     slot-names  : the internal names of the slots
;     combination : procedure being specialized, followed by its arguments
;     se          : slots-or-exprs, the qualifiers of the macro

(define-syntax srfi-26-internal-cut
  (syntax-rules (<> <...>)

    ;; construct fixed- or variable-arity procedure:
    ;;   (begin proc) throws an error if proc is not an <expression>
    ((srfi-26-internal-cut (slot-name ...) (proc arg ...))
     (lambda (slot-name ...) ((begin proc) arg ...)))
    ((srfi-26-internal-cut (slot-name ...) (proc arg ...) <...>)
     (lambda (slot-name ... . rest-slot) (apply proc arg ... rest-slot)))

    ;; process one slot-or-expr
    ((srfi-26-internal-cut (slot-name ...)   (position ...)      <>  . se)
     (srfi-26-internal-cut (slot-name ... x) (position ... x)        . se))
    ((srfi-26-internal-cut (slot-name ...)   (position ...)      nse . se)
     (srfi-26-internal-cut (slot-name ...)   (position ... nse)      . se))))

; (srfi-26-internal-cute slot-names nse-bindings combination . se)
;   transformer used internally
;     slot-names     : the internal names of the slots
;     nse-bindings   : let-style bindings for the non-slot expressions.
;     combination    : procedure being specialized, followed by its arguments
;     se             : slots-or-exprs, the qualifiers of the macro

(define-syntax srfi-26-internal-cute
  (syntax-rules (<> <...>)

    ;; If there are no slot-or-exprs to process, then:
    ;; construct a fixed-arity procedure,
    ((srfi-26-internal-cute
      (slot-name ...) nse-bindings (proc arg ...))
     (let nse-bindings (lambda (slot-name ...) (proc arg ...))))
    ;; or a variable-arity procedure
    ((srfi-26-internal-cute
      (slot-name ...) nse-bindings (proc arg ...) <...>)
     (let nse-bindings (lambda (slot-name ... . x) (apply proc arg ... x))))

    ;; otherwise, process one slot:
    ((srfi-26-internal-cute
      (slot-name ...)         nse-bindings  (position ...)   <>  . se)
     (srfi-26-internal-cute
      (slot-name ... x)       nse-bindings  (position ... x)     . se))
    ;; or one non-slot expression
    ((srfi-26-internal-cute
      slot-names              nse-bindings  (position ...)   nse . se)
     (srfi-26-internal-cute
      slot-names ((x nse) . nse-bindings) (position ... x)       . se))))

; exported syntax

(define-syntax <>
  (identifier-syntax
    (error #f "misplaced aux keyword <>")))
(define-syntax <...>
  (identifier-syntax
    (error #f "misplaced aux keyword <...>")))

(define-syntax cut
  (syntax-rules ()
    ((cut . slots-or-exprs)
     (srfi-26-internal-cut () () . slots-or-exprs))))

(define-syntax cute
  (syntax-rules ()
    ((cute . slots-or-exprs)
     (srfi-26-internal-cute () () () . slots-or-exprs))))

;; ———————————————— 改写自 srfi/%3a156/srfi-156-impl.scm ————————————————

;; Reference Implementation from SRFI 156
;;
;; Copyright (C) Panicz Maciej Godek (2017). All Rights Reserved.
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to
;; deal in the Software without restriction, including without limitation the
;; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
;; sell copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
;; IN THE SOFTWARE.
;;
;; 12/31/2017 - AWK - shimmed extract-placehoders to allow for _ in R6RS scheme

(define-syntax infix/postfix
  (syntax-rules ()
    ((infix/postfix x somewhat?)
     (somewhat? x))

    ((infix/postfix left related-to? right)
     (related-to? left right))

    ((infix/postfix left related-to? right . likewise)
     (let ((right* right))
       (and (infix/postfix left related-to? right*)
            (infix/postfix right* . likewise))))))

(define-syntax extract-placeholders
  (lambda (x)
    (syntax-case x ()
      [(_ final () () body) #'(final (infix/postfix . body))]
      [(_ final () args body) #'(lambda args (final (infix/postfix . body)))]
      [(k final (underscore op . rest) (args ...) (body ...))
       (eq? (syntax->datum #'underscore) '_)
       #'(k final rest (args ... arg) (body ... arg op))]
      [(k final (arg op . rest) args (body ...))
       #'(k final rest args (body ... arg op))]
      [(k final (underscore) (args ...) (body ...))
       (eq? (syntax->datum #'underscore) '_)
       #'(k final () (args ... arg) (body ... arg))]
      [(k final (arg) args (body ...))
       #'(k final () args (body ... arg))])))

#;(define-syntax extract-placeholders
  (syntax-rules (_)
    ((extract-placeholders final () () body)
     (final (infix/postfix . body)))

    ((extract-placeholders final () args body)
     (lambda args (final (infix/postfix . body))))

    ((extract-placeholders final (_ op . rest) (args ...) (body ...))
     (extract-placeholders final rest (args ... arg) (body ... arg op)))

    ((extract-placeholders final (arg op . rest) args (body ...))
     (extract-placeholders final rest args (body ... arg op)))

    ((extract-placeholders final (_) (args ...) (body ...))
     (extract-placeholders final () (args ... arg) (body ... arg)))

    ((extract-placeholders final (arg) args (body ...))
     (extract-placeholders final () args (body ... arg)))))

(define-syntax identity-syntax
  (syntax-rules ()
    ((identity-syntax form)
     form)))

(define-syntax is
  (syntax-rules ()
    ((is . something)
     (extract-placeholders identity-syntax something () ()))))

(define-syntax isnt
  (syntax-rules ()
    ((isnt . something)
     (extract-placeholders not something () ()))))

;; ———————————————— 改写自 srfi/%3a51/srfi-51-impl.scm ————————————————

;;
;; Reference implementation of SRFI 51
;;
;; Copyright (C) Joo ChurlSoo (2004). All Rights Reserved.
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to
;; deal in the Software without restriction, including without limitation the
;; rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
;; sell copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
;; IN THE SOFTWARE.
;;

(define (rest-values rest . default)
  (let* ((caller (if (or (null? default)
			 (boolean? (car default))
			 (integer? (car default))
			 (memq (car default) (list + -)))
		     '()
		     (if (string? rest) rest (list rest))))
	 (rest-list (if (null? caller) rest (car default)))
	 (rest-length (if (list? rest-list)
			  (length rest-list)
			  (if (string? caller)
			      (error caller rest-list 'rest-list
				     '(list? rest-list))
			      (apply error "bad rest list" rest-list 'rest-list
				     '(list? rest-list) caller))))
	 (default (if (null? caller) default (cdr default)))
	 (default-list (if (null? default) default (cdr default)))
	 (default-length (length default-list))
	 (number
	  (and (not (null? default))
	       (let ((option (car default)))
		 (or (and (integer? option)
			  (or (and (> rest-length (abs option))
				   (if (string? caller)
				       (error caller rest-list 'rest-list
					      `(<= (length rest-list)
						   ,(abs option)))
				       (apply error "too many arguments"
					      rest-list 'rest-list
					      `(<= (length rest-list)
						   ,(abs option))
					      caller)))
			      (and (> default-length (abs option))
				   (if (string? caller)
				       (error caller default-list
					      'default-list
					      `(<= (length default-list)
						   ,(abs option)))
				       (apply error "too many defaults"
					      default-list 'default-list
					      `(<= (length default-list)
						   ,(abs option))
					      caller)))
			      option))
		     (eq? option #t)
		     (and (not option) 'false)
		     (and (eq? option +) +)
		     (and (eq? option -) -)
		     (if (string? caller)
			 (error caller option 'option
				'(or (boolean? option)
				     (integer? option)
				     (memq option (list + -))))
			 (apply error "bad optional argument" option 'option
				'(or (boolean? option)
				     (integer? option)
				     (memq option (list + -)))
				caller)))))))
    (cond
     ((or (eq? #t number) (eq? 'false number))
      (and (not (every pair? default-list))
	   (if (string? caller)
	       (error caller default-list 'default-list
		      '(every pair? default-list))
	       (apply error "bad default list" default-list 'default-list
		      '(every pair? default-list) caller)))
      (let loop ((rest-list rest-list)
		 (default-list default-list)
		 (result '()))
	(if (null? default-list)
	    (if (null? rest-list)
		(apply values (reverse result))
		(if (eq? #t number)
		    (if (string? caller)
			(error caller rest-list 'rest-list '(null? rest-list))
			(apply error "bad argument" rest-list 'rest-list
			       '(null? rest-list) caller))
		    (apply values (append-reverse result rest-list))))
	    (if (null? rest-list)
		(apply values (append-reverse result (map car default-list)))
		(let ((default (car default-list)))
		  (let lp ((rest rest-list)
			   (head '()))
		    (if (null? rest)
			(loop (reverse head)
			      (cdr default-list)
			      (cons (car default) result))
			(if (list? default)
			    (if (member (car rest) default)
				(loop (append-reverse head (cdr rest))
				      (cdr default-list)
				      (cons (car rest) result))
				(lp (cdr rest) (cons (car rest) head)))
			    (if ((cdr default) (car rest))
				(loop (append-reverse head (cdr rest))
				      (cdr default-list)
				      (cons (car rest) result))
				(lp (cdr rest) (cons (car rest) head)))))))))))
     ((or (and (integer? number) (> number 0))
	  (eq? number +))
      (and (not (every pair? default-list))
	   (if (string? caller)
	       (error caller default-list 'default-list
		      '(every pair? default-list))
	       (apply error "bad default list" default-list 'default-list
		      '(every pair? default-list) caller)))
      (let loop ((rest rest-list)
		 (default default-list))
	(if (or (null? rest) (null? default))
	    (apply values
		   (if (> default-length rest-length)
		       (append rest-list
			       (map car (list-tail default-list rest-length)))
		       rest-list))
	    (let ((arg (car rest))
		  (par (car default)))
	      (if (list? par)
		  (if (member arg par)
		      (loop (cdr rest) (cdr default))
		      (if (string? caller)
			  (error caller arg 'arg `(member arg ,par))
			  (apply error "unmatched argument"
				 arg 'arg `(member arg ,par) caller)))
		  (if ((cdr par) arg)
		      (loop (cdr rest) (cdr default))
		      (if (string? caller)
			  (error caller arg 'arg `(,(cdr par) arg))
			  (apply error "incorrect argument"
				 arg 'arg `(,(cdr par) arg) caller))))))))
     (else
      (apply values (if (> default-length rest-length)
			(append rest-list (list-tail default-list rest-length))
			rest-list))))))

(define-syntax arg-and
  (syntax-rules()
    ((arg-and arg (a1 a2 ...) ...)
     (and (or (symbol? 'arg)
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(arg-and arg (a1 a2 ...) ...)))
	  (or (a1 a2 ...)
	      (error "incorrect argument" arg 'arg '(a1 a2 ...)))
	  ...))
    ((arg-and caller arg (a1 a2 ...) ...)
     (and (or (symbol? 'arg)
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(arg-and caller arg (a1 a2 ...) ...)))
	  (or (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	  ...))))

;; accessory macro for arg-ands
(define-syntax caller-arg-and
  (syntax-rules()
    ((caller-arg-and caller arg (a1 a2 ...) ...)
     (and (or (symbol? 'arg)
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(caller-arg-and caller arg (a1 a2 ...) ...)))
	  (or (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	  ...))
    ((caller-arg-and null caller arg (a1 a2 ...) ...)
     (and (or (symbol? 'arg)
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(caller-arg-and caller arg (a1 a2 ...) ...)))
	  (or (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	  ...))))

(define-syntax arg-ands
  (syntax-rules (common)
    ((arg-ands (a1 a2 ...) ...)
     (and (arg-and a1 a2 ...) ...))
    ((arg-ands common caller (a1 a2 ...) ...)
     (and (caller-arg-and caller a1 a2 ...) ...))))

(define-syntax arg-or
  (syntax-rules()
    ((arg-or arg (a1 a2 ...) ...)
     (or (and (not (symbol? 'arg))
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(arg-or arg (a1 a2 ...) ...)))
	 (and (a1 a2 ...)
	      (error "incorrect argument" arg 'arg '(a1 a2 ...)))
	 ...))
    ((arg-or caller arg (a1 a2 ...) ...)
     (or (and (not (symbol? 'arg))
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(arg-or caller arg (a1 a2 ...) ...)))
	 (and (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	 ...))))

;; accessory macro for arg-ors
(define-syntax caller-arg-or
  (syntax-rules()
    ((caller-arg-or caller arg (a1 a2 ...) ...)
     (or (and (not (symbol? 'arg))
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(caller-arg-or caller arg (a1 a2 ...) ...)))
	 (and (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	 ...))
    ((caller-arg-or null caller arg (a1 a2 ...) ...)
     (or (and (not (symbol? 'arg))
	      (error "bad syntax" 'arg '(symbol? 'arg)
		     '(caller-arg-or caller arg (a1 a2 ...) ...)))
	 (and (a1 a2 ...)
	      (if (string? caller)
		  (error caller arg 'arg '(a1 a2 ...))
		  (error "incorrect argument" arg 'arg '(a1 a2 ...) caller)))
	 ...))))

(define-syntax arg-ors
  (syntax-rules (common)
    ((arg-ors (a1 a2 ...) ...)
     (or (arg-or a1 a2 ...) ...))
    ((arg-ors common caller (a1 a2 ...) ...)
     (or (caller-arg-or caller a1 a2 ...) ...))))

(define-syntax err-and
  (syntax-rules ()
    ((err-and err expression ...)
     (and (or expression
	      (if (string? err)
		  (error err 'expression)
		  (error "false expression" 'expression err)))
	  ...))))

(define-syntax err-ands
  (syntax-rules ()
    ((err-ands (err expression ...)  ...)
     (and (err-and err expression ...)
	  ...))))

(define-syntax err-or
  (syntax-rules ()
    ((err-or err expression ...)
     (or (and expression
	      (if (string? err)
		  (error err 'expression)
		  (error "true expression" 'expression err)))
	 ...))))

(define-syntax err-ors
  (syntax-rules ()
    ((err-ors (err expression ...) ...)
     (or (err-or err expression ...)
	 ...))))

;; ———————————————— SRFI 102 ————————————————

(define (arity-at-least? obj)
  (and (integer? obj) (inexact? obj) (not (negative? obj))))

(define (arity-at-least-value arity-at-least)
  (assert (arity-at-least? arity-at-least))
  (exact arity-at-least))

(define (procedure-arity-includes? proc k)
  (assert (procedure? proc))
  (assert (and (integer? k) (exact? k) (not (negative? k))))
  (let* ((a (procedure-arity proc))
         (a (if (list? a) a (if (number? a) (list a) '()))))
    (exists (lambda (x) (if (exact? x) (= k x) (<= x k))) a)))
)
