;;; (ironscheme std lazy) 与基础库 delay / force 的测试（designs/08-std-library.md D7）。
;;; 迭代强制的用例取自 SRFI 45 的文本（André van Tonder）。
(import (rnrs) (rnrs r5rs) (only (ironscheme) include) (ironscheme std lazy))
(include "tests/std/check.ss")

(check (force (delay (+ 1 2))) => 3)
(check (force (eager 5)) => 5)
(check (force (lazy (delay 7))) => 7)
(check (force (delay-force (delay 8))) => 8)

;; 只求值一次
(define count 0)
(define p (delay (begin (set! count (+ count 1)) count)))
(force p) (force p)
(check count => 1)

;; SRFI 45：重入——强制过程中再次强制自己，以先完成的为准
(define r-count 0)
(define r (delay (begin (set! r-count (+ r-count 1))
                        (if (> r-count x) r-count (force r)))))
(define x 5)
(check (force r) => 6)
(set! x 10)
(check (force r) => 6)

;; 空间安全：一百万层的 lazy 链（原实现会栈溢出）
(define (loop n) (lazy (if (= n 0) (delay 'done) (loop (- n 1)))))
(check (force (loop 1000000)) => 'done)

;; SRFI 45 的 stream-filter 用例：在一百万个元素中找到最后一个
(define (stream-drop s index)
  (lazy (if (zero? index) s (stream-drop (cdr (force s)) (- index 1)))))
(define (from n) (delay (cons n (from (+ n 1)))))
(check (car (force (stream-drop (from 0) 100000))) => 100000)

(check-report "std lazy")
