;;; lower-async 的快照测试（iron-051，designs/10-async.md §3.2）：手写 Lcore（展开器对各形式的输出形状）经
;;; parse-core → lower-async 后的 L0（.la），以及透传各 pass 后的 L2、L3，与 tests/compiler/snapshots/ 下的文件比较。
;;; codegen 尚未支持（iron-052），不比较 Lcil。文件不存在时生成；不一致时写出 .actual 并失败。更新快照：删除文件后重跑。
;;; 另有错误用例：await 出现在不允许的位置时的错误信息。
(import (rnrs) (ironscheme) (nanopass)
        (ironscheme compiler languages) (ironscheme compiler parse) (ironscheme compiler async)
        (ironscheme compiler front) (ironscheme compiler closures))

;; dynamic-wind 与 with-exception-handler 按全局位置的名字识别（g$名字$…）
(define cases
  '((async-named-let
     ;; (let loop ((l l) (acc 0)) (if (null? l) acc (loop (cdr l) ($fx+ acc (await (car l))))))
     (async-lambda (l)
       ((letrec ((loop (case-lambda ((l acc) (if (null? l) acc (loop (cdr l) ($fx+ acc (await (car l)))))))))
          loop)
        l '0)))
    (async-do
     ;; (do ((i 0 (+ i 1))) ((= i n) i) (await (f i)))
     (async-lambda (n f)
       (letrec ((loop (case-lambda ((i) (if ($fx=? i n) i (begin (await (f i)) (loop ($fx+ i '1))))))))
         (loop '0))))
    (async-parameterize
     ;; (parameterize ((p 1)) (await t))
     (async-lambda (p t)
       ((case-lambda
          ((p1 v1)
           ((case-lambda
              ((swap) (g$dynamic-wind$1$%b swap (case-lambda (() (await t))) swap)))
            (case-lambda (() ((case-lambda ((tmp) (p1 v1) (set! v1 tmp))) (p1)))))))
        p '1)))
    (async-dynamic-wind
     (async-lambda (t)
       (g$dynamic-wind$1$%b (case-lambda (() (display 'in))) (case-lambda (() (await t))) (case-lambda (() (display 'out))))))
    (async-guard
     ;; (guard (e ((symbol? e) e)) (await t))
     (async-lambda (t)
       ((call/cc
          (case-lambda
            ((outerk)
             (g$with-exception-handler$1$%b
               (case-lambda
                 ((e)
                  ((call/cc
                     (case-lambda
                       ((raisek)
                        (outerk (case-lambda (() (if (symbol? e) e ((case-lambda (() (g$raise-continuable$1$%b e))))))))))))))
               (case-lambda
                 (()
                  (call-with-values
                    (case-lambda (() (await t)))
                    (case-lambda (args (outerk (case-lambda (() (apply g$values$1$%b args))))))))))))))))
    (async-with-exception-handler
     (async-lambda (h t)
       (g$with-exception-handler$1$%b h (case-lambda (() (await t))))))
    (async-operand
     ;; (list (f) (await t) (g))：操作数位置的 await，前后操作数都要先绑定
     (async-lambda (f g t)
       (cons (f) (cons (await t) (g)))))
    (async-and-or
     ;; and / or 展开成 $and? / $or?（L0 的 and / or 节点）
     (async-lambda (a t u)
       (if ($and? a (await t)) ($or? (await u) '0) '#f)))
    (async-nested-lambda-ok
     ;; 普通 lambda 里没有 await 时不动；嵌套的 async-lambda 各自处理
     (async-lambda (l)
       (g$for-each$1$%b (case-lambda ((x) (display x))) l)
       (await ((async-lambda (y) (await y)) l))))))

(define (lower lcore)
  (let* ((l0 (parse-core lcore))
         (la (begin (reset-fresh-names!) (lower-async l0)))
         (an (analyze la))
         (l2 (convert-assignments (cp0-lite (check-forward (simplify-letrec la an) an)) an))
         (l3 (uncover-free l2)))
    (values la l2 l3)))

(define (pp->string x) (call-with-string-output-port (lambda (p) (pretty-print x p))))

(define failures 0)
(define created 0)

(define (check! name stage text)
  (let ((file (string-append "tests/compiler/snapshots/" (symbol->string name) "." stage)))
    (cond
      ((not (file-exists? file))
       (call-with-output-file file (lambda (p) (put-string p text)))
       (set! created (+ created 1)))
      ((not (string=? text (call-with-input-file file get-string-all)))
       (let ((actual (string-append file ".actual")))
         (when (file-exists? actual) (delete-file actual))
         (call-with-output-file actual (lambda (p) (put-string p text)))
         (set! failures (+ failures 1))
         (display "MISMATCH: ") (display file) (newline))))))

(for-each
  (lambda (c)
    (let ((name (car c)))
      (guard (e (#t (set! failures (+ failures 1))
                    (display "ERROR in ") (display name) (display ": ")
                    (display (if (message-condition? e) (condition-message e) e)) (newline)))
        (let-values (((la l2 l3) (lower (cadr c))))
          (check! name "la" (pp->string (unparse-L0 la)))
          (check! name "l2" (pp->string (unparse-L2 l2)))
          (check! name "l3" (pp->string (unparse-L3 l3)))))))
  cases)

;; 没有 async-lambda 的单元原样返回（同一对象）
(let ((l0 (parse-core '(case-lambda ((x) (g$dynamic-wind$1$%b x x x))))))
  (unless (eq? l0 (lower-async l0))
    (set! failures (+ failures 1))
    (display "lower-async changed a unit without async-lambda") (newline)))

;; 错误用例：(输入 期望出现在错误信息里的片段)
(define error-cases
  '((for-each-callback
     (async-lambda (l) (g$for-each$1$%b (case-lambda ((x) (await x))) l))
     "nested lambda")
    (non-tail-loop
     (async-lambda (l)
       ((letrec ((loop (case-lambda ((l) (if (null? l) '0 ($fx+ '1 (loop (cdr (await l)))))))))
          loop)
        l))
     "non-tail position")
    (loop-arity
     (async-lambda (l)
       (letrec ((loop (case-lambda ((a b) (await a) (loop b)))))
         (loop l l)))
     "different number of arguments")
    (loop-as-value
     (async-lambda (l)
       (letrec ((loop (case-lambda ((a) (await a) (loop a)))))
         (begin (g$display$1$%b loop) (loop l))))
     "used as a value")
    (await-in-finally
     (async-lambda (t)
       (g$dynamic-wind$1$%b (case-lambda (() '0)) (case-lambda (() '1)) (case-lambda (() (await t)))))
     "finally")
    (mutual-recursion
     (async-lambda (t)
       (letrec ((f (case-lambda ((x) (g (await x))))) (g (case-lambda ((y) (f y)))))
         (f t)))
     "mutually recursive")
    (outside-async
     (case-lambda ((t) (await t)))
     "not inside an async-lambda")))

(for-each
  (lambda (c)
    (let ((name (car c)) (lcore (cadr c)) (expected (caddr c)))
      (let ((msg (guard (e ((message-condition? e) (condition-message e)) (#t "no condition"))
                   (lower lcore)
                   "no error")))
        (define (contains? s sub)
          (let ((n (string-length s)) (m (string-length sub)))
            (let loop ((i 0))
              (cond
                ((> (+ i m) n) #f)
                ((string=? (substring s i (+ i m)) sub) #t)
                (else (loop (+ i 1)))))))
        (unless (contains? msg expected)
          (set! failures (+ failures 1))
          (display "WRONG ERROR for ") (display name) (display ": ") (display msg) (newline)))))
  error-cases)

(display "async-snapshots: ") (display (* 3 (length cases))) (display " compared, ")
(display (length error-cases)) (display " error cases, ")
(display created) (display " created, ") (display failures) (display " failed") (newline)
(unless (= failures 0) (exit 1))
