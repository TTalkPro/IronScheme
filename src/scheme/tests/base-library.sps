;;; 基础库问题修复的回归测试（iron-054）。每组对应 tasks/iron-054-base-library-fixes.md 中的一项。
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
(define-syntax raises?
  (syntax-rules ()
    ((_ expr) (guard (e (#t #t)) expr #f))))

;;; A：string-copy 的结果可变
(check (let ((s (string-copy "abc"))) (string-set! s 0 #\x) s) => "xbc")
(check (let* ((m (make-string 2 #\a)) (s (string-copy m))) (string-set! s 0 #\b) (list m s)) => '("aa" "ba"))

;;; C：原生行尾随平台
(check (native-eol-style) => (if (clr-static-call System.OperatingSystem IsWindows) 'crlf 'lf))
(check (transcoder-eol-style (native-transcoder)) => (native-eol-style))

;;; D：format
(check (format "~d|~x|~o|~b" 10 255 8 5) => "10|ff|10|101")
(check (format "~a ~s~%" "x" "y") => "x \"y\"\n")
(check (format "a~nb") => "a\nb")
(check (format "~a ~*~a" 1 2 3) => "1 3")
(check (format "~1@*~a ~0@*~a" 'x 'y) => "y x")                  ; SRFI 29 的位置参数
(check (format "~a ~:*~a" 'x) => "x x")
(check (format "~2*~a" 1 2 3) => "3")
(check (format "~~") => "~")
(check (raises? (format "~q" 1)) => #t)                          ; 未知指令报错（原来原样输出）
(check (raises? (format "~a")) => #t)                            ; 参数不足
(check (raises? (format "~d" 'x)) => #t)

;;; E：define-values
(define-values (q r) (div-and-mod 17 5))
(check (list q r) => '(3 2))
(define-values (h . t) (values 1 2 3))
(check (list h t) => '(1 (2 3)))
(define-values all (values 1 2))
(check all => '(1 2))
(define-values () (values))
(check (let () (define-values (a b) (values 1 2)) (define c 3) (+ a b c)) => 6)

;;; F：bitwise-copy-bit 的下标 31
(check (bitwise-copy-bit 0 31 1) => (expt 2 31))
(check (bitwise-copy-bit 0 30 1) => (expt 2 30))
(check (bitwise-copy-bit (expt 2 31) 31 0) => 0)

;;; G：eq / eqv 散列表的散列函数为 #f
(check (hashtable-hash-function (make-eq-hashtable)) => #f)
(check (hashtable-hash-function (make-eqv-hashtable)) => #f)
(check (hashtable-hash-function (hashtable-copy (make-eqv-hashtable))) => #f)
(check (eq? (hashtable-hash-function (make-hashtable string-hash string=?)) string-hash) => #t)
(check (eq? (hashtable-equivalence-function (make-eqv-hashtable)) eqv?) => #t)

;;; H：string-compare 返回 -1 / 0 / 1
(check (map string-compare '("a" "c" "b" "ab") '("c" "a" "b" "a")) => '(-1 1 0 1))

;;; I：vector-binary-search（SRFI 133 的接口）
(define v '#(1 3 5 7 9))
(check (vector-binary-search v 7 -) => 3)
(check (vector-binary-search v 4 -) => #f)
(check (vector-binary-search v 1 - 1) => #f)
(check (vector-binary-search v 9 - 0 5) => 4)
(check (vector-binary-search v 5) => 2)
(check (vector-binary-search '#("a" "c" "e") "c") => 1)
(check (vector-binary-search '#(#\a #\c) #\b) => #f)

;;; J：string-hash 非负、只取决于内容
(check (string-hash "hello") => 262089899)                       ; FNV-1a（0x4f9f2cab）的低 30 位，跨进程不变
(check (for-all (lambda (s) (and (fixnum? (string-hash s)) (>= (string-hash s) 0)))
                '("" "a" "hello" "\x10000;" "a much longer string with spaces"))
       => #t)
(check (= (string-ci-hash "HeLLo") (string-ci-hash "hello")) => #t)
(check (>= (symbol-hash 'some-symbol) 0) => #t)

;;; K：数的比较的快速路径（iron-059）：同为 fixnum / 同为 flonum 时直接比较，结果须与通用路径一致
(define (all-compares a b) (list (= a b) (< a b) (<= a b) (> a b) (>= a b)))
(check (all-compares 1 2) => '(#f #t #t #f #f))
(check (all-compares -5 -5) => '(#t #f #t #f #t))
(check (all-compares (greatest-fixnum) (least-fixnum)) => '(#f #f #f #t #t))
(check (all-compares 1.5 2.5) => '(#f #t #t #f #f))
(check (all-compares -0.0 0.0) => '(#t #f #t #f #t))
(check (all-compares +nan.0 +nan.0) => '(#f #f #f #f #f))
(check (all-compares +nan.0 1.0) => '(#f #f #f #f #f))
(check (all-compares 1.0 +nan.0) => '(#f #f #f #f #f))
(check (all-compares +inf.0 +inf.0) => '(#t #f #t #f #t))
(check (all-compares -inf.0 +inf.0) => '(#f #t #t #f #f))
(check (all-compares 1e308 +inf.0) => '(#f #t #t #f #f))
(check (all-compares 1 1.0) => '(#t #f #t #f #t))                 ; fixnum 与 flonum 混合
(check (all-compares 0 -0.0) => '(#t #f #t #f #t))
(check (all-compares 3 +nan.0) => '(#f #f #f #f #f))
(check (all-compares +inf.0 (greatest-fixnum)) => '(#f #f #f #t #t))
(check (all-compares (greatest-fixnum) 2147483647.5) => '(#f #t #t #f #f))
(check (all-compares (least-fixnum) -2147483648.0) => '(#t #f #t #f #t))
(check (all-compares (expt 2 31) 2147483647) => '(#f #f #f #t #t))
(check (all-compares 1/3 0.3333333333333333) => '(#f #f #f #t #t))   ; 精确比较
(check (all-compares 9007199254740993 9007199254740992.0) => '(#f #f #f #t #t))
(check (= 1+2i 1+2i) => #t)
(check (< 1 2 3 3) => #f)
(check (<= 1 2 3 3) => #t)
(check (= 2 2 2.0) => #t)
(check (raises? (= 1 'a)) => #t)
(check (raises? (< 'a 1)) => #t)
(check (raises? (< 1+2i 1)) => #t)

(display (if (= failures 0) "base-library: all passed" "base-library: failed"))
(display " (") (display count) (display " checks)")
(newline)
