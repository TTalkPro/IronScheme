;;; 原语表：由 IronScheme.PrimGen 从 IronScheme.Core 生成，请勿手工修改。
;;; 设计：designs/03-compiler.md §6；任务：tasks/iron-012-primgen.md
;;;
;;; (primitive 名字 重载 …)
;;;   重载 = (overload "类型全名" "方法名" 固定参数个数 剩余参数? (标志 …) 内联模板)
;;;   标志：pure（可常量折叠）、unsafe（不做类型检查）、allow-tail-call；内联模板为名字或 #f
;;; (special 名字 种类)：编译器专门处理的原语；同名的 primitive 条目（若有）是非内联时的后备实现
(primitive-table 1
  (primitive $bytevector-ref
    (overload "IronScheme.Core.Unsafe" "ByteVectorRef" 2 #f (pure unsafe) $bytevector-ref))
  (primitive $bytevector-set!
    (overload "IronScheme.Core.Unsafe" "ByteVectorSet" 3 #f (unsafe) $bytevector-set!))
  (primitive $car
    (overload "IronScheme.Core.Unsafe" "Car" 1 #f (pure unsafe) $car))
  (primitive $cdr
    (overload "IronScheme.Core.Unsafe" "Cdr" 1 #f (pure unsafe) $cdr))
  (primitive $check-initialized
    (overload "IronScheme.Core.Calls" "CheckInitialized" 2 #f () #f))
  (primitive $fl*
    (overload "IronScheme.Core.Unsafe" "FlMul" 2 #f (pure unsafe) $fl*))
  (primitive $fl+
    (overload "IronScheme.Core.Unsafe" "FlAdd" 2 #f (pure unsafe) $fl+))
  (primitive $fl-
    (overload "IronScheme.Core.Unsafe" "FlNeg" 1 #f (pure unsafe) $fl-)
    (overload "IronScheme.Core.Unsafe" "FlSub" 2 #f (pure unsafe) $fl-))
  (primitive $fl/
    (overload "IronScheme.Core.Unsafe" "FlDiv" 2 #f (pure unsafe) $fl/))
  (primitive $fl<=?
    (overload "IronScheme.Core.Unsafe" "FlLe" 2 #f (pure unsafe) $fl<=?))
  (primitive $fl<?
    (overload "IronScheme.Core.Unsafe" "FlLt" 2 #f (pure unsafe) $fl<?))
  (primitive $fl=?
    (overload "IronScheme.Core.Unsafe" "FlEq" 2 #f (pure unsafe) $fl=?))
  (primitive $fl>=?
    (overload "IronScheme.Core.Unsafe" "FlGe" 2 #f (pure unsafe) $fl>=?))
  (primitive $fl>?
    (overload "IronScheme.Core.Unsafe" "FlGt" 2 #f (pure unsafe) $fl>?))
  (primitive $fx*
    (overload "IronScheme.Core.Unsafe" "FxMul" 2 #f (pure unsafe) $fx*))
  (primitive $fx+
    (overload "IronScheme.Core.Unsafe" "FxAdd" 2 #f (pure unsafe) $fx+))
  (primitive $fx-
    (overload "IronScheme.Core.Unsafe" "FxNeg" 1 #f (pure unsafe) $fx-)
    (overload "IronScheme.Core.Unsafe" "FxSub" 2 #f (pure unsafe) $fx-))
  (primitive $fx<=?
    (overload "IronScheme.Core.Unsafe" "FxLe" 2 #f (pure unsafe) $fx<=?))
  (primitive $fx<?
    (overload "IronScheme.Core.Unsafe" "FxLt" 2 #f (pure unsafe) $fx<?))
  (primitive $fx=?
    (overload "IronScheme.Core.Unsafe" "FxEq" 2 #f (pure unsafe) $fx=?))
  (primitive $fx>=?
    (overload "IronScheme.Core.Unsafe" "FxGe" 2 #f (pure unsafe) $fx>=?))
  (primitive $fx>?
    (overload "IronScheme.Core.Unsafe" "FxGt" 2 #f (pure unsafe) $fx>?))
  (primitive $fxand
    (overload "IronScheme.Core.Unsafe" "FxAnd" 2 #f (pure unsafe) $fxand))
  (primitive $fxarithmetic-shift-left
    (overload "IronScheme.Core.Unsafe" "FxShl" 2 #f (pure unsafe) $fxarithmetic-shift-left))
  (primitive $fxarithmetic-shift-right
    (overload "IronScheme.Core.Unsafe" "FxShr" 2 #f (pure unsafe) $fxarithmetic-shift-right))
  (primitive $fxdiv
    (overload "IronScheme.Core.Unsafe" "FxDiv" 2 #f (pure unsafe) $fxdiv))
  (primitive $fxdiv0
    (overload "IronScheme.Core.Unsafe" "FxDiv0" 2 #f (pure unsafe) $fxdiv0))
  (primitive $fxeven?
    (overload "IronScheme.Core.Unsafe" "FxEven" 1 #f (pure unsafe) $fxeven?))
  (primitive $fxior
    (overload "IronScheme.Core.Unsafe" "FxIor" 2 #f (pure unsafe) $fxior))
  (primitive $fxmod
    (overload "IronScheme.Core.Unsafe" "FxMod" 2 #f (pure unsafe) $fxmod))
  (primitive $fxmod0
    (overload "IronScheme.Core.Unsafe" "FxMod0" 2 #f (pure unsafe) $fxmod0))
  (primitive $fxnegative?
    (overload "IronScheme.Core.Unsafe" "FxNegative" 1 #f (pure unsafe) $fxnegative?))
  (primitive $fxnot
    (overload "IronScheme.Core.Unsafe" "FxNot" 1 #f (pure unsafe) $fxnot))
  (primitive $fxodd?
    (overload "IronScheme.Core.Unsafe" "FxOdd" 1 #f (pure unsafe) $fxodd?))
  (primitive $fxpositive?
    (overload "IronScheme.Core.Unsafe" "FxPositive" 1 #f (pure unsafe) $fxpositive?))
  (primitive $fxxor
    (overload "IronScheme.Core.Unsafe" "FxXor" 2 #f (pure unsafe) $fxxor))
  (primitive $fxzero?
    (overload "IronScheme.Core.Unsafe" "FxZero" 1 #f (pure unsafe) $fxzero?))
  (primitive $gensym-realm
    (overload "IronScheme.Core.SymbolPrimitives" "GensymRealm" 0 #f () #f)
    (overload "IronScheme.Core.SymbolPrimitives" "GensymRealm" 1 #f () #f))
  (primitive $gensym-scope
    (overload "IronScheme.Core.SymbolPrimitives" "GensymScope" 0 #f () #f)
    (overload "IronScheme.Core.SymbolPrimitives" "GensymScope" 1 #f () #f))
  (primitive $runtime-hooks-missing
    (overload "IronScheme.Core.RuntimeHooks" "Missing" 0 #f () #f))
  (primitive $set-runtime-hook!
    (overload "IronScheme.Core.RuntimeHooks" "SetRuntimeHook" 2 #f () #f))
  (primitive $uninitialized
    (overload "IronScheme.Core.Calls" "UninitializedValue" 0 #f () #f))
  (primitive $vector-ref
    (overload "IronScheme.Core.Unsafe" "VectorRef" 2 #f (pure unsafe) $vector-ref))
  (primitive $vector-set!
    (overload "IronScheme.Core.Unsafe" "VectorSet" 3 #f (unsafe) $vector-set!))
  (primitive apply
    (overload "IronScheme.Core.Control" "Apply" 1 #t (allow-tail-call) #f))
  (primitive bignum-sqrt
    (overload "IronScheme.Core.Builtins" "SqrtBigInteger" 1 #f (pure) #f))
  (primitive bignum-sqrt-exact
    (overload "IronScheme.Core.Builtins" "ExactSqrtBigInteger" 1 #f (pure) #f))
  (primitive bytevector->string
    (overload "IronScheme.Core.IO" "ByteVectorToString" 2 #f () #f))
  (primitive call-with-current-continuation
    (overload "IronScheme.Core.Control" "CallWithCurrentContinuation" 1 #f () #f))
  (primitive call-with-values
    (overload "IronScheme.Core.Control" "CallWithValues" 2 #f (allow-tail-call) #f))
  (primitive call/cc
    (overload "IronScheme.Core.Control" "CallWithCurrentContinuation" 1 #f () #f))
  (primitive car
    (overload "IronScheme.Core.Builtins" "Car" 1 #f () car))
  (primitive cdr
    (overload "IronScheme.Core.Builtins" "Cdr" 1 #f () cdr))
  (primitive command-line
    (overload "IronScheme.Core.Builtins" "CommandLine" 0 #f () #f))
  (primitive compile-to-current-directory?
    (overload "IronScheme.Core.Builtins" "CompileToCurrentDirectory" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "CompileToCurrentDirectory" 1 #f () #f))
  (primitive compress-constants?
    (overload "IronScheme.Core.Builtins" "CompressConstants" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "CompressConstants" 1 #f () #f))
  (primitive condition
    (overload "IronScheme.Core.Conditions" "MakeCondition" 0 #t () #f))
  (primitive condition-accessor
    (overload "IronScheme.Core.Conditions" "ConditionAccessor" 2 #f () #f))
  (primitive condition-predicate
    (overload "IronScheme.Core.Conditions" "ConditionPredicate" 1 #f () #f))
  (primitive cons
    (overload "IronScheme.Core.Builtins" "Cons" 2 #f () cons))
  (primitive debug-mode?
    (overload "IronScheme.Core.Builtins" "IsDebugMode" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "IsDebugMode" 1 #f () #f))
  (primitive decompose-flonum
    (overload "IronScheme.Core.Builtins" "DecomposeFlonum" 1 #f () #f))
  (primitive deserialize-port
    (overload "IronScheme.Core.Fasl" "DeserializePort" 1 #f () #f))
  (primitive deterministic-gensym?
    (overload "IronScheme.Core.Builtins" "DeterministicGensym" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "DeterministicGensym" 1 #f () #f))
  (primitive eof-object
    (overload "IronScheme.Core.Builtins" "EofObject" 0 #f () #f))
  (primitive eof-object?
    (overload "IronScheme.Core.Builtins" "IsEof" 1 #f () #f))
  (primitive eq?
    (overload "IronScheme.Core.Builtins" "IsEqual" 2 #f (pure) eq?))
  (primitive eqv?
    (overload "IronScheme.Core.Builtins" "IsEqualValue" 2 #f (pure) eqv?))
  (primitive ffi-callback-internal
    (overload "IronScheme.Core.Ffi" "Callback" 1 #t () #f))
  (primitive ffi-callout-internal
    (overload "IronScheme.Core.Ffi" "Callout" 1 #t () #f))
  (primitive fx*internal
    (overload "IronScheme.Core.Builtins" "FxMultiplyInternal" 2 #f (pure) #f))
  (primitive fx+internal
    (overload "IronScheme.Core.Builtins" "FxPlusInternal" 2 #f (pure) #f))
  (primitive fx-internal
    (overload "IronScheme.Core.Builtins" "FxMinusInternal" 2 #f (pure) #f))
  (primitive fxarithmetic-shift-left-internal
    (overload "IronScheme.Core.Builtins" "FxShiftLeftInternal" 2 #f (pure) #f))
  (primitive generic*
    (overload "IronScheme.Core.Builtins" "Multiply" 2 #f (pure) #f))
  (primitive generic+
    (overload "IronScheme.Core.Builtins" "Add" 2 #f (pure) #f))
  (primitive generic-
    (overload "IronScheme.Core.Builtins" "Subtract" 2 #f (pure) #f))
  (primitive generic-div
    (overload "IronScheme.Core.Builtins" "Div" 2 #f (pure) #f))
  (primitive generic-negate
    (overload "IronScheme.Core.Builtins" "Negate" 1 #f (pure) #f))
  (primitive generic/
    (overload "IronScheme.Core.Builtins" "Divide" 2 #f (pure) #f))
  (primitive gensym
    (overload "IronScheme.Core.SymbolPrimitives" "Gensym" 0 #f () #f)
    (overload "IronScheme.Core.SymbolPrimitives" "Gensym" 1 #f () #f))
  (primitive get-clr-type
    (overload "IronScheme.Core.Builtins" "GetClrType" 1 #f () #f)
    (overload "IronScheme.Core.Builtins" "GetClrType" 1 #t () #f))
  (primitive get-command-line
    (overload "IronScheme.Core.Builtins" "CommandLine" 0 #f () #f))
  (primitive get-library-paths
    (overload "IronScheme.Core.Builtins" "GetLibraryPaths" 0 #f () #f))
  (primitive hashtable-entries
    (overload "IronScheme.Core.Hashtables" "HashtableEntries" 1 #f () #f))
  (primitive hashtable-for-each
    (overload "IronScheme.Core.Hashtables" "HashtableForEach" 2 #f () #f))
  (primitive hashtable-map
    (overload "IronScheme.Core.Hashtables" "HashtableMap" 2 #f () #f))
  (primitive inexact=?
    (overload "IronScheme.Core.Builtins" "InexactEqual" 2 #f (pure) #f))
  (primitive ironscheme-runtime
    (overload "IronScheme.Core.Builtins" "GetRuntime" 0 #f () #f))
  (primitive ironscheme-version
    (overload "IronScheme.Core.Builtins" "Version" 0 #f () #f))
  (primitive list*
    (overload "IronScheme.Core.Builtins" "ListStar" 1 #t () #f)
    (overload "IronScheme.Core.Builtins" "ListStar" 2 #f () #f)
    (overload "IronScheme.Core.Builtins" "ListStar" 3 #f () #f)
    (overload "IronScheme.Core.Builtins" "ListStar" 4 #f () #f))
  (primitive list-prim
    (overload "IronScheme.Core.Builtins" "List" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "List" 0 #t () #f)
    (overload "IronScheme.Core.Builtins" "List" 1 #f () #f)
    (overload "IronScheme.Core.Builtins" "List" 2 #f () #f)
    (overload "IronScheme.Core.Builtins" "List" 3 #f () #f)
    (overload "IronScheme.Core.Builtins" "List" 4 #f () #f)
    (overload "IronScheme.Core.Builtins" "List" 5 #f () #f))
  (primitive load-library-dll
    (overload "IronScheme.Core.ModuleLoader" "LoadLibraryDll" 1 #f () #f))
  (primitive lw-debug-mode?
    (overload "IronScheme.Core.Builtins" "IsLightWeightDebugMode" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "IsLightWeightDebugMode" 1 #f () #f))
  (primitive make-annotation
    (overload "IronScheme.Core.Builtins" "MakeAnnotation" 3 #f () #f))
  (primitive make-record-constructor-descriptor
    (overload "IronScheme.Core.Records" "MakeRecordConstructorDescriptor" 3 #f () #f))
  (primitive make-record-type-descriptor
    (overload "IronScheme.Core.Records" "MakeRecordTypeDescriptor" 6 #f () #f)
    (overload "IronScheme.Core.Records" "MakeRecordTypeDescriptorTyped" 7 #f () #f))
  (primitive not
    (overload "IronScheme.Core.Builtins" "Not" 1 #f (pure) not))
  (primitive null?
    (overload "IronScheme.Core.Builtins" "IsNull" 1 #f (pure) null?))
  (primitive open-file-input/output-port
    (overload "IronScheme.Core.IO" "OpenFileInputOutputPort" 1 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileInputOutputPort" 2 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileInputOutputPort" 3 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileInputOutputPort" 4 #f () #f))
  (primitive open-file-output-port
    (overload "IronScheme.Core.IO" "OpenFileOutputPort" 1 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileOutputPort" 2 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileOutputPort" 3 #f () #f)
    (overload "IronScheme.Core.IO" "OpenFileOutputPort" 4 #f () #f))
  (primitive open-tcp-input/output-port
    (overload "IronScheme.Core.Builtins" "OpenTcpInputOutputPort" 3 #f () #f))
  (primitive pair?
    (overload "IronScheme.Core.Builtins" "IsPair" 1 #f (pure) pair?))
  (primitive pinvoke-call-internal
    (overload "IronScheme.Core.Ffi" "PInvokeCall" 3 #t () #f))
  (primitive pointer+
    (overload "IronScheme.Core.Builtins" "PointerAdd" 2 #f () #f))
  (primitive read-annotated
    (overload "IronScheme.Core.Builtins" "ReadAnnotated" 1 #f () #f))
  (primitive record-accessor
    (overload "IronScheme.Core.Records" "RecordAccessor" 2 #f () #f))
  (primitive record-constructor
    (overload "IronScheme.Core.Records" "RecordConstructor" 1 #f () #f))
  (primitive record-mutator
    (overload "IronScheme.Core.Records" "RecordMutator" 2 #f () #f))
  (primitive record-predicate
    (overload "IronScheme.Core.Records" "RecordPredicate" 1 #f () #f))
  (primitive record-rtd
    (overload "IronScheme.Core.Records" "RecordRtd" 1 #f () #f))
  (primitive record?
    (overload "IronScheme.Core.Records" "IsRecord" 1 #f () #f))
  (primitive remove-location
    (overload "IronScheme.Core.SymbolPrimitives" "RemoveLocation" 1 #f () #f))
  (primitive reverse!
    (overload "IronScheme.Core.Builtins" "NReverse" 1 #f () #f))
  (primitive serialize-port
    (overload "IronScheme.Core.Fasl" "SerializePort" 2 #f () #f))
  (primitive set-symbol-value!
    (overload "IronScheme.Core.SymbolPrimitives" "SetSymbolValue" 2 #f () #f))
  (primitive simple-conditions
    (overload "IronScheme.Core.Conditions" "SimpleConditions" 1 #f () #f))
  (primitive strict-mode?
    (overload "IronScheme.Core.Builtins" "StrictMode" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "StrictMode" 1 #f () #f))
  (primitive string->bytevector
    (overload "IronScheme.Core.IO" "StringToByteVector" 2 #f () #f))
  (primitive string->number
    (overload "IronScheme.Core.Builtins" "StringToNumber" 1 #f (pure) #f)
    (overload "IronScheme.Core.Builtins" "StringToNumber" 2 #f (pure) #f))
  (primitive string->symbol
    (overload "IronScheme.Core.SymbolPrimitives" "StringToSymbol" 1 #f (pure) #f))
  (primitive string->xml
    (overload "IronScheme.Core.Builtins" "StringToXml" 1 #f () #f))
  (primitive string-split
    (overload "IronScheme.Core.Builtins" "StringSplit" 1 #t () #f))
  (primitive symbol->string
    (overload "IronScheme.Core.SymbolPrimitives" "SymbolToString" 1 #f (pure) #f))
  (primitive symbol-bound?
    (overload "IronScheme.Core.SymbolPrimitives" "IsSymbolBound" 1 #f () #f))
  (primitive symbol-value
    (overload "IronScheme.Core.SymbolPrimitives" "SymbolValue" 1 #f () #f))
  (primitive time-it
    (overload "IronScheme.Core.Builtins" "TimeIt" 2 #f () #f))
  (primitive ungensym
    (overload "IronScheme.Core.SymbolPrimitives" "Ungensym" 1 #f (pure) #f))
  (primitive unspecified?
    (overload "IronScheme.Core.Builtins" "IsUnspecified" 1 #f () #f))
  (primitive vector
    (overload "IronScheme.Core.Builtins" "Vector" 0 #t () vector))
  (primitive vector-append
    (overload "IronScheme.Core.Builtins" "VectorAppend" 0 #t () #f))
  (primitive vector-filter
    (overload "IronScheme.Core.Builtins" "VectorFilter" 2 #f () #f))
  (primitive void
    (overload "IronScheme.Core.Builtins" "Void" 0 #f (pure) void))
  (primitive with-clr-exception-handler
    (overload "IronScheme.Core.Exceptions" "WithClrExceptionHandler" 2 #f () #f))
  (primitive with-timeout
    (overload "IronScheme.Core.Builtins" "WithTimeout" 2 #f () #f))
  (special $and? and)   ; 短路与，参数为未求值表达式，结果为 CLR bool
  (special $break break)   ; 调用 Debugger.Break
  (special $or? or)   ; 短路或，参数为未求值表达式，结果为 CLR bool
  (special $throw throw)   ; 抛出参数（一个 .NET 异常对象）
  (special $try/finally try-finally)   ; ($try/finally body finalizer)：finalizer 在 finally 中求值
  (special apply apply)   ; 展开最后一个列表参数
  (special call-with-current-continuation escape-frame)   ; 同 call/cc
  (special call-with-values call-with-values)   ; 消费者为字面 lambda 时可内联
  (special call/cc escape-frame)   ; 逃逸续延捕获帧（02 §6）
  (special values values)   ; 在 Scheme 中定义（build/exceptions.sls）；作为原语出现时编译为多值构造
)
