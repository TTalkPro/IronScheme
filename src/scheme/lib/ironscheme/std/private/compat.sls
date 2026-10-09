#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std private compat) —— 并入参照实现时用的兼容层（designs/08-std-library.md D4），不对外。
;;;
;;;   SRFI-23-error->R6RS  包住参照代码：其中按 SRFI 23 调用的 (error 消息 对象 …) 改为 assertion-violation，
;;;                        who 为外层 define 的名字（来自 chez-srfi 的 (srfi :23 error tricks)）
;;;   vanish-define        让参照代码中某些名字的 define 消失，改用导入的绑定（来自 chez-srfi 的 (srfi private vanish)）
;;;   check-arg            参照代码的参数检查，不检查（同 chez-srfi 的 (srfi private check-arg)）
;;;   let-optionals* :optional  可选参数（scsh 的 LET-OPTIONALS，经 chez-srfi 的 (srfi private let-opt)）
;;;   srfi-9:define-record-type  SRFI 9 形式的记录定义（来自 chez-srfi 的 (srfi :9 records)），给沿用 SRFI 9 的参照代码用
;;;
;;; 前三项与 srfi-9:define-record-type 原作者 Derick Eddington（MIT 许可，见 LICENSES/chez-srfi.txt）。
;;; let-optionals* 与 :optional 的版权与许可如下：
;;;
;;; LET-OPTIONALS macros
;;; Copyright (c) 2001 by Olin Shivers.
;;; 
;;; Copyright (c) 1993-2003 Richard Kelsey and Jonathan Rees
;;; Copyright (c) 1994-2003 by Olin Shivers and Brian D. Carlstrom.
;;; Copyright (c) 1999-2003 by Martin Gasbichler.
;;; Copyright (c) 2001-2003 by Michael Sperber.
;;;
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
;;; 3. The name of the authors may not be used to endorse or promote products
;;;    derived from this software without specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS OR
;;; IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
;;; OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
;;; IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT,
;;; INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
;;; NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
;;; THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
(library (ironscheme std private compat)
  (export
    SRFI-23-error->R6RS vanish-define check-arg let-optionals* :optional srfi-9:define-record-type)
  (import
    (except (rnrs) error)
    (for (only (rnrs base) begin) (meta -1)))

;; ———————————————— SRFI 23 的 error 改为 R6RS 条件 ————————————————
  (define-syntax error-wrap
    (lambda (stx)
      (syntax-case stx ()
        ((_ ctxt signal . forms)
         (with-syntax ((e (datum->syntax #'ctxt 'error)))
           #'(let-syntax ((e (identifier-syntax signal)))
               . forms))))))

  (define (AV who)
    (lambda args (apply assertion-violation who args)))

  (define-syntax SRFI-23-error->R6RS
    (lambda (stx)
      (syntax-case stx ()
        ((ctxt ewho . forms)
         (with-syntax ((e (datum->syntax #'ctxt 'error))
                       (d (datum->syntax #'ctxt 'define)))
           #'(let-syntax ((e (identifier-syntax (AV 'ewho)))
                          (d (lambda (stx)
                               (syntax-case stx ()
                                 ((kw (id . formals) . body)
                                  (identifier? #'id)
                                  #'(error-wrap kw (AV 'id)
                                     (d (id . formals) . body)))
                                 ((kw id . r)
                                  (identifier? #'id)
                                  #'(error-wrap kw (AV 'id)
                                     (d id . r)))))))
               . forms))))))

;; ———————————————— vanish-define ————————————————
  (define-syntax vanish-define
    (lambda (stx)
      (syntax-case stx ()
        ((_ def (vanish ...))
         (for-all identifier? #'(def vanish ...))
         #'(make-vanish-define (syntax def) (syntax vanish) ...)))))

  (define (make-vanish-define def . to-vanish)
    (lambda (stx)
      (define (vanish? id)
        (memp (lambda (x) (free-identifier=? id x))
              to-vanish))
      (syntax-case stx ()
        ((_ name . _)
         (and (identifier? #'name)
              (vanish? #'name))
         #'(begin))
        ((_ (name . _) . _)
         (and (identifier? #'name)
              (vanish? #'name))
         #'(begin))
        ((_ . r)
         (cons def #'r)))))

;; ———————————————— check-arg：不检查 ————————————————
  (define-syntax check-arg
    (syntax-rules ()
      ((_ pred val who) val)))

;; ———————————————— SRFI 9 形式的 define-record-type ————————————————
  (define-syntax srfi-9:define-record-type
    (lambda (stx)
      (syntax-case stx ()
        ((_ type (constructor constructor-tag ...)
            predicate
            (field-tag accessor setter ...) ...)
         (and (for-all identifier?
                       #'(type constructor constructor-tag ... predicate
                          field-tag ... accessor ... setter ... ...))
              (for-all (lambda (s) (<= 0 (length s) 1))
                       #'((setter ...) ...))
              (for-all (lambda (ct)
                         (memp (lambda (ft) (bound-identifier=? ct ft))
                               #'(field-tag ...)))
                       #'(constructor-tag ...)))
         (with-syntax (((field-clause ...)
                        (map (lambda (clause)
                               (if (= 2 (length clause))
                                 #`(immutable . #,clause)
                                 #`(mutable . #,clause)))
                             #'((field-tag accessor setter ...) ...)))
                       ((unspec-tag ...)
                        (remp (lambda (ft)
                                (memp (lambda (ct) (bound-identifier=? ft ct))
                                      #'(constructor-tag ...)))
                              #'(field-tag ...))))
           #'(define-record-type (type constructor predicate)
               (protocol (lambda (ctor)
                           (lambda (constructor-tag ...)
                             (define unspec-tag) ...
                             (ctor field-tag ...))))
               (fields field-clause ...)))))))

;; ———————————————— let-optionals* 与 :optional（error 即 assertion-violation） ————————————————
  (define-syntax error
    (syntax-rules ()
      ((_ who msg irritant ...) (assertion-violation who msg irritant ...))))

;;; (:optional rest-arg default-exp [test-pred])
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; This form is for evaluating optional arguments and their defaults
;;; in simple procedures that take a *single* optional argument. It is
;;; a macro so that the default will not be computed unless it is needed.
;;; 
;;; REST-ARG is a rest list from a lambda -- e.g., R in
;;;     (lambda (a b . r) ...)
;;; - If REST-ARG has 0 elements, evaluate DEFAULT-EXP and return that.
;;; - If REST-ARG has 1 element, return that element.
;;; - If REST-ARG has >1 element, error.
;;;
;;; If there is an TEST-PRED form, it is a predicate that is used to test
;;; a non-default value. If the predicate returns false, an error is raised.

(define-syntax :optional
  (syntax-rules ()
    ([_ rest default-exp]
     (let ((maybe-arg rest))
       (if (pair? maybe-arg)
	   (if (null? (cdr maybe-arg)) (car maybe-arg)
	       (error ':optional "too many optional arguments" maybe-arg))
	   default-exp)))
    ([_ rest default-exp arg-test]
     (let ((maybe-arg rest))
       (if (pair? maybe-arg)
	   (if (null? (cdr maybe-arg))
	       (let ((val (car maybe-arg)))
		 (if (arg-test val) val
		     (error ':optional "optional argument failed test" val)))
	       (error ':optional "too many optional arguments" maybe-arg))
	   default-exp)))))
 ; erutcurts-enifed

;;; Here is a simpler but less-efficient version of LET-OPTIONALS*.
;;; It redundantly performs end-of-list checks for every optional var,
;;; even after the list runs out.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-syntax let-optionals*
  (syntax-rules ()
    ((let-optionals* arg (opt-clause ...) body ...)
     (let ((rest arg))
       (%let-optionals* rest (opt-clause ...) body ...)))))

;;; The arg-list expression *must* be a variable.
;;; (Or must be side-effect-free, in any event.)

(define-syntax %let-optionals*
  (syntax-rules ()
    ((%let-optionals* arg (((var ...) xparser) opt-clause ...) body ...)
     (call-with-values (lambda () (xparser arg))
       (lambda (rest var ...)
         (%let-optionals* rest (opt-clause ...) body ...))))
    
    ((%let-optionals* arg ((var default) opt-clause ...) body ...)
     (call-with-values (lambda () (if (null? arg) (values default '())
				      (values (car arg) (cdr arg))))
       (lambda (var rest)
	 (%let-optionals* rest (opt-clause ...) body ...))))

    ((%let-optionals* arg ((var default test) opt-clause ...) body ...)
     (call-with-values (lambda ()
			 (if (null? arg) (values default '())
			     (let ((var (car arg)))
			       (if test (values var (cdr arg))
				   (error 'let-optionals* "arg failed LET-OPT test" var)))))
       (lambda (var rest)
	 (%let-optionals* rest (opt-clause ...) body ...))))

    ((%let-optionals* arg ((var default test supplied?) opt-clause ...) body ...)
     (call-with-values (lambda ()
			 (if (null? arg) (values default #f '())
			     (let ((var (car arg)))
			       (if test (values var #t (cdr arg))
				   (error 'let-optionals* "arg failed LET-OPT test" var)))))
       (lambda (var supplied? rest)
	 (%let-optionals* rest (opt-clause ...) body ...))))

    ((%let-optionals* arg (rest) body ...)
     (let ((rest arg)) body ...))

    ((%let-optionals* arg () body ...)
     (if (null? arg) (begin body ...)
	 (error 'let-optionals* "too many arguments in let-opt" arg)))))
; erutcurts-enifed
)
