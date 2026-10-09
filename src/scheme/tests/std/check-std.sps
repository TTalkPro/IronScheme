;;; std 库的守卫（designs/08-std-library.md D2）：每个 (ironscheme std …) 库都能加载，
;;; 其导出与 (ironscheme) 没有交集（既不冲突，也不转导出基础库已有的名字）。
;;; 库清单来自 lib/ironscheme/std 下的 .sls 文件（private/ 与 LICENSES/ 除外）。
(import (ironscheme) (ironscheme clr))

(define std-dir "lib/ironscheme/std")

(define (library-names)
  (let ((root (clr-static-call System.IO.Path (GetFullPath String) std-dir)))
    (list-sort
      (lambda (a b) (string<? (format "~a" a) (format "~a" b)))
      (filter values
        (map (lambda (file)
               (let* ((rel (substring file (+ (string-length root) 1) (string-length file)))
                      (rel (clr-call String (Replace String String) rel "\\" "/"))
                      (base (substring rel 0 (- (string-length rel) 4)))
                      (parts (let split ((s base) (acc '()))
                               (let ((i (let loop ((i 0)) (cond ((= i (string-length s)) #f)
                                                                 ((char=? (string-ref s i) #\/) i)
                                                                 (else (loop (+ i 1)))))))
                                 (if i
                                     (split (substring s (+ i 1) (string-length s)) (cons (substring s 0 i) acc))
                                     (reverse (cons s acc)))))))
                 (and (not (member (car parts) '("private" "LICENSES")))
                      (append '(ironscheme std) (map string->symbol parts)))))
             (vector->list (clr-static-call System.IO.Directory (GetFiles String String System.IO.SearchOption)
                                            root "*.sls" 'AllDirectories)))))))

(define base-names (environment-symbols (environment '(ironscheme))))

(define failures 0)

(for-each
  (lambda (lib)
    (guard (e (#t (set! failures (+ failures 1))
                  (display "FAIL ") (write lib) (display ": cannot load: ")
                  (display (if (message-condition? e) (condition-message e) e)) (newline)))
      (let* ((names (environment-symbols (environment lib)))
             (clash (filter (lambda (n) (memq n base-names)) names)))
        (if (null? clash)
            (begin (write lib) (display " ") (display (length names)) (newline))
            (begin
              (set! failures (+ failures 1))
              (display "FAIL ") (write lib) (display ": also in (ironscheme): ") (write clash) (newline))))))
  (library-names))

(display (if (= failures 0) "check-std: all passed" "check-std: failed"))
(newline)
