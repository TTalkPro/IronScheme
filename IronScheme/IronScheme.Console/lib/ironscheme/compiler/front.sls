#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; 前中端 pass（designs/03-compiler.md §4 第 2 ~ 5 步，iron-023）。
;;;
;;;   analyze            L0 上的一遍分析：每个 letrec 右边引用了哪些同组变量、哪些词法变量被赋值、
;;;                      哪些被 lambda 捕获（出现在某个 lambda 的自由变量中）
;;;   simplify-letrec    L0 → L1：recognize-let（((lambda (x …) body) e …) → let）与 letrec 拆分：
;;;                      连续的、未被赋值的 lambda 绑定成为一组 letrec；其余绑定成为 let；
;;;                      右边引用了"之后才绑定"的变量时，这些变量先绑定为未初始化，再按顺序 set!
;;;   cp0-lite           L1 → L1：if 的常量测试、begin 中无副作用的常量、少量纯原语的常量折叠
;;;   convert-assignments L1 → L2：既被赋值又被捕获的词法变量改为 Box
(library (ironscheme compiler front)
  (export analyze simplify-letrec cp0-lite convert-assignments
          analysis-assigned analysis-captured analysis-massigned)
  (import
    (rnrs)
    (only (ironscheme) void)
    (nanopass)
    (ironscheme compiler languages))

  ;; —— 小集合（无重复的列表）——
  (define (set-add x s) (if (memq x s) s (cons x s)))
  (define (set-union a b)
    (cond
      ((null? a) b)
      ((null? b) a)
      (else (fold-left (lambda (s x) (set-add x s)) b a))))
  (define (set-minus s xs) (filter (lambda (x) (not (memq x xs))) s))
  (define (union* ss) (fold-left set-union '() ss))

  (define-record-type analysis
    (fields assigned      ; eq 哈希表：被 set! 的词法变量
            captured      ; eq 哈希表：出现在某个 lambda 自由变量中的词法变量
            letrec-refs   ; eq 哈希表：letrec 右边（L0 记录）→ 它引用的同组变量
            massigned))   ; eq 哈希表：被 mset! 的库变量（除初始化外还被赋值，不能当作已知过程直接调用）

  (define (analyze ir)
    (let ((assigned (make-eq-hashtable))
          (captured (make-eq-hashtable))
          (letrec-refs (make-eq-hashtable))
          (massigned (make-eq-hashtable)))
      ;; 返回 e 中自由出现的词法变量
      (define (Expr e)
        (nanopass-case (L0 Expr) e
          [,x (list x)]
          [(quote ,d) '()]
          [(if ,e0 ,e1 ,e2) (union* (list (Expr e0) (Expr e1) (Expr e2)))]
          [(begin ,e* ... ,e) (union* (map Expr (cons e e*)))]
          [(set! ,x ,e) (hashtable-set! assigned x #t) (set-add x (Expr e))]
          [(gref ,s) '()]
          [(gset! ,s ,e) (Expr e)]
          [(mref ,x) '()]
          [(mset! ,x ,e) (hashtable-set! massigned x #t) (Expr e)]
          [(prim ,pr) '()]
          [(primcall ,pr ,e* ...) (union* (map Expr e*))]
          [(lambda ,nm ,cl* ...)
           (let ((fv (union* (map Clause cl*))))
             (for-each (lambda (x) (hashtable-set! captured x #t)) fv)
             fv)]
          [(letrec ([,x* ,e*] ...) ,body)
           (let ((fvs (map Expr e*)))
             (for-each (lambda (rhs fv) (hashtable-set! letrec-refs rhs (filter (lambda (x) (memq x x*)) fv))) e* fvs)
             (set-minus (union* (cons (Expr body) fvs)) x*))]
          [(library ,d ([,x* ,s* ,e*] ...) ,body) (union* (cons (Expr body) (map Expr e*)))]
          [(call ,e ,e* ...) (union* (map Expr (cons e e*)))]
          [(and ,e* ...) (union* (map Expr e*))]
          [(or ,e* ...) (union* (map Expr e*))]
          [(throw ,e) (Expr e)]
          [(break) '()]
          [(try-finally ,e0 ,e1) (set-union (Expr e0) (Expr e1))]
          [(clr-call ,d0 ,d1 ,st ,e* ...) (union* (map Expr e*))]
          [(clr-field-get ,d0 ,d1 ,st ,e* ...) (union* (map Expr e*))]
          [(clr-field-set ,d0 ,d1 ,st ,e* ...) (union* (map Expr e*))]
          [(clr-new ,d ,e* ...) (union* (map Expr e*))]
          [(clr-new-array ,d ,e) (Expr e)]
          [(clr-cast ,d ,e) (Expr e)]
          [(clr-is ,d ,e) (Expr e)]
          [(clr-type ,d) '()]
          [(clr-using ,d) '()]
          [(clr-reference ,d) '()]
          [(clr-namespaces) '()]
          [(unsupported ,d ,e* ...) (union* (map Expr e*))]))
      (define (Clause cl)
        (nanopass-case (L0 Clause) cl
          [(clause (,x* ...) ,x ,body)
           (set-minus (Expr body) (if x (cons x x*) x*))]))
      (Expr ir)
      (make-analysis assigned captured letrec-refs massigned)))

  (define (lambda-form? e)
    (nanopass-case (L0 Expr) e
      [(lambda ,nm ,cl* ...) #t]
      [else #f]))

;; —— simplify-letrec（含 recognize-let）：L0 → L1 ——
  ;;
  ;; letrec 的绑定 i 的右边引用了变量 v（v 在 i 处或之后绑定）时：若从 i 到 v 的绑定都是 lambda 且变量都未被赋值，
  ;; 它们会落在同一组 letrec 中，引用合法；否则 v 是"前向变量"：在整个结构外先绑定为未指定值，到它的位置再 set!。
  (define-pass simplify-letrec : L0 (ir an) -> L1 ()
    (definitions
      (define assigned (analysis-assigned an))
      (define (assigned? x) (hashtable-ref assigned x #f))
      (define refs (analysis-letrec-refs an))
      (define (groupable? x e) (and (lambda-form? e) (not (assigned? x))))
      ;; 从 x 到 v（含两端）的绑定都可并入同一组
      (define (same-run? x v x* e*)
        (let loop ((xs x*) (es e*) (started #f))
          (cond
            ((null? xs) #f)
            ((and (not started) (not (eq? (car xs) x))) (loop (cdr xs) (cdr es) #f))
            ((not (groupable? (car xs) (car es))) #f)
            ((eq? (car xs) v) #t)
            (else (loop (cdr xs) (cdr es) #t)))))
      (define (forward-vars x* e*)
        (let loop ((xs x*) (es e*) (acc '()))
          (if (null? xs)
              acc
              (let* ((r (hashtable-ref refs (car es) '()))
                     (bad (filter (lambda (v) (and (memq v xs) (not (same-run? (car xs) v x* e*)))) r)))
                (loop (cdr xs) (cdr es) (fold-left (lambda (s v) (set-add v s)) acc bad)))))))
    (Expr : Expr (ir) -> Expr ()
      [(call ,e ,[e*] ...)
       ;; recognize-let：((lambda (x …) body) e …) → (let ((x e) …) body)
       (or (nanopass-case (L0 Expr) e
             [(lambda ,nm ,cl)
              (nanopass-case (L0 Clause) cl
                [(clause (,x* ...) ,x ,body)
                 (and (not x) (= (length x*) (length e*))
                      `(let ([,x* ,e*] ...) ,(Expr body)))])]
             [else #f])
           `(call ,(Expr e) ,e* ...))]
      [(letrec ([,x* ,e*] ...) ,[body])
       (let ((forward (forward-vars x* e*)))
         (for-each (lambda (v) (hashtable-set! assigned v #t)) forward)
         (let ((inner
                (let loop ((xs x*) (es e*))
                  (cond
                    ((null? xs) body)
                    ((groupable? (car xs) (car es))
                     (let group ((xs xs) (es es) (gx '()) (ge '()))
                       (if (and (pair? xs) (groupable? (car xs) (car es)))
                           (group (cdr xs) (cdr es) (cons (car xs) gx) (cons (LambdaOf (car es)) ge))
                           `(letrec ([,(reverse gx) ,(reverse ge)] ...) ,(loop xs es)))))
                    ((memq (car xs) forward)
                     `(begin (set! ,(car xs) ,(Expr (car es))) ,(loop (cdr xs) (cdr es))))
                    (else
                     `(let ([,(car xs) ,(Expr (car es))]) ,(loop (cdr xs) (cdr es))))))))
           (if (null? forward)
               inner
               `(let ([,forward ,(map (lambda (v) `(quote ,(void))) forward)] ...) ,inner))))])
    (LambdaOf : LambdaExpr (ir) -> LambdaExpr ())
    (Expr ir))

  ;; —— cp0-lite：L1 → L1 ——
  (define (fixnum-value? d) (and (fixnum? d) #t))

  (define-pass cp0-lite : L1 (ir) -> L1 ()
    (definitions
      (define (const? e) (nanopass-case (L1 Expr) e [(quote ,d) #t] [else #f]))
      (define (const-value e) (nanopass-case (L1 Expr) e [(quote ,d) d] [else #f]))
      ;; 只折叠这些原语（原语表中都标为 pure），结果仍是可编码的常量
      (define (fold pr args)
        (and (for-all const? args)
             (let ((vs (map const-value args)))
               (case pr
                 ((not) (and (= (length vs) 1) (list (not (car vs)))))
                 ((null?) (and (= (length vs) 1) (list (null? (car vs)))))
                 ((pair?) (and (= (length vs) 1) (list (pair? (car vs)))))
                 ((eq?) (and (= (length vs) 2) (for-all (lambda (v) (or (symbol? v) (boolean? v) (null? v) (fixnum? v))) vs)
                             (list (eq? (car vs) (cadr vs)))))
                 ((fixnum?) (and (= (length vs) 1) (list (fixnum? (car vs)))))
                 (($fx+ $fx- $fx* $fx<? $fx<=? $fx>? $fx>=? $fx=?)
                  (and (= (length vs) 2) (for-all fixnum-value? vs)
                       (let ((a (car vs)) (b (cadr vs)))
                         (case pr
                           (($fx+) (let ((r (+ a b))) (and (fixnum? r) (list r))))
                           (($fx-) (let ((r (- a b))) (and (fixnum? r) (list r))))
                           (($fx*) (let ((r (* a b))) (and (fixnum? r) (list r))))
                           (($fx<?) (list (< a b)))
                           (($fx<=?) (list (<= a b)))
                           (($fx>?) (list (> a b)))
                           (($fx>=?) (list (>= a b)))
                           (else (list (= a b)))))))
                 (else #f))))))
    (Expr : Expr (ir) -> Expr ()
      [(if ,[e0] ,[e1] ,[e2])
       (if (const? e0) (if (const-value e0) e1 e2) `(if ,e0 ,e1 ,e2))]
      [(primcall ,pr ,[e*] ...)
       (let ((r (fold pr e*)))
         (if r `(quote ,(car r)) `(primcall ,pr ,e* ...)))]
      [(begin ,[e*] ... ,[e])
       (let ((e* (filter (lambda (x) (not (const? x))) e*)))
         (if (null? e*) e `(begin ,e* ... ,e)))]))

  ;; —— convert-assignments：L1 → L2 ——
  (define-pass convert-assignments : L1 (ir an) -> L2 ()
    (definitions
      (define (boxed? x)
        (and (hashtable-ref (analysis-assigned an) x #f)
             (hashtable-ref (analysis-captured an) x #f))))
    (Expr : Expr (ir) -> Expr ()
      [,x (if (boxed? x) `(unbox ,x) x)]
      [(set! ,x ,[e]) (if (boxed? x) `(set-box! ,x ,e) `(set! ,x ,e))]
      [(let ([,x* ,[e*]] ...) ,[body])
       `(let ([,x* ,(map (lambda (x e) (if (boxed? x) `(box ,e) e)) x* e*)] ...) ,body)])
    (Clause : Clause (ir) -> Clause ()
      [(clause (,x* ...) ,x ,[body])
       ;; 被装箱的形参：进入时把形参换成 Box
       (let ((bx (filter boxed? (if x (cons x x*) x*))))
         `(clause (,x* ...) ,x
            ,(if (null? bx)
                 body
                 `(begin ,(map (lambda (v) `(set! ,v (box ,v))) bx) ... ,body))))]))
  )
