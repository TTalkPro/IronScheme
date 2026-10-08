;; 研究笔记 nanopass.md §2 的示例（iron-017）：在 stage0 上运行，结果应与 Chez 一致
(import (rnrs) (only (ironscheme) void) (nanopass))
(define (datum? x) #t)

(define-language L0
  (terminals (symbol (x)) (datum (d)))
  (Expr (e)
    x
    (quote d)
    (if e0 e1 e2)
    (when e0 e1)
    (lambda (x* ...) e)
    (call e0 e1 ...)))

(define-language L1 (extends L0)
  (Expr (e) (- (when e0 e1))))          ; L1 = L0 去掉 when

(define-parser parse-L0 L0)

(define-pass remove-when : L0 (ir) -> L1 ()
  (Expr : Expr (ir) -> Expr ()
    [(when ,[e0] ,[e1]) `(if ,e0 ,e1 (quote ,(void)))]))

(write (unparse-L1 (remove-when (parse-L0 '(lambda (a) (call f (when a (quote 1))))))))
(newline)
