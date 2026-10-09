#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std localization) —— 本地化（designs/08-std-library.md）
;;; 词源：SRFI 29（Scott G. Miller）。参照实现取自 SRFI 29 文档，Copyright (C) Scott G. Miller (2002)
;;; （声明见下方代码）；经 chez-srfi 收入（LICENSES/chez-srfi.txt）。
;;;
;;; 与 SRFI 文本 / 参照实现不同的取舍（D4）：
;;;   ① current-language、current-country 的缺省值取自 .NET 的 CultureInfo.CurrentCulture（如 en-US → en、us；
;;;      de-DE → de、de）；不变区域（未设置区域时）退回参照实现的 en、us。
;;;   ② current-locale-details 参照实现未提供（chez-srfi 中调用即报错）；这里缺省为空表，可设置。
;;;   ③ load-bundle!、store-bundle! 同参照实现：不持久化，返回 #f。store-bundle 是 store-bundle! 的别名。
;;;
;;; 你要的在 IronScheme 里叫什么（D2）：SRFI 29 自带的 format（支持位置参数 ~n@*）与基础库 format 同名，
;;;   不导出，只在本库内部使用；基础库的 format 自 iron-054 起也支持 ~n@*，本地化模板可直接用它：
;;;   (format (localized-template 'pkg 'msg) 参数 …)。
(library (ironscheme std localization)
  (export
    current-country current-language current-locale-details declare-bundle! load-bundle!
    localized-template store-bundle store-bundle!)
  (import
    (rnrs)
    (only (ironscheme) open-output-string get-output-string)
    (only (ironscheme clr) clr-static-prop-get clr-prop-get clr-new))

;; ———————————————— 当前区域（取自 .NET） ————————————————
(define (current-culture) (clr-static-prop-get System.Globalization.CultureInfo CurrentCulture))

;; 不变区域（未设置 LANG 等时）没有语言与国家，退回 SRFI 29 参照实现的缺省值 en / us
(define (invariant-culture?)
  (string=? "" (clr-prop-get System.Globalization.CultureInfo Name (current-culture))))

(define (culture-language)
  (if (invariant-culture?)
      'en
      (string->symbol
        (string-downcase (clr-prop-get System.Globalization.CultureInfo TwoLetterISOLanguageName (current-culture))))))

(define (culture-country)
  (if (invariant-culture?)
      'us
      (let ((name (clr-prop-get System.Globalization.CultureInfo Name (current-culture))))
        (string->symbol
          (string-downcase
            (clr-prop-get System.Globalization.RegionInfo TwoLetterISORegionName
              (clr-new System.Globalization.RegionInfo name)))))))

;; SRFI 29：其余区域细节（编码等），符号的表。IronScheme 的字符串与端口按 Unicode 处理，没有区域编码可报，
;; 缺省为空表；与 current-language 一样可以设置
(define current-locale-details
  (let ((details '()))
    (lambda args
      (if (null? args)
          details
          (set! details (car args))))))

(define-syntax store-bundle (identifier-syntax store-bundle!))

;; reference implementation taken from srfi :29 documenation

;; Copyright (C) Scott G. Miller (2002). All Rights Reserved.
;;
;; This document and translations of it may be copied and furnished to
;; others, and derivative works that comment on or otherwise explain it or
;; assist in its implementation may be prepared, copied, published and
;; distributed, in whole or in part, without restriction of any kind,
;; provided that the above copyright notice and this paragraph are included
;; on all such copies and derivative works. However, this document itself may
;; not be modified in any way, such as by removing the copyright notice or
;; references to the Scheme Request For Implementation process or editors,
;; except as needed for the purpose of developing SRFIs in which case the
;; procedures for copyrights defined in the SRFI process must be followed, or
;; as required to translate it into languages other than English.
;;
;; The limited permissions granted above are perpetual and will not be
;; revoked by the authors or their successors or assigns.
;; 
;; This document and the information contained herein is provided on an "AS
;; IS" basis and THE AUTHOR AND THE SRFI EDITORS DISCLAIM ALL WARRANTIES,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTY THAT THE USE
;; OF THE INFORMATION HEREIN WILL NOT INFRINGE ANY RIGHTS OR ANY IMPLIED
;; WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
;;

;; The association list in which bundles will be stored
(define *localization-bundles* '())

;; The current-language and current-country functions provided
;; here must be rewritten for each Scheme system to default to the
;; actual locale of the session
;; （IronScheme：缺省值取自 .NET 的 CultureInfo.CurrentCulture，见文件头）
(define current-language
  (let ((current-language-value (culture-language)))
    (lambda args
      (if (null? args)
          current-language-value
          (set! current-language-value (car args))))))

(define current-country
  (let ((current-country-value (culture-country)))
    (lambda args
      (if (null? args)
          current-country-value
          (set! current-country-value (car args))))))

;; The load-bundle! and store-bundle! both return #f in this
;; reference implementation.  A compliant implementation need
;; not rewrite these procedures.
(define load-bundle!
  (lambda (bundle-specifier)
    #f))

(define store-bundle!
  (lambda (bundle-specifier)
    #f))

;; Declare a bundle of templates with a given bundle specifier
(define declare-bundle!
  (letrec ((remove-old-bundle
             (lambda (specifier bundle)
               (cond ((null? bundle) '())
                     ((equal? (caar bundle) specifier)
                      (cdr bundle))
                     (else (cons (car bundle)
                                 (remove-old-bundle specifier
                                                    (cdr bundle))))))))
    (lambda (bundle-specifier bundle-assoc-list)
      (set! *localization-bundles*
            (cons (cons bundle-specifier bundle-assoc-list)
                  (remove-old-bundle bundle-specifier
                                     *localization-bundles*))))))

;;Retrieve a localized template given its package name and a template name
(define localized-template
  (letrec ((rdc
             (lambda (ls)
               (if (null? (cdr ls))
                   '()
                   (cons (car ls) (rdc (cdr ls))))))
           (find-bundle
             (lambda (specifier template-name)
               (cond ((assoc specifier *localization-bundles*) =>
                                                               (lambda (bundle) bundle))
                     ((null? specifier) #f)
                     (else (find-bundle (rdc specifier)
                                        template-name))))))
    (lambda (package-name template-name)
      (let loop ((specifier (cons package-name
                                  (list (current-language)
                                        (current-country)))))
        (and (not (null? specifier))
             (let ((bundle (find-bundle specifier template-name)))
               (and bundle
                    (cond ((assq template-name bundle) => cdr)
                          ((null? (cdr specifier)) #f)
                          (else (loop (rdc specifier)))))))))))

;;An SRFI-28 and SRFI-29 compliant version of format.  It requires
;;SRFI-23 for error reporting.
;; （IronScheme：只在本库内部，不导出，见文件头）
(define format
  (lambda (format-string . objects)
    (let ((buffer (open-output-string)))
      (let loop ((format-list (string->list format-string))
                 (objects objects)
                 (object-override #f))
        (cond ((null? format-list) (get-output-string buffer))
              ((char=? (car format-list) #\~)
               (cond ((null? (cdr format-list))
                      (error 'format "Incomplete escape sequence"))
                     ((char-numeric? (cadr format-list))
                      (let posloop ((fl (cddr format-list))
                                    (pos (string->number
                                           (string (cadr format-list)))))
                        (cond ((null? fl)
                               (error 'format "Incomplete escape sequence"))
                              ((and (eq? (car fl) '#\@)
                                    (null? (cdr fl)))
                               (error 'format "Incomplete escape sequence"))
                              ((and (eq? (car fl) '#\@)
                                    (eq? (cadr fl) '#\*))
                               (loop (cddr fl) objects (list-ref objects pos)))
                              (else
                                (posloop (cdr fl)
                                         (+ (* 10 pos)
                                            (string->number
                                              (string (car fl)))))))))
                     (else
                       (case (cadr format-list)
                         ((#\a)
                          (cond (object-override
                                  (begin
                                    (display object-override buffer)
                                    (loop (cddr format-list) objects #f)))
                                ((null? objects)
                                 (error 'format "No value for escape sequence"))
                                (else
                                  (begin
                                    (display (car objects) buffer)
                                    (loop (cddr format-list)
                                          (cdr objects) #f)))))
                         ((#\s)
                          (cond (object-override
                                  (begin
                                    (display object-override buffer)
                                    (loop (cddr format-list) objects #f)))
                                ((null? objects)
                                 (error 'format "No value for escape sequence"))
                                (else
                                  (begin
                                    (write (car objects) buffer)
                                    (loop (cddr format-list)
                                          (cdr objects) #f)))))
                         ((#\%)
                          (if object-override
                              (error 'format "Escape sequence following positional override does not require a value"))
                          (display #\newline buffer)
                          (loop (cddr format-list) objects #f))
                         ((#\~)
                          (if object-override
                              (error 'format "Escape sequence following positional override does not require a value"))
                          (display #\~ buffer)
                          (loop (cddr format-list) objects #f))
                         (else
                           (error 'format "Unrecognized escape sequence"))))))
              (else (display (car format-list) buffer)
                    (loop (cdr format-list) objects #f)))))))
)
