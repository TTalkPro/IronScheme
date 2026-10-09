;;; (ironscheme std args) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 37 的测试，
;;; 按 SRFI 37 的文本编写，每个导出名至少一项。
(import (rnrs) (only (ironscheme) include) (ironscheme std args))
(include "tests/std/check.ss")

;; 处理过程把 (名字 参数) 记到种子（一个表）里；操作数记为 (operand x)；未知选项记为 (unknown 名字 参数)
(define (record name arg seed) (cons (list name arg) seed))
(define opts
  (list (option '(#\v "verbose") #f #f (lambda (o n a s) (record 'verbose a s)))
        (option '(#\o "output") #t #f (lambda (o n a s) (record 'output a s)))
        (option '(#\l "level") #f #t (lambda (o n a s) (record 'level a s)))))
(define (parse args)
  (reverse
    (args-fold args opts
               (lambda (o n a s) (cons (list 'unknown n a) s))
               (lambda (operand s) (cons (list 'operand operand) s))
               '())))

;;; ———————————————— option 及其访问器 ————————————————
(define o (car opts))
(check (option? o) => #t)
(check (option? 'x) => #f)
(check (option-names o) => '(#\v "verbose"))
(check (option-required-arg? (cadr opts)) => #t)
(check (option-optional-arg? (caddr opts)) => #t)
(check (procedure? (option-processor o)) => #t)
(check-raises assertion-violation? (option '() #f #f values))           ; 名字表为空
(check-raises assertion-violation? (option '(#\x) #t #t values))        ; 不能既必需又可选

;;; ———————————————— args-fold ————————————————
(check (parse '()) => '())
(check (parse '("a" "b")) => '((operand "a") (operand "b")))
(check (parse '("-v")) => '((verbose #f)))
(check (parse '("--verbose")) => '((verbose #f)))
(check (parse '("-o" "f")) => '((output "f")))                          ; 短选项，参数在下一个
(check (parse '("-of")) => '((output "f")))                             ; 短选项，参数紧接
(check (parse '("--output=f")) => '((output "f")))
(check (parse '("--output" "f")) => '((output "f")))
(check (parse '("-vof" "x")) => '((verbose #f) (output "f") (operand "x")))   ; 合并的短选项
(check (parse '("-l")) => '((level #f)))                                ; 可选参数省略
(check (parse '("-l3")) => '((level "3")))
(check (parse '("--level=3")) => '((level "3")))
(check (parse '("--level" "3")) => '((level #f) (operand "3")))         ; 长选项的可选参数只能用 =
(check (parse '("-x")) => '((unknown #\x #f)))
(check (parse '("--what=1")) => '((unknown "what" "1")))
(check (parse '("--" "-v" "a")) => '((operand "-v") (operand "a")))     ; -- 之后都是操作数
;; 多个种子
(check (call-with-values
         (lambda ()
           (args-fold '("-v" "a" "b")
                      (list (option '(#\v) #f #f (lambda (o n a c1 c2) (values (+ c1 1) c2))))
                      (lambda (o n a c1 c2) (values c1 c2))
                      (lambda (operand c1 c2) (values c1 (+ c2 1)))
                      0 0))
         list)
       => '(1 2))

(check-report "std args")
