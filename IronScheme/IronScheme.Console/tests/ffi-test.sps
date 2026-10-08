;;; FFI 冒烟测试（iron-032）：ffi-callback 产生原生函数指针，ffi-callout 再调用它；pinvoke-call 调用 C 运行库。
(import (rnrs) (ironscheme ffi) (ironscheme clr))

(define failures 0)
(define (check name got expected)
  (unless (equal? got expected)
    (set! failures (+ failures 1))
    (display "FAIL ") (display name) (display ": ") (write got) (display " expected ") (write expected) (newline)))

(define add ((ffi-callout int32 (int32 int32)) ((ffi-callback int32 (int32 int32)) (lambda (a b) (+ a b)))))
(check 'int32 (add 3 4) 7)

(define twice ((make-ffi-callout 'double '(double)) ((make-ffi-callback 'double '(double)) (lambda (x) (* x 2.0)))))
(check 'double (twice 1.25) 2.5)

(define big ((ffi-callout int64 (int64)) ((ffi-callback int64 (int64)) (lambda (x) (* x 2)))))
(check 'int64 (big 4294967296) 8589934592)

(define called #f)
(define notify ((ffi-callout void ()) ((ffi-callback void ()) (lambda () (set! called #t)))))
(notify)
(check 'void called #t)

(check 'pointer (pointer? ((ffi-callback int32 ()) (lambda () 0))) #t)

;; C 运行库：Windows 为 msvcrt，其他平台为 libc（Linux 上为 libc.so.6）
(define strlen
  (if (char=? (clr-static-field-get System.IO.Path DirectorySeparatorChar) #\\)
      (pinvoke-call msvcrt strlen int32 (string))
      (pinvoke-call libc.so.6 strlen int32 (string))))
(check 'pinvoke (strlen "hello") 5)

(define libc (dlopen (if (char=? (clr-static-field-get System.IO.Path DirectorySeparatorChar) #\\) "msvcrt" "libc.so.6")))
(check (quote dlsym) (((ffi-callout int32 (string)) (dlsym libc "strlen")) "abc") 3)
(dlclose libc)

(define missing (pinvoke-call no-such-library foo int32 ()))
(check 'missing-library (guard (e ((assertion-violation? e) 'error)) (missing)) 'error)

(display (if (= failures 0) "ffi: all passed" "ffi: failed"))
(newline)
