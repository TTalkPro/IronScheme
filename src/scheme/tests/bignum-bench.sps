;;; 大整数基准（iron-059）。不在测试中运行；在 src/scheme 下用 Release 构建手动运行：
;;;   dotnet ../IronScheme.Host/bin/Release/net10.0/IronScheme.Host.dll -I lib tests/bignum-bench.sps
;;; 每项先热身 2 轮再计时 5 轮，报告最小值与中位数（ms）。热身是必须的：BCL 中 BigInteger 的方法
;;; 由分层编译从预编译代码换到 PGO 插桩版本（更慢）再到 tier1，只跑一轮的结果会落在这个过程中，波动可达两三倍。
;;; 校验值是结果对 1000000007 取模，用来核对改动前后结果一致。
(import (ironscheme) (ironscheme clr))

(define warmup-rounds 2)
(define timed-rounds 5)

(define (ticks) (clr-static-call System.Diagnostics.Stopwatch GetTimestamp))
(define (elapsed-ms t0)
  (/ (* (- (ticks) t0) 1000.0) (clr-static-field-get System.Diagnostics.Stopwatch Frequency)))

(define (pad s n)
  (if (< (string-length s) n) (string-append s (make-string (- n (string-length s)) #\space)) s))
(define (ms->string x) (number->string (/ (round (* x 10)) 10)))

;; 运行 thunk 若干轮，打印最小值与中位数，返回最后一轮的结果
(define (bench name thunk)
  (do ((i 0 (+ i 1))) ((= i warmup-rounds)) (thunk))
  (let loop ((i 0) (times '()) (result #f))
    (if (= i timed-rounds)
        (let ((sorted (list-sort < times)))
          (display (pad name 18))
          (display "min ") (display (pad (ms->string (car sorted)) 9))
          (display "median ") (display (ms->string (list-ref sorted (div timed-rounds 2))))
          (newline)
          result)
        (let* ((t0 (ticks)) (r (thunk)) (t (elapsed-ms t0)))
          (loop (+ i 1) (cons t times) r)))))

(define (fact n) (let f ((i 1) (a 1)) (if (> i n) a (f (+ i 1) (* a i)))))
(define (fib n) (let f ((i 0) (a 0) (b 1)) (if (= i n) a (f (+ i 1) b (+ a b)))))

(define checks '())
(define (check name v) (set! checks (cons (cons name (mod v 1000000007)) checks)))

(define f20k (bench "fact 20000" (lambda () (fact 20000))))
(check "fact" f20k)
(check "fib" (bench "fib 100000" (lambda () (fib 100000))))
(define s (bench "number->string" (lambda () (number->string f20k))))
(check "len" (string-length s))
(check "parse" (bench "string->number" (lambda () (string->number s))))
(check "hex" (string-length (bench "number->string 16" (lambda () (number->string f20k 16)))))
(define x (expt 3 300000))
(check "sq" (bench "square" (lambda () (* x x))))
(check "div" (bench "div" (lambda () (div x (expt 7 50000)))))
(check "gcd" (bench "gcd" (lambda () (gcd (fact 3000) (expt 6 4000)))))
(define h (bench "ratnum" (lambda () (let f ((i 1) (s 0)) (if (> i 2000) (inexact s) (f (+ i 1) (+ s (/ 1 i))))))))
(check "bits" (bench "bitwise" (lambda () (let f ((i 0) (a 0)) (if (= i 20000) (bitwise-length a) (f (+ i 1) (bitwise-xor (bitwise-arithmetic-shift-left a 3) (+ i (- x)))))))))

(newline)
(for-each (lambda (c) (display (car c)) (display " = ") (display (cdr c)) (newline)) (reverse checks))
(display "harmonic 2000 = ") (display h) (newline)
