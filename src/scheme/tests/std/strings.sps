;;; (ironscheme std strings) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 13 / 152 的测试，
;;; 按 SRFI 13 与 SRFI 152 的文本（含其中的例子）编写，每个导出名至少一项。
(import (rnrs) (rnrs mutable-strings) (only (ironscheme) include)
        (ironscheme std strings) (ironscheme std char-sets))
(include "tests/std/check.ss")

;;; ———————————————— 谓词 ————————————————
(check (string-null? "") => #t)
(check (string-null? "a") => #f)
(check (string-every char-alphabetic? "abc") => #t)
(check (string-every char-alphabetic? "ab1") => #f)
(check (string-every char-alphabetic? "") => #t)
(check (string-every (lambda (c) (char->integer c)) "ab") => 98)        ; 返回最后一次的值
(check (string-any char-numeric? "ab1") => #t)
(check (string-any char-numeric? "abc") => #f)
(check (string-any #\b "abc") => #t)                                   ; 字符作为谓词
(check (string-every char-set:digit "123" 1) => #t)                    ; 字符集作为谓词，带 start

;;; ———————————————— 构造 ————————————————
(check (string-tabulate (lambda (i) (integer->char (+ i 97))) 3) => "abc")
(check (string-unfold null? car cdr '(#\a #\b #\c)) => "abc")
(check (string-unfold null? car cdr '(#\a #\b) "<" (lambda (x) ">")) => "<ab>")
(check (string-unfold-right null? car cdr '(#\a #\b #\c)) => "cba")
(check (reverse-list->string '(#\a #\b #\c)) => "cba")
(check (string-join '("a" "b" "c")) => "a b c")
(check (string-join '("a" "b" "c") ":") => "a:b:c")
(check (string-join '("a" "b") ":" 'suffix) => "a:b:")
(check (string-join '("a" "b") ":" 'prefix) => ":a:b")
(check (string-join '() ":" 'infix) => "")
(check-raises assertion-violation? (string-join '() ":" 'strict-infix))

;;; ———————————————— 选取 ————————————————
(check (string-take "Pete Szilagyi" 6) => "Pete S")
(check (string-drop "Pete Szilagyi" 6) => "zilagyi")
(check (string-take-right "Beta rules" 5) => "rules")
(check (string-drop-right "Beta rules" 5) => "Beta ")
(check (string-pad "325" 5) => "  325")
(check (string-pad "71325" 5) => "71325")
(check (string-pad "8871325" 5) => "71325")                            ; 从左截
(check (string-pad "7" 3 #\0) => "007")
(check (string-pad-right "325" 5) => "325  ")
(check (string-pad-right "8871325" 5) => "88713")
(check (string-trim "  The outlook wasn't brilliant,  \n\r") => "The outlook wasn't brilliant,  \n\r")
(check (string-trim-right "  The outlook wasn't brilliant,  \n\r") => "  The outlook wasn't brilliant,")
(check (string-trim-both "  The outlook wasn't brilliant,  \n\r") => "The outlook wasn't brilliant,")
(check (string-trim-both "xxaxx" #\x) => "a")
(check (substring/shared "hello" 1 3) => "el")
(check (substring/shared "hello" 2) => "llo")
(check (xsubstring "abcdef" 2) => "cdefab")
(check (xsubstring "abcdef" -2) => "efabcd")
(check (xsubstring "abc" 0 7) => "abcabca")
(check (let ((s (make-string 6 #\-))) (string-xcopy! s 0 "abc" 1 7) s) => "bcabca")

;;; ———————————————— 比较 ————————————————
;; SRFI 13：比较为真时返回不匹配处的下标（真值），为假时返回 #f；这里只看真假
(define (truth x) (and x #t))
(check (truth (string= "abc" "abc")) => #t)
(check (truth (string= "abc" "abd")) => #f)
(check (string= "xabc" "abc" 1) => 4)                                ; s1 从 1 起；为真时返回下标                                 ; s1 的 start
(check (truth (string<> "abc" "abd")) => #t)
(check (truth (string< "abc" "abd")) => #t)
(check (truth (string> "abc" "abd")) => #f)
(check (truth (string<= "abc" "abc")) => #t)
(check (truth (string>= "abd" "abc")) => #t)
(check (truth (string-ci= "ABC" "abc")) => #t)
(check (truth (string-ci<> "ABC" "abd")) => #t)
(check (truth (string-ci< "ABC" "abd")) => #t)
(check (truth (string-ci> "ABD" "abc")) => #t)
(check (truth (string-ci<= "ABC" "abc")) => #t)
(check (truth (string-ci>= "ABC" "abd")) => #f)
(check (string-compare-ci "ABC" "abd" (lambda (i) 'lt) (lambda (i) 'eq) (lambda (i) 'gt)) => 'lt)
(check (string-compare-ci "abc" "ABC" (lambda (i) 'lt) (lambda (i) i) (lambda (i) 'gt)) => 3)
(check (= (string-hash-ci "ABC") (string-hash-ci "abc")) => #t)
(check (< (string-hash-ci "abc" 10) 10) => #t)

;;; ———————————————— 前缀与后缀 ————————————————
(check (string-prefix-length "prefix" "preface") => 4)
(check (string-suffix-length "ending" "pending") => 6)
(check (string-prefix-length-ci "PREfix" "preface") => 4)
(check (string-suffix-length-ci "ENDING" "pending") => 6)
(check (string-prefix? "pre" "prefix") => #t)
(check (string-prefix? "fix" "prefix") => #f)
(check (string-suffix? "fix" "prefix") => #t)
(check (string-prefix-ci? "PRE" "prefix") => #t)
(check (string-suffix-ci? "FIX" "prefix") => #t)

;;; ———————————————— 查找 ————————————————
(check (string-index "hello" #\l) => 2)
(check (string-index "hello" #\z) => #f)
(check (string-index "hello world" char-whitespace?) => 5)
(check (string-index "hello" #\l 3) => 3)
(check (string-index-right "hello" #\l) => 3)
(check (string-skip "   abc" #\space) => 3)
(check (string-skip "aaa" #\a) => #f)
(check (string-skip-right "abc   " char-set:whitespace) => 2)
(check (string-count "banana" #\a) => 3)
(check (string-count "banana" (char-set #\b #\n)) => 3)
(check (string-contains "eek -- what a geek." "ee" 12 18) => 15)
(check (string-contains "hello" "ll") => 2)
(check (string-contains "hello" "z") => #f)
(check (string-contains-ci "HELLO" "ll") => 2)
(check (string-contains-right "abcabc" "bc") => 4)
(check (string-contains-right "abc" "x") => #f)

;;; ———————————————— 大小写（就地修改） ————————————————
;; string-copy 的结果可变（iron-054 修正了基础库；此前它返回不可变字符串）
(check (let ((s (string-copy "hello"))) (string-upcase! s) s) => "HELLO")
(check (let ((s (string-copy "HELLO"))) (string-downcase! s 1 3) s) => "HelLO")
(check (let ((s (string-copy "hello world"))) (string-titlecase! s) s) => "Hello World")

;;; ———————————————— 反转、拼接 ————————————————
(check (string-reverse "abc") => "cba")
(check (string-reverse "abcde" 1 4) => "dcb")
(check (let ((s (string-copy "abc"))) (string-reverse! s) s) => "cba")
(check (string-concatenate '("a" "bc" "")) => "abc")
(check (string-concatenate/shared '("a" "bc")) => "abc")
(check (string-append/shared "a" "" "bc") => "abc")
(check (string-concatenate-reverse '("c" "b" "a")) => "abc")
(check (string-concatenate-reverse '("c" "b") "xyz" 1) => "bcx")       ; final-string 与 end
(check (string-concatenate-reverse/shared '("b" "a")) => "ab")

;;; ———————————————— 映射、折叠 ————————————————
(check (string-map char-upcase "abc") => "ABC")
(check (string-map char-upcase "abcd" 1 3) => "BC")
(check (let ((s (string-copy "abc"))) (string-map! char-upcase s) s) => "ABC")
(check (string-fold cons '() "abc") => '(#\c #\b #\a))
(check (string-fold-right cons '() "abc") => '(#\a #\b #\c))
(check (string-fold (lambda (c n) (if (char-upper-case? c) (+ n 1) n)) 0 "AbC") => 2)
(check (let ((l '())) (string-for-each-index (lambda (i) (set! l (cons i l))) "abc") l) => '(2 1 0))

;;; ———————————————— 过滤、删除、替换、切分 ————————————————
(check (string-filter char-alphabetic? "a1b2") => "ab")      ; SRFI 13 的参数次序：谓词在前也可以（参照实现两种都收）
(check (string-delete char-alphabetic? "a1b2") => "12")
(check (string-filter #\a "banana") => "aaa")
(check (string-replace "The TCL programmer endured daily ridicule." "another miserable perl drone" 4 7) =>
       "The another miserable perl drone programmer endured daily ridicule.")
(check (string-replace "abc" "XYZ" 1 1) => "aXYZbc")
(check (string-tokenize "Help make programs run, run, RUN!") => '("Help" "make" "programs" "run," "run," "RUN!"))
(check (string-tokenize "a1b22c" char-set:letter) => '("a" "b" "c"))
(check (let ((s (make-string 5 #\-))) (string-copy! s 1 "abc") s) => "-abc-")

;;; ———————————————— SRFI 152 部分 ————————————————
(check (string-take-while "aab" (lambda (c) (char=? c #\a))) => "aa")
(check (string-take-while-right "abb" (lambda (c) (char=? c #\b))) => "bb")
(check (string-drop-while "aab" (lambda (c) (char=? c #\a))) => "b")
(check (string-drop-while-right "abb" (lambda (c) (char=? c #\b))) => "a")
(check (call-with-values (lambda () (string-span "aab" (lambda (c) (char=? c #\a)))) list) => '("aa" "b"))
(check (call-with-values (lambda () (string-break "aab" (lambda (c) (char=? c #\b)))) list) => '("aa" "b"))
(check (string-remove (lambda (c) (char=? c #\a)) "banana") => "bnn")
(check (string-replicate "abc" 0 7) => "abcabca")
(check (string-replicate "abc" -2 3) => "bcabc")
(check (string-segment "abcdefg" 3) => '("abc" "def" "g"))
(check (string-split "a,b,,c" ",") => '("a" "b" "" "c"))
(check (string-split "a b" " " 'infix) => '("a" "b"))
(check (string-split ",a," "," 'prefix) => '("a" ""))
(check (string-split "" "," 'infix) => '())
(check (string->vector "abc") => '#(#\a #\b #\c))
(check (string->vector "abcd" 1 3) => '#(#\b #\c))
(check (vector->string '#(#\a #\b #\c)) => "abc")
(check (vector->string '#(#\a #\b #\c) 1) => "bc")
(check (read-string 3 (open-string-input-port "abcdef")) => "abc")
(check (read-string 10 (open-string-input-port "ab")) => "ab")
(check (eof-object? (read-string 3 (open-string-input-port ""))) => #t)
(check (call-with-string-output-port (lambda (p) (write-string "hello" p))) => "hello")
(check (call-with-string-output-port (lambda (p) (write-string "hello" p 1 3))) => "el")

(check-report "std strings")
