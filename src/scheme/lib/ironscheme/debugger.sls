#| License
Copyright (c) 2007-2016 Llewellyn Pritchard
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; 交互式调试器。原实现建立在旧运行时（DLR）的轻量调试设施上（Microsoft.Scripting.Debugging 的
;;; StackFrame、SourceSpan 与 lw-debugger 钩子）；新运行时不提供调试器（designs/02-runtime.md §10），
;;; 这里保留导出，调用时报"不支持"（iron-031）。
(library (ironscheme debugger)
  (export 
    step-into
    ;breakpoints
    )
  (import (ironscheme))

  (define (step-into filename)
    (assertion-violation 'step-into "the debugger is not supported by the new runtime" filename)))
