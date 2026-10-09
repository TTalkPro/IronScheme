;;; 同步完成的 (await t) 每次调用的纳秒数（iron-052 验收：≤ 50 ns，Release 构建下测）。
;;; 同一循环先调用同步的过程，减去循环本身与调用的开销。
(import (ironscheme) (ironscheme clr) (only (ironscheme core) task-result task-from-result))

(define-async (echo t) (await t))
(define (echo-sync t) t)
(define done (task-from-result 1))

(define (ticks) (clr-static-call System.Diagnostics.Stopwatch GetTimestamp))
(define (ns-per-call f n)
  (let ((t0 (ticks)))
    (let loop ((i 0)) (unless (fx=? i n) (f done) (loop (fx+ i 1))))
    (/ (* (- (ticks) t0) 1e9) (clr-static-field-get System.Diagnostics.Stopwatch Frequency) n)))

(ns-per-call echo 200000)   ; 预热
(ns-per-call echo-sync 200000)
(define base (ns-per-call echo-sync 2000000))
(define total (ns-per-call echo 2000000))
(define ns (- total base))
(display "sync call: ") (display (round base)) (display " ns; async call with sync await: ") (display (round total))
(display " ns; difference: ") (display (round ns)) (display " ns") (newline)
(display (if (<= ns 50) "async-bench: ok" "async-bench: slow")) (newline)
