;;; (ironscheme std format) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 54 的测试，
;;; 按 SRFI 54 的文本（含其中的例子）编写。
(import (rnrs) (only (ironscheme) include) (ironscheme std format))
(include "tests/std/check.ss")

;; 无格式参数：转为字符串，末尾的字符串参数接在后面
(check (cat 12) => "12")
(check (cat "abc") => "abc")
(check (cat #\a) => "a")
(check (cat #t) => "#t")
(check (cat 'sym) => "sym")
(check (cat '(1 "a")) => "(1 \"a\")")
(check (cat 1 " and " "2") => "1 and 2")
;; 宽度：正数右对齐，负数左对齐
(check (cat "abc" 5) => "  abc")
(check (cat "abc" -5) => "abc  ")
(check (cat 12 5 #\0) => "00012")
(check (cat 12 -5 #\0) => "12000")
;; 精度（不精确整数表示小数位数），SRFI 54 的例子
(check (cat 129.995 -10 2.) => "130.00    ")
(check (cat 129.995 10 2.) => "    130.00")
;; SRFI 54 文本的例子 (cat 129.985 10 2.) => "    129.99" 依赖十进制：129.985 的双精度值是 129.98499999…，
;; 正确舍入为 129.98。这里换成不受表示误差影响的值。
(check (cat 129.986 10 2.) => "    129.99")
(check (cat 129 -2.) => "129.00")
(check (cat 129.995 2. 'exact) => "#e130.00")
;; 符号、基数
(check (cat 129 'sign) => "+129")
(check (cat -129 'sign) => "-129")
(check (cat 255 'hexadecimal) => "#xff")
(check (cat 5 'binary) => "#b101")
(check (cat 8 'octal) => "#o10")
;; 分隔符
(check (cat 1234567 '(#\,)) => "1,234,567")
(check (cat 1234567 '(#\space 2)) => "1 23 45 67")
;; 截取：(take 前 后)
(check (cat "abcdefg" '(3)) => "abc")
(check (cat "abcdefg" '(-3)) => "defg")
;; 写出过程、管道、转换器
(check (cat "abc" write) => "\"abc\"")
(check (cat "abc" (list string-upcase)) => "ABC")
(check (cat 'x (cons symbol? (lambda (s) "<sym>"))) => "<sym>")
;; 端口：#t 为当前输出端口；给端口时同时写出
(check (call-with-string-output-port (lambda (p) (cat 42 p))) => "42")
;; 错误
(check-raises assertion-violation? (cat 1.5 'hexadecimal 2.))

(check-report "std format")
