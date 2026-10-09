;;; fmt.sls --- R6RS library for the fmt core
;;
;; Based on fmt-scheme48.scm, which is
;; Copyright (c) 2007, 2009, 2011 Alex Shinn.  All rights reserved.
;; BSD-style license: http://synthcode.com/license.txt
;;
;; R6RS adaption Copyright (c) 2009, 2011 Andreas Rottmann, same license.
#!r6rs

(library (wak fmt)
  (export new-fmt-state
          fmt fmt-start fmt-if fmt-capture fmt-let fmt-bind fmt-null
          fmt-ref fmt-set! fmt-add-properties! fmt-set-property!
          fmt-col fmt-set-col! fmt-row fmt-set-row!
          fmt-radix fmt-set-radix! fmt-precision fmt-set-precision!
          fmt-properties fmt-set-properties! fmt-width fmt-set-width!
          fmt-writer fmt-set-writer! fmt-port fmt-set-port!
          fmt-decimal-sep fmt-set-decimal-sep!
          copy-fmt-state
          fmt-file fmt-try-fit cat apply-cat nl fl nl-str
          fmt-join fmt-join/last fmt-join/dot fmt-join/prefix
          fmt-join/suffix fmt-join/range
          pad pad/right pad/left pad/both trim trim/left trim/both trim/length
          fit fit/left fit/both tab-to space-to wrt wrt/unshared dsp
          pretty pretty/unshared slashified maybe-slashified
          num num/si num/fit num/comma radix fix decimal-align ellipses
          upcase downcase titlecase pad-char comma-char decimal-char
          with-width wrap-lines fold-lines justify
          make-string-fmt-transformer
          make-space make-nl-space display-to-string write-to-string
          fmt-columns columnar tabular line-numbers)
  (import (except (rnrs base) error)
          (rename (only (rnrs base) error)
                  (error rnrs:error))
          (rnrs unicode)
          (rnrs control)
          (except (rnrs lists) remove)
          ;; fmt 按 SRFI 1 使用谓词版 remove（iron-046：SRFI 1 的 remove 即 R6RS 的 remp）
          (rename (only (rnrs lists) remp) (remp remove))
          (only (ironscheme) make-list)
          (rnrs arithmetic bitwise)
          (rnrs io simple)
          (rnrs io ports)
          (rnrs mutable-pairs)
          (rnrs r5rs)
          (rnrs hashtables)
          (only (ironscheme) open-output-string get-output-string)
          (ironscheme std lists)
          (ironscheme std strings)
          (wak private let-optionals)
          (wak private include))

  ;; 原用 SRFI 69 的散列表（iron-046 改为 R6RS 散列表；SRFI 69 的名字在 std hashtables 中已废弃）
  (define (make-eq?-table) (make-eq-hashtable))
  (define (hash-table-ref/default table key default) (hashtable-ref table key default))
  (define (hash-table-set! table key value) (hashtable-set! table key value))
  (define (hash-table-walk table proc)
    (let-values (((keys values) (hashtable-entries table)))
      (vector-for-each proc keys values)))
  
  (define (error . args)
    (apply rnrs:error "fmt" args))
  
  (define call-with-output-string call-with-string-output-port)
  (define read-line get-line)
  
  (include-file ((wak fmt private) mantissa))
  (include-file ((wak fmt private) fmt))
  (include-file ((wak fmt private) fmt-pretty))
  (include-file ((wak fmt private) fmt-column)))
