;;; (ironscheme std persistent random-access-lists) 的测试（designs/08-std-library.md D8）。即 SRFI 101 的测试
;;; （Copyright (c) David Van Horn 2009，MIT 式许可）。原测试以 (srfi :101) 遮蔽基础库的 car、cons、quote 等；
;;; 这里机械改写：这 44 个名字改为 ra- 版本，'数据 改为 (ra-quote 数据)，r6: 前缀的基础库名去掉前缀。
;;; check-expect / check-error 改为计入 tests/std/check.ss 的计数。
(import (rnrs) (only (ironscheme) include) (ironscheme std persistent random-access-lists))
(include "tests/std/check.ss")

;; 原 check-expect 用 assert 逐层比较（失败即中止）；这里改为比较结果计入 check.ss 的计数
(define (ra-equal? c e)
  (if (ra-pair? c)
      (and (ra-pair? e)
           (ra-equal? (ra-car c) (ra-car e))
           (ra-equal? (ra-cdr c) (ra-cdr e)))
      (equal? c e)))

(define-syntax check-expect
  (syntax-rules ()
    ((_ c e) (check (ra-equal? c e) => #t))))

(define-syntax check-error
  (syntax-rules ()
    ((_ e)
     (check (let ((f (ra-cons 0 0)))
              (guard (g ((eq? f g) 'no-error)
                        (else 'OK))
                (begin e
                       (raise f))))
            => 'OK))))

; quote  

; Bug in Larceny prevents this from working
; https://trac.ccs.neu.edu/trac/larceny/ticket/656
;(check-expect (quote 5) (r6:quote 5))
;(check-expect (quote x) (r6:quote x))

(check-expect (let ((f (lambda () (ra-quote (x)))))
                (eq? (f) (f)))
              #t)

(check-expect (ra-quote (1 2 3)) (ra-list 1 2 3))

; pair?
(check-expect (ra-pair? (ra-cons (ra-quote a) (ra-quote b))) #t)
(check-expect (ra-pair? (ra-list (ra-quote a) (ra-quote b) (ra-quote c))) #t)
(check-expect (ra-pair? (ra-quote ())) #f)
(check-expect (ra-pair? (ra-quote #(a b))) #f)

; cons
(check-expect (ra-cons (ra-quote a) (ra-quote ())) (ra-list (ra-quote a)))
(check-expect (ra-cons (ra-list (ra-quote a)) (ra-list (ra-quote b) (ra-quote c) (ra-quote d)))
              (ra-list (ra-list (ra-quote a)) (ra-quote b) (ra-quote c) (ra-quote d)))
(check-expect (ra-cons "a" (ra-list (ra-quote b) (ra-quote c)))
              (ra-list "a" (ra-quote b) (ra-quote c)))
(check-expect (ra-cons (ra-quote a) 3)
              (ra-cons (ra-quote a) 3))
(check-expect (ra-cons (ra-list (ra-quote a) (ra-quote b)) (ra-quote c))
              (ra-cons (ra-list (ra-quote a) (ra-quote b)) (ra-quote c)))

; car
(check-expect (ra-car (ra-list (ra-quote a) (ra-quote b) (ra-quote c)))
              (ra-quote a))
(check-expect (ra-car (ra-list (ra-list (ra-quote a)) (ra-quote b) (ra-quote c) (ra-quote d)))
              (ra-list (ra-quote a)))
(check-expect (ra-car (ra-cons 1 2)) 1)
(check-error (ra-car (ra-quote ())))

; cdr
(check-expect (ra-cdr (ra-list (ra-list (ra-quote a)) (ra-quote b) (ra-quote c) (ra-quote d)))
              (ra-list (ra-quote b) (ra-quote c) (ra-quote d)))
(check-expect (ra-cdr (ra-cons 1 2))
              2)
(check-error (ra-cdr (ra-quote ())))

; null?
(check-expect (eq? ra-null? null?) #t)
(check-expect (ra-null? (ra-quote ())) #t)
(check-expect (ra-null? (ra-cons 1 2)) #f)
(check-expect (ra-null? 4) #f)

; list?
(check-expect (ra-list? (ra-list (ra-quote a) (ra-quote b) (ra-quote c))) #t)
(check-expect (ra-list? (ra-quote ())) #t)
(check-expect (ra-list? (ra-cons (ra-quote a) (ra-quote b))) #f)

; list
(check-expect (ra-list (ra-quote a) (+ 3 4) (ra-quote c))
              (ra-list (ra-quote a) 7 (ra-quote c)))
(check-expect (ra-list) (ra-quote ()))

; make-list
(check-expect (ra-length (ra-make-list 5)) 5)
(check-expect (ra-make-list 5 0)
              (ra-list 0 0 0 0 0))

; length
(check-expect (ra-length (ra-list (ra-quote a) (ra-quote b) (ra-quote c))) 3)
(check-expect (ra-length (ra-list (ra-quote a) (ra-list (ra-quote b)) (ra-list (ra-quote c)))) 3)
(check-expect (ra-length (ra-quote ())) 0)

; append
(check-expect (ra-append (ra-list (ra-quote x)) (ra-list (ra-quote y))) (ra-list (ra-quote x) (ra-quote y)))
(check-expect (ra-append (ra-list (ra-quote a)) (ra-list (ra-quote b) (ra-quote c) (ra-quote d))) (ra-list (ra-quote a) (ra-quote b) (ra-quote c) (ra-quote d)))
(check-expect (ra-append (ra-list (ra-quote a) (ra-list (ra-quote b))) (ra-list (ra-list (ra-quote c)))) 
              (ra-list (ra-quote a) (ra-list (ra-quote b)) (ra-list (ra-quote c))))
(check-expect (ra-append (ra-list (ra-quote a) (ra-quote b)) (ra-cons (ra-quote c) (ra-quote d))) 
              (ra-cons (ra-quote a) (ra-cons (ra-quote b) (ra-cons (ra-quote c) (ra-quote d)))))
(check-expect (ra-append (ra-quote ()) (ra-quote a)) (ra-quote a))

; reverse
(check-expect (ra-reverse (ra-list (ra-quote a) (ra-quote b) (ra-quote c)))
              (ra-list (ra-quote c) (ra-quote b) (ra-quote a)))
(check-expect (ra-reverse (ra-list (ra-quote a) (ra-list (ra-quote b) (ra-quote c)) (ra-quote d) (ra-list (ra-quote e) (ra-list (ra-quote f)))))
              (ra-list (ra-list (ra-quote e) (ra-list (ra-quote f))) (ra-quote d) (ra-list (ra-quote b) (ra-quote c)) (ra-quote a)))

; list-tail
(check-expect (ra-list-tail (ra-list (ra-quote a) (ra-quote b) (ra-quote c) (ra-quote d)) 2)
              (ra-list (ra-quote c) (ra-quote d)))

; list-ref
(check-expect (ra-list-ref (ra-list (ra-quote a) (ra-quote b) (ra-quote c) (ra-quote d)) 2) (ra-quote c))

; list-set
(check-expect (list-set (ra-list (ra-quote a) (ra-quote b) (ra-quote c) (ra-quote d)) 2 (ra-quote x))
              (ra-list (ra-quote a) (ra-quote b) (ra-quote x) (ra-quote d)))

; list-ref/update
(let-values (((a b) 
              (list-ref/update (ra-list 7 8 9 10) 2 -)))
  (check-expect a 9)
  (check-expect b (ra-list 7 8 -9 10)))

; map
(check-expect (ra-map ra-cadr (ra-list (ra-list (ra-quote a) (ra-quote b)) (ra-list (ra-quote d) (ra-quote e)) (ra-list (ra-quote g) (ra-quote h))))
              (ra-list (ra-quote b) (ra-quote e) (ra-quote h)))
(check-expect (ra-map (lambda (n) (expt n n))
                   (ra-list 1 2 3 4 5))
              (ra-list 1 4 27 256 3125))
(check-expect (ra-map + (ra-list 1 2 3) (ra-list 4 5 6))
              (ra-list 5 7 9))

; for-each
(check-expect (let ((v (make-vector 5)))
                (ra-for-each (lambda (i)
                            (vector-set! v i (* i i)))
                          (ra-list 0 1 2 3 4))
                v)
              (ra-quote #(0 1 4 9 16)))

; random-access-list->linear-access-list
; linear-access-list->random-access-list
(check-expect (random-access-list->linear-access-list (ra-quote ())) (ra-quote ()))
(check-expect (linear-access-list->random-access-list (ra-quote ())) (ra-quote ()))

(check-expect (random-access-list->linear-access-list (ra-list 1 2 3))
              (list 1 2 3))

(check-expect (linear-access-list->random-access-list (list 1 2 3))
              (ra-list 1 2 3))

;;; ———————————————— 补充（iron-045）：原测试没有覆盖的 ra-c…r ————————————————
;; 深度为 4 的完全二叉树，叶子名记录从根到叶依次取 car（a）或 cdr（d）的路径（倒序书写）；
;; 对每个访问器，先用它走若干层，再一路取 ra-car 走到叶子，与期望的叶子比较。
(define tree4 (ra-quote ((((xaaaa . xdaaa) . (xadaa . xddaa)) . ((xaada . xdada) . (xadda . xddda))) . (((xaaad . xdaad) . (xadad . xddad)) . ((xaadd . xdadd) . (xaddd . xdddd))))))
(check (ra-car (ra-car (ra-caar tree4))) => 'xaaaa)
(check (ra-car (ra-car (ra-cadr tree4))) => 'xaaad)
(check (ra-car (ra-car (ra-cdar tree4))) => 'xaada)
(check (ra-car (ra-car (ra-cddr tree4))) => 'xaadd)
(check (ra-car (ra-caaar tree4)) => 'xaaaa)
(check (ra-car (ra-caadr tree4)) => 'xaaad)
(check (ra-car (ra-cadar tree4)) => 'xaada)
(check (ra-car (ra-caddr tree4)) => 'xaadd)
(check (ra-car (ra-cdaar tree4)) => 'xadaa)
(check (ra-car (ra-cdadr tree4)) => 'xadad)
(check (ra-car (ra-cddar tree4)) => 'xadda)
(check (ra-car (ra-cdddr tree4)) => 'xaddd)
(check (ra-caaaar tree4) => 'xaaaa)
(check (ra-caaadr tree4) => 'xaaad)
(check (ra-caadar tree4) => 'xaada)
(check (ra-caaddr tree4) => 'xaadd)
(check (ra-cadaar tree4) => 'xadaa)
(check (ra-cadadr tree4) => 'xadad)
(check (ra-caddar tree4) => 'xadda)
(check (ra-cadddr tree4) => 'xaddd)
(check (ra-cdaaar tree4) => 'xdaaa)
(check (ra-cdaadr tree4) => 'xdaad)
(check (ra-cdadar tree4) => 'xdada)
(check (ra-cdaddr tree4) => 'xdadd)
(check (ra-cddaar tree4) => 'xddaa)
(check (ra-cddadr tree4) => 'xddad)
(check (ra-cdddar tree4) => 'xddda)
(check (ra-cddddr tree4) => 'xdddd)

(check-report "std persistent random-access-lists")
