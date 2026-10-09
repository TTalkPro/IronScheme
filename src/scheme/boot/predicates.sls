#| License
Copyright (c) 2007-2016 Llewellyn Pritchard
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

(library (boot predicates)
  (export
    bignum?
    rectnum?
    ratnum?
    complexnum?
    flonum?
    fixnum?
    number?
    stringbuilder?
    string?
    clr-string?
    char?
    vector?
    bytevector?
    symbol?
    boolean?
    procedure?
    condition?
    valuetype-vector?)
  (import 
    (except 
      (rnrs)
      fixnum?
      flonum?
      number?
      string?
      char?
      vector?
      bytevector?
      symbol?
      boolean?
      procedure?
      condition?)
    (ironscheme unsafe)
    (ironscheme clr))
    
  (clr-using IronScheme.Core)
  (clr-using Oyster.Math)
  (clr-using System.Text)
  
  (define (valuetype-vector? obj)
    (and (clr-is Array obj)
         (let ((t (clr-call Type GetElementType (clr-call Object GetType obj))))
          (clr-prop-get Type IsValueType t))))
  
  (define (condition? obj)
    (clr-is IronScheme.Core.Condition obj))
    
  (define (fixnum? obj)
    (clr-is Int32 obj))
    
  (define (flonum? obj)
    (clr-is Double obj))

  (define (bignum? obj)
    (clr-is IntX obj))
    
  (define (rectnum? obj)
    (clr-is ComplexFraction obj)) 
  
  (define (ratnum? obj)
    (clr-is Fraction obj))
  
  (define (complexnum? obj)
    (clr-is Complex64 obj))
    
  (define (number? obj)
    ($or? (fixnum? obj)
          (flonum? obj)
          (bignum? obj)
          (ratnum? obj)
          (complexnum? obj)
          (rectnum? obj))) 

  (define (clr-string? obj)
    (clr-is String obj))

  ;; 不是 System.String 的 Scheme 字符串：SchemeString（可变串与含 BMP 外字符的不可变串，iron-055）；
  ;; 旧种子过渡期也认 StringBuilder。名字沿用旧称。
  (define (stringbuilder? obj)
    (or (clr-is SchemeString obj)
        (clr-is StringBuilder obj)))
    
  (define (string? obj)
    (or (clr-string? obj) 
        (stringbuilder? obj)))

  (define (char? obj)
    (or (clr-is Char obj)
        (clr-is SchemeChar obj)))

  (define (vector? obj)
    (clr-is Object[] obj))

  (define (bytevector? obj)
    (clr-is Byte[] obj))

  (define (symbol? obj)
    (clr-is Symbol obj))
    
  (define (boolean? obj)
    (clr-is Boolean obj))
   
  (define (procedure? obj)
    (clr-is Procedure obj)))
