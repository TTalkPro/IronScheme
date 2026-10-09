#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std syntax) —— 常用的语法扩展（designs/08-std-library.md）
;;;
;;; 词源（D1：出处写在这里，不进库名）：
;;;   cond-expand  SRFI 0     and-let*  SRFI 2（Oleg Kiselyov）     receive  SRFI 8（John David Stone）
;;;   fluid-let    SRFI 15    rec       SRFI 31（Mirko Luedde）      assume   SRFI 145
;;; 实现改写自 chez-srfi（Derick Eddington 等，MIT 许可，见 LICENSES/chez-srfi.txt）。
;;;
;;; 与 SRFI 文本不同的取舍（D4）：
;;;   ① cond-expand 的特性只有 r6rs、ironscheme、操作系统（windows / linux / osx，非 Windows 另有 posix）
;;;      与体系结构（x86-64 / arm64 …）。⛔ 不声明 srfi-N：本仓库没有 (srfi …) 库了（D5），
;;;      声明了会让可移植代码以为能 import (srfi :N)。
;;;   ② assume 总是检查（SRFI 145 允许不检查），失败时 assertion-violation；成功时返回表达式的值。
;;;
;;; 你要的在 IronScheme 里叫什么（D2：与基础库同名的不在这里）：
;;;   SRFI 11 let-values / SRFI 16 case-lambda / SRFI 39 parameterize → 基础库已有
;;;   SRFI 61 cond 的 guard 子句 => → R6RS cond 已有
(library (ironscheme std syntax)
  (export cond-expand and-let* receive fluid-let rec assume)
  (import (rnrs) (only (ironscheme unsafe) $os-name $cpu-architecture))

  ;; ———————————————— cond-expand ————————————————

  (define-syntax cond-expand
    (lambda (stx)
      ;; 宿主特性由原语给出（11 §1 D5）：os-name 是 "Windows" / "Linux" / "macOS" …，cpu-architecture 是 "x86-64" / "i386" / "arm64" …
      (define (os-features)
        (let ((os ($os-name)))
          (append (if (string=? os "Windows") '(windows) '(posix))
                  (if (string=? os "Linux") '(linux) '())
                  (if (string=? os "macOS") '(osx darwin) '()))))
      (define (arch-features)
        (let ((a (string->symbol ($cpu-architecture))))
          (case a
            ((arm64) '(arm64 aarch64))
            (else (list a)))))
      (define features (append '(r6rs ironscheme clr) (os-features) (arch-features)))
      (define (fulfilled? req)
        (syntax-case req (and or not)
          ((and r ...) (for-all fulfilled? #'(r ...)))
          ((or r ...) (exists fulfilled? #'(r ...)))
          ((not r) (not (fulfilled? #'r)))
          (id (identifier? #'id) (and (memq (syntax->datum #'id) features) #t))
          (_ (syntax-violation 'cond-expand "invalid feature requirement" stx req))))
      (syntax-case stx (else)
        ((_) (syntax-violation 'cond-expand "unfulfilled cond-expand" stx))
        ((_ (else body ...)) #'(begin body ...))
        ((_ (req body ...) more ...)
         (if (fulfilled? #'req)
             #'(begin body ...)
             #'(cond-expand more ...))))))

  ;; ———————————————— and-let* ————————————————

  (define-syntax and-let*
    (syntax-rules ()
      ((_ . r) (and-let*-core #t . r))))

  (define-syntax and-let*-core
    (lambda (stx)
      (syntax-case stx ()
        ((kw _ ((var expr) . c) . b)
         #'(let ((var expr))
             (and var (kw var c . b))))
        ((kw last ((expr) . c) . b)
         #'(kw last ((t expr) . c) . b))
        ((kw _ (id . c) . b)
         (identifier? #'id)
         #'(and id (kw id c . b)))
        ((_ last ())
         #'last)
        ((_ _ () . b)
         #'(let () . b)))))

  ;; ———————————————— receive ————————————————

  (define-syntax receive
    (syntax-rules ()
      ((_ formals expression b b* ...)
       (call-with-values (lambda () expression) (lambda formals b b* ...)))))

  ;; ———————————————— fluid-let ————————————————

  (define-syntax fluid-let
    (syntax-rules ()
      ((_ ((v1 e1) ...) b1 b2 ...)
       (fluid-let "temps" () ((v1 e1) ...) b1 b2 ...))
      ((_ "temps" (t ...) ((v1 e1) x ...) b1 b2 ...)
       (let ((temp e1))
         (fluid-let "temps" ((temp e1 v1) t ...) (x ...) b1 b2 ...)))
      ((_ "temps" ((t e v) ...) () b1 b2 ...)
       (let-syntax ((swap! (syntax-rules ()
                             ((swap! a b) (let ((tmp a)) (set! a b) (set! b tmp))))))
         (dynamic-wind
           (lambda () (swap! t v) ...)
           (lambda () b1 b2 ...)
           (lambda () (swap! t v) ...))))))

  ;; ———————————————— rec ————————————————

  (define-syntax rec
    (syntax-rules ()
      ((_ (name . variables) . body) (letrec ((name (lambda variables . body))) name))
      ((_ name expression) (letrec ((name expression)) name))))

  ;; ———————————————— assume ————————————————

  (define-syntax assume
    (syntax-rules ()
      ((_ expression message ...)
       (let ((v expression))
         (if v v (assertion-violation 'assume "invalid assumption" 'expression message ...)))))))
