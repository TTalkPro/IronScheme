;; iron-014 在新系统上的验证（iron-017）：同一库两次展开（两个进程）得到的核心形式应逐字相同。
;; 用法：stage0 [--deterministic] boot-seed.core deterministic.sps
;; 与 library-expander 一样，在以库名为名的 gensym 作用域中调用 core-library-expander。
(import (rnrs) (ironscheme) (only (ironscheme unsafe) $gensym-scope))

(define lib
  '(library (det test)
     (export f g point-x)
     (import (rnrs))
     (define-record-type point (fields x y))
     (define (f x)
       (let loop ((i x) (acc '()))
         (if (= i 0) acc (loop (- i 1) (cons (make-point i i) acc)))))
     (define-syntax g
       (syntax-rules () ((_ a) (f a))))))

(let ((saved ($gensym-scope)))
  ($gensym-scope '(det test))
  (let-values (((name ver imp* inv* vis* invoke-code visit-code export-subst export-env guard-code guard-req*)
                (core-library-expander lib)))
    ($gensym-scope saved)
    (pretty-print (expanded->core invoke-code))
    (pretty-print export-subst)))
