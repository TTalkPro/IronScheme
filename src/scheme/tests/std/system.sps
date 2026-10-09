;;; (ironscheme std system) 的测试（designs/08-std-library.md D8）。SRFI 98 部分改写自 chez-srfi 的
;;; tests/os-environment-variables.sps（Derick Eddington，MIT 许可）：原测试的 4 项 check 与 1 个 assert
;;; 全部保留（assert 改为 check）。SRFI 112 部分按 08 / 文件头写明的实际取值编写。
(import (rnrs) (only (ironscheme) include) (ironscheme std system))
(include "tests/std/check.ss")

;;; ———————————————— SRFI 98 ————————————————
(check (list? (get-environment-variables)) => #t)
(check (for-all (lambda (a)
                  (and (pair? a)
                       (string? (car a))
                       (positive? (string-length (car a)))
                       (string? (cdr a))))
                (get-environment-variables))
       => #t)
(check (for-all (lambda (a)
                  (let ((v (get-environment-variable (car a))))
                    (and (string? v)
                         (string=? v (cdr a)))))
                (get-environment-variables))
       => #t)
(check (not (assoc "BLAH" (get-environment-variables))) => #t)
(check (get-environment-variable "BLAH") => #f)

;;; ———————————————— SRFI 112 ————————————————
(check (implementation-name) => "IronScheme")
(check (string? (implementation-version)) => #t)
(check (and (member (cpu-architecture) '("x86-64" "i386" "arm64" "arm" "wasm" "s390x" "loongarch64" "armv6" "ppc64le" "riscv64")) #t) => #t)
(check (and (string? (machine-name)) (> (string-length (machine-name)) 0)) => #t)
(check (and (string? (os-name)) (> (string-length (os-name)) 0)) => #t)
(check (or (not (os-version)) (string? (os-version))) => #t)

(check-report "std system")
