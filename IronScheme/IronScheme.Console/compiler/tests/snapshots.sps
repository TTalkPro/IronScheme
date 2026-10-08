;;; 快照测试（iron-022 ~ iron-026）：手写 Lcore 经各 pass 后的 L0、L2、L3 与 Lcil 文本，与 compiler/tests/snapshots/ 下的文件比较。
;;; 文件不存在时生成；不一致时写出 .actual 文件并失败。更新快照：删除对应文件后重跑。
(import (rnrs) (ironscheme) (nanopass)
        (ironscheme compiler languages) (ironscheme compiler parse) (ironscheme compiler front)
        (ironscheme compiler closures) (ironscheme compiler)
        (only (ironscheme compiler lcil) lcil->string))

(define cases
  '((closure
     (case-lambda ((x) (case-lambda ((y) ($fx+ x y))))))
    (named-let-loop
     ((letrec ((loop (case-lambda ((i acc) (if ($fx=? i '10) acc (loop ($fx+ i '1) (cons i acc)))))))
        loop)
      '0 '()))
    (letrec-forward
     (case-lambda
       ((n)
        (letrec* ((f (case-lambda ((x) (g x))))
                  (g (case-lambda ((y) (if (null? y) total (f (cdr y))))))
                  (total ($fx+ n '1))
                  (bump (case-lambda (() (set! n ($fx+ n '1)) n))))
          (begin (bump) (f '(1 2)))))))
    (case-lambda-rest
     (case-lambda ((a) a) ((a b) (cons a b)) ((a b c d e) (vector a b c d e)) ((a . r) r)))
    (library
     (library-letrec* (snapshot lib)
       ((u g$u (clr-using-internal 'System.Text))
        (len g$len (case-lambda ((l) (if (null? l) '0 ($fx+ '1 (len (cdr l)))))))
        (sum g$sum (case-lambda ((l acc) (if (null? l) acc (sum (cdr l) ($fx+ acc (car l)))))))
        (sb g$sb (case-lambda ((s) (clr-call-internal 'StringBuilder 'ToString (clr-new-internal 'StringBuilder s)))))
        (safe g$safe (case-lambda ((th) ($try/finally (th) (g$cleanup)))))
        (table g$table (cons 'a '#(1 "x" 2.5))))
       (begin (len '(1 2 3)) (sum '(1 2) '0))))))

(define (pp->string x) (call-with-string-output-port (lambda (p) (pretty-print x p))))

(define failures 0)
(define created 0)

(define (check! name stage text)
  (let ((file (string-append "compiler/tests/snapshots/" (symbol->string name) "." stage)))
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
    (let* ((name (car c)) (lcore (cadr c))
           (l0 (parse-core lcore))
           (an (analyze l0))
           (l2 (convert-assignments (cp0-lite (simplify-letrec l0 an)) an))
           (l3 (uncover-free l2)))
      (check! name "l0" (pp->string (unparse-L0 l0)))
      (check! name "l2" (pp->string (unparse-L2 l2)))
      (check! name "l3" (pp->string (unparse-L3 l3)))
      (check! name "lcil" (compile->lcil-text (list lcore) (symbol->string name) "#Module"))))
  cases)

;; 确定性：同一输入编译两次，Lcil 逐字相同
(for-each
  (lambda (c)
    (unless (string=? (compile->lcil-text (list (cadr c)) "d" "#Module") (compile->lcil-text (list (cadr c)) "d" "#Module"))
      (set! failures (+ failures 1))
      (display "NONDETERMINISTIC: ") (display (car c)) (newline)))
  cases)

(display "snapshots: ") (display (* 4 (length cases))) (display " compared, ")
(display created) (display " created, ") (display failures) (display " failed") (newline)
(unless (= failures 0) (exit 1))
