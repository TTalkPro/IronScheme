#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; 代码生成：L3 → Lcil（designs/03-compiler.md §4 第 7 ~ 15 步，§5 ~ §7；iron-024 ~ iron-026）。
;;;
;;; 第一版把设计中的 convert-closures、lift-to-classes、lower-loops、lower-calls、lower-interop、
;;; normalize-context、lift-try、linearize 合在一遍按上下文生成栈式代码的过程里完成：
;;;
;;; - 每个 lambda 一个 Procedure 子类（有剩余参数子句时为 VariadicProcedure）。子句体是方法 C0、C1 …；
;;;   Invoke0..4 / InvokeN 按 case-lambda 的子句顺序转发（02 §4）。
;;;   没有自由变量的 lambda：子句方法是静态方法，实例是单例（静态字段 Instance）。
;;;   有自由变量的 lambda：自由变量是实例字段 c0、c1 …；letrec 绑定的 lambda 引用自己时用 this。
;;; - 库变量（library-letrec*）是模块类型的静态字段。库变量绑定的、没有自由变量且不被再赋值的 lambda
;;;   是"已知过程"：模块入口先创建全部已知过程并写入字段与位置（与旧系统的静态链接一致，允许跨库前向调用），
;;;   参数个数相符的调用直接 call 静态子句方法。
;;; - 自尾调用（自己是 letrec 变量或已知过程）在尾位置且参数个数与当前子句相同时，重新赋参数并跳回方法开头。
;;; - 其余尾位置调用加 tail. 前缀；try 区域内不加（03 §5）。
;;; - 上下文：value（结果留在栈上）、effect（不留）、test（留 CLR bool）、tail（返回）。
;;;   谓词原语在 test 上下文直接生成比较。
;;; - try 要求进入时求值栈为空：多操作数的形式中，若排在后面的操作数含 try，先把各操作数存入临时变量（lift-try）。
;;; - 常量：fixnum、布尔、'()、字符、字符串直接生成；其余进常量表（iron-020 的编码）。
(library (ironscheme compiler codegen)
  (export generate-unit canonical-gensyms)
  (import
    (rnrs)
    (only (ironscheme) void unspecified? make-parameter gensym)
    (nanopass)
    (ironscheme compiler languages)
    (ironscheme compiler primitives)
    (ironscheme compiler constants)
    (only (ironscheme clr) clr-is))

  ;; 规范 gensym 名（iron-030，designs/05-bootstrap.md §7 的后备方案）：设为 #t 时，常量表中本进程生成的 gensym
  ;; （名字以本进程的 TICKS 后缀结尾）按首次出现的顺序改名为 g$名字$序号$%b。构建过程本身用非确定性 gensym，
  ;; 名字带进程时间戳，与运行中系统（上一级镜像）里的名字绝不冲突；产物中的名字只取决于输入。
  (define canonical-gensyms (make-parameter #f))

  (define (process-gensym-suffix)
    (let* ((s (symbol->string (gensym)))
           (n (string-length s)))
      (let loop ((i (- n 1)))
        (if (char=? (string-ref s i) #\$) (substring s i n) (loop (- i 1))))))

  ;; 对编码后的常量（中立编码 S 表达式）改名
  (define (canonicalize-encodings encs)
    (let* ((suffix (process-gensym-suffix))
           (k (string-length suffix))
           (renamed (make-hashtable string-hash string=?))
           (next 0))
      (define (rename s)
        (let ((n (string-length s)))
          (if (and (> n (+ k 2)) (char=? (string-ref s 0) #\g) (char=? (string-ref s 1) #\$)
                   (string=? (substring s (- n k) n) suffix))
              (or (hashtable-ref renamed s #f)
                  (let ((new (string-append (substring s 0 (gensym-name-end s)) "$" (number->string next) "$%b")))
                    (set! next (+ next 1))
                    (hashtable-set! renamed s new)
                    new))
              s)))
      (define (walk x)
        (cond
          ((and (pair? x) (memq (car x) '(sym gensym)) (pair? (cdr x)) (string? (cadr x)))
           (list (car x) (rename (cadr x))))
          ((pair? x) (map walk x))
          (else x)))
      (map walk encs)))

  ;; "g$名字$序号$后缀" 中 "g$名字" 的结束位置
  (define (gensym-name-end s)
    (let loop ((i 2))
      (cond
        ((= i (string-length s)) i)
        ((char=? (string-ref s i) #\$) i)
        (else (loop (+ i 1))))))

  (define obj "System.Object")
  (define proc-type "IronScheme.Core.Procedure")
  (define variadic-type "IronScheme.Core.VariadicProcedure")
  (define cons-type "IronScheme.Core.Cons")
  (define box-type "IronScheme.Core.Box")
  (define symbol-type "IronScheme.Core.Symbol")
  (define rt-type "IronScheme.Core.RT")
  (define calls-type "IronScheme.Core.Calls")

  (define (objs n) (if (= n 0) '() (cons obj (objs (- n 1)))))

  ;; ———————————————— 编译单元 ————————————————

  (define-record-type unit
    (fields name                 ; 程序集名
            module               ; 模块类型名
            (mutable classes)    ; 已生成的类型（逆序）
            (mutable consts)     ; 常量（逆序）
            (mutable nconsts)
            const-index          ; eq 哈希表：常量 → 下标
            (mutable namespaces)
            (mutable references)
            (mutable mfields)    ; 模块静态字段名（逆序）
            mfield-of            ; eq 哈希表：库变量 → 字段名
            known                ; eq 哈希表：库变量 → known 记录（已知过程）
            (mutable prelink)    ; ((类名 字段名 位置符号或 #f) …)
            (mutable counter)
            massigned))

  (define-record-type known
    (fields class clauses))      ; clauses：((固定参数个数 . 剩余?) …)

  (define (next-id! u)
    (let ((n (unit-counter u)))
      (unit-counter-set! u (+ n 1))
      n))

  (define (add-class! u c) (unit-classes-set! u (cons c (unit-classes u))))

  ;; eq 哈希表是 .NET Hashtable，按 Equals 比较：0.0 与 -0.0（及含它们的复数）相等，含 -0.0 的常量不去重
  (define (neg-zero? x) (and (flonum? x) (flzero? x) (fl<? (fl/ 1.0 x) 0.0)))

  (define (signed-zero-constant? d)
    (and (number? d) (inexact? d)
         (or (neg-zero? d)
             (and (not (real? d)) (or (neg-zero? (real-part d)) (neg-zero? (imag-part d)))))))

  (define (constant-index! u d)
    (or (and (not (signed-zero-constant? d)) (hashtable-ref (unit-const-index u) d #f))
        (let ((k (unit-nconsts u)))
          (unless (signed-zero-constant? d) (hashtable-set! (unit-const-index u) d k))
          (unit-consts-set! u (cons d (unit-consts u)))
          (unit-nconsts-set! u (+ k 1))
          k)))

  (define (add-namespace! u ns)
    (unless (member ns (unit-namespaces u))
      (unit-namespaces-set! u (append (unit-namespaces u) (list ns)))))

  (define (add-reference! u r)
    (unless (member r (unit-references u))
      (unit-references-set! u (append (unit-references u) (list r)))))

  (define (mfield! u x)
    (or (hashtable-ref (unit-mfield-of u) x #f)
        (let ((f (string-append "m" (number->string (length (unit-mfields u))) "$" (sanitize (pretty x)))))
          (hashtable-set! (unit-mfield-of u) x f)
          (unit-mfields-set! u (cons f (unit-mfields u)))
          f)))

  ;; 类型名只用安全字符：反射按名字查类型时 . + , [ ] & * 等有特殊含义
  (define (sanitize s)
    (let ((s (if (symbol? s) (symbol->string s) s)))
      (list->string
        (map (lambda (c)
               (if (or (char-alphabetic? c) (char-numeric? c) (memv c '(#\$ #\_ #\- #\? #\! #\< #\> #\= #\* #\%)))
                   (if (memv c '(#\* #\< #\>)) #\_ c)
                   #\_))
             (string->list s)))))

  (define (pretty x)
    (let* ((s (if (symbol? x) (symbol->string x) x))
           (n (string-length s)))
      (if (and (> n 2) (char=? (string-ref s 0) #\g) (char=? (string-ref s 1) #\$))
          (let loop ((i 2))
            (cond
              ((= i n) s)
              ((char=? (string-ref s i) #\$) (substring s 2 i))
              (else (loop (+ i 1)))))
          s)))

  ;; ———————————————— 方法上下文 ————————————————

  (define-record-type mctx
    (fields unit
            class                ; 所属类型名
            static?
            vars                 ; eq 哈希表：变量 → (arg . i) | (local . i) | (field . 名字) | (self)
            (mutable locals)     ; 局部变量类型（逆序）
            (mutable nlocals)
            (mutable buffer)     ; 指令（逆序）
            (mutable nlabels)
            (mutable try-depth)
            loop-label           ; 自尾调用跳回的标签，#f 表示不做
            loop-arity           ; 当前子句的固定参数个数（有剩余参数时为 #f）
            self-mref            ; 已知过程自己的库变量（自尾调用识别），或 #f
            arg-base))           ; 第一个形参的 ldarg 下标（实例方法为 1）

  (define (make-method-ctx u class static? loop-label loop-arity self-mref)
    (make-mctx u class static? (make-eq-hashtable) '() 0 '() 0 0 loop-label loop-arity self-mref (if static? 0 1)))

  (define (emit! mc . ins)
    (for-each (lambda (i) (mctx-buffer-set! mc (cons i (mctx-buffer mc)))) ins))

  (define (new-label! mc)
    (let ((n (mctx-nlabels mc)))
      (mctx-nlabels-set! mc (+ n 1))
      (string->symbol (string-append "L" (number->string n)))))

  (define (new-local! mc type)
    (let ((n (mctx-nlocals mc)))
      (mctx-locals-set! mc (cons type (mctx-locals mc)))
      (mctx-nlocals-set! mc (+ n 1))
      n))

  ;; 在单独的缓冲区中生成代码，返回指令列表（正序）
  (define (with-buffer mc thunk)
    (let ((saved (mctx-buffer mc)))
      (mctx-buffer-set! mc '())
      (thunk)
      (let ((code (reverse (mctx-buffer mc))))
        (mctx-buffer-set! mc saved)
        code)))

  (define (emit-code! mc code) (for-each (lambda (i) (emit! mc i)) code))

  (define (contains-try? code) (exists (lambda (i) (eq? (car i) 'try)) code))

  ;; 依次生成多个操作数（每个 gen 产生一个值）。排在后面的操作数含 try 时，先全部存入临时变量（lift-try）。
  (define (operands! mc gens)
    (let ((codes (map (lambda (g) (with-buffer mc g)) gens)))
      (if (and (pair? codes) (exists contains-try? (cdr codes)))
          (let ((temps (map (lambda (c) (let ((t (new-local! mc obj))) (emit-code! mc c) (emit! mc `(stloc ,t)) t)) codes)))
            (for-each (lambda (t) (emit! mc `(ldloc ,t))) temps))
          (for-each (lambda (c) (emit-code! mc c)) codes))))

  ;; 把栈上 n 个值（已按顺序压栈）收进 object[]：先存临时变量再建数组
  (define (pack-array! mc n)
    (let ((temps (let loop ((i 0) (acc '())) (if (= i n) acc (loop (+ i 1) (cons (new-local! mc obj) acc))))))
      ;; temps 为逆序：最后压栈的值先出栈
      (for-each (lambda (t) (emit! mc `(stloc ,t))) temps)
      (emit! mc `(ldc.i4 ,n) `(newarr ,obj))
      (let loop ((ts (reverse temps)) (i 0))
        (unless (null? ts)
          (emit! mc '(dup) `(ldc.i4 ,i) `(ldloc ,(car ts)) '(stelem.ref))
          (loop (cdr ts) (+ i 1))))))

  ;; ———————————————— 结果按上下文收尾 ————————————————

  ;; 栈上是一个 object
  (define (finish-value! mc ctx)
    (case ctx
      ((value) (void))
      ((effect) (emit! mc '(pop)))
      ((test) (emit! mc `(call ,rt-type "IsTrue" (,obj) "System.Boolean")))
      ((tail) (emit! mc '(ret)))))

  ;; 栈上是一个 CLR bool
  (define (finish-bool! mc ctx)
    (case ctx
      ((test) (void))
      ((effect) (emit! mc '(pop)))
      ((value) (emit! mc `(call ,rt-type "Bool" ("System.Boolean") ,obj)))
      ((tail) (emit! mc `(call ,rt-type "Bool" ("System.Boolean") ,obj) '(ret)))))

  ;; 没有值（赋值等）
  (define (finish-none! mc ctx)
    (case ctx
      ((effect) (void))
      ((test) (emit! mc '(ldc.i4 1)))
      ((value) (emit! mc `(ldsfld "IronScheme.Core.Unspecified" "Instance")))
      ((tail) (emit! mc `(ldsfld "IronScheme.Core.Unspecified" "Instance") '(ret)))))

  (define (tail-ok? mc ctx) (and (eq? ctx 'tail) (= (mctx-try-depth mc) 0)))

  ;; ———————————————— 常量 ————————————————

  ;; 落单的代理项无法写成 Lcil 字符串，这样的字符串进常量表
  (define (bmp-safe-string? s)
    (let ((n (string-length s)))
      (let loop ((i 0))
        (or (= i n)
            (let ((k (char->integer (string-ref s i))))
              (cond
                ((and (<= #xD800 k #xDBFF) (< (+ i 1) n) (<= #xDC00 (char->integer (string-ref s (+ i 1))) #xDFFF)) (loop (+ i 2)))
                ((<= #xD800 k #xDFFF) #f)
                (else (loop (+ i 1)))))))))

  (define (load-constant! mc d)
    (cond
      ((and (fixnum? d) (exact? d)) (emit! mc `(ldc.i4 ,d) `(call ,rt-type "Box" ("System.Int32") ,obj)))
      ((eq? d #t) (emit! mc `(ldsfld ,rt-type "True")))
      ((eq? d #f) (emit! mc `(ldsfld ,rt-type "False")))
      ((null? d) (emit! mc '(ldnull)))
      ((unspecified? d) (emit! mc `(ldsfld "IronScheme.Core.Unspecified" "Instance")))
      ((and (char? d) (< (char->integer d) #x10000))
       (emit! mc `(ldc.i4 ,(char->integer d)) '(box "System.Char")))
      ((and (string? d) (string-immutable? d) (bmp-safe-string? d)) (emit! mc `(ldstr ,d)))
      (else (emit! mc `(ldconst ,(constant-index! (mctx-unit mc) d))))))

  ;; 字面字符串是不可变的 .NET string；可变字符串（StringBuilder）进常量表
  (define (string-immutable? s) (not (clr-is System.Text.StringBuilder s)))

  (define (load-symbol! mc s) (emit! mc `(ldconst ,(constant-index! (mctx-unit mc) s))))

  ;; ———————————————— 变量 ————————————————

  (define (var-location mc x)
    (or (hashtable-ref (mctx-vars mc) x #f)
        (error 'codegen "unbound variable" x)))

  (define (load-var! mc x)
    (let ((loc (var-location mc x)))
      (case (car loc)
        ((arg) (emit! mc `(ldarg ,(cdr loc))))
        ((local) (emit! mc `(ldloc ,(cdr loc))))
        ((field) (emit! mc '(ldarg 0) `(ldfld ,(mctx-class mc) ,(cdr loc))))
        ((self) (if (mctx-static? mc)
                    (emit! mc `(ldsfld ,(mctx-class mc) "Instance"))
                    (emit! mc '(ldarg 0)))))))

  (define (store-var! mc x)
    (let ((loc (var-location mc x)))
      (case (car loc)
        ((arg) (emit! mc `(starg ,(cdr loc))))
        ((local) (emit! mc `(stloc ,(cdr loc))))
        (else (error 'codegen "cannot assign captured variable (should be boxed)" x)))))

  (define (bind-local! mc x)
    (let ((i (new-local! mc obj)))
      (hashtable-set! (mctx-vars mc) x (cons 'local i))
      i))

  ;; 实参都是 (clr-cast T e) 时返回类型名列表（Lcil 的实参类型提示，发射器据此静态决议重载，iron-033）；否则 #f
  (define (cast-types e*)
    (and (pair? e*)
         (let loop ((e* e*) (acc '()))
           (if (null? e*)
               (reverse acc)
               (let ((d (nanopass-case (L3 Expr) (car e*) [(clr-cast ,d ,e) d] [else #f])))
                 (and d (loop (cdr e*) (cons d acc))))))))

  ;; ———————————————— 表达式 ————————————————

  (define (cg e mc ctx)
    (nanopass-case (L3 Expr) e
      [,x (unless (eq? ctx 'effect) (load-var! mc x) (finish-value! mc ctx))]
      [(quote ,d)
       (case ctx
         ((effect) (void))
         ((test) (emit! mc `(ldc.i4 ,(if d 1 0))))
         (else (load-constant! mc d) (finish-value! mc ctx)))]
      [(if ,e0 ,e1 ,e2)
       (let ((else-l (new-label! mc)) (end-l (new-label! mc)))
         (cg e0 mc 'test)
         (emit! mc `(brfalse ,else-l))
         (cg e1 mc ctx)
         (unless (eq? ctx 'tail) (emit! mc `(br ,end-l)))
         (emit! mc `(label ,else-l))
         (cg e2 mc ctx)
         (unless (eq? ctx 'tail) (emit! mc `(label ,end-l))))]
      [(begin ,e* ... ,e)
       (for-each (lambda (x) (cg x mc 'effect)) e*)
       (cg e mc ctx)]
      [(set! ,x ,e)
       (cg e mc 'value)
       (store-var! mc x)
       (finish-none! mc ctx)]
      [(gref ,s)
       (unless (eq? ctx 'effect)
         (load-symbol! mc s)
         (emit! mc `(call ,calls-type "Global" (,obj) ,obj))
         (finish-value! mc ctx))]
      [(gset! ,s ,e)
       (operands! mc (list (lambda () (load-symbol! mc s)) (lambda () (cg e mc 'value))))
       (emit! mc `(call ,calls-type "SetGlobal" (,obj ,obj) "System.Void"))
       (finish-none! mc ctx)]
      [(mref ,x)
       (unless (eq? ctx 'effect)
         (emit! mc `(ldsfld ,(unit-module (mctx-unit mc)) ,(mfield! (mctx-unit mc) x)))
         (finish-value! mc ctx))]
      [(mset! ,x ,e)
       (cg e mc 'value)
       (emit! mc `(stsfld ,(unit-module (mctx-unit mc)) ,(mfield! (mctx-unit mc) x)))
       (finish-none! mc ctx)]
      [(prim ,pr)
       (unless (eq? ctx 'effect)
         (load-symbol! mc pr)
         (emit! mc `(call ,calls-type "Global" (,obj) ,obj))
         (finish-value! mc ctx))]
      [(primcall ,pr ,e* ...) (cg-primcall pr e* mc ctx)]
      [(lambda ,nm (,x* ...) ,cl* ...)
       (unless (eq? ctx 'effect)
         (let ((c (lambda-class! e mc #f #f)))
           (make-closure! mc c x* #f)
           (finish-value! mc ctx)))]
      [(letrec ([,x* ,le*] ...) ,body)
       ;; 先创建全部过程对象，再填自由变量字段：组内互相引用
       (let ((classes (map (lambda (x le) (lambda-class! le mc x #f)) x* le*)))
         (for-each (lambda (x) (bind-local! mc x)) x*)
         (for-each
           (lambda (x c)
             (if (car c)
                 (emit! mc `(ldsfld ,(cadr c) "Instance"))
                 (emit! mc `(newobj ,(cadr c) ())))
             (store-var! mc x))
           x* classes)
         (for-each
           (lambda (x c le)
             (unless (car c)
               (nanopass-case (L3 LambdaExpr) le
                 [(lambda ,nm (,x1* ...) ,cl* ...)
                  (fill-fields! mc c (remq x x1*) (lambda () (load-var! mc x)))])))
           x* classes le*)
         (cg body mc ctx))]
      [(let ([,x* ,e*] ...) ,body)
       (let ((slots (map (lambda (e) (cg e mc 'value) (let ((i (new-local! mc obj))) (emit! mc `(stloc ,i)) i)) e*)))
         (for-each (lambda (x i) (hashtable-set! (mctx-vars mc) x (cons 'local i))) x* slots)
         (cg body mc ctx))]
      [(library ,d ([,x* ,s* ,e*] ...) ,body)
       ;; 非顶层的 library-letrec*（compile-library 把库的 invoke 代码包在 lambda 中）：库变量仍是模块静态字段，
       ;; 按顺序求值并写入；不做已知过程的预链接
       (let ((u (mctx-unit mc)))
         (for-each
           (lambda (x s e)
             (let ((field (mfield! u x)))
               (cg e mc 'value)
               (emit! mc `(stsfld ,(unit-module u) ,field))
               (unless (null? d)
                 (emit! mc `(ldconst ,(constant-index! u s)) `(castclass ,symbol-type)
                        `(ldsfld ,(unit-module u) ,field) `(stfld ,symbol-type "Value")))))
           x* s* e*)
         (cg body mc ctx))]
      [(call ,e0 ,e* ...) (cg-call e0 e* mc ctx)]
      [(and ,e* ...)
       (if (null? e*)
           (begin (emit! mc '(ldc.i4 1)) (finish-bool! mc ctx))
           (let ((false-l (new-label! mc)) (end-l (new-label! mc)))
             (for-each (lambda (x) (cg x mc 'test) (emit! mc `(brfalse ,false-l))) e*)
             (emit! mc '(ldc.i4 1) `(br ,end-l) `(label ,false-l) '(ldc.i4 0) `(label ,end-l))
             (finish-bool! mc ctx)))]
      [(or ,e* ...)
       (if (null? e*)
           (begin (emit! mc '(ldc.i4 0)) (finish-bool! mc ctx))
           (let ((true-l (new-label! mc)) (end-l (new-label! mc)))
             (for-each (lambda (x) (cg x mc 'test) (emit! mc `(brtrue ,true-l))) e*)
             (emit! mc '(ldc.i4 0) `(br ,end-l) `(label ,true-l) '(ldc.i4 1) `(label ,end-l))
             (finish-bool! mc ctx)))]
      [(throw ,e)
       (cg e mc 'value)
       (emit! mc '(castclass "System.Exception") '(throw))
       ;; 之后的代码不可达；value / test 上下文补一个值保持栈形状一致
       (case ctx
         ((value) (emit! mc '(ldnull)))
         ((test) (emit! mc '(ldc.i4 0)))
         (else (void)))]
      [(break)
       (emit! mc `(call ,calls-type "Break" () ,obj))
       (finish-value! mc ctx)]
      [(try-finally ,e0 ,e1)
       (let* ((tmp (and (not (eq? ctx 'effect)) (new-local! mc obj)))
              (body (begin
                      (mctx-try-depth-set! mc (+ (mctx-try-depth mc) 1))
                      (let ((b (with-buffer mc (lambda () (cg e0 mc (if tmp 'value 'effect)) (when tmp (emit! mc `(stloc ,tmp))))))
                            (f (with-buffer mc (lambda () (cg e1 mc 'effect)))))
                        (mctx-try-depth-set! mc (- (mctx-try-depth mc) 1))
                        (cons b f)))))
         (emit! mc `(try (body ,@(car body)) (finally ,@(cdr body))))
         (when tmp
           (emit! mc `(ldloc ,tmp))
           (finish-value! mc ctx)))]
      [(clr-call ,d0 ,d1 ,st ,e* ...)
       (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
       (let ((hints (and (string? d1) (cast-types (if st e* (cdr e*)))))
             (argc (- (length e*) (if st 0 1))))
         (emit! mc (if hints `(clr-call ,d0 ,d1 ,st ,argc ,hints) `(clr-call ,d0 ,d1 ,st ,argc))))
       (finish-value! mc ctx)]
      [(clr-field-get ,d0 ,d1 ,st ,e* ...)
       (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
       (emit! mc `(clr-field-get ,d0 ,d1 ,st))
       (finish-value! mc ctx)]
      [(clr-field-set ,d0 ,d1 ,st ,e* ...)
       (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
       (emit! mc `(clr-field-set ,d0 ,d1 ,st))
       (finish-value! mc ctx)]
      [(clr-new ,d ,e* ...)
       (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
       (let ((hints (cast-types e*)))
         (emit! mc (if hints `(clr-new ,d ,(length e*) ,hints) `(clr-new ,d ,(length e*)))))
       (finish-value! mc ctx)]
      [(clr-new-array ,d ,e) (cg e mc 'value) (emit! mc `(clr-new-array ,d)) (finish-value! mc ctx)]
      [(clr-cast ,d ,e) (cg e mc 'value) (emit! mc `(clr-cast ,d)) (finish-value! mc ctx)]
      [(clr-is ,d ,e) (cg e mc 'value) (emit! mc `(clr-is ,d)) (finish-value! mc ctx)]
      [(clr-type ,d) (emit! mc `(clr-type ,d)) (finish-value! mc ctx)]
      [(clr-using ,d) (add-namespace! (mctx-unit mc) d) (finish-none! mc ctx)]
      [(clr-reference ,d) (add-reference! (mctx-unit mc) d) (finish-none! mc ctx)]
      [(clr-namespaces)
       (unless (eq? ctx 'effect)
         (load-constant! mc (unit-namespaces (mctx-unit mc)))
         (finish-value! mc ctx))]
      [(unsupported ,d ,e* ...)
       (for-each (lambda (x) (cg x mc 'effect)) e*)
       (emit! mc `(ldstr ,d) `(call ,calls-type "Unsupported" ("System.String") ,obj))
       (finish-value! mc ctx)]
      [(box ,e)
       (cg e mc 'value)
       (emit! mc `(newobj ,box-type (,obj)))
       (finish-value! mc ctx)]
      [(unbox ,x)
       (unless (eq? ctx 'effect)
         (load-var! mc x)
         (emit! mc `(castclass ,box-type) `(ldfld ,box-type "Value"))
         (finish-value! mc ctx))]
      [(set-box! ,x ,e)
       (operands! mc (list (lambda () (load-var! mc x) (emit! mc `(castclass ,box-type)))
                           (lambda () (cg e mc 'value))))
       (emit! mc `(stfld ,box-type "Value"))
       (finish-none! mc ctx)]))

  ;; ———————————————— 调用 ————————————————

  (define (invoke-method n)
    (if (<= n 4)
        `(callvirt ,proc-type ,(string-append "Invoke" (number->string n)) ,(objs n) ,obj)
        `(callvirt ,proc-type "InvokeN" ("System.Object[]") ,obj)))

  (define (self-call? e0 mc)
    (nanopass-case (L3 Expr) e0
      [,x (let ((loc (hashtable-ref (mctx-vars mc) x #f))) (and loc (eq? (car loc) 'self)))]
      [(mref ,x) (eq? x (mctx-self-mref mc))]
      [else #f]))

  ;; 已知过程：按参数个数取第一个匹配的子句；是固定参数子句时返回其下标
  (define (known-target e0 mc argc)
    (nanopass-case (L3 Expr) e0
      [(mref ,x)
       (let ((k (hashtable-ref (unit-known (mctx-unit mc)) x #f)))
         (and k
              (let loop ((cls (known-clauses k)) (i 0))
                (cond
                  ((null? cls) #f)
                  ((cdar cls) #f)   ; 先匹配到剩余参数子句：走一般调用
                  ((= (caar cls) argc) (cons (known-class k) i))
                  (else (loop (cdr cls) (+ i 1)))))))]
      [else #f]))

  (define (cg-call e0 e* mc ctx)
    (let ((argc (length e*)))
      (cond
        ;; 自尾调用 → 循环
        ((and (tail-ok? mc ctx) (mctx-loop-label mc) (eqv? (mctx-loop-arity mc) argc) (self-call? e0 mc))
         (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
         (let loop ((i (- argc 1)))
           (when (>= i 0)
             (emit! mc `(starg ,(+ i (mctx-arg-base mc))))
             (loop (- i 1))))
         (emit! mc `(br ,(mctx-loop-label mc))))
        ;; 已知过程 → 直接调用静态子句方法
        ((known-target e0 mc argc)
         => (lambda (t)
              (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
              (when (tail-ok? mc ctx) (emit! mc '(tail)))
              (emit! mc `(call ,(car t) ,(string-append "C" (number->string (cdr t))) ,(objs argc) ,obj))
              (finish-value! mc ctx)))
        (else
         (operands! mc (cons (lambda () (cg e0 mc 'value) (emit! mc `(call ,calls-type "Proc" (,obj) ,proc-type)))
                             (map (lambda (x) (lambda () (cg x mc 'value))) e*)))
         (when (> argc 4) (pack-array! mc argc))
         (when (tail-ok? mc ctx) (emit! mc '(tail)))
         (emit! mc (invoke-method argc))
         (finish-value! mc ctx)))))

  ;; ———————————————— 原语（03 §6）————————————————

  (define (cg-primcall pr e* mc ctx)
    (let* ((p (primitive-info pr))
           (argc (length e*))
           (o (and p (primitive-overload p argc))))
      (define (args!) (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*)))
      ;; 拆箱的操作数；fixnum 常量直接 ldc.i4，不装箱再拆箱
      (define (unbox-args! type)
        (operands! mc (map (lambda (x)
                             (lambda ()
                               (let ((k (and (string=? type "System.Int32") (fixnum-constant x))))
                                 (if k
                                     (emit! mc `(ldc.i4 ,k))
                                     (begin (cg x mc 'value) (emit! mc `(unbox.any ,type)))))))
                           e*)))
      (cond
        ((not o)
         ;; 没有参数个数相符的重载：经值槽调用，运行时报参数个数错误
         (cg-call-prim-value pr e* mc ctx))
        ;; 尾位置的 apply：展开参数后 tail. callvirt InvokeN，保证真尾调用
        ((and (eq? pr 'apply) (>= argc 2) (tail-ok? mc ctx))
         (operands! mc (cons (lambda () (cg (car e*) mc 'value) (emit! mc `(call ,calls-type "Proc" (,obj) ,proc-type)))
                             (map (lambda (x) (lambda () (cg x mc 'value))) (cdr e*))))
         (pack-array! mc (- argc 1))
         (emit! mc `(call ,calls-type "ApplyArgs" ("System.Object[]") "System.Object[]")
                '(tail) `(callvirt ,proc-type "InvokeN" ("System.Object[]") ,obj) '(ret)))
        (else
         (case (overload-inline o)
           ((void) (args!) (for-each (lambda (x) (emit! mc '(pop))) e*) (finish-none! mc ctx))
           (($car $cdr)
            (args!)
            (emit! mc `(castclass ,cons-type) `(ldfld ,cons-type ,(if (eq? pr '$car) "car" "cdr")))
            (finish-value! mc ctx))
           ((cons)
            (args!)
            (emit! mc `(newobj ,cons-type (,obj ,obj)))
            (finish-value! mc ctx))
           ((eq?) (args!) (emit! mc '(ceq)) (finish-bool! mc ctx))
           ((not)
            (args!)
            (emit! mc `(call ,rt-type "IsTrue" (,obj) "System.Boolean") '(ldc.i4 0) '(ceq))
            (finish-bool! mc ctx))
           ((null?) (args!) (emit! mc '(ldnull) '(ceq)) (finish-bool! mc ctx))
           ((pair?) (args!) (emit! mc `(isinst ,cons-type) '(ldnull) '(cgt.un)) (finish-bool! mc ctx))
           (($fx+ $fx* $fxand $fxior $fxxor)
            (unbox-args! "System.Int32")
            (emit! mc (case pr (($fx+) '(add)) (($fx*) '(mul)) (($fxand) '(and)) (($fxior) '(or)) (else '(xor))))
            (emit! mc `(call ,rt-type "Box" ("System.Int32") ,obj))
            (finish-value! mc ctx))
           (($fx-)
            (unbox-args! "System.Int32")
            (emit! mc (if (= argc 1) '(neg) '(sub)) `(call ,rt-type "Box" ("System.Int32") ,obj))
            (finish-value! mc ctx))
           (($fxnot)
            (unbox-args! "System.Int32")
            (emit! mc '(not) `(call ,rt-type "Box" ("System.Int32") ,obj))
            (finish-value! mc ctx))
           (($fx=? $fx<? $fx>? $fx<=? $fx>=?)
            (unbox-args! "System.Int32")
            (emit-compare! mc pr #f)
            (finish-bool! mc ctx))
           (($fxzero? $fxnegative? $fxpositive?)
            (unbox-args! "System.Int32")
            (emit! mc '(ldc.i4 0))
            (emit! mc (case pr (($fxzero?) '(ceq)) (($fxnegative?) '(clt)) (else '(cgt))))
            (finish-bool! mc ctx))
           (($fl+ $fl* $fl/)
            (unbox-args! "System.Double")
            (emit! mc (case pr (($fl+) '(add)) (($fl*) '(mul)) (else '(div))) '(box "System.Double"))
            (finish-value! mc ctx))
           (($fl-)
            (unbox-args! "System.Double")
            (emit! mc (if (= argc 1) '(neg) '(sub)) '(box "System.Double"))
            (finish-value! mc ctx))
           (($fl=? $fl<? $fl>? $fl<=? $fl>=?)
            (unbox-args! "System.Double")
            (emit-compare! mc pr #t)
            (finish-bool! mc ctx))
           (else (cg-static-call! o e* mc ctx)))))))

  ;; 比较：栈上两个同类型数 → CLR bool。浮点的 <= / >= 对 NaN 为假
  (define (emit-compare! mc pr float?)
    (case pr
      (($fx=? $fl=?) (emit! mc '(ceq)))
      (($fx<? $fl<?) (emit! mc '(clt)))
      (($fx>? $fl>?) (emit! mc '(cgt)))
      (($fx<=? $fl<=?) (emit! mc (if float? '(cgt.un) '(cgt)) '(ldc.i4 0) '(ceq)))
      (($fx>=? $fl>=?) (emit! mc (if float? '(clt.un) '(clt)) '(ldc.i4 0) '(ceq)))))

  (define (fixnum-constant e)
    (nanopass-case (L3 Expr) e
      [(quote ,d) (and (fixnum? d) (exact? d) d)]
      [else #f]))

  (define (cg-static-call! o e* mc ctx)
    (let* ((argc (length e*))
           (fixed (overload-fixed o))
           (rest? (overload-rest? o)))
      (operands! mc (map (lambda (x) (lambda () (cg x mc 'value))) e*))
      (when rest? (pack-array! mc (- argc fixed)))
      (let ((tail? (and (tail-ok? mc ctx) (overload-allow-tail-call? o))))
        (when tail? (emit! mc '(tail)))
        (emit! mc `(call ,(overload-type o) ,(overload-method o)
                         ,(append (objs fixed) (if rest? '("System.Object[]") '()))
                         ,obj))
        (if tail? (emit! mc '(ret)) (finish-value! mc ctx)))))

  (define (cg-call-prim-value pr e* mc ctx)
    (operands! mc (cons (lambda ()
                          (load-symbol! mc pr)
                          (emit! mc `(call ,calls-type "Global" (,obj) ,obj) `(call ,calls-type "Proc" (,obj) ,proc-type)))
                        (map (lambda (x) (lambda () (cg x mc 'value))) e*)))
    (when (> (length e*) 4) (pack-array! mc (length e*)))
    (when (tail-ok? mc ctx) (emit! mc '(tail)))
    (emit! mc (invoke-method (length e*)))
    (finish-value! mc ctx))

  ;; ———————————————— lambda → 类 ————————————————

  ;; 返回 (static? 类名)。self：letrec 中绑定此 lambda 的变量（体内对它的引用即 this），或 #f；
  ;; self-mref：已知过程的库变量，或 #f
  (define (lambda-class! le mc self self-mref . preset)
    (nanopass-case (L3 LambdaExpr) le
      [(lambda ,nm (,x1* ...) ,cl* ...)
       (let* ((u (mctx-unit mc))
              (fields (if self (remq self x1*) x1*))
              (static? (null? fields))
              (name (if (pair? preset) (car preset) (class-name u nm)))
              (clauses (map clause-shape cl*))
              (variadic? (exists cdr clauses))
              (base (if variadic? variadic-type proc-type))
              (field-names (let loop ((fs fields) (i 0))
                             (if (null? fs) '() (cons (string-append "c" (number->string i)) (loop (cdr fs) (+ i 1))))))
              (methods '()))
         (define (add-method! m) (set! methods (cons m methods)))
         ;; 子句方法 C0、C1 …
         (let loop ((cl* cl*) (i 0))
           (unless (null? cl*)
             (add-method! (clause-method u name static? (car cl*) i fields field-names self self-mref))
             (loop (cdr cl*) (+ i 1))))
         ;; Invoke0..4：转发到第一个匹配的固定参数子句
         (let k-loop ((k 0))
           (when (<= k 4)
             (let ((t (first-match clauses k)))
               (when (and t (not (cdr (list-ref clauses t))))
                 (add-method!
                   `(method ,(string-append "Invoke" (number->string k)) (attrs override) (params ,@(objs k)) (ret ,obj)
                      (body ,@(if static? '() '((ldarg 0)))
                            ,@(let a-loop ((j 1)) (if (> j k) '() (cons `(ldarg ,j) (a-loop (+ j 1)))))
                            (tail)
                            (call ,name ,(string-append "C" (number->string t)) ,(objs (+ k (if static? 0 0))) ,obj)
                            (ret))))))
             (k-loop (+ k 1))))
         ;; InvokeN：有剩余参数或参数多于 4 个的子句时，按子句顺序分派
         (when (exists (lambda (c) (or (cdr c) (> (car c) 4))) clauses)
           (add-method! (invoke-n-method name static? clauses)))
         ;; procedure-arity（与旧系统一致）：固定参数子句为 n，有剩余参数的为 n.0；多个子句为列表，没有子句为 '()
         (add-method!
           (let ((arity (let ((as (map (lambda (c) (if (cdr c) (inexact (car c)) (car c))) clauses)))
                          (cond ((null? as) '()) ((null? (cdr as)) (car as)) (else as)))))
             `(method "get_Arity" (attrs override) (params) (ret ,obj)
                (body ,@(cond
                          ((null? arity) '((ldnull)))
                          ((fixnum? arity) `((ldc.i4 ,arity) (call ,rt-type "Box" ("System.Int32") ,obj)))
                          (else `((ldconst ,(constant-index! u arity)))))
                      (ret)))))
         ;; procedure-form：各子句的 (名字 . 形参)，形参取源码中的名字（REPL 的参数提示使用，iron-038）
         (unless (null? cl*)
           (add-method!
             `(method "get_Form" (attrs override) (params) (ret ,obj)
                (body (ldconst ,(constant-index! u (map (lambda (cl) (clause-form nm cl)) cl*)))
                      (ret)))))
         (when nm
           (add-method! `(method "get_Name" (attrs override) (params) (ret "System.String")
                           (body (ldstr ,(if (symbol? nm) (symbol->string nm) nm)) (ret)))))
         (add-method! `(method ".ctor" (attrs ctor) (params)
                         (body (ldarg 0) (call ,base ".ctor" () "System.Void") (ret))))
         (when static?
           (add-method! `(method ".cctor" (attrs cctor) (params)
                           (body (newobj ,name ()) (stsfld ,name "Instance") (ret)))))
         (add-class! u
           `(type ,name (base ,base) (attrs sealed)
              ,@(if static? `((field "Instance" ,name static)) (map (lambda (f) `(field ,f ,obj)) field-names))
              ,@(reverse methods)))
         (list static? name))]))

  (define (class-name u nm)
    (string-append (sanitize (unit-module u)) "$" (number->string (next-id! u))
                   (if nm (string-append "$" (sanitize nm)) "")))

  ;; 子句的 (名字 . 形参)：形参是 psyntax 生成的 gensym（g$名字$序号$后缀），还原为源码中的名字
  (define (clause-form nm cl)
    (define (source-name x)
      (let* ((s (symbol->string x)) (n (string-length s)))
        (if (and (> n 2) (char=? (string-ref s 0) #\g) (char=? (string-ref s 1) #\$))
            (let loop ((i (- n 1)) (dollars 0))
              (cond
                ((< i 2) x)
                ((char=? (string-ref s i) #\$)
                 (if (= dollars 1) (string->symbol (substring s 2 i)) (loop (- i 1) (+ dollars 1))))
                (else (loop (- i 1) dollars))))
            x)))
    (nanopass-case (L3 Clause) cl
      [(clause (,x* ...) ,x ,body)
       (cons (if (symbol? nm) nm (if (string? nm) (string->symbol nm) 'lambda))
             (let loop ((xs x*))
               (if (null? xs)
                   (if x (source-name x) '())
                   (cons (source-name (car xs)) (loop (cdr xs))))))]))

  (define (clause-shape cl)
    (nanopass-case (L3 Clause) cl
      [(clause (,x* ...) ,x ,body) (cons (length x*) (and x #t))]))

  (define (first-match clauses k)
    (let loop ((cs clauses) (i 0))
      (cond
        ((null? cs) #f)
        ((if (cdar cs) (>= k (caar cs)) (= k (caar cs))) i)
        (else (loop (cdr cs) (+ i 1))))))

  (define (invoke-n-method name static? clauses)
    (let loop ((cs clauses) (i 0) (code '()))
      (if (null? cs)
          `(method "InvokeN" (attrs override) (params "System.Object[]") (ret ,obj)
             (body ,@(reverse code)
                   (ldarg 0) (ldarg 1) (ldlen) (conv.i4)
                   (call ,proc-type "ArityError" ("System.Int32") ,obj)
                   (ret)))
          (let* ((n (caar cs)) (rest? (cdar cs))
                 (next (string->symbol (string-append "N" (number->string i))))
                 (load-args (let a-loop ((j 0)) (if (= j n) '() (cons* '(ldarg 1) `(ldc.i4 ,j) '(ldelem.ref) (a-loop (+ j 1))))))
                 (block
                  `((ldarg 1) (ldlen) (conv.i4) (ldc.i4 ,n) ,(if rest? `(blt ,next) `(bne.un ,next))
                    ,@(if static? '() '((ldarg 0)))
                    ,@load-args
                    ,@(if rest? `((ldarg 1) (ldc.i4 ,n) (call ,variadic-type "RestList" ("System.Object[]" "System.Int32") ,obj)) '())
                    (call ,name ,(string-append "C" (number->string i)) ,(objs (+ n (if rest? 1 0))) ,obj)
                    (ret)
                    (label ,next))))
            (loop (cdr cs) (+ i 1) (append (reverse block) code))))))

  (define (clause-method u class static? cl i fields field-names self self-mref)
    (nanopass-case (L3 Clause) cl
      [(clause (,x* ...) ,x ,body)
       (let* ((start (string->symbol "start"))
              (mc (make-method-ctx u class static? start (and (not x) (length x*)) self-mref))
              (params (if x (append x* (list x)) x*)))
         (let loop ((ps params) (j (mctx-arg-base mc)))
           (unless (null? ps)
             (hashtable-set! (mctx-vars mc) (car ps) (cons 'arg j))
             (loop (cdr ps) (+ j 1))))
         (for-each (lambda (f n) (hashtable-set! (mctx-vars mc) f (cons 'field n))) fields field-names)
         (when self (hashtable-set! (mctx-vars mc) self '(self)))
         (emit! mc `(label ,start))
         (cg body mc 'tail)
         (finish-method mc (string-append "C" (number->string i)) (if static? '(static) '()) (objs (length params))))]))

  (define (finish-method mc name attrs params)
    `(method ,name (attrs ,@attrs) (params ,@params) (ret ,obj)
       (locals ,@(reverse (mctx-locals mc)))
       (clr-namespaces)
       (body ,@(reverse (mctx-buffer mc)))))

  ;; 创建闭包：newobj 后逐个写自由变量字段
  (define (make-closure! mc c fv* self)
    (if (car c)
        (emit! mc `(ldsfld ,(cadr c) "Instance"))
        (begin
          (emit! mc `(newobj ,(cadr c) ()))
          (fill-fields! mc c fv* #f))))

  ;; 栈顶（load 为 #f 时）或 load 产生的对象：写入自由变量字段
  (define (fill-fields! mc c fv* load)
    (let loop ((fs fv*) (i 0))
      (unless (null? fs)
        (if load (begin (load) (emit! mc `(castclass ,(cadr c)))) (emit! mc '(dup)))
        (load-var! mc (car fs))
        (emit! mc `(stfld ,(cadr c) ,(string-append "c" (number->string i))))
        (loop (cdr fs) (+ i 1)))))

  ;; ———————————————— 编译单元 ————————————————

  ;; forms：L3 顶层表达式列表。返回 (values Lcil 的 S 表达式 常量列表)。
  ;; live? 为真时（内存模式 eval）常量不编码，Lcil 中写 (live-constants n)，常量对象由调用者交给发射器：
  ;; 语法对象的 mark、rib 靠 eq? 身份工作，编码再解码的副本会破坏它们。
  (define (generate-unit forms assembly-name module-name massigned . live?)
    (let ((u (make-unit assembly-name module-name '() '() 0 (make-eq-hashtable) '() '() '() (make-eq-hashtable)
                        (make-eq-hashtable) '() 0 massigned)))
      ;; 1. 已知过程：库变量绑定的、无自由变量且不被再赋值的 lambda
      (for-each (lambda (f) (collect-known! u f)) forms)
      ;; 2. 每个顶层形式一个静态方法 Init<k>
      (let* ((inits
              (let loop ((fs forms) (k 0))
                (if (null? fs)
                    '()
                    (cons (top-level-method u (car fs) k) (loop (cdr fs) (+ k 1))))))
             (entry
              `(method "Initialize" (attrs static) (params) (ret ,obj)
                 (body
                   ;; 预链接：先建好全部已知过程并写入字段与位置
                   ,@(apply append
                       (map (lambda (p)
                              (let ((class (car p)) (field (cadr p)) (loc (caddr p)))
                                `((ldsfld ,class "Instance") (stsfld ,module-name ,field)
                                  ,@(if loc
                                        `((ldconst ,(constant-index! u loc)) (castclass ,symbol-type)
                                          (ldsfld ,module-name ,field) (stfld ,symbol-type "Value"))
                                        '()))))
                            (reverse (unit-prelink u))))
                   ,@(let loop ((k 0) (n (length inits)))
                       (cond
                         ((= n 0) `((ldsfld "IronScheme.Core.Unspecified" "Instance") (ret)))
                         ((= k (- n 1)) `((call ,module-name ,(init-name k) () ,obj) (ret)))
                         (else (cons* `(call ,module-name ,(init-name k) () ,obj) '(pop) (loop (+ k 1) n))))))))
             (module
              `(type ,module-name (attrs abstract sealed)
                 ,@(map (lambda (f) `(field ,f ,obj static)) (reverse (unit-mfields u)))
                 ,@inits
                 ,entry))
             (namespaces (unit-namespaces u)))
        (values
         `(lcil 1
           (assembly ,assembly-name
             (references "IronScheme.Core" ,@(unit-references u))
             (entry ,module-name "Initialize"))
           ,@(let ((cs (reverse (unit-consts u))))
               (cond
                 ((null? cs) '())
                 ((and (pair? live?) (car live?)) `((live-constants ,(length cs))))
                 (else
                  `((constants ,@(let loop ((encs (let ((e (encode-constants cs)))
                                                     (if (canonical-gensyms) (canonicalize-encodings e) e)))
                                            (i 0))
                                   (if (null? encs) '() (cons (list i (car encs)) (loop (cdr encs) (+ i 1))))))))))
           ,@(map (lambda (t) (fill-namespaces t namespaces)) (cons module (reverse (unit-classes u)))))
          (reverse (unit-consts u))))))

  (define (init-name k) (string-append "Init" (number->string k)))

  ;; 把方法中的占位 (clr-namespaces . NAMESPACES) 换成单元的命名空间列表（方法生成时可能还没见到全部 clr-using）
  (define (fill-namespaces t namespaces)
    (map (lambda (item)
           (if (and (pair? item) (eq? (car item) 'method))
               (map (lambda (c)
                      (if (and (pair? c) (eq? (car c) 'clr-namespaces)) `(clr-namespaces ,@namespaces) c))
                    item)
               item))
         t))

  (define (collect-known! u form)
    (nanopass-case (L3 Expr) form
      [(library ,d ([,x* ,s* ,e*] ...) ,body)
       (for-each
         (lambda (x s e)
           (nanopass-case (L3 Expr) e
             [(lambda ,nm (,x1* ...) ,cl* ...)
              (when (and (null? x1*) (not (hashtable-ref (unit-massigned u) x #f)))
                (hashtable-set! (unit-known u) x (make-known (class-name u nm) (map clause-shape cl*))))]
             [else (void)]))
         x* s* e*)]
      [else (void)]))

  (define (top-level-method u form k)
    (let ((mc (make-method-ctx u (unit-module u) #t #f #f #f)))
      (nanopass-case (L3 Expr) form
        [(library ,d ([,x* ,s* ,e*] ...) ,body)
         (let ((program? (null? d)))
           (for-each
             (lambda (x s e)
               (let ((field (mfield! u x))
                     (k (hashtable-ref (unit-known u) x #f)))
                 (if k
                     ;; 已知过程：类在这里生成，赋值由入口的预链接完成
                     (let ((c (lambda-class! e mc #f x (known-class k))))
                       (unit-prelink-set! u (cons (list (cadr c) field (if program? #f s)) (unit-prelink u))))
                     (begin
                       (cg (named-lambda e) mc 'value)
                       (emit! mc `(stsfld ,(unit-module u) ,field))
                       (unless program?
                         (emit! mc `(ldconst ,(constant-index! u s)) `(castclass ,symbol-type)
                                `(ldsfld ,(unit-module u) ,field) `(stfld ,symbol-type "Value")))))))
             x* s* e*)
           (cg body mc 'tail))]
        [else (cg form mc 'tail)])
      (finish-method mc (init-name k) '(static) '())))

  (define (named-lambda e) e)

  ;; 已知过程的类名在 collect-known! 中预先确定，所以任何位置（包括类生成之前）的直接调用都能引用它。
  )
