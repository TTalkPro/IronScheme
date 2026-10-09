;;; (ironscheme std string-cursors) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 130 的测试，
;;; 按 SRFI 130 的文本编写，每个导出名至少一项。本实现中游标即下标。
(import (rnrs) (only (ironscheme) include) (ironscheme std string-cursors))
(include "tests/std/check.ss")

(define s "hello world")

;;; ———————————————— 游标 ————————————————
(check (string-cursor? (string-cursor-start s)) => #t)
(check (string-cursor-start s) => 0)
(check (string-cursor-end s) => 11)
(check (string-cursor-next s 0) => 1)
(check (string-cursor-prev s 1) => 0)
(check (string-cursor-forward s 0 5) => 5)
(check (string-cursor-back s 5 2) => 3)
(check (string-cursor=? 2 2) => #t)
(check (string-cursor<? 1 2) => #t)
(check (string-cursor>? 1 2) => #f)
(check (string-cursor<=? 2 2) => #t)
(check (string-cursor>=? 1 2) => #f)
(check (string-cursor-diff s 2 7) => 5)
(check (string-cursor->index s 4) => 4)
(check (string-index->cursor s 4) => 4)
(check (string-ref/cursor s 4) => #\o)

;;; ———————————————— 谓词与构造 ————————————————
(check (string-null? "") => #t)
(check (string-every char-alphabetic? "abc") => #t)
(check (string-any char-numeric? "a1") => #t)
(check (string-tabulate (lambda (i) (integer->char (+ i 97))) 3) => "abc")
(check (string-unfold null? car cdr '(#\a #\b)) => "ab")
(check (string-unfold-right null? car cdr '(#\a #\b)) => "ba")
(check (reverse-list->string '(#\a #\b)) => "ba")
(check (string-join '("a" "b") "-") => "a-b")

;;; ———————————————— 转换与选取（游标参数） ————————————————
(check (string->list/cursors "abcd" 1 3) => '(#\b #\c))
(check (string->vector/cursors "abcd" 2) => '#(#\c #\d))
(check (substring/cursors s 6 11) => "world")
(check (string-copy/cursors s 0 5) => "hello")
(check (string-take s 5) => "hello")
(check (string-take-right s 5) => "world")
(check (string-drop s 6) => "world")
(check (string-drop-right s 6) => "hello")
(check (string-pad "7" 3 #\0) => "007")
(check (string-pad-right "7" 3 #\0) => "700")
(check (string-trim "  a  ") => "a  ")
(check (string-trim-right "  a  ") => "  a")
(check (string-trim-both "  a  ") => "a")

;;; ———————————————— 前缀、后缀与查找（返回游标） ————————————————
(check (string-prefix-length "prefix" "preface") => 4)
(check (string-suffix-length "ending" "pending") => 6)
(check (string-prefix? "he" s) => #t)
(check (string-suffix? "ld" s) => #t)
(check (string-index s #\o) => 4)
(check (string-index s #\z) => 11)                         ; 找不到：末端游标（不是 #f）
(check (string-index-right s #\o) => 8)                    ; 返回匹配字符之后的游标
(check (string-skip s char-alphabetic?) => 5)
(check (string-skip-right "abc  " char-whitespace?) => 3)
(check (string-contains s "wor") => 6)
(check (string-contains s "xyz") => #f)
(check (string-contains-right "abcabc" "bc") => 4)

;;; ———————————————— 其余 ————————————————
(check (string-reverse "abc") => "cba")
(check (string-concatenate '("a" "b")) => "ab")
(check (string-concatenate-reverse '("b" "a")) => "ab")
(check (string-fold cons '() "ab") => '(#\b #\a))
(check (string-fold-right cons '() "ab") => '(#\a #\b))
(check (let ((l '())) (string-for-each-cursor (lambda (c) (set! l (cons c l))) "abc") l) => '(2 1 0))
(check (string-replicate "abc" 0 5) => "abcab")
(check (string-count "banana" (lambda (c) (char=? c #\a))) => 3)
(check (string-replace "abcd" "XY" 1 3) => "aXYd")
(check (string-split "a,b,c" ",") => '("a" "b" "c"))
(check (string-filter char-alphabetic? "a1b2") => "ab")
(check (string-remove char-alphabetic? "a1b2") => "12")

(check-report "std string-cursors")
