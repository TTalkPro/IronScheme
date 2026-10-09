;;; (ironscheme std localization) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 29 的测试，
;;; 按 SRFI 29 的文本（含其中的例子）编写，每个导出名至少一项。
(import (rnrs) (only (ironscheme) include) (ironscheme std localization))
(include "tests/std/check.ss")

;;; ———————————————— 当前区域 ————————————————
(check (symbol? (current-language)) => #t)
(check (symbol? (current-country)) => #t)
(check (list? (current-locale-details)) => #t)
(current-language 'en)
(current-country 'us)
(current-locale-details '(utf-8))
(check (list (current-language) (current-country) (current-locale-details)) => '(en us (utf-8)))

;;; ———————————————— 模板包 ————————————————
;; SRFI 29 的例子：一个包，英语与法语两份模板
(let ((translations
       '(((en) . ((time . "It's ~a, ~a.")
                  (goodbye . "Goodbye, ~a.")))
         ((fr) . ((time . "~1@*~a, c'est ~a.")
                  (goodbye . "Au revoir, ~a."))))))
  (for-each (lambda (translation)
              (let ((bundle-name (cons 'hello-program (car translation))))
                (if (not (load-bundle! bundle-name))
                    (begin
                      (declare-bundle! bundle-name (cdr translation))
                      (store-bundle! bundle-name)))))
            translations))
(check (localized-template 'hello-program 'goodbye) => "Goodbye, ~a.")
(current-language 'fr)
(check (localized-template 'hello-program 'goodbye) => "Au revoir, ~a.")
(check (localized-template 'hello-program 'time) => "~1@*~a, c'est ~a.")
(check (localized-template 'hello-program 'missing) => #f)
(check (localized-template 'no-such-package 'goodbye) => #f)
;; 回退：(包 语言 国家) → (包 语言) → (包)
(current-language 'en)
(current-country 'gb)
(declare-bundle! '(hello-program en gb) '((goodbye . "Cheerio, ~a.")))
(check (localized-template 'hello-program 'goodbye) => "Cheerio, ~a.")
(check (localized-template 'hello-program 'time) => "It's ~a, ~a.")     ; en-gb 没有，回退到 en
(declare-bundle! '(hello-program) '((title . "Hello")))
(check (localized-template 'hello-program 'title) => "Hello")           ; 回退到只有包名的模板包
;; 重新声明取代旧的
(declare-bundle! '(hello-program en gb) '((goodbye . "Bye, ~a.")))
(check (localized-template 'hello-program 'goodbye) => "Bye, ~a.")
;; 不持久化
(check (load-bundle! '(hello-program en)) => #f)
(check (store-bundle! '(hello-program en)) => #f)
(check (store-bundle '(hello-program en)) => #f)

(check-report "std localization")
