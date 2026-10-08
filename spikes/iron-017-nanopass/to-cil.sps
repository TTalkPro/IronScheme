;; 研究笔记 nanopass.md §8.2 的 to-cil 示例（iron-017）：在 stage0 上运行，Lcil 输出应与 Chez 一致。
;; 与原文的差别：导入 (rnrs) 与 IronScheme 的 format / pretty-print；IronScheme 的 format 不支持 ~{ ~}，
;; 改用 int64-list 拼接；方法体文本打印到标准输出而不是写文件。
(import (rnrs) (only (ironscheme) format pretty-print) (nanopass))

(define (int64? n) (and (integer? n) (exact? n)))
(define (prim? p) (memq p '(+ - <)))

;; 源语言：带 let / if 的整数表达式
(define-language Lsrc
  (terminals (symbol (x)) (int64 (n)) (prim (pr)))
  (Prog (p) (program (x* ...) e))
  (Expr (e)
    x
    (const n)
    (prim pr e0 e1)
    (if e0 e1 e2)
    (let ([x e0]) e1)))

;; 目标语言：CIL 指令（栈式）
(define-language Lcil
  (terminals (symbol (x l)) (int64 (n)))
  (Method (m) (method (x0* ...) (x1* ...) i* ...))   ; 参数 局部变量 指令
  (Instr (i)
    (ldarg x) (ldloc x) (stloc x) (ldc n)
    (add) (sub) (clt)
    (label l) (br l) (brfalse l) (ret)))

(define-parser parse-Lsrc Lsrc)

;; Lcil 指令构造函数（在输出语言上下文里构造，保证符合文法）
(define (ins op . args)
  (with-output-language (Lcil Instr)
    (case op
      [(ldarg) `(ldarg ,(car args))] [(ldloc) `(ldloc ,(car args))]
      [(stloc) `(stloc ,(car args))] [(ldc) `(ldc ,(car args))]
      [(add) `(add)] [(sub) `(sub)] [(clt) `(clt)] [(ret) `(ret)]
      [(label) `(label ,(car args))] [(br) `(br ,(car args))]
      [(brfalse) `(brfalse ,(car args))])))

(define-pass to-cil : Lsrc (ir) -> Lcil ()
  (definitions
    (define params '())
    (define locals '())
    (define counter 0)
    (define (fresh-label)
      (set! counter (+ counter 1))
      (string->symbol (format "L~a" counter))))
  (Prog : Prog (ir) -> Method ()
    [(program (,x* ...) ,e)
     (set! params x*)
     (let ([body (Expr e)])
       `(method (,x* ...) (,(reverse locals) ...) ,(append body (list (ins 'ret))) ...))])
  ;; 每个表达式生成"把它的值压栈"的指令序列
  (Expr : Expr (ir) -> * (i*)
    [,x (list (if (memq x params) (ins 'ldarg x) (ins 'ldloc x)))]
    [(const ,n) (list (ins 'ldc n))]
    [(prim ,pr ,e0 ,e1)
     (append (Expr e0) (Expr e1)
             (list (case pr [(+) (ins 'add)] [(-) (ins 'sub)] [(<) (ins 'clt)])))]
    [(if ,e0 ,e1 ,e2)
     (let ([else-l (fresh-label)] [end-l (fresh-label)])
       (append (Expr e0) (list (ins 'brfalse else-l))
               (Expr e1) (list (ins 'br end-l) (ins 'label else-l))
               (Expr e2) (list (ins 'label end-l))))]
    [(let ([,x ,e0]) ,e1)
     (set! locals (cons x locals))
     (append (Expr e0) (list (ins 'stloc x)) (Expr e1))]))

;; 把 Lcil 打印成 ILAsm 文本（普通 Scheme 函数，不是 pass）
(define (int64-list xs)
  (if (null? xs) ""
      (fold-left (lambda (acc x) (string-append acc ", int64 " (symbol->string x)))
                 (string-append "int64 " (symbol->string (car xs))) (cdr xs))))

(define (emit-ilasm m)
  (let* ([s (unparse-Lcil m)] [args (cadr s)] [locs (caddr s)] [instrs (cdddr s)])
    (define (op i)
      (case (car i)
        [(ldarg) (format "    ldarg ~a" (cadr i))]
        [(ldloc) (format "    ldloc ~a" (cadr i))]
        [(stloc) (format "    stloc ~a" (cadr i))]
        [(ldc) (format "    ldc.i8 ~a" (cadr i))]
        [(add sub) (format "    ~a" (car i))]
        [(clt) "    clt\n    conv.i8"]
        [(label) (format "  ~a:" (cadr i))]
        [(br brfalse) (format "    ~a ~a" (car i) (cadr i))]
        [(ret) "    ret"]))
    (string-append
      (format "  .method public static int64 Run(~a) cil managed {\n" (int64-list args))
      "    .maxstack 8\n"
      (if (null? locs) ""
          (format "    .locals init (~a)\n" (int64-list locs)))
      (apply string-append (map (lambda (i) (string-append (op i) "\n")) instrs))
      "  }\n")))

(define src
  '(program (a b)
     (let ([s (prim + a b)])
       (if (prim < s (const 10))
           (prim - (const 100) s)
           (prim + s s)))))

(define m (to-cil (parse-Lsrc src)))
(pretty-print (unparse-Lcil m))
(display (emit-ilasm m))
