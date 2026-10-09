;;; 字符串按码点（iron-055，designs/12-strings.md）：BMP 之外的字符在字符串中只占一个位置。
(import (ironscheme) (ironscheme clr))

(define failures 0)
(define count 0)
(define-syntax check
  (syntax-rules (=>)
    ((_ expr => expected)
     (let ((v (guard (e (#t (list 'raised (if (message-condition? e) (condition-message e) e)))) expr)))
       (set! count (+ count 1))
       (unless (equal? v expected)
         (set! failures (+ failures 1))
         (display "FAIL: ") (write 'expr) (display " => ") (write v)
         (display ", expected ") (write expected) (newline))))))

(define grin #\x1F600)
(define s "a\x1F600;b")                    ; 字面量：含 BMP 外字符

;;; 长度、下标、子串
(check (string-length s) => 3)
(check (string-ref s 1) => grin)
(check (string-ref s 2) => #\b)
(check (substring s 1 3) => (string grin #\b))
(check (string->list s) => (list #\a grin #\b))
(check (list->string (list grin grin)) => "\x1F600;\x1F600;")
(check (string-length (make-string 4 grin)) => 4)
(check (string-length (string-append s s)) => 6)
(check (string? s) => #t)

;;; 修改：可变串写入 BMP 外字符后就地变宽，其他下标不受影响
(define m (make-string 3 #\x))
(string-set! m 1 grin)
(check m => "x\x1F600;x")
(check (string-length m) => 3)
(string-set! m 2 #\y)
(check m => "x\x1F600;y")
(string-fill! m #\x10400)
(check m => "\x10400;\x10400;\x10400;")
(check (let ((c (string-copy s))) (string-set! c 0 #\z) (list c s)) => (list "z\x1F600;b" s))
(check (guard (e (#t 'raised)) (string-set! s 0 #\z)) => 'raised)      ; 字面量不可变

;;; 比较：按码点（U+FFFF < U+10000；UTF-16 码元比较会得到相反结果）
(check (string<? "\xFFFF;" "\x10000;") => #t)
(check (string<? "\xE000;" "\x10000;") => #t)
(check (string=? s (string #\a grin #\b)) => #t)
(check (equal? s (string-copy s)) => #t)
(check (string-compare "\x10000;" "\xFFFF;") => 1)
(check (string-ci=? "\x10400;" "\x10428;") => #t)                      ; Deseret 的大小写

;;; 符号、散列
(check (symbol->string (string->symbol s)) => s)
(check (string-length (symbol->string (string->symbol s))) => 3)
(check (= (string-hash s) (string-hash (string-copy s))) => #t)
(define ht (make-hashtable string-hash string=?))
(hashtable-set! ht s 1)
(check (hashtable-ref ht (string-copy s) #f) => 1)

;;; 端口：按码点读写
(check (call-with-string-output-port (lambda (p) (put-string p s 1 2))) => (string grin #\b))
(check (let ((p (open-string-input-port s)))
         (list (read-char p) (peek-char p) (read-char p) (read-char p) (eof-object? (read-char p))))
       => (list #\a grin grin #\b #t))
(check (get-string-n (open-string-input-port s) 2) => (string #\a grin))
(check (get-line (open-string-input-port "\x1F600;x\ny")) => "\x1F600;x")
(check (let ((p (open-string-input-port "\x1F600;"))) (peek-char p) (get-line p)) => "\x1F600;")
(check (eof-object? (get-string-all (open-string-input-port ""))) => #t)  ; R6RS：没有字符时为文件尾
(check (read (open-string-input-port "(\"\x1F600;\")")) => (list (string grin)))
(check (call-with-string-output-port (lambda (p) (write s p))) => "\"a\x1F600;b\"")

;;; 编码转换与 .NET 互操作
(check (string->utf8 s) => #vu8(97 240 159 152 128 98))
(check (utf8->string #vu8(97 240 159 152 128 98)) => s)
(check (string-length (utf8->string #vu8(240 159 152 128))) => 1)
(check (string-length (clr-static-call System.String (Concat System.String System.String) "x" (clr-call System.Object ToString s))) => 4)   ; .NET 返回的串经入口规范化
(check (clr-prop-get System.String Length s) => 4)                                                      ; 传给 .NET 时为 UTF-16
(check (string-upcase "a\x10428;") => "A\x10400;")
(check (char-upcase #\x10428) => #\x10400)
(check (char-downcase #\x10400) => #\x10428)
(check (string-length (number->string 12)) => 2)

;;; 纯 BMP 字符串仍是 System.String
(check (clr-is System.String "abc") => #t)
(check (clr-is System.String (string-append "a" "b")) => #t)
(check (clr-is System.String (substring "abcd" 1 3)) => #t)

(display (if (= failures 0) "unicode-strings: all passed" "unicode-strings: failed"))
(display " (") (display count) (display " checks)")
(newline)
