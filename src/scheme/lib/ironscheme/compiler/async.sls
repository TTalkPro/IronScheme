#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; lower-async：L0 → L0，接在 parse-core 之后（designs/10-async.md §3.2，iron-051）。
;;; 只改 async-lambda 的体，把它整理成 codegen 能直接生成状态机的形状；单元里没有 async-lambda 时原样返回。
;;;
;;;   prep   D9  单个 letrec 绑定的 lambda，全部引用都是参数个数相符的尾调用 ⇒ (label f (x …) body fbody)，调用 ⇒ (jump f e …)
;;;          D10 立即调用的 lambda ⇒ let；dynamic-wind / with-exception-handler / call-with-values / call/cc 的字面 lambda 实参内联
;;;              （let 绑定的 lambda 若全部引用都在这些位置，也内联并删除绑定——parameterize 展开出来的 swap）
;;;   spill  D11 await 只留在语句位置：其他位置的子表达式从左到右 let 绑定到临时变量；含 await 的 and / or 改写成 if
;;;   check  D2  剩余的 await 若在普通 lambda 体内或 finally 里，报错并说明原因
;;;
;;; 嵌套的普通 lambda 的体不做任何变换（它们编译成普通过程）；嵌套的 async-lambda 各自独立处理。
;;; dynamic-wind 与 with-exception-handler 是 (boot exceptions) 里的 Scheme 过程，展开后是全局位置 (gref g$dynamic-wind$…)，
;;; 编译器看不到绑定身份，这里按位置符号的名字识别（见 10 §3.2 的说明）；call-with-values 与 call/cc 是原语（primcall）。
(library (ironscheme compiler async)
  (export lower-async lower-loops reset-fresh-names! loops-made)
  (import (rnrs) (only (ironscheme) void) (only (ironscheme unsafe) $get-environment-variable) (nanopass) (ironscheme compiler languages))

  ;; —— 通用工具 ——

  ;; 展开器的 gensym 名字 g$名字$… → 名字
  (define (pretty-name x)
    (let* ((s (symbol->string x))
           (n (string-length s)))
      (if (and (> n 2) (char=? (string-ref s 0) #\g) (char=? (string-ref s 1) #\$))
          (let loop ((i 2))
            (cond
              ((= i n) s)
              ((char=? (string-ref s i) #\$) (substring s 2 i))
              (else (loop (+ i 1)))))
          s)))

  (define (err msg node)
    (syntax-violation 'async-lambda (string-append "await outside async-lambda: " msg) (unparse-L0 node)))

  (define (clause-body cl)
    (nanopass-case (L0 Clause) cl [(clause (,x* ...) ,x ,body) body]))

  ;; 子表达式（不含绑定信息）
  (define (kids e)
    (nanopass-case (L0 Expr) e
      [,x '()]
      [(quote ,d) '()]
      [(if ,e0 ,e1 ,e2) (list e0 e1 e2)]
      [(begin ,e* ... ,e) (append e* (list e))]
      [(set! ,x ,e) (list e)]
      [(gref ,s) '()]
      [(gset! ,s ,e) (list e)]
      [(mref ,x) '()]
      [(mset! ,x ,e) (list e)]
      [(prim ,pr) '()]
      [(primcall ,pr ,e* ...) e*]
      [(lambda ,nm ,cl* ...) (map clause-body cl*)]
      [(async-lambda ,nm ,cl) (list (clause-body cl))]
      [(letrec ([,x* ,e*] ...) ,body) (append e* (list body))]
      [(let ([,x* ,e*] ...) ,body) (append e* (list body))]
      [(library ,d ([,x* ,s* ,e*] ...) ,body) (append e* (list body))]
      [(call ,e ,e* ...) (cons e e*)]
      [(and ,e* ...) e*]
      [(or ,e* ...) e*]
      [(throw ,e) (list e)]
      [(break) '()]
      [(try-finally ,e0 ,e1) (list e0 e1)]
      [(await ,e) (list e)]
      [(label ,x (,x* ...) ,body0 ,body1) (list body0 body1)]
      [(jump ,x ,e* ...) e*]
      [(escape-frame ,x ,body) (list body)]
      [(host-call ,d0 ,d1 ,st ,e* ...) e*]
      [(host-field-get ,d0 ,d1 ,st ,e* ...) e*]
      [(host-field-set ,d0 ,d1 ,st ,e* ...) e*]
      [(host-new ,d ,e* ...) e*]
      [(host-new-array ,d ,e) (list e)]
      [(host-cast ,d ,e) (list e)]
      [(host-is ,d ,e) (list e)]
      [(host-typeof ,d) '()]
      [(host-using ,d) '()]
      [(host-reference ,d) '()]
      [(host-namespaces) '()]
      [(unsupported ,d ,e* ...) e*]))

  ;; 单元里有没有 async-lambda 或 await：返回 async / await / #f（await 只在没有 async-lambda 时才需要报告）
  (define (scan e)
    (nanopass-case (L0 Expr) e
      [(async-lambda ,nm ,cl) 'async]
      [(await ,e) 'await]
      [else
       (let loop ((ks (kids e)) (r #f))
         (if (null? ks)
             r
             (let ((k (scan (car ks))))
               (if (eq? k 'async) 'async (loop (cdr ks) (or r k))))))]))

  ;; e 里有没有 await（不进入任何 lambda）
  (define (await-in? e)
    (nanopass-case (L0 Expr) e
      [(await ,e) #t]
      [(lambda ,nm ,cl* ...) #f]
      [(async-lambda ,nm ,cl) #f]
      [else (exists await-in? (kids e))]))

  ;; e 里有没有 await（进入普通 lambda，不进入 async-lambda）
  (define (await-deep? e)
    (nanopass-case (L0 Expr) e
      [(await ,e) #t]
      [(async-lambda ,nm ,cl) #f]
      [else (exists await-deep? (kids e))]))

  (define (var-ref? e v)
    (nanopass-case (L0 Expr) e [,x (eq? x v)] [else #f]))

  ;; 单子句、无剩余参数的 lambda：返回 (values 形参表 体)，否则 (values #f #f)
  (define (simple-lambda e)
    (nanopass-case (L0 Expr) e
      [(lambda ,nm ,cl)
       (nanopass-case (L0 Clause) cl
         [(clause (,x* ...) ,x ,body) (if x (values #f #f) (values x* body))])]
      [else (values #f #f)]))

  ;; 系统的过程：名字相符，且位置是 boot 镜像的（后缀 $%b，05 §7；用户自己定义的同名过程带进程戳，iron-034f 补）
  (define (gref-named? e name)
    (nanopass-case (L0 Expr) e
      [(gref ,s) (and (string=? (pretty-name s) name)
                      (let* ((str (symbol->string s)) (n (string-length str)))
                        (and (> n 3) (string=? (substring str (- n 3) n) "$%b"))))]
      [else #f]))

  ;; —— 入口 ——

  (define (lower-async ir)
    (if (scan ir)                                  ; 只有 await 没有 async-lambda 时 transform 报错
        (transform ir)
        ir))

  ;; 找到每个 async-lambda，先处理嵌套的，再整理它自己的体；async-lambda 之外的 await 报错
  (define-pass transform : L0 (ir) -> L0 ()
    (definitions
      (define depth 0))
    (Expr : Expr (ir) -> Expr ()
      [(await ,e)
       (when (= depth 0) (err "not inside an async-lambda" ir))
       `(await ,(Expr e))]
      [(async-lambda ,nm ,cl)
       (nanopass-case (L0 Clause) cl
         [(clause (,x* ...) ,x ,body)
          (set! depth (+ depth 1))
          (let ((b (Expr body)))
            (set! depth (- depth 1))
            `(async-lambda ,nm (clause (,x* ...) ,x ,(async-body b))))])]))

  (define (async-body body)
    (let* ((reasons (make-eq-hashtable))
           (p (prep body reasons))
           (s (spill p)))
      (check s reasons)
      s))

  ;; —— D9 / D10：prep ——

  (define counter 0)
  ;; 临时变量名按编译单元从头编号（驱动在每个单元开始时调用），输出确定
  (define (reset-fresh-names!) (set! counter 0))
  (define (fresh name)
    (set! counter (+ counter 1))
    (string->symbol (string-append name "%" (number->string counter))))

  ;; v 在 e 中的引用是否都是参数个数为 n 的尾调用。返回 #f（合格）或原因符号：
  ;; value（当值使用）、arity（参数个数不符）、non-tail（非尾位置调用）、closure（在嵌套 lambda 里引用）、assigned
  (define (check-refs v n e tail? in-lambda?)
    (define (r e tail?) (check-refs v n e tail? in-lambda?))
    (define (r* es) (exists (lambda (e) (r e #f)) es))
    (nanopass-case (L0 Expr) e
      [,x (and (eq? x v) (if in-lambda? 'closure 'value))]
      [(set! ,x ,e) (if (eq? x v) 'assigned (r e #f))]
      [(call ,e ,e* ...)
       (cond
         ((var-ref? e v)
          (cond
            (in-lambda? 'closure)
            ((not (= (length e*) n)) 'arity)
            ((not tail?) 'non-tail)
            (else (r* e*))))
         (else
          ;; 立即调用的 lambda：体在尾位置
          (let-values (((x* body) (simple-lambda e)))
            (if (and x* (= (length x*) (length e*)))
                (or (r* e*) (r body tail?))
                (or (r e #f) (r* e*))))))]
      [(if ,e0 ,e1 ,e2) (or (r e0 #f) (r e1 tail?) (r e2 tail?))]
      [(begin ,e* ... ,e) (or (r* e*) (r e tail?))]
      [(let ([,x* ,e*] ...) ,body) (or (r* e*) (r body tail?))]
      [(letrec ([,x* ,e*] ...) ,body) (or (r* e*) (r body tail?))]
      [(lambda ,nm ,cl* ...)
       (exists (lambda (cl) (check-refs v n (clause-body cl) #f #t)) cl*)]
      [(async-lambda ,nm ,cl) (check-refs v n (clause-body cl) #f #t)]
      [else (r* (kids e))]))

  ;; 把 e 的尾位置上对 v 的调用改成 jump
  (define (jumpify v node)
    (with-output-language (L0 Expr)
      (nanopass-case (L0 Expr) node
        [(call ,e ,e* ...)
         (cond
           ((var-ref? e v) `(jump ,v ,e* ...))
           (else
            (let-values (((x* body) (simple-lambda e)))
              (if (and x* (= (length x*) (length e*)))
                  `(call (lambda #f (clause (,x* ...) #f ,(jumpify v body))) ,e* ...)
                  node))))]
        [(if ,e0 ,e1 ,e2) `(if ,e0 ,(jumpify v e1) ,(jumpify v e2))]
        [(begin ,e* ... ,e) `(begin ,e* ... ,(jumpify v e))]
        [(let ([,x* ,e*] ...) ,body) `(let ([,x* ,e*] ...) ,(jumpify v body))]
        [(letrec ([,x* ,e*] ...) ,body) `(letrec ([,x* ,e*] ...) ,(jumpify v body))]
        [else node])))

  ;; 内联位置：返回 (values 槽位实参表 槽位要求的参数个数表 其余实参表)，不是内联形式时 (values #f #f #f)
  (define (inline-slots e)
    (nanopass-case (L0 Expr) e
      [(call ,e ,e* ...)
       (cond
         ((and (gref-named? e "dynamic-wind") (= (length e*) 3)) (values e* '(0 0 0) '()))
         ((and (gref-named? e "with-exception-handler") (= (length e*) 2)) (values (list (cadr e*)) '(0) (list (car e*))))
         (else (values #f #f #f)))]
      [(primcall ,pr ,e* ...)
       (cond
         ((and (eq? pr 'call-with-values) (= (length e*) 2)) (values (list (car e*)) '(0) (list (cadr e*))))
         ((and (memq pr '(call/cc call-with-current-continuation)) (= (length e*) 1)) (values e* '(1) '()))
         (else (values #f #f #f)))]
      [else (values #f #f #f)]))

  ;; v（绑定到形参个数为 k 的 lambda）的全部引用是否都在内联位置、且槽位要求的参数个数相符
  (define (refs-inlinable? v k e)
    (define (ok? e)
      (cond
        ((var-ref? e v) #f)
        (else
         (let-values (((slots arities others) (inline-slots e)))
           (if slots
               (and (for-all (lambda (s a) (if (var-ref? s v) (= a k) (ok? s))) slots arities)
                    (for-all ok? others)
                    ;; 操作符本身
                    (nanopass-case (L0 Expr) e [(call ,e ,e* ...) (ok? e)] [else #t]))
               (nanopass-case (L0 Expr) e
                 [(set! ,x ,e) (and (not (eq? x v)) (ok? e))]
                 [else (for-all ok? (kids e))]))))))
    (ok? e))

  (define-pass prep : L0 (ir reasons) -> L0 ()
    (definitions
      ;; 要代入内联位置的 let 绑定 lambda：变量 → lambda 节点
      (define inline-env (make-eq-hashtable))
      ;; 槽位实参：字面 lambda，或 inline-env 里的变量；返回 (values 形参表 体) 或 (values #f #f)
      (define (slot-lambda e)
        (nanopass-case (L0 Expr) e
          [,x (let ((le (hashtable-ref inline-env x #f))) (if le (simple-lambda le) (values #f #f)))]
          [else (simple-lambda e)]))
      (define (thunk-body e)
        (let-values (((x* body) (slot-lambda e)))
          (and x* (null? x*) body)))
      (define (named-letrec? e)
        (nanopass-case (L0 Expr) e
          [(letrec ([,x* ,e*] ...) ,body)
           (and (= (length x*) 1) (var-ref? body (car x*)) (cons (car x*) (car e*)))]
          [else #f])))
    (Expr : Expr (ir) -> Expr ()
      ;; 普通 lambda 的体不动；嵌套的 async-lambda 已经处理过
      [(lambda ,nm ,cl* ...) ir]
      [(async-lambda ,nm ,cl) ir]
      [(call ,e ,e* ...)
       (let-values (((x* body) (simple-lambda e)))
         (cond
           ;; 立即调用的 lambda → let；绑定的 lambda 若全部引用都在内联位置，代入并删除绑定（D10）
           ((and x* (= (length x*) (length e*)))
            (let ((rhs* (map Expr e*)))
              (let loop ((xs x*) (rs rhs*) (keep-x '()) (keep-r '()))
                (cond
                  ((null? xs)
                   (let ((b (Expr body)))
                     (if (null? keep-x) b `(let ([,(reverse keep-x) ,(reverse keep-r)] ...) ,b))))
                  (else
                   (let-values (((p* lb) (simple-lambda (car rs))))
                     (if (and p* (refs-inlinable? (car xs) (length p*) body))
                         (begin
                           (hashtable-set! inline-env (car xs) (car rs))
                           (loop (cdr xs) (cdr rs) keep-x keep-r))
                         (loop (cdr xs) (cdr rs) (cons (car xs) keep-x) (cons (car rs) keep-r)))))))))
           ;; ((letrec ((f le)) f) e …) → (letrec ((f le)) (f e …))：命名 let 的形状
           ((named-letrec? e)
            => (lambda (f.le)
                 (Expr `(letrec ([,(car f.le) ,(cdr f.le)]) (call ,(car f.le) ,e* ...)))))
           ;; (dynamic-wind (lambda () b) (lambda () body) (lambda () a)) → (begin b (try-finally body a))
           ((and (gref-named? e "dynamic-wind") (= (length e*) 3)
                 (thunk-body (car e*)) (thunk-body (cadr e*)) (thunk-body (caddr e*)))
            `(begin ,(Expr (thunk-body (car e*)))
                    (try-finally ,(Expr (thunk-body (cadr e*))) ,(Expr (thunk-body (caddr e*))))))
           ;; (with-exception-handler h (lambda () body)) → 保存 / 设置 / 恢复处理器栈
           ((and (gref-named? e "with-exception-handler") (= (length e*) 2) (thunk-body (cadr e*)))
            (let ((old (fresh "handlers")))
              `(let ([,old (primcall $current-handlers)])
                 (begin
                   (primcall $set-current-handlers! (primcall cons ,(Expr (car e*)) ,old))
                   (try-finally ,(Expr (thunk-body (cadr e*)))
                                (primcall $set-current-handlers! ,old))))))
           (else `(call ,(Expr e) ,(map Expr e*) ...))))]
      [(primcall ,pr ,e* ...)
       (cond
         ;; (call-with-values (lambda () body) consumer) → (let ((t body)) (call-with-values (lambda () t) consumer))
         ((and (eq? pr 'call-with-values) (= (length e*) 2) (thunk-body (car e*)))
          (let ((t (fresh "values")))
            `(let ([,t ,(Expr (thunk-body (car e*)))])
               (primcall call-with-values (lambda #f (clause () #f ,t)) ,(Expr (cadr e*))))))
         ;; (call/cc (lambda (k) body)) → (escape-frame k body)
         ((and (memq pr '(call/cc call-with-current-continuation)) (= (length e*) 1))
          (let-values (((x* body) (slot-lambda (car e*))))
            (if (and x* (= (length x*) 1))
                `(escape-frame ,(car x*) ,(Expr body))
                `(primcall ,pr ,(map Expr e*) ...))))
         (else `(primcall ,pr ,(map Expr e*) ...)))]
      [(letrec ([,x* ,e*] ...) ,body)
       ;; D9：单个绑定、全部引用都是参数个数相符的尾调用 → label / jump
       (let-values (((p* fbody) (if (= (length x*) 1) (simple-lambda (car e*)) (values #f #f))))
         (cond
           ((and p*
                 (let ((f (car x*)) (n (length p*)))
                   (let ((bad (or (check-refs f n body #t #f) (check-refs f n fbody #t #f))))
                     (when bad (hashtable-set! reasons (car e*) bad))
                     (not bad))))
            (let ((f (car x*)))
              `(label ,f (,p* ...) ,(Expr (jumpify f body)) ,(Expr (jumpify f fbody)))))
           (else
            (when (> (length x*) 1)
              (for-each (lambda (e) (hashtable-set! reasons e 'multi)) e*))
            `(letrec ([,x* ,(map Expr e*)] ...) ,(Expr body)))))]))

  ;; —— D11：spill ——

  (define (trivial? e)
    (nanopass-case (L0 Expr) e
      [(quote ,d) #t]
      [(prim ,pr) #t]
      [else #f]))

  ;; 值位置的一个子表达式：含 await 时先绑定到临时变量
  (define (V1 e k)
    (with-output-language (L0 Expr)
      (if (await-in? e)
          (let ((t (fresh "t")))
            `(let ([,t ,(S e)]) ,(k t)))
          (k e))))

  ;; 值位置的一组子表达式：任一含 await 时全部从左到右绑定（求值顺序不变）
  (define (V* es k)
    (with-output-language (L0 Expr)
      (if (exists await-in? es)
          (let loop ((es es) (ts '()))
            (cond
              ((null? es) (k (reverse ts)))
              ((trivial? (car es)) (loop (cdr es) (cons (car es) ts)))
              (else
               (let ((t (fresh "t")))
                 `(let ([,t ,(S (car es))]) ,(loop (cdr es) (cons t ts)))))))
          (k es))))

  (define (and->if es)
    (with-output-language (L0 Expr)
      (cond
        ((null? es) `(quote #t))
        ((null? (cdr es)) (car es))
        (else `(if ,(car es) ,(and->if (cdr es)) (quote #f))))))

  (define (or->if es)
    (with-output-language (L0 Expr)
      (cond
        ((null? es) `(quote #f))
        ((null? (cdr es)) (car es))
        (else
         (let ((t (fresh "t")))
           `(let ([,t ,(car es)]) (if ,t ,t ,(or->if (cdr es)))))))))

  ;; 语句位置
  (define (S e)
    (with-output-language (L0 Expr)
      (nanopass-case (L0 Expr) e
        [(if ,e0 ,e1 ,e2) (V1 e0 (lambda (t) `(if ,t ,(S e1) ,(S e2))))]
        [(begin ,e* ... ,e) `(begin ,(map S e*) ... ,(S e))]
        [(set! ,x ,e) (V1 e (lambda (t) `(set! ,x ,t)))]
        [(gset! ,s ,e) (V1 e (lambda (t) `(gset! ,s ,t)))]
        [(mset! ,x ,e) (V1 e (lambda (t) `(mset! ,x ,t)))]
        [(primcall ,pr ,e* ...) (V* e* (lambda (ts) `(primcall ,pr ,ts ...)))]
        [(letrec ([,x* ,e*] ...) ,body) `(letrec ([,x* ,(map S e*)] ...) ,(S body))]
        [(let ([,x* ,e*] ...) ,body) `(let ([,x* ,(map S e*)] ...) ,(S body))]
        [(call ,e ,e* ...) (V* (cons e e*) (lambda (ts) `(call ,(car ts) ,(cdr ts) ...)))]
        [(and ,e* ...) (if (exists await-in? e*) (S (and->if e*)) e)]
        [(or ,e* ...) (if (exists await-in? e*) (S (or->if e*)) e)]
        [(throw ,e) (V1 e (lambda (t) `(throw ,t)))]
        [(try-finally ,e0 ,e1) `(try-finally ,(S e0) ,e1)]
        [(await ,e) (V1 e (lambda (t) `(await ,t)))]
        [(label ,x (,x* ...) ,body0 ,body1) `(label ,x (,x* ...) ,(S body0) ,(S body1))]
        [(jump ,x ,e* ...) (V* e* (lambda (ts) `(jump ,x ,ts ...)))]
        [(escape-frame ,x ,body) `(escape-frame ,x ,(S body))]
        [(host-call ,d0 ,d1 ,st ,e* ...) (V* e* (lambda (ts) `(host-call ,d0 ,d1 ,st ,ts ...)))]
        [(host-field-get ,d0 ,d1 ,st ,e* ...) (V* e* (lambda (ts) `(host-field-get ,d0 ,d1 ,st ,ts ...)))]
        [(host-field-set ,d0 ,d1 ,st ,e* ...) (V* e* (lambda (ts) `(host-field-set ,d0 ,d1 ,st ,ts ...)))]
        [(host-new ,d ,e* ...) (V* e* (lambda (ts) `(host-new ,d ,ts ...)))]
        [(host-new-array ,d ,e) (V1 e (lambda (t) `(host-new-array ,d ,t)))]
        [(host-cast ,d ,e) (V1 e (lambda (t) `(host-cast ,d ,t)))]
        [(host-is ,d ,e) (V1 e (lambda (t) `(host-is ,d ,t)))]
        [(unsupported ,d ,e* ...) (V* e* (lambda (ts) `(unsupported ,d ,ts ...)))]
        [else e])))

  (define (spill e) (S e))

  ;; —— D2：check ——

  (define (reason-message r)
    (case r
      ((closure) "the loop procedure is captured by a nested lambda")
      ((non-tail) "the loop procedure is called in non-tail position (only tail-recursive local loops may await)")
      ((arity) "the loop procedure is called with a different number of arguments")
      ((value) "the loop procedure is used as a value")
      ((assigned) "the loop procedure is assigned")
      ((multi) "mutually recursive local procedures cannot await")
      (else "await inside a nested lambda (for-each callbacks etc.); only the async-lambda body and the forms it inlines may await")))

  (define (check e reasons)
    (nanopass-case (L0 Expr) e
      [(lambda ,nm ,cl* ...)
       (when (exists (lambda (cl) (await-deep? (clause-body cl))) cl*)
         (err (reason-message (hashtable-ref reasons e #f)) e))]
      [(async-lambda ,nm ,cl) (void)]
      [(try-finally ,e0 ,e1)
       (when (await-in? e1)
         (err "await in a finally part (dynamic-wind after thunk, or handler cleanup)" e))
       (check e0 reasons)
       (check e1 reasons)]
      [else (for-each (lambda (k) (check k reasons)) (kids e))]))

  ;; —— lower-loops（iron-034b）：D9 推广到全部代码 ——
  ;; 单绑定 letrec 的 lambda，全部引用都是参数个数相符的尾调用（相对于 letrec 的体或 lambda 自己的体）时，
  ;; 改为 (label f (x …) body fbody) 与 (jump f e …)：命名 let 与 do 不再各生成一个过程类，循环变量是局部变量。
  ;; 只做 D9，不做 D10 / D11；跨 try、跨嵌套 lambda 的调用不算尾调用（check-refs），jump 不会跳出 try 区域。
  ;; ((letrec ((f le)) f) e …)（命名 let 的展开形状）先归一成 (letrec ((f le)) (f e …))。
  ;; 至今生成的 label 个数：编译驱动据此只对含循环的形式做类型推断（codegen 的 loop-forms）
  (define loops-count 0)
  ;; 测量开关：IRONSCHEME_NO_034 含 letlab 时不做 let 的降级
  (define let-labels? (let ((v ($get-environment-variable "IRONSCHEME_NO_034")))
                        (not (and (string? v) (let loop ((i 0)) (and (<= (+ i 6) (string-length v))
                                                                      (or (string=? (substring v i (+ i 6)) "letlab") (loop (+ i 1)))))))))
  (define (loops-made) loops-count)

  (define-pass lower-loops : L0 (ir) -> L0 ()
    (definitions
      ;; (lambda () body) → body，否则 #f
      (define (thunk-literal? e)
        (nanopass-case (L0 Expr) e
          [(lambda ,nm ,cl)
           (nanopass-case (L0 Clause) cl [(clause (,x* ...) ,x ,body) (and (null? x*) (not x) body)])]
          [else #f]))
      (define (consumer-literal? e)
        (nanopass-case (L0 Expr) e [(lambda ,nm ,cl) #t] [else #f]))
      (define (consumer-parts e)
        (nanopass-case (L0 Expr) e
          [(lambda ,nm ,cl) (nanopass-case (L0 Clause) cl [(clause (,x* ...) ,x ,body) (values nm x* x body)])]))
      ;; let 绑定的单子句 lambda，体里只在尾位置按相符的参数个数调用（不作为值、不在嵌套 lambda 里）：
      ;; 变成 label（nanopass 生成的处理器每个子句一个 rhs / else-th 闭包，每次调用都分配；变成 label 后不再分配）。
      ;; let 的右边看不到同一 let 绑定的名字，所以 lambda 体里不会跳到兄弟 label；label 依次嵌套在体外，
      ;; 其余绑定照旧放在最外层的 let 里（先求值，与原来顺序相同；lambda 的创建没有副作用）
      (define (lower-let x* e* body)
        (let loop ((xs x*) (es e*) (keep-x '()) (keep-e '()) (labels '()))
          (if (pair? xs)
              (let-values (((p* fbody) (simple-lambda (car es))))
                (if (and let-labels? p* (not (check-refs (car xs) (length p*) body #t #f)))
                    (loop (cdr xs) (cdr es) keep-x keep-e (cons (list (car xs) p* fbody) labels))
                    (loop (cdr xs) (cdr es) (cons (car xs) keep-x) (cons (car es) keep-e) labels)))
              (with-output-language (L0 Expr)
                (if (null? labels)
                    `(let ([,x* ,(map Expr e*)] ...) ,(Expr body))
                    (let* ((jbody (fold-left (lambda (b l) (jumpify (car l) b)) body labels))
                           (inner (fold-left (lambda (b l)
                                               (set! loops-count (+ loops-count 1))
                                               `(label ,(car l) (,(cadr l) ...) ,b ,(Expr (caddr l))))
                                             (Expr jbody)
                                             labels)))
                      (if (null? keep-x)
                          inner
                          `(let ([,(reverse keep-x) ,(map Expr (reverse keep-e))] ...) ,inner))))))))
      (define (named-letrec? e)
        (nanopass-case (L0 Expr) e
          [(letrec ([,x* ,e*] ...) ,body)
           (and (= (length x*) 1) (var-ref? body (car x*)) (cons (car x*) (car e*)))]
          [else #f])))
    (Expr : Expr (ir) -> Expr ()
      [(call ,e ,e* ...)
       (cond
         ((named-letrec? e)
          => (lambda (f.le)
               (Expr `(letrec ([,(car f.le) ,(cdr f.le)]) (call ,(car f.le) ,e* ...)))))
         (else
          (let-values (((p* b) (simple-lambda e)))
            (if (and p* (= (length p*) (length e*)))
                (lower-let p* e* b)                  ; 立即调用的 lambda 就是 let
                `(call ,(Expr e) ,(map Expr e*) ...)))))]
      ;; D6：(call-with-values (lambda () p) (lambda (x … [. r]) b)) →
      ;;   (let ((t p)) (if (个数相符 t) (let ((x ($values-ref t i)) … [(r ($values-tail t n))]) b) 原来的形式报错))
      ;; 错误分支用同名、同形参的空体 lambda 当消费者，由它报与原来相同的参数个数错误
      [(primcall ,pr ,e* ...)
       (guard (and (eq? pr 'call-with-values) (= (length e*) 2) (thunk-literal? (car e*)) (consumer-literal? (cadr e*))))
       (let-values (((nm x* rest cbody) (consumer-parts (cadr e*))))
         (let* ((t (fresh "values"))
                (n (length x*))
                (count `(primcall $values-count ,t))
                (test (if rest `(primcall $fx>=? ,count (quote ,n)) `(primcall $fx=? ,count (quote ,n))))
                (refs (let loop ((i 0) (xs x*))
                        (if (null? xs) '() (cons `(primcall $values-ref ,t (quote ,i)) (loop (+ i 1) (cdr xs))))))
                (bind-x* (if rest (append x* (list rest)) x*))
                (bind-e* (if rest (append refs (list `(primcall $values-tail ,t (quote ,n)))) refs)))
           `(let ([,t ,(Expr (thunk-literal? (car e*)))])
              (if ,test
                  (let ([,bind-x* ,bind-e*] ...) ,(Expr cbody))
                  (primcall call-with-values
                            (lambda #f (clause () #f ,t))
                            (lambda ,nm (clause (,(map (lambda (x) (fresh "arg")) x*) ...) ,(and rest (fresh "rest")) (quote #f))))))))]
      ;; let（也包括立即调用的 lambda，即展开器的 let）：见 definitions 中的 lower-let
      [(let ([,x* ,e*] ...) ,body) (lower-let x* e* body)]
      [(letrec ([,x* ,e*] ...) ,body)
       (let-values (((p* fbody) (if (= (length x*) 1) (simple-lambda (car e*)) (values #f #f))))
         (if (and p*
                  (let ((f (car x*)) (n (length p*)))
                    (not (or (check-refs f n body #t #f) (check-refs f n fbody #t #f)))))
             (let ((f (car x*)))
               (set! loops-count (+ loops-count 1))
               `(label ,f (,p* ...) ,(Expr (jumpify f body)) ,(Expr (jumpify f fbody))))
             `(letrec ([,x* ,(map Expr e*)] ...) ,(Expr body))))])))
