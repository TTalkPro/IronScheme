;;; (ironscheme std numeric-vectors) 的测试（designs/08-std-library.md D8）。chez-srfi 没有 SRFI 4 的测试，
;;; 按 SRFI 4 的文本编写：每种向量的八个过程、取值范围的两端与越界。
(import (rnrs) (only (ironscheme) include) (ironscheme std numeric-vectors))
(include "tests/std/check.ss")

;;; ———————————————— s8vector ————————————————
(check (s8vector? (s8vector)) => #t)
(check (s8vector? (vector 1)) => #f)
(check (s8vector->list (make-s8vector 3 7)) => '(7 7 7))
(check (s8vector-length (make-s8vector 4)) => 4)
(check (s8vector->list (s8vector -128 0 127)) => '(-128 0 127))
(check (s8vector-ref (list->s8vector '(1 2 3)) 2) => 3)
(check (let ((v (make-s8vector 2 0))) (s8vector-set! v 1 127) (s8vector->list v)) => '(0 127))
(check-raises (lambda (e) #t) (s8vector 128))
(check-raises (lambda (e) #t) (s8vector -129))

;;; ———————————————— u8vector ————————————————
(check (u8vector? (u8vector)) => #t)
(check (u8vector? (vector 1)) => #f)
(check (u8vector->list (make-u8vector 3 7)) => '(7 7 7))
(check (u8vector-length (make-u8vector 4)) => 4)
(check (u8vector->list (u8vector 0 0 255)) => '(0 0 255))
(check (u8vector-ref (list->u8vector '(1 2 3)) 2) => 3)
(check (let ((v (make-u8vector 2 0))) (u8vector-set! v 1 255) (u8vector->list v)) => '(0 255))
(check-raises (lambda (e) #t) (u8vector 256))
(check-raises (lambda (e) #t) (u8vector -1))

;;; ———————————————— s16vector ————————————————
(check (s16vector? (s16vector)) => #t)
(check (s16vector? (vector 1)) => #f)
(check (s16vector->list (make-s16vector 3 7)) => '(7 7 7))
(check (s16vector-length (make-s16vector 4)) => 4)
(check (s16vector->list (s16vector -32768 0 32767)) => '(-32768 0 32767))
(check (s16vector-ref (list->s16vector '(1 2 3)) 2) => 3)
(check (let ((v (make-s16vector 2 0))) (s16vector-set! v 1 32767) (s16vector->list v)) => '(0 32767))
(check-raises (lambda (e) #t) (s16vector 32768))
(check-raises (lambda (e) #t) (s16vector -32769))

;;; ———————————————— u16vector ————————————————
(check (u16vector? (u16vector)) => #t)
(check (u16vector? (vector 1)) => #f)
(check (u16vector->list (make-u16vector 3 7)) => '(7 7 7))
(check (u16vector-length (make-u16vector 4)) => 4)
(check (u16vector->list (u16vector 0 0 65535)) => '(0 0 65535))
(check (u16vector-ref (list->u16vector '(1 2 3)) 2) => 3)
(check (let ((v (make-u16vector 2 0))) (u16vector-set! v 1 65535) (u16vector->list v)) => '(0 65535))
(check-raises (lambda (e) #t) (u16vector 65536))
(check-raises (lambda (e) #t) (u16vector -1))

;;; ———————————————— s32vector ————————————————
(check (s32vector? (s32vector)) => #t)
(check (s32vector? (vector 1)) => #f)
(check (s32vector->list (make-s32vector 3 7)) => '(7 7 7))
(check (s32vector-length (make-s32vector 4)) => 4)
(check (s32vector->list (s32vector -2147483648 0 2147483647)) => '(-2147483648 0 2147483647))
(check (s32vector-ref (list->s32vector '(1 2 3)) 2) => 3)
(check (let ((v (make-s32vector 2 0))) (s32vector-set! v 1 2147483647) (s32vector->list v)) => '(0 2147483647))
(check-raises (lambda (e) #t) (s32vector 2147483648))
(check-raises (lambda (e) #t) (s32vector -2147483649))

;;; ———————————————— u32vector ————————————————
(check (u32vector? (u32vector)) => #t)
(check (u32vector? (vector 1)) => #f)
(check (u32vector->list (make-u32vector 3 7)) => '(7 7 7))
(check (u32vector-length (make-u32vector 4)) => 4)
(check (u32vector->list (u32vector 0 0 4294967295)) => '(0 0 4294967295))
(check (u32vector-ref (list->u32vector '(1 2 3)) 2) => 3)
(check (let ((v (make-u32vector 2 0))) (u32vector-set! v 1 4294967295) (u32vector->list v)) => '(0 4294967295))
(check-raises (lambda (e) #t) (u32vector 4294967296))
(check-raises (lambda (e) #t) (u32vector -1))

;;; ———————————————— s64vector ————————————————
(check (s64vector? (s64vector)) => #t)
(check (s64vector? (vector 1)) => #f)
(check (s64vector->list (make-s64vector 3 7)) => '(7 7 7))
(check (s64vector-length (make-s64vector 4)) => 4)
(check (s64vector->list (s64vector -9223372036854775808 0 9223372036854775807)) => '(-9223372036854775808 0 9223372036854775807))
(check (s64vector-ref (list->s64vector '(1 2 3)) 2) => 3)
(check (let ((v (make-s64vector 2 0))) (s64vector-set! v 1 9223372036854775807) (s64vector->list v)) => '(0 9223372036854775807))
(check-raises (lambda (e) #t) (s64vector 9223372036854775808))
(check-raises (lambda (e) #t) (s64vector -9223372036854775809))

;;; ———————————————— u64vector ————————————————
(check (u64vector? (u64vector)) => #t)
(check (u64vector? (vector 1)) => #f)
(check (u64vector->list (make-u64vector 3 7)) => '(7 7 7))
(check (u64vector-length (make-u64vector 4)) => 4)
(check (u64vector->list (u64vector 0 0 18446744073709551615)) => '(0 0 18446744073709551615))
(check (u64vector-ref (list->u64vector '(1 2 3)) 2) => 3)
(check (let ((v (make-u64vector 2 0))) (u64vector-set! v 1 18446744073709551615) (u64vector->list v)) => '(0 18446744073709551615))
(check-raises (lambda (e) #t) (u64vector 18446744073709551616))
(check-raises (lambda (e) #t) (u64vector -1))

;;; ———————————————— f32vector ————————————————
(check (f32vector? (f32vector 1.5)) => #t)
(check (f32vector? (u8vector 1)) => #f)
(check (f32vector->list (make-f32vector 2 0.5)) => '(0.5 0.5))
(check (f32vector-length (f32vector 1.0 2.0 3.0)) => 3)
(check (f32vector-ref (list->f32vector '(1.25 -2.5)) 1) => -2.5)
(check (let ((v (make-f32vector 2 0.0))) (f32vector-set! v 0 3.0) (f32vector->list v)) => '(3.0 0.0))

;;; ———————————————— f64vector ————————————————
(check (f64vector? (f64vector 1.5)) => #t)
(check (f64vector? (u8vector 1)) => #f)
(check (f64vector->list (make-f64vector 2 0.5)) => '(0.5 0.5))
(check (f64vector-length (f64vector 1.0 2.0 3.0)) => 3)
(check (f64vector-ref (list->f64vector '(1.25 -2.5)) 1) => -2.5)
(check (let ((v (make-f64vector 2 0.0))) (f64vector-set! v 0 3.0) (f64vector->list v)) => '(3.0 0.0))

(check (u8vector? (s8vector 1)) => #f)                     ; 各类型互不相同

(check-report "std numeric-vectors")
