;;; iron-034 的固定基准（D1）：每项跑三次取中位数，打印表格。不进 dotnet test，手动运行：
;;;   cd src/scheme && dotnet ../IronScheme.Host/bin/Release/net10.0/IronScheme.Host.dll -I lib -I lib/nanopass-framework-scheme tests/perf/run-all.sps
;;; 进程级的项（boot-load、r6rs-run、wordcount）另起宿主进程计时，宿主路径取当前进程的命令行。
(import (rnrs) (ironscheme) (ironscheme clr) (ironscheme compiler))

(clr-using System)
(clr-using System.Diagnostics)

(define (now) (clr-static-call Stopwatch GetTimestamp))
(define (elapsed-ms t0) (exact (round (/ (* 1000 (- (now) t0)) (clr-static-field-get Stopwatch Frequency)))))
(define (time-ms thunk) (let ((t0 (now))) (thunk) (elapsed-ms t0)))
(define (median3 thunk)
  (let ((xs (list-sort < (list (time-ms thunk) (time-ms thunk) (time-ms thunk)))))
    (cadr xs)))

;; 另起宿主进程：dotnet <宿主 dll> --boot <镜像> -I lib 参数…
(define host-args
  (let ((args (clr-static-call Environment GetCommandLineArgs)))
    (vector-ref args 0)))
(define (run-host . args)
  (let ((psi (clr-new ProcessStartInfo "dotnet")))
    (for-each (lambda (a) (clr-call System.Collections.ObjectModel.Collection<String> Add (clr-prop-get ProcessStartInfo ArgumentList psi) a))
              (append (list host-args "--boot" "boot/ironscheme.boot.dll" "-I" "lib") args))
    (clr-prop-set! ProcessStartInfo RedirectStandardOutput psi #t)
    (clr-prop-set! ProcessStartInfo UseShellExecute psi #f)
    (let ((p (clr-static-call Process (Start ProcessStartInfo) psi)))
      (clr-call System.IO.StreamReader ReadToEnd (clr-prop-get Process StandardOutput p))
      (clr-call Process WaitForExit p))))

;; ———— 进程内 ————
(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(define (fl-loop n) (let loop ((i 0) (acc 0.0)) (if (= i n) acc (loop (+ i 1) (fl+ acc 1.5)))))
(define (arith-loop n)
  (let loop ((i 0)) (if (= i n) i (loop (+ i 1))))
  (let loop ((i n)) (if (< i 1) i (loop (- i 1)))))
(define seed-forms
  (call-with-input-file "boot/boot-seed.core"
    (lambda (p) (let loop ((acc '())) (let ((x (read p))) (if (eof-object? x) (reverse acc) (loop (cons x acc))))))))

;; wordcount 的输入：约 1 MB
(define wc-input "tests/perf/wordcount-input.txt")
(unless (file-exists? wc-input)
  (call-with-output-file wc-input
    (lambda (p)
      (let loop ((i 0))
        (when (< i 20000)
          (put-string p "the quick brown fox jumps over the lazy dog and the cat's hat\n")
          (loop (+ i 1)))))))

(define results
  (list
    (cons "boot-load" (median3 (lambda () (run-host "tests/perf/empty.sps"))))
    (cons "compile-seed" (median3 (lambda () (compile-forms->lcil seed-forms "perf" "#Module"))))
    (cons "r6rs-run" (median3 (lambda () (run-host "tests/r6rs/run.sps"))))
    (cons "fib" (median3 (lambda () (fib 30))))
    (cons "fl-loop" (median3 (lambda () (fl-loop 1000000))))
    (cons "arith-loop" (median3 (lambda () (arith-loop 1000000))))
    (cons "wordcount" (median3 (lambda () (run-host "../../examples/WordCount/wordcount.sps" wc-input))))))

(for-each (lambda (r)
            (display (car r)) (display (make-string (- 14 (string-length (car r))) #\space))
            (display (cdr r)) (display " ms") (newline))
          results)
