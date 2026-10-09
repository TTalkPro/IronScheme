#| License
Copyright (c) 2007-2016 Llewellyn Pritchard
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

(library (boot misc)
  (export 
    procedure-arity
    procedure-name
    procedure-form
    procedure-environment
    make-guid
    typeof
    clr-type?
    set-symbol-value!
    gc-collect
    vector-reverse!
    vector-copy
    vector-contains?
    vector-index-of
    vector-binary-search
    )
  (import 
    (rnrs)
    (only (ironscheme) string-compare)
    (ironscheme contracts)
    (ironscheme clr))
  
  (clr-using IronScheme.Core)
  
  (define/contract (procedure-arity proc:procedure)
    (clr-prop-get Procedure Arity proc))
    
  (define/contract (procedure-name proc:procedure)
    (string->symbol (clr-prop-get Procedure Name proc)))

  ;; 每个子句一个值：(名字 . 形参)（编译器生成 Form 属性，iron-038）；未知时为 unspecified
  (define/contract (procedure-form proc:procedure)
    (let ((f (clr-prop-get Procedure Form proc)))
      (if (pair? f) (apply values f) f)))

  (define/contract (procedure-environment proc:procedure)
    #f)
    
  (define (make-guid)
    (clr-static-call Guid NewGuid))
  
  (define (typeof obj)
    (if (null? obj)
        (clr-type-of Object)
        (clr-call Object GetType obj))) 
        
  (define (clr-type? o)
    (clr-is Type o))
    
  (define (set-symbol-value! symbol value)
    (clr-static-call Builtins SetSymbolValueFast symbol value))
    
  (define (gc-collect)
    (clr-static-call GC Collect)) 
    
  ;; SRFI 133 的接口（iron-054；原来是 .NET 的 Array.BinarySearch：默认比较器，找不到时返回负数）：
  ;; (vector-binary-search 向量 值 比较过程 [start end])，(比较过程 元素 值) 返回负数 / 0 / 正数；
  ;; 找到时返回下标，否则 #f。省略比较过程时按实数、字符串、字符的自然序比较。
  (define (default-binary-search-compare x y)
    (cond
      [(and (real? x) (real? y)) (cond [(< x y) -1] [(> x y) 1] [else 0])]
      [(and (string? x) (string? y)) (string-compare x y)]
      [(and (char? x) (char? y)) (cond [(char<? x y) -1] [(char>? x y) 1] [else 0])]
      [else (assertion-violation 'vector-binary-search "no default ordering for these values" x y)]))

  (define/contract vector-binary-search
    (case-lambda
      [(vec value) (vector-binary-search vec value default-binary-search-compare)]
      [(vec value cmp) (vector-binary-search vec value cmp 0 (vector-length vec))]
      [(vec value cmp start) (vector-binary-search vec value cmp start (vector-length vec))]
      [(vec:vector value cmp:procedure start:fixnum end:fixnum)
        (unless (<= 0 start end (vector-length vec))
          (assertion-violation 'vector-binary-search "invalid range" start end))
        (let loop ((lo start) (hi end))
          (and (< lo hi)
               (let* ((mid (div (+ lo hi) 2))
                      (c (cmp (vector-ref vec mid) value)))
                 (cond
                   [(zero? c) mid]
                   [(negative? c) (loop (+ mid 1) hi)]
                   [else (loop lo mid)]))))]))
  
  (define/contract (vector-index-of vec:vector obj)
    (clr-static-call Array IndexOf vec obj))
    
  (define/contract (vector-contains? vec:vector obj)
    (fx>=? (clr-static-call Array IndexOf vec obj) 0))
    
  (define/contract (vector-copy vec:vector)
    (clr-call Array Clone vec))
    
  (define/contract (vector-reverse! vec:vector)
    (clr-static-call Array Reverse vec)))      