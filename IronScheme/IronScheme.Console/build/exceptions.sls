#| License
Copyright (c) 2007-2016 Llewellyn Pritchard
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

(library (ironscheme exceptions)
  (export
    with-exception-handler
    guard
    raise
    else
    =>
    assertion-violation
    error
    raise-continuable
    dynamic-wind
    io-decoding-error
    io-encoding-error
    undefined-error
    lexical-error
    syntax-error
    file-not-found-violation
    i/o-port-violation
    file-already-exists-violation
    file-in-use-violation
    values)
  (import 
    ;(psyntax config) 
    (only (ironscheme) import make-stacktrace-condition stacktrace-condition? display-stacktrace ungensym make-parameter parameterize)
    (ironscheme clr)
    (ironscheme unsafe)
    (ironscheme contracts)
    (except (rnrs) 
      with-exception-handler 
      raise 
      raise-continuable 
      assertion-violation 
      error
      dynamic-wind
      values))
      
  (clr-using IronScheme.Core)
      
  (define (values . x)
    (if (and (not (null? x))
             (null? (cdr x)))
        (car x)
        (clr-new MultipleValues (list->vector x))))      
    
  (define (dynamic-wind in proc out)
    (in)
    ($try/finally (proc)
                  (out)))      

  (define *current-exception-handlers*
    (make-parameter
      (list 
        (lambda (condition)
          ($throw (clr-new IronScheme.Core.SchemeException condition))))))

  (define/contract (with-exception-handler handler:procedure thunk:procedure)
    (with-exception-handlers (cons handler (*current-exception-handlers*))
                             thunk))

  (define (with-exception-handlers new-handlers thunk)
    (parameterize ((*current-exception-handlers* new-handlers)) (thunk)))
          
  (define (add-stacktrace con)
    (if (or (not (display-stacktrace))
            (not (serious-condition? con))
            (not (condition? con))
            (non-continuable-violation? con)
            (stacktrace-condition? con))
        con
        (let ((cc (simple-conditions con)))
          (apply condition
                 (append cc
                        (list (make-stacktrace-condition
                                (clr-static-call IronScheme.Core.Exceptions 
                                                 GetStackTrace))))))))

  (define (raise obj)
    (let ((obj (add-stacktrace obj)))
      (let ((handlers (*current-exception-handlers*)))
        (with-exception-handlers (cdr handlers)
          (lambda ()
            ((car handlers) obj)
            (raise
              (condition
                (make-non-continuable-violation)
                (make-message-condition "handler returned"))))))))

  (define (raise-continuable obj)
    (let ((obj (add-stacktrace obj)))
      (let ((handlers (*current-exception-handlers*)))
        (with-exception-handlers (cdr handlers)
          (lambda ()
            ((car handlers) obj))))))
          
  (define (assertion-violation who msg . irritants)
    (raise
      (condition
        (make-assertion-violation)
        (if who (make-who-condition who) (condition))
        (make-message-condition msg)
        (make-irritants-condition irritants))))

  (define (error who msg . irritants)
    (raise
      (condition
        (make-error)
        (if who (make-who-condition who) (condition))
        (make-message-condition msg)
        (make-irritants-condition irritants))))
        
  (define (io-decoding-error)
    (raise (make-i/o-decoding-error #f)))
            
  (define (io-encoding-error)
    (raise (make-i/o-encoding-error #f #f)))
        
  (define (undefined-error sym)
    (raise 
      (condition
        (make-undefined-violation)
        (make-message-condition "attempted to use undefined symbol")
        (make-irritants-condition (list (ungensym sym))))))
        
  (define (lexical-error msg what)
    (raise 
      (condition
        (make-lexical-violation)
        (make-message-condition msg)
        (make-irritants-condition (list what)))))           

  (define (syntax-error who msg form subform)
    (raise 
      (condition
        (make-who-condition who)
        (make-message-condition msg)
        (make-syntax-violation form subform))))
        
  (define (file-not-found-violation who msg filename)
    (raise
      (condition
        (make-assertion-violation)
        (if who (make-who-condition who) (condition))
        (make-message-condition msg)
        (make-i/o-file-does-not-exist-error filename))))  

  (define (i/o-port-violation who msg port)
    (raise
      (condition
        (make-assertion-violation)
        (if who (make-who-condition who) (condition))
        (make-message-condition msg)
        (make-i/o-port-error port))))

  (define (file-already-exists-violation who filename)
    (raise
      (condition
        (if who (make-who-condition who) (condition))
        (make-i/o-file-already-exists-error filename))))
        
  (define (file-in-use-violation who filename)
    (raise
      (condition
        (if who (make-who-condition who) (condition))
        (make-i/o-file-protection-error filename))))

  ;; 新运行时（IronScheme.Core）经 RuntimeHooks 回调这些过程，取代旧 Glue.il 对 boot dll 的直接引用
  ($set-runtime-hook! 'raise raise)
  ($set-runtime-hook! 'raise-continuable raise-continuable)
  ($set-runtime-hook! 'with-exception-handler with-exception-handler)
  ($set-runtime-hook! 'assertion-violation assertion-violation)
  ($set-runtime-hook! 'undefined-error undefined-error)
  ($set-runtime-hook! 'lexical-error lexical-error)
  ($set-runtime-hook! 'syntax-error syntax-error)
  ($set-runtime-hook! 'i/o-port-violation i/o-port-violation)
  ($set-runtime-hook! 'file-not-found-violation file-not-found-violation)
  ($set-runtime-hook! 'file-in-use-violation file-in-use-violation)
  ($set-runtime-hook! 'file-already-exists-violation file-already-exists-violation)
  ($set-runtime-hook! 'io-decoding-error io-decoding-error)
  ($set-runtime-hook! 'io-encoding-error io-encoding-error))