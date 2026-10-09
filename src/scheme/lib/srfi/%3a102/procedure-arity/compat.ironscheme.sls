(library (srfi :102 procedure-arity compat)
  (export procedure-arity)
  (import (rename (ironscheme) (procedure-arity host:procedure-arity)))

  (define (procedure-arity proc)
    (let ((a (host:procedure-arity proc))) 
      (cond
        [(null? a) #f]
        [else a])))
)
