#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std string-cursors) —— 字符串游标（designs/08-std-library.md）
;;; 词源：SRFI 130（John Cowan）。参照实现 William D Clinger（MIT 许可，版权声明见下方代码），
;;; 建立在 SRFI 13（(ironscheme std strings)）之上；R6RS 改写来自 chez-srfi（LICENSES/chez-srfi.txt）。
;;;
;;; 本实现中游标就是下标（SRFI 130 允许），因此游标与 (ironscheme std strings) 的下标可以互换。
;;;
;;; ⚠ 与 (ironscheme std strings) 有 34 个同名过程（string-index string-contains string-take …），语义按
;;;   SRFI 130：如 string-index 找不到时返回末端游标而不是 #f，string-contains 返回游标。
;;;   两个库同时使用时给其一加前缀：(import (prefix (ironscheme std string-cursors) sc:))。
;;; 与参照实现不同（D4）：string->list/cursors、string->vector/cursors、string-copy/cursors 在参照实现中
;;; 直接取 R7RS 的同名过程（收 start、end），R6RS 的版本只收一个参数；这里补上游标参数。
;;; 本库所有名字都是基础库没有的（D2）。
(library (ironscheme std string-cursors)
  (export
    reverse-list->string string->list/cursors string->vector/cursors string-any
    string-concatenate string-concatenate-reverse string-contains string-contains-right
    string-copy/cursors string-count string-cursor->index string-cursor-back
    string-cursor-diff string-cursor-end string-cursor-forward string-cursor-next
    string-cursor-prev string-cursor-start string-cursor<=? string-cursor<? string-cursor=?
    string-cursor>=? string-cursor>? string-cursor? string-drop string-drop-right
    string-every string-filter string-fold string-fold-right string-for-each-cursor
    string-index string-index->cursor string-index-right string-join string-null? string-pad
    string-pad-right string-prefix-length string-prefix? string-ref/cursor string-remove
    string-replace string-replicate string-reverse string-skip string-skip-right string-split
    string-suffix-length string-suffix? string-tabulate string-take string-take-right
    string-trim string-trim-both string-trim-right string-unfold string-unfold-right
    substring/cursors)
  (import
    (rnrs)
    (rename (only (ironscheme std strings) string-index string-index-right
                      string-contains string-filter string-replace
                      string-count string-fold-right string-fold
                      string-concatenate-reverse string-concatenate
                      string-reverse string-suffix? string-prefix?
                      string-suffix-length string-prefix-length
                      string-trim-both string-trim-right string-trim
                      string-pad-right string-pad string-drop-right
                      string-drop string-take-right string-take string-join
                      reverse-list->string string-unfold-right string-unfold
                      string-tabulate string-any string-every string-null?)
                (string-index srfi-13:string-index)
                (string-index-right srfi-13:string-index-right))
    (only (ironscheme) last-pair))

;; ———————————————— 改写自 srfi/%3a130/130.body.scm ————————————————

;;; Copyright (C) William D Clinger (2016).
;;; 
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use,
;;; copy, modify, merge, publish, distribute, sublicense, and/or
;;; sell copies of the Software, and to permit persons to whom the
;;; Software is furnished to do so, subject to the following
;;; conditions:
;;; 
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;; 
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;;; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;;; OTHER DEALINGS IN THE SOFTWARE. 

;;; For convenient interoperation with SRFI 13,
;;; cursors ought to be the same as indexes.

;;; Some of the FIXME comments mark procedures that really ought
;;; to do more checking for "is an error" situations.

;; added for chez scheme support
(define string->vector
  (lambda (str)
    (let ([len (string-length str)])
      (let ([v (make-vector len)])
        (do ([i (fx- len 1) (fx- i 1)])
            ((fx=? i -1))
          (vector-set! v i (string-ref str i)))
        v))))

(define (string-cursor? x)
  (and (and (integer? x) (exact? x))
       (>= x 0)))

(define (string-cursor-start s) 0)
(define (string-cursor-end s) (string-length s))
(define (string-cursor-next s curs) (+ curs 1))                         ; FIXME
(define (string-cursor-prev s curs) (- curs 1))                         ; FIXME
(define (string-cursor-forward s curs n) (+ curs n))                    ; FIXME
(define (string-cursor-back s curs n) (- curs n))                       ; FIXME
(define (string-cursor=? curs1 curs2) (= curs1 curs2))
(define (string-cursor<? curs1 curs2) (< curs1 curs2))
(define (string-cursor>? curs1 curs2) (> curs1 curs2))
(define (string-cursor<=? curs1 curs2) (<= curs1 curs2))
(define (string-cursor>=? curs1 curs2) (>= curs1 curs2))
(define (string-cursor-diff s start end) (- end start))                 ; FIXME
(define (string-cursor->index s curs) curs)
(define (string-index->cursor s idx) idx)

;; 参照实现直接用 R7RS 的 string->list / string->vector / string-copy（收 start、end）；
;; R6RS 的版本只收一个参数，这里补上游标参数（iron-042）
(define (%cursor-substring s rest)
  (cond ((null? rest) s)
        ((null? (cdr rest)) (substring s (car rest) (string-length s)))
        (else (substring s (car rest) (cadr rest)))))
(define (string->list/cursors s . start+end) (string->list (%cursor-substring s start+end)))
(define (string->vector/cursors s . start+end) (string->vector (%cursor-substring s start+end)))

(define string-ref/cursor string-ref)
(define substring/cursors substring)
(define (string-copy/cursors s . start+end) (string-copy (%cursor-substring s start+end)))

;;; The SRFI 13 procedures return #f sometimes, so they can't be the same
;;; even if cursors are the same as indexes.
;;; Furthermore string-index-right and string-skip-right return the
;;; successor of the cursor for the character found.

(define string-index
  (case-lambda
   ((s pred)
    (string-index s pred 0 (string-length s)))
   ((s pred start)
    (string-index s pred start (string-length s)))
   ((s pred start end)
    (or (srfi-13:string-index s pred start end)
        end))))

(define string-index-right
  (case-lambda
   ((s pred)
    (string-index-right s pred 0 (string-length s)))
   ((s pred start)
    (string-index-right s pred start (string-length s)))
   ((s pred start end)
    (let ((i (srfi-13:string-index-right s pred start end)))
      (if i (+ i 1) start)))))

(define (string-skip s pred . rest)
  (apply string-index s (lambda (x) (not (pred x))) rest))

(define (string-skip-right s pred . rest)
  (apply string-index-right s (lambda (x) (not (pred x))) rest))

;;; FIXME: inefficient

(define string-contains-right
  (case-lambda
   ((s1 s2)
    (string-contains-right s1 s2 0 (string-length s1) 0 (string-length s2)))
   ((s1 s2 start1)
    (string-contains-right s1 s2
                           start1 (string-length s1) 0 (string-length s2)))
   ((s1 s2 start1 end1)
    (string-contains-right s1 s2 start1 end1 0 (string-length s2)))
   ((s1 s2 start1 end1 start2)
    (string-contains-right s1 s2 start1 end1 start2 (string-length s2)))
   ((s1 s2 start1 end1 start2 end2)
    (if (= start2 end2)
        end1
        (let loop ((i #f)
                   (j (string-contains s1 s2 start1 end1 start2 end2)))
          (if (and j (< j end1))
              (loop j (string-contains s1 s2 (+ j 1) end1 start2 end2))
              i))))))

(define string-for-each-cursor
  (case-lambda
   ((proc s)
    (string-for-each-cursor proc s 0 (string-length s)))
   ((proc s start)
    (string-for-each-cursor proc s start (string-length s)))
   ((proc s start end)
    (do ((i start (+ i 1)))
        ((>= i end))
      (proc i)))))

(define string-replicate
  (case-lambda
   ((s from to start end)
    (string-replicate (substring s start end) from to))
   ((s from to start)
    (string-replicate (substring s start (string-length s)) from to))
   ((s from to)
    (let* ((n (- to from))
           (len (string-length s)))
      (cond ((= n 0)
             "")
            ((or (< n 0)
                 (= len 0))
             (assertion-violation 'string-replicate
                                  "unexpected arguments"
                                  s from to))
            (else
             (let* ((from (mod from len)) ; make from non-negative
                    (to (+ from n)))
               (do ((replicates '() (cons s replicates))
                    (replicates-length 0 (+ replicates-length len)))
                   ((>= replicates-length to)
                    (substring (apply string-append replicates)
                               from to))))))))))

(define string-split
  (case-lambda
   ((s delimiter grammar limit start end)
    (string-split (substring s start end) delimiter grammar limit))
   ((s delimiter grammar limit start)
    (string-split (substring s start (string-length s))
                  delimiter grammar limit))
   ((s delimiter)
    (string-split s delimiter 'infix #f))
   ((s delimiter grammar)
    (string-split s delimiter grammar #f))
   ((s delimiter grammar limit)
    (define (complain)
      (assertion-violation 'string-split
                           "unexpected arguments"
                           s delimiter grammar limit))
    (let* ((limit (or limit (string-length s)))
           (splits
            (cond ((= 0 (string-length delimiter))
                   (string-split-into-characters s limit))
                  (else
                   (string-split-using-word s delimiter limit)))))
      (case grammar
       ((infix strict-infix)
        (if (= 0 (string-length s))
            (if (eq? grammar 'infix)
                '()
                (complain))
            splits))
       ((prefix)
        (if (and (pair? splits)
                 (= 0 (string-length (car splits))))
            (cdr splits)
            splits))
       ((suffix)
        (if (and (pair? splits)
                 (= 0 (string-length (car (last-pair splits)))))
            (reverse (cdr (reverse splits)))
            splits))
       (else
        (complain)))))))

(define (string-split-into-characters s limit)
  (let ((n (string-length s)))
    (cond ((> n (+ limit 1))
           (append (string-split-into-characters (substring s 0 limit) limit)
                   (substring s limit n)))
          (else
           (map string (string->list s))))))

;;; FIXME: inefficient

(define (string-split-using-word s sep limit)
  (cond ((= 0 limit)
         (list s))
        (else
         (let ((i (string-contains s sep)))
           (if i
               (cons (substring s 0 i)
                     (string-split-using-word
                      (substring s (+ i (string-length sep)) (string-length s))
                      sep
                      (- limit 1)))
               (list s))))))

(define (string-remove pred s . args)
  (apply string-filter
         (lambda (c) (not (pred c)))
         s
         args))
)
