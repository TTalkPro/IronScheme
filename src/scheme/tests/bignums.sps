;;; 大整数的回归测试（iron-059：改用 System.Numerics.BigInteger，进制转换与位运算改由宿主完成）。
;;; 位运算与进制转换和逐位算出的参照值比较（参照用的是原来的 Scheme 算法）。
(import (ironscheme))

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

;;; 参照实现：只用 div、mod、比较，逐位计算
(define (ref-bit-count n)
  (if (negative? n)
      (- -1 (ref-bit-count (- -1 n)))
      (let f ((n n) (c 0)) (if (zero? n) c (f (div n 2) (+ c (mod n 2)))))))
(define (ref-length n)
  (let f ((n (if (negative? n) (- -1 n) n)) (c 0)) (if (zero? n) c (f (div n 2) (+ c 1)))))
(define (ref-first-bit-set n)
  (if (zero? n) -1 (let f ((n n) (c 0)) (if (odd? n) c (f (div n 2) (+ c 1))))))
(define (ref-bit-set? n k) (odd? (div n (expt 2 k))))
(define (ref-shift n k) (if (>= k 0) (* n (expt 2 k)) (div n (expt 2 (- k)))))
(define (ref-reverse n start end)
  (let* ((w (- end start))
         (field (mod (div n (expt 2 start)) (expt 2 w)))
         (rev (let f ((i 0) (x field) (r 0)) (if (= i w) r (f (+ i 1) (div x 2) (+ (* r 2) (mod x 2)))))))
    (+ (- n (* field (expt 2 start))) (* rev (expt 2 start)))))
(define (ref->string n radix)
  (define (digit d) (string-ref "0123456789abcdef" d))
  (if (zero? n) "0"
      (let f ((m (abs n)) (a '()))
        (if (zero? m)
            (list->string (if (negative? n) (cons #\- a) a))
            (f (div m radix) (cons (digit (mod m radix)) a))))))

;;; 样本：正负、跨越 fixnum 边界、2 的幂附近
(define samples
  (let ((base (list 0 1 -1 2147483647 -2147483648 2147483648 -2147483649
                    (expt 2 64) (- (expt 2 64)) (- (expt 2 64) 1) (- 1 (expt 2 64))
                    (expt 3 100) (- (expt 3 100)) (* (expt 2 200) (expt 7 30)) (- (* (expt 2 200) (expt 7 30))))))
    (append base (map (lambda (n) (+ n 12345)) base))))

(for-each
  (lambda (n)
    (check (bitwise-bit-count n) => (ref-bit-count n))
    (check (bitwise-length n) => (ref-length n))
    (check (bitwise-first-bit-set n) => (ref-first-bit-set n))
    (check (map (lambda (k) (bitwise-bit-set? n k)) '(0 1 31 32 63 64 100 400))
           => (map (lambda (k) (ref-bit-set? n k)) '(0 1 31 32 63 64 100 400)))
    (check (map (lambda (k) (bitwise-arithmetic-shift n k)) '(-300 -65 -33 -32 -31 -1 0 1 31 33 100))
           => (map (lambda (k) (ref-shift n k)) '(-300 -65 -33 -32 -31 -1 0 1 31 33 100)))
    (check (map (lambda (r) (number->string n r)) '(2 8 10 16))
           => (map (lambda (r) (ref->string n r)) '(2 8 10 16)))
    (check (map (lambda (r) (string->number (ref->string n r) r)) '(2 8 10 16))
           => (list n n n n))
    (check (bitwise-not n) => (- -1 n))
    (unless (negative? n)
      (check (bitwise-reverse-bit-field n 3 90) => (ref-reverse n 3 90))))
  samples)

(check (bitwise-bit-set? (- (expt 2 100)) (expt 2 40)) => #t)
(check (bitwise-bit-set? (expt 2 100) (expt 2 40)) => #f)
(check (bitwise-reverse-bit-field #b1010010 1 4) => #b1011000)   ; R6RS 的例子
(check (string->number "#xDEADBEEFDEADBEEFDEADBEEF") => #xdeadbeefdeadbeefdeadbeef)
(check (string->number "-123456789012345678901234567890") => (- 123456789012345678901234567890))

;;; 移位的快速路径与边界（iron-059）
(define-syntax raises?
  (syntax-rules ()
    ((_ expr) (guard (e (#t #t)) expr #f))))
(check (bitwise-arithmetic-shift-left 5 0) => 5)
(check (bitwise-arithmetic-shift-right -5 0) => -5)
(check (bitwise-arithmetic-shift-left 1 31) => 2147483648)
(check (fixnum? (bitwise-arithmetic-shift-right (expt 2 40) 20)) => #t)
(check (bitwise-arithmetic-shift-right (- (expt 2 100)) 1000000) => -1)
(check (bitwise-arithmetic-shift-right (expt 2 100) 1000000) => 0)
(check (bitwise-arithmetic-shift-right -1 5) => -1)
(check (bitwise-arithmetic-shift -7 -1) => -4)
(check (bitwise-arithmetic-shift 7 (least-fixnum)) => 0)
(check (bitwise-arithmetic-shift -7 (least-fixnum)) => -1)
(check (bitwise-arithmetic-shift (expt 2 70) (- (expt 2 80))) => 0)
(check (bitwise-arithmetic-shift (- (expt 2 70)) (- (expt 2 80))) => -1)
(check (bitwise-arithmetic-shift-right 12345 (expt 2 80)) => 0)
(check (raises? (bitwise-arithmetic-shift-left 1 -1)) => #t)
(check (raises? (bitwise-arithmetic-shift-right 1 -1)) => #t)
(check (raises? (bitwise-arithmetic-shift-left 1.5 2)) => #t)
(check (raises? (bitwise-arithmetic-shift 1 (expt 2 80))) => #t)

;;; 到 flonum 的转换：正确舍入，超出范围为无穷（原来得 +nan.0）
(check (inexact (expt 2 1100)) => +inf.0)
(check (inexact (- (expt 10 400))) => -inf.0)
(check (inexact (/ (+ (expt 10 400) 1) (* 4 (expt 10 400)))) => 0.25)
(check (inexact (+ (expt 2 53) 1)) => 9007199254740992.0)
(check (inexact (+ (expt 2 53) 3)) => 9007199254740996.0)
(check (- (expt 2 31)) => -2147483648)
(check (fixnum? (- (expt 2 31))) => #t)

(display (if (= failures 0) "bignums: all passed" "bignums: failed"))
(display " (") (display count) (display " checks)")
(newline)
