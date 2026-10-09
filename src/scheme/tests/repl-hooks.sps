;;; REPL 补全与提示钩子（iron-038）：psyntax main 登记的 repl-complete、repl-describe
(import (ironscheme))

(define complete (symbol-value 'repl-complete))
(define describe (symbol-value 'repl-describe))
(define failures 0)
(define (check name got expected)
  (unless (equal? got expected)
    (set! failures (+ failures 1))
    (display "FAIL ") (display name) (display ": ") (write got) (display " expected ") (write expected) (newline)))

(check 'symbol (list-sort string<? (complete "list-t" #f)) '("list-tail"))
(check 'library-installed (and (member "(rnrs base)" (complete "(rnrs b" #t)) #t) #t)
(check 'library-file (and (member "(srfi :1 lists)" (complete "(srfi :1" #t)) #t) #t)
(check 'hint-compiled (describe "list-tail") "(list-tail lst index)")
(check 'hint-clauses (describe "map") "(map proc list1) | (map proc list1 . lists)")
(check 'hint-primitive (string? (describe "car")) #t)
(check 'hint-syntax (describe "define") #f)
(check 'hint-unbound (describe "no-such-binding") #f)
(define (my-fun alpha beta . rest) alpha)
(check 'procedure-form (call-with-values (lambda () (procedure-form my-fun)) list) '((my-fun alpha beta . rest)))

(display (if (= failures 0) "repl-hooks: all passed" "repl-hooks: failed"))
(newline)
