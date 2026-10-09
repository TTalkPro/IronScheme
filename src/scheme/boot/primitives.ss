;;; 原语表：由 IronScheme.PrimGen 从 IronScheme.Core 生成，请勿手工修改。
;;; 设计：designs/03-compiler.md §6；任务：tasks/iron-012-primgen.md
;;;
;;; (primitive 名字 重载 …)
;;;   重载 = (overload "类型全名" "方法名" 固定参数个数 剩余参数? (标志 …) 内联模板)
;;;   标志：pure（可常量折叠）、unsafe（不做类型检查）、allow-tail-call；内联模板为名字或 #f
;;; (special 名字 种类)：编译器专门处理的原语；同名的 primitive 条目（若有）是非内联时的后备实现
(primitive-table 1
  (primitive $annotation-expression
    (overload "IronScheme.Core.AnnotationPrimitives" "Expression" 1 #f (pure unsafe) #f))
  (primitive $annotation-source
    (overload "IronScheme.Core.AnnotationPrimitives" "Source" 1 #f (pure unsafe) #f))
  (primitive $annotation-stripped
    (overload "IronScheme.Core.AnnotationPrimitives" "Stripped" 1 #f (pure unsafe) #f))
  (primitive $annotation?
    (overload "IronScheme.Core.AnnotationPrimitives" "IsAnnotation" 1 #f (pure unsafe) #f))
  (primitive $application-directory
    (overload "IronScheme.Core.HostPrimitives" "ApplicationDirectory" 0 #f (unsafe) #f))
  (primitive $bignum->bytes
    (overload "IronScheme.Core.HostPrimitives" "BignumToBytes" 1 #f (pure unsafe) #f))
  (primitive $bignum->fixnum
    (overload "IronScheme.Core.HostPrimitives" "BignumToFixnum" 1 #f (pure unsafe) #f))
  (primitive $bignum->flonum
    (overload "IronScheme.Core.HostPrimitives" "BignumToFlonum" 1 #f (pure unsafe) #f))
  (primitive $bignum->string
    (overload "IronScheme.Core.HostPrimitives" "BignumToString" 2 #f (pure unsafe) #f))
  (primitive $bignum-and
    (overload "IronScheme.Core.HostPrimitives" "BignumAnd" 2 #f (pure unsafe) #f))
  (primitive $bignum-bit-count
    (overload "IronScheme.Core.HostPrimitives" "BignumBitCount" 1 #f (pure unsafe) #f))
  (primitive $bignum-bit-length
    (overload "IronScheme.Core.HostPrimitives" "BignumBitLength" 1 #f (pure unsafe) #f))
  (primitive $bignum-bit-set?
    (overload "IronScheme.Core.HostPrimitives" "IsBignumBitSet" 2 #f (pure unsafe) #f))
  (primitive $bignum-expt
    (overload "IronScheme.Core.HostPrimitives" "BignumExpt" 2 #f (pure unsafe) #f))
  (primitive $bignum-first-bit-set
    (overload "IronScheme.Core.HostPrimitives" "BignumFirstBitSet" 1 #f (pure unsafe) #f))
  (primitive $bignum-fits-fixnum?
    (overload "IronScheme.Core.HostPrimitives" "BignumFitsFixnum" 1 #f (pure unsafe) #f))
  (primitive $bignum-ior
    (overload "IronScheme.Core.HostPrimitives" "BignumIor" 2 #f (pure unsafe) #f))
  (primitive $bignum-negative?
    (overload "IronScheme.Core.HostPrimitives" "IsBignumNegative" 1 #f (pure unsafe) #f))
  (primitive $bignum-not
    (overload "IronScheme.Core.HostPrimitives" "BignumNot" 1 #f (pure unsafe) #f))
  (primitive $bignum-quotient
    (overload "IronScheme.Core.HostPrimitives" "BignumQuotient" 2 #f (pure unsafe) #f))
  (primitive $bignum-remainder
    (overload "IronScheme.Core.HostPrimitives" "BignumRemainder" 2 #f (pure unsafe) #f))
  (primitive $bignum-reverse-bits
    (overload "IronScheme.Core.HostPrimitives" "BignumReverseBits" 2 #f (pure unsafe) #f))
  (primitive $bignum-shift-left
    (overload "IronScheme.Core.HostPrimitives" "BignumShiftLeft" 2 #f (pure unsafe) #f))
  (primitive $bignum-shift-right
    (overload "IronScheme.Core.HostPrimitives" "BignumShiftRight" 2 #f (pure unsafe) #f))
  (primitive $bignum-xor
    (overload "IronScheme.Core.HostPrimitives" "BignumXor" 2 #f (pure unsafe) #f))
  (primitive $bignum?
    (overload "IronScheme.Core.HostPrimitives" "IsBignum" 1 #f (pure unsafe) #f))
  (primitive $binary-input-port?
    (overload "IronScheme.Core.PortPrimitives" "IsBinaryInputPort" 1 #f (pure unsafe) #f))
  (primitive $binary-output-port?
    (overload "IronScheme.Core.PortPrimitives" "IsBinaryOutputPort" 1 #f (pure unsafe) #f))
  (primitive $binary-port?
    (overload "IronScheme.Core.PortPrimitives" "IsBinaryPort" 1 #f (pure unsafe) #f))
  (primitive $boolean?
    (overload "IronScheme.Core.HostPrimitives" "IsBoolean" 1 #f (pure unsafe) #f))
  (primitive $buffered-port?
    (overload "IronScheme.Core.PortPrimitives" "IsBufferedPort" 1 #f (pure unsafe) #f))
  (primitive $bytes->bignum
    (overload "IronScheme.Core.HostPrimitives" "BytesToBignum" 1 #f (pure unsafe) #f))
  (primitive $bytes->double
    (overload "IronScheme.Core.HostPrimitives" "BytesToDouble" 1 #f (pure unsafe) #f))
  (primitive $bytes->single
    (overload "IronScheme.Core.HostPrimitives" "BytesToSingle" 1 #f (pure unsafe) #f))
  (primitive $bytes->sint
    (overload "IronScheme.Core.HostPrimitives" "BytesToSint" 2 #f (pure unsafe) #f))
  (primitive $bytes->uint
    (overload "IronScheme.Core.HostPrimitives" "BytesToUint" 2 #f (pure unsafe) #f))
  (primitive $bytevector-clone
    (overload "IronScheme.Core.HostPrimitives" "BytevectorClone" 1 #f (unsafe) #f))
  (primitive $bytevector-copy!
    (overload "IronScheme.Core.HostPrimitives" "BytevectorCopy" 5 #f (unsafe) #f))
  (primitive $bytevector-length
    (overload "IronScheme.Core.HostPrimitives" "BytevectorLength" 1 #f (pure unsafe) #f))
  (primitive $bytevector-output-port-extract
    (overload "IronScheme.Core.PortPrimitives" "BytevectorOutputPortExtract" 1 #f (unsafe) #f))
  (primitive $bytevector-ref
    (overload "IronScheme.Core.Unsafe" "ByteVectorRef" 2 #f (pure unsafe) $bytevector-ref))
  (primitive $bytevector-reverse!
    (overload "IronScheme.Core.HostPrimitives" "BytevectorReverse" 1 #f (unsafe) #f))
  (primitive $bytevector-set!
    (overload "IronScheme.Core.Unsafe" "ByteVectorSet" 3 #f (unsafe) $bytevector-set!))
  (primitive $bytevector-truncate
    (overload "IronScheme.Core.PortPrimitives" "BytevectorTruncate" 2 #f (unsafe) #f))
  (primitive $bytevector?
    (overload "IronScheme.Core.HostPrimitives" "IsBytevector" 1 #f (pure unsafe) #f))
  (primitive $car
    (overload "IronScheme.Core.Unsafe" "Car" 1 #f (pure unsafe) $car))
  (primitive $cdr
    (overload "IronScheme.Core.Unsafe" "Cdr" 1 #f (pure unsafe) $cdr))
  (primitive $char->integer
    (overload "IronScheme.Core.HostPrimitives" "CharToInteger" 1 #f (pure unsafe) #f))
  (primitive $char-alphabetic?
    (overload "IronScheme.Core.HostPrimitives" "IsCharAlphabetic" 1 #f (pure unsafe) #f))
  (primitive $char-downcase
    (overload "IronScheme.Core.HostPrimitives" "CharDowncase" 1 #f (pure unsafe) #f))
  (primitive $char-general-category
    (overload "IronScheme.Core.HostPrimitives" "CharGeneralCategory" 1 #f (pure unsafe) #f))
  (primitive $char-numeric?
    (overload "IronScheme.Core.HostPrimitives" "IsCharNumeric" 1 #f (pure unsafe) #f))
  (primitive $char-upcase
    (overload "IronScheme.Core.HostPrimitives" "CharUpcase" 1 #f (pure unsafe) #f))
  (primitive $char-whitespace?
    (overload "IronScheme.Core.HostPrimitives" "IsCharWhitespace" 1 #f (pure unsafe) #f))
  (primitive $char?
    (overload "IronScheme.Core.HostPrimitives" "IsChar" 1 #f (pure unsafe) #f))
  (primitive $chars->string
    (overload "IronScheme.Core.HostPrimitives" "CharsToString" 1 #f (unsafe) #f))
  (primitive $check-initialized
    (overload "IronScheme.Core.Calls" "CheckInitialized" 2 #f () #f))
  (primitive $codec-get-bytes
    (overload "IronScheme.Core.HostPrimitives" "CodecGetBytes" 2 #f (unsafe) #f))
  (primitive $codec-get-string
    (overload "IronScheme.Core.HostPrimitives" "CodecGetString" 2 #f (unsafe) #f))
  (primitive $codec?
    (overload "IronScheme.Core.PortPrimitives" "IsCodec" 1 #f (pure unsafe) #f))
  (primitive $compare-time
    (overload "IronScheme.Core.HostPrimitives" "CompareTime" 2 #f (pure unsafe) #f))
  (primitive $complex-acos
    (overload "IronScheme.Core.HostPrimitives" "ComplexAcos" 1 #f (pure unsafe) #f))
  (primitive $complex-asin
    (overload "IronScheme.Core.HostPrimitives" "ComplexAsin" 1 #f (pure unsafe) #f))
  (primitive $complex-atan
    (overload "IronScheme.Core.HostPrimitives" "ComplexAtan" 1 #f (pure unsafe) #f))
  (primitive $complex-cos
    (overload "IronScheme.Core.HostPrimitives" "ComplexCos" 1 #f (pure unsafe) #f))
  (primitive $complex-cosh
    (overload "IronScheme.Core.HostPrimitives" "ComplexCosh" 1 #f (pure unsafe) #f))
  (primitive $complex-exp
    (overload "IronScheme.Core.HostPrimitives" "ComplexExp" 1 #f (pure unsafe) #f))
  (primitive $complex-expt
    (overload "IronScheme.Core.HostPrimitives" "ComplexExpt" 2 #f (pure unsafe) #f))
  (primitive $complex-log
    (overload "IronScheme.Core.HostPrimitives" "ComplexLog" 1 #f (pure unsafe) #f))
  (primitive $complex-sin
    (overload "IronScheme.Core.HostPrimitives" "ComplexSin" 1 #f (pure unsafe) #f))
  (primitive $complex-sinh
    (overload "IronScheme.Core.HostPrimitives" "ComplexSinh" 1 #f (pure unsafe) #f))
  (primitive $complex-sqrt
    (overload "IronScheme.Core.HostPrimitives" "ComplexSqrt" 1 #f (pure unsafe) #f))
  (primitive $complex-tan
    (overload "IronScheme.Core.HostPrimitives" "ComplexTan" 1 #f (pure unsafe) #f))
  (primitive $complex-tanh
    (overload "IronScheme.Core.HostPrimitives" "ComplexTanh" 1 #f (pure unsafe) #f))
  (primitive $complexnum->rectnum
    (overload "IronScheme.Core.HostPrimitives" "ComplexnumToRectnum" 1 #f (pure unsafe) #f))
  (primitive $complexnum-imag
    (overload "IronScheme.Core.HostPrimitives" "ComplexnumImag" 1 #f (pure unsafe) #f))
  (primitive $complexnum-real
    (overload "IronScheme.Core.HostPrimitives" "ComplexnumReal" 1 #f (pure unsafe) #f))
  (primitive $complexnum?
    (overload "IronScheme.Core.HostPrimitives" "IsComplexnum" 1 #f (pure unsafe) #f))
  (primitive $compound-condition?
    (overload "IronScheme.Core.HostPrimitives" "IsCompoundCondition" 1 #f (pure unsafe) #f))
  (primitive $condition?
    (overload "IronScheme.Core.HostPrimitives" "IsCondition" 1 #f (pure unsafe) #f))
  (primitive $console-error-port
    (overload "IronScheme.Core.PortPrimitives" "ConsoleError" 0 #f (unsafe) #f))
  (primitive $console-foreground-color
    (overload "IronScheme.Core.HostPrimitives" "ConsoleForegroundColor" 0 #f (unsafe) #f))
  (primitive $console-input-port
    (overload "IronScheme.Core.PortPrimitives" "ConsoleInput" 0 #f (unsafe) #f))
  (primitive $console-output-port
    (overload "IronScheme.Core.PortPrimitives" "ConsoleOutput" 0 #f (unsafe) #f))
  (primitive $cpu-architecture
    (overload "IronScheme.Core.HostPrimitives" "CpuArchitecture" 0 #f (pure unsafe) #f))
  (primitive $culture-country
    (overload "IronScheme.Core.HostPrimitives" "CultureCountry" 0 #f (unsafe) #f))
  (primitive $culture-language
    (overload "IronScheme.Core.HostPrimitives" "CultureLanguage" 0 #f (unsafe) #f))
  (primitive $culture-name
    (overload "IronScheme.Core.HostPrimitives" "CultureName" 0 #f (unsafe) #f))
  (primitive $current-directory
    (overload "IronScheme.Core.HostPrimitives" "CurrentDirectory" 0 #f (unsafe) #f))
  (primitive $current-handlers
    (overload "IronScheme.Core.ExceptionHandlers" "Current" 0 #f (unsafe) #f))
  (primitive $custom-port-input
    (overload "IronScheme.Core.PortPrimitives" "CustomPortInput" 1 #f (pure unsafe) #f))
  (primitive $custom-port-output
    (overload "IronScheme.Core.PortPrimitives" "CustomPortOutput" 1 #f (pure unsafe) #f))
  (primitive $custom-textual-port?
    (overload "IronScheme.Core.PortPrimitives" "IsCustomTextualPort" 1 #f (pure unsafe) #f))
  (primitive $delete-file
    (overload "IronScheme.Core.HostPrimitives" "DeleteFile" 1 #f (unsafe) #f))
  (primitive $directory-create
    (overload "IronScheme.Core.HostPrimitives" "DirectoryCreate" 1 #f (unsafe) #f))
  (primitive $directory-exists?
    (overload "IronScheme.Core.HostPrimitives" "DirectoryExists" 1 #f (unsafe) #f))
  (primitive $directory-files
    (overload "IronScheme.Core.HostPrimitives" "DirectoryFiles" 2 #f (unsafe) #f))
  (primitive $double->bytes
    (overload "IronScheme.Core.HostPrimitives" "DoubleToBytes" 1 #f (pure unsafe) #f))
  (primitive $eq-hashtable?
    (overload "IronScheme.Core.HostPrimitives" "IsEqHashtable" 1 #f (pure unsafe) #f))
  (primitive $exact-compare
    (overload "IronScheme.Core.HostPrimitives" "ExactCompare" 2 #f (pure unsafe) #f))
  (primitive $exception->string
    (overload "IronScheme.Core.HostPrimitives" "ExceptionToString" 1 #f (unsafe) #f))
  (primitive $exception-message
    (overload "IronScheme.Core.HostPrimitives" "ExceptionMessage" 1 #f (unsafe) #f))
  (primitive $exception?
    (overload "IronScheme.Core.HostPrimitives" "IsException" 1 #f (pure unsafe) #f))
  (primitive $exit
    (overload "IronScheme.Core.HostPrimitives" "Exit" 1 #f (unsafe) #f))
  (primitive $file-exists?
    (overload "IronScheme.Core.HostPrimitives" "FileExists" 1 #f (unsafe) #f))
  (primitive $file-last-write-time
    (overload "IronScheme.Core.HostPrimitives" "FileLastWriteTime" 1 #f (unsafe) #f))
  (primitive $file-mtime
    (overload "IronScheme.Core.HostPrimitives" "FileMtime" 1 #f (unsafe) #f))
  (primitive $fixnum->bignum
    (overload "IronScheme.Core.HostPrimitives" "FixnumToBignum" 1 #f (pure unsafe) #f))
  (primitive $fixnum->flonum
    (overload "IronScheme.Core.HostPrimitives" "FixnumToFlonum" 1 #f (pure unsafe) #f))
  (primitive $fixnum->string
    (overload "IronScheme.Core.HostPrimitives" "FixnumToString" 2 #f (pure unsafe) #f))
  (primitive $fixnum?
    (overload "IronScheme.Core.HostPrimitives" "IsFixnum" 1 #f (pure unsafe) #f))
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
  (primitive $flabs
    (overload "IronScheme.Core.HostPrimitives" "FlAbs" 1 #f (pure unsafe) #f))
  (primitive $flacos
    (overload "IronScheme.Core.HostPrimitives" "FlAcos" 1 #f (pure unsafe) #f))
  (primitive $flasin
    (overload "IronScheme.Core.HostPrimitives" "FlAsin" 1 #f (pure unsafe) #f))
  (primitive $flatan
    (overload "IronScheme.Core.HostPrimitives" "FlAtan" 1 #f (pure unsafe) #f))
  (primitive $flatan2
    (overload "IronScheme.Core.HostPrimitives" "FlAtan2" 2 #f (pure unsafe) #f))
  (primitive $flceiling
    (overload "IronScheme.Core.HostPrimitives" "FlCeiling" 1 #f (pure unsafe) #f))
  (primitive $flcos
    (overload "IronScheme.Core.HostPrimitives" "FlCos" 1 #f (pure unsafe) #f))
  (primitive $flcosh
    (overload "IronScheme.Core.HostPrimitives" "FlCosh" 1 #f (pure unsafe) #f))
  (primitive $flexp
    (overload "IronScheme.Core.HostPrimitives" "FlExp" 1 #f (pure unsafe) #f))
  (primitive $flexpt
    (overload "IronScheme.Core.HostPrimitives" "FlExpt" 2 #f (pure unsafe) #f))
  (primitive $flfloor
    (overload "IronScheme.Core.HostPrimitives" "FlFloor" 1 #f (pure unsafe) #f))
  (primitive $flinfinite?
    (overload "IronScheme.Core.HostPrimitives" "IsFlInfinite" 1 #f (pure unsafe) #f))
  (primitive $fllog
    (overload "IronScheme.Core.HostPrimitives" "FlLog" 1 #f (pure unsafe) #f))
  (primitive $fllog2
    (overload "IronScheme.Core.HostPrimitives" "FlLog2" 2 #f (pure unsafe) #f))
  (primitive $flnan?
    (overload "IronScheme.Core.HostPrimitives" "IsFlNan" 1 #f (pure unsafe) #f))
  (primitive $flonum->ratnum
    (overload "IronScheme.Core.HostPrimitives" "FlonumToRatnum" 1 #f (pure unsafe) #f))
  (primitive $flonum?
    (overload "IronScheme.Core.HostPrimitives" "IsFlonum" 1 #f (pure unsafe) #f))
  (primitive $flround
    (overload "IronScheme.Core.HostPrimitives" "FlRound" 1 #f (pure unsafe) #f))
  (primitive $flsin
    (overload "IronScheme.Core.HostPrimitives" "FlSin" 1 #f (pure unsafe) #f))
  (primitive $flsinh
    (overload "IronScheme.Core.HostPrimitives" "FlSinh" 1 #f (pure unsafe) #f))
  (primitive $flsqrt
    (overload "IronScheme.Core.HostPrimitives" "FlSqrt" 1 #f (pure unsafe) #f))
  (primitive $fltan
    (overload "IronScheme.Core.HostPrimitives" "FlTan" 1 #f (pure unsafe) #f))
  (primitive $fltanh
    (overload "IronScheme.Core.HostPrimitives" "FlTanh" 1 #f (pure unsafe) #f))
  (primitive $fltruncate
    (overload "IronScheme.Core.HostPrimitives" "FlTruncate" 1 #f (pure unsafe) #f))
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
  (primitive $fxabs
    (overload "IronScheme.Core.HostPrimitives" "FxAbs" 1 #f (pure unsafe) #f))
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
  (primitive $gc-collect
    (overload "IronScheme.Core.HostPrimitives" "GcCollect" 0 #f (unsafe) #f))
  (primitive $gensym-realm
    (overload "IronScheme.Core.SymbolPrimitives" "GensymRealm" 0 #f () #f)
    (overload "IronScheme.Core.SymbolPrimitives" "GensymRealm" 1 #f () #f))
  (primitive $gensym-scope
    (overload "IronScheme.Core.SymbolPrimitives" "GensymScope" 0 #f () #f)
    (overload "IronScheme.Core.SymbolPrimitives" "GensymScope" 1 #f () #f))
  (primitive $get-environment-variable
    (overload "IronScheme.Core.HostPrimitives" "GetEnvironmentVariable" 1 #f (unsafe) #f))
  (primitive $get-output-string
    (overload "IronScheme.Core.PortPrimitives" "GetOutputString" 1 #f (unsafe) #f))
  (primitive $hashtable-clear!
    (overload "IronScheme.Core.HostPrimitives" "HashtableClear" 1 #f (unsafe) #f))
  (primitive $hashtable-clone
    (overload "IronScheme.Core.HostPrimitives" "HashtableClone" 1 #f (unsafe) #f))
  (primitive $hashtable-contains?
    (overload "IronScheme.Core.HostPrimitives" "HashtableContains" 2 #f (unsafe) #f))
  (primitive $hashtable-count
    (overload "IronScheme.Core.HostPrimitives" "HashtableCount" 1 #f (unsafe) #f))
  (primitive $hashtable-equivalence-function
    (overload "IronScheme.Core.HostPrimitives" "HashtableEquivalenceFunction" 1 #f (pure unsafe) #f))
  (primitive $hashtable-from-null
    (overload "IronScheme.Core.HostPrimitives" "HashtableFromNull" 1 #f (pure unsafe) #f))
  (primitive $hashtable-get
    (overload "IronScheme.Core.HostPrimitives" "HashtableGet" 2 #f (unsafe) #f))
  (primitive $hashtable-hash-function
    (overload "IronScheme.Core.HostPrimitives" "HashtableHashFunction" 1 #f (pure unsafe) #f))
  (primitive $hashtable-keys
    (overload "IronScheme.Core.HostPrimitives" "HashtableKeys" 1 #f (unsafe) #f))
  (primitive $hashtable-mutable?
    (overload "IronScheme.Core.HostPrimitives" "IsHashtableMutable" 1 #f (pure unsafe) #f))
  (primitive $hashtable-put!
    (overload "IronScheme.Core.HostPrimitives" "HashtablePut" 3 #f (unsafe) #f))
  (primitive $hashtable-readonly-copy
    (overload "IronScheme.Core.HostPrimitives" "HashtableReadOnlyCopy" 1 #f (unsafe) #f))
  (primitive $hashtable-remove!
    (overload "IronScheme.Core.HostPrimitives" "HashtableRemove" 2 #f (unsafe) #f))
  (primitive $hashtable-to-null
    (overload "IronScheme.Core.HostPrimitives" "HashtableToNull" 1 #f (pure unsafe) #f))
  (primitive $hashtable?
    (overload "IronScheme.Core.HostPrimitives" "IsHashtable" 1 #f (pure unsafe) #f))
  (primitive $immutable-string?
    (overload "IronScheme.Core.HostPrimitives" "IsImmutableString" 1 #f (pure unsafe) #f))
  (primitive $inexact-compare
    (overload "IronScheme.Core.HostPrimitives" "InexactCompare" 2 #f (pure unsafe) #f))
  (primitive $input-port?
    (overload "IronScheme.Core.PortPrimitives" "IsInputPort" 1 #f (pure unsafe) #f))
  (primitive $integer->char
    (overload "IronScheme.Core.HostPrimitives" "IntegerToChar" 1 #f (pure unsafe) #f))
  (primitive $latin-1-codec
    (overload "IronScheme.Core.PortPrimitives" "Latin1Codec" 0 #f (unsafe) #f))
  (primitive $list->typed-vector
    (overload "IronScheme.Core.HostPrimitives" "ListToTypedVector" 2 #f (unsafe) #f))
  (primitive $list->vector
    (overload "IronScheme.Core.HostPrimitives" "ListToVector" 1 #f (unsafe) #f))
  (primitive $list-copy
    (overload "IronScheme.Core.HostPrimitives" "ListCopy" 1 #f (unsafe) #f))
  (primitive $machine-name
    (overload "IronScheme.Core.HostPrimitives" "MachineName" 0 #f (unsafe) #f))
  (primitive $make-bytevector
    (overload "IronScheme.Core.HostPrimitives" "MakeBytevector" 1 #f (unsafe) #f))
  (primitive $make-complexnum
    (overload "IronScheme.Core.HostPrimitives" "MakeComplexnum" 2 #f (pure unsafe) #f))
  (primitive $make-custom-binary-input-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomBinaryInputPort" 5 #f (unsafe) #f))
  (primitive $make-custom-binary-input/output-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomBinaryInputOutputPort" 6 #f (unsafe) #f))
  (primitive $make-custom-binary-output-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomBinaryOutputPort" 5 #f (unsafe) #f))
  (primitive $make-custom-textual-input-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomTextualInputPort" 5 #f (unsafe) #f))
  (primitive $make-custom-textual-input/output-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomTextualInputOutputPort" 6 #f (unsafe) #f))
  (primitive $make-custom-textual-output-port
    (overload "IronScheme.Core.PortPrimitives" "MakeCustomTextualOutputPort" 5 #f (unsafe) #f))
  (primitive $make-eq-hashtable
    (overload "IronScheme.Core.HostPrimitives" "MakeEqHashtable" 1 #f (unsafe) #f))
  (primitive $make-guid
    (overload "IronScheme.Core.HostPrimitives" "MakeGuid" 0 #f (unsafe) #f))
  (primitive $make-hashtable
    (overload "IronScheme.Core.HostPrimitives" "MakeHashtable" 3 #f (unsafe) #f))
  (primitive $make-multiple-values
    (overload "IronScheme.Core.HostPrimitives" "MakeMultipleValues" 1 #f (unsafe) #f))
  (primitive $make-param-slot
    (overload "IronScheme.Core.Parameters" "MakeSlot" 1 #f (unsafe) #f))
  (primitive $make-random
    (overload "IronScheme.Core.HostPrimitives" "MakeRandom" 0 #f (unsafe) #f))
  (primitive $make-rectnum
    (overload "IronScheme.Core.HostPrimitives" "MakeRectnum" 2 #f (pure unsafe) #f))
  (primitive $make-semaphore
    (overload "IronScheme.Core.HostPrimitives" "MakeSemaphore" 1 #f (unsafe) #f))
  (primitive $make-string
    (overload "IronScheme.Core.HostPrimitives" "MakeString" 2 #f (unsafe) #f))
  (primitive $make-transcoder
    (overload "IronScheme.Core.PortPrimitives" "MakeTranscoder" 3 #f (unsafe) #f))
  (primitive $make-typed-vector
    (overload "IronScheme.Core.HostPrimitives" "MakeTypedVector" 2 #f (unsafe) #f))
  (primitive $make-utf16-codec
    (overload "IronScheme.Core.HostPrimitives" "MakeUtf16Codec" 1 #f (unsafe) #f))
  (primitive $make-utf32-codec
    (overload "IronScheme.Core.HostPrimitives" "MakeUtf32Codec" 1 #f (unsafe) #f))
  (primitive $make-vector
    (overload "IronScheme.Core.HostPrimitives" "MakeVector" 1 #f (unsafe) #f))
  (primitive $multiple-values?
    (overload "IronScheme.Core.HostPrimitives" "IsMultipleValues" 1 #f (pure unsafe) #f))
  (primitive $mutable-string?
    (overload "IronScheme.Core.HostPrimitives" "IsMutableString" 1 #f (pure unsafe) #f))
  (primitive $native-eol-style
    (overload "IronScheme.Core.PortPrimitives" "NativeEolStyle" 0 #f (pure unsafe) #f))
  (primitive $native-transcoder
    (overload "IronScheme.Core.PortPrimitives" "NativeTranscoder" 0 #f (pure unsafe) #f))
  (primitive $object->string
    (overload "IronScheme.Core.HostPrimitives" "ObjectToString" 1 #f (unsafe) #f))
  (primitive $object-hash
    (overload "IronScheme.Core.HostPrimitives" "ObjectHash" 1 #f (pure unsafe) #f))
  (primitive $open-bytevector-input-port
    (overload "IronScheme.Core.PortPrimitives" "OpenBytevectorInputPort" 1 #f (unsafe) #f))
  (primitive $open-bytevector-output-port
    (overload "IronScheme.Core.PortPrimitives" "OpenBytevectorOutputPort" 0 #f (unsafe) #f))
  (primitive $open-file-input-port
    (overload "IronScheme.Core.PortPrimitives" "OpenFileInputPort" 2 #f (unsafe) #f))
  (primitive $open-input-file
    (overload "IronScheme.Core.PortPrimitives" "OpenInputFile" 1 #f (unsafe) #f))
  (primitive $open-output-file
    (overload "IronScheme.Core.PortPrimitives" "OpenOutputFile" 2 #f (unsafe) #f))
  (primitive $open-output-string
    (overload "IronScheme.Core.PortPrimitives" "OpenOutputString" 0 #f (unsafe) #f))
  (primitive $open-string-input-port
    (overload "IronScheme.Core.PortPrimitives" "OpenStringInputPort" 1 #f (unsafe) #f))
  (primitive $os-description
    (overload "IronScheme.Core.HostPrimitives" "OsDescription" 0 #f (pure unsafe) #f))
  (primitive $os-name
    (overload "IronScheme.Core.HostPrimitives" "OsName" 0 #f (pure unsafe) #f))
  (primitive $os-windows?
    (overload "IronScheme.Core.HostPrimitives" "IsWindows" 0 #f (pure unsafe) #f))
  (primitive $output-port?
    (overload "IronScheme.Core.PortPrimitives" "IsOutputPort" 1 #f (pure unsafe) #f))
  (primitive $param-ref
    (overload "IronScheme.Core.Parameters" "Ref" 1 #f (unsafe) #f))
  (primitive $param-set!
    (overload "IronScheme.Core.Parameters" "Set" 2 #f (unsafe) #f))
  (primitive $path-change-extension
    (overload "IronScheme.Core.HostPrimitives" "PathChangeExtension" 2 #f (pure unsafe) #f))
  (primitive $path-combine
    (overload "IronScheme.Core.HostPrimitives" "PathCombine" 2 #f (pure unsafe) #f))
  (primitive $path-directory-name
    (overload "IronScheme.Core.HostPrimitives" "PathDirectoryName" 1 #f (pure unsafe) #f))
  (primitive $path-extension
    (overload "IronScheme.Core.HostPrimitives" "PathExtension" 1 #f (pure unsafe) #f))
  (primitive $path-file-name
    (overload "IronScheme.Core.HostPrimitives" "PathFileName" 1 #f (pure unsafe) #f))
  (primitive $path-full
    (overload "IronScheme.Core.HostPrimitives" "PathFull" 1 #f (unsafe) #f))
  (primitive $path-trim-separator
    (overload "IronScheme.Core.HostPrimitives" "PathTrimSeparator" 1 #f (pure unsafe) #f))
  (primitive $plain-string?
    (overload "IronScheme.Core.HostPrimitives" "IsPlainString" 1 #f (pure unsafe) #f))
  (primitive $port-close-input
    (overload "IronScheme.Core.PortPrimitives" "CloseInput" 1 #f (unsafe) #f))
  (primitive $port-close-output
    (overload "IronScheme.Core.PortPrimitives" "CloseOutput" 1 #f (unsafe) #f))
  (primitive $port-flush
    (overload "IronScheme.Core.PortPrimitives" "Flush" 1 #f (unsafe) #f))
  (primitive $port-has-position?
    (overload "IronScheme.Core.PortPrimitives" "HasPosition" 1 #f (unsafe) #f))
  (primitive $port-has-set-position?
    (overload "IronScheme.Core.PortPrimitives" "HasSetPosition" 1 #f (unsafe) #f))
  (primitive $port-peek-char
    (overload "IronScheme.Core.PortPrimitives" "PeekChar" 1 #f (unsafe) #f))
  (primitive $port-position
    (overload "IronScheme.Core.PortPrimitives" "Position" 1 #f (unsafe) #f))
  (primitive $port-read-all
    (overload "IronScheme.Core.PortPrimitives" "ReadAll" 1 #f (unsafe) #f))
  (primitive $port-read-byte
    (overload "IronScheme.Core.PortPrimitives" "ReadByte" 1 #f (unsafe) #f))
  (primitive $port-read-bytes
    (overload "IronScheme.Core.PortPrimitives" "ReadBytes" 4 #f (unsafe) #f))
  (primitive $port-read-char
    (overload "IronScheme.Core.PortPrimitives" "ReadChar" 1 #f (unsafe) #f))
  (primitive $port-read-line
    (overload "IronScheme.Core.PortPrimitives" "ReadLine" 1 #f (unsafe) #f))
  (primitive $port-read-string
    (overload "IronScheme.Core.PortPrimitives" "ReadString" 2 #f (unsafe) #f))
  (primitive $port-set-position!
    (overload "IronScheme.Core.PortPrimitives" "SetPosition" 2 #f (unsafe) #f))
  (primitive $port-transcoder
    (overload "IronScheme.Core.PortPrimitives" "PortTranscoder" 1 #f (unsafe) #f))
  (primitive $port-write-byte
    (overload "IronScheme.Core.PortPrimitives" "WriteByte" 2 #f (unsafe) #f))
  (primitive $port-write-bytes
    (overload "IronScheme.Core.PortPrimitives" "WriteBytes" 4 #f (unsafe) #f))
  (primitive $port-write-char
    (overload "IronScheme.Core.PortPrimitives" "WriteChar" 2 #f (unsafe) #f))
  (primitive $port-write-string
    (overload "IronScheme.Core.PortPrimitives" "WriteString" 2 #f (unsafe) #f))
  (primitive $procedure-arity
    (overload "IronScheme.Core.HostPrimitives" "ProcedureArity" 1 #f (pure unsafe) #f))
  (primitive $procedure-form
    (overload "IronScheme.Core.HostPrimitives" "ProcedureForm" 1 #f (pure unsafe) #f))
  (primitive $procedure-name
    (overload "IronScheme.Core.HostPrimitives" "ProcedureName" 1 #f (pure unsafe) #f))
  (primitive $procedure?
    (overload "IronScheme.Core.HostPrimitives" "IsProcedure" 1 #f (pure unsafe) #f))
  (primitive $program-failed
    (overload "IronScheme.Core.HostPrimitives" "ProgramFailed" 0 #f (unsafe) #f))
  (primitive $random-next
    (overload "IronScheme.Core.HostPrimitives" "RandomNext" 2 #f (unsafe) #f))
  (primitive $ratnum->flonum
    (overload "IronScheme.Core.HostPrimitives" "RatnumToFlonum" 1 #f (pure unsafe) #f))
  (primitive $ratnum-denominator
    (overload "IronScheme.Core.HostPrimitives" "RatnumDenominator" 1 #f (pure unsafe) #f))
  (primitive $ratnum-numerator
    (overload "IronScheme.Core.HostPrimitives" "RatnumNumerator" 1 #f (pure unsafe) #f))
  (primitive $ratnum?
    (overload "IronScheme.Core.HostPrimitives" "IsRatnum" 1 #f (pure unsafe) #f))
  (primitive $rcd-parent
    (overload "IronScheme.Core.HostPrimitives" "RcdParent" 1 #f (pure unsafe) #f))
  (primitive $rcd-protocol
    (overload "IronScheme.Core.HostPrimitives" "RcdProtocol" 1 #f (pure unsafe) #f))
  (primitive $rcd-rtd
    (overload "IronScheme.Core.HostPrimitives" "RcdRtd" 1 #f (pure unsafe) #f))
  (primitive $rcd?
    (overload "IronScheme.Core.HostPrimitives" "IsRcd" 1 #f (pure unsafe) #f))
  (primitive $real-compare
    (overload "IronScheme.Core.HostPrimitives" "RealCompare" 2 #f (pure unsafe) #f))
  (primitive $record-fields
    (overload "IronScheme.Core.HostPrimitives" "RecordFields" 1 #f (pure unsafe) #f))
  (primitive $record-rtd
    (overload "IronScheme.Core.HostPrimitives" "RecordRtd" 1 #f (pure unsafe) #f))
  (primitive $record?
    (overload "IronScheme.Core.HostPrimitives" "IsRecord" 1 #f (pure unsafe) #f))
  (primitive $rectnum->complexnum
    (overload "IronScheme.Core.HostPrimitives" "RectnumToComplexnum" 1 #f (pure unsafe) #f))
  (primitive $rectnum-imag
    (overload "IronScheme.Core.HostPrimitives" "RectnumImag" 1 #f (pure unsafe) #f))
  (primitive $rectnum-real
    (overload "IronScheme.Core.HostPrimitives" "RectnumReal" 1 #f (pure unsafe) #f))
  (primitive $rectnum?
    (overload "IronScheme.Core.HostPrimitives" "IsRectnum" 1 #f (pure unsafe) #f))
  (primitive $rtd-field-mutable?
    (overload "IronScheme.Core.HostPrimitives" "IsRtdFieldMutable" 2 #f (pure unsafe) #f))
  (primitive $rtd-field-names
    (overload "IronScheme.Core.HostPrimitives" "RtdFieldNames" 1 #f (pure unsafe) #f))
  (primitive $rtd-generative?
    (overload "IronScheme.Core.HostPrimitives" "IsRtdGenerative" 1 #f (pure unsafe) #f))
  (primitive $rtd-name
    (overload "IronScheme.Core.HostPrimitives" "RtdName" 1 #f (pure unsafe) #f))
  (primitive $rtd-opaque?
    (overload "IronScheme.Core.HostPrimitives" "IsRtdOpaque" 1 #f (pure unsafe) #f))
  (primitive $rtd-parent
    (overload "IronScheme.Core.HostPrimitives" "RtdParent" 1 #f (pure unsafe) #f))
  (primitive $rtd-sealed?
    (overload "IronScheme.Core.HostPrimitives" "IsRtdSealed" 1 #f (pure unsafe) #f))
  (primitive $rtd-uid
    (overload "IronScheme.Core.HostPrimitives" "RtdUid" 1 #f (pure unsafe) #f))
  (primitive $rtd?
    (overload "IronScheme.Core.HostPrimitives" "IsRtd" 1 #f (pure unsafe) #f))
  (primitive $runtime-hooks-missing
    (overload "IronScheme.Core.RuntimeHooks" "Missing" 0 #f () #f))
  (primitive $semaphore-release!
    (overload "IronScheme.Core.HostPrimitives" "SemaphoreRelease" 1 #f (unsafe) #f))
  (primitive $semaphore-wait!
    (overload "IronScheme.Core.HostPrimitives" "SemaphoreWait" 1 #f (unsafe) #f))
  (primitive $set-car!
    (overload "IronScheme.Core.HostPrimitives" "SetCar" 2 #f (unsafe) #f))
  (primitive $set-cdr!
    (overload "IronScheme.Core.HostPrimitives" "SetCdr" 2 #f (unsafe) #f))
  (primitive $set-compile-target!
    (overload "IronScheme.Core.HostPrimitives" "SetCompileTarget" 1 #f (unsafe) #f))
  (primitive $set-console-foreground-color!
    (overload "IronScheme.Core.HostPrimitives" "SetConsoleForegroundColor" 1 #f (unsafe) #f))
  (primitive $set-current-directory!
    (overload "IronScheme.Core.HostPrimitives" "SetCurrentDirectory" 1 #f (unsafe) #f))
  (primitive $set-current-handlers!
    (overload "IronScheme.Core.ExceptionHandlers" "Set" 1 #f (unsafe) #f))
  (primitive $set-runtime-hook!
    (overload "IronScheme.Core.RuntimeHooks" "SetRuntimeHook" 2 #f () #f))
  (primitive $single->bytes
    (overload "IronScheme.Core.HostPrimitives" "SingleToBytes" 1 #f (pure unsafe) #f))
  (primitive $sint->bytes
    (overload "IronScheme.Core.HostPrimitives" "SintToBytes" 2 #f (pure unsafe) #f))
  (primitive $stack-trace
    (overload "IronScheme.Core.HostPrimitives" "StackTrace" 0 #f (unsafe) #f))
  (primitive $standard-error-port
    (overload "IronScheme.Core.PortPrimitives" "StandardError" 0 #f (unsafe) #f))
  (primitive $standard-input-port
    (overload "IronScheme.Core.PortPrimitives" "StandardInput" 0 #f (unsafe) #f))
  (primitive $standard-output-port
    (overload "IronScheme.Core.PortPrimitives" "StandardOutput" 0 #f (unsafe) #f))
  (primitive $start-thread
    (overload "IronScheme.Core.HostPrimitives" "StartThread" 1 #f (unsafe) #f))
  (primitive $string->immutable
    (overload "IronScheme.Core.HostPrimitives" "StringToImmutable" 1 #f (unsafe) #f))
  (primitive $string->list
    (overload "IronScheme.Core.HostPrimitives" "StringToList" 1 #f (unsafe) #f))
  (primitive $string->symbol
    (overload "IronScheme.Core.HostPrimitives" "StringToSymbol" 1 #f (pure unsafe) #f))
  (primitive $string-append
    (overload "IronScheme.Core.HostPrimitives" "StringAppend" 1 #f (unsafe) #f))
  (primitive $string-ci-hash
    (overload "IronScheme.Core.HostPrimitives" "StringCiHash" 1 #f (pure unsafe) #f))
  (primitive $string-compare
    (overload "IronScheme.Core.HostPrimitives" "StringCompare" 2 #f (pure unsafe) #f))
  (primitive $string-copy
    (overload "IronScheme.Core.HostPrimitives" "StringCopy" 1 #f (unsafe) #f))
  (primitive $string-fill!
    (overload "IronScheme.Core.HostPrimitives" "StringFill" 2 #f (unsafe) #f))
  (primitive $string-format
    (overload "IronScheme.Core.HostPrimitives" "StringFormat" 2 #f (unsafe) #f))
  (primitive $string-hash
    (overload "IronScheme.Core.HostPrimitives" "StringHash" 1 #f (pure unsafe) #f))
  (primitive $string-length
    (overload "IronScheme.Core.HostPrimitives" "StringLength" 1 #f (pure unsafe) #f))
  (primitive $string-lower
    (overload "IronScheme.Core.HostPrimitives" "StringLower" 1 #f (pure unsafe) #f))
  (primitive $string-mutable?
    (overload "IronScheme.Core.HostPrimitives" "IsStringMutable" 1 #f (pure unsafe) #f))
  (primitive $string-normalize
    (overload "IronScheme.Core.HostPrimitives" "StringNormalize" 2 #f (pure unsafe) #f))
  (primitive $string-ref
    (overload "IronScheme.Core.HostPrimitives" "StringRef" 2 #f (pure unsafe) #f))
  (primitive $string-replace
    (overload "IronScheme.Core.HostPrimitives" "StringReplace" 3 #f (pure unsafe) #f))
  (primitive $string-set!
    (overload "IronScheme.Core.HostPrimitives" "StringSet" 3 #f (unsafe) #f))
  (primitive $substring
    (overload "IronScheme.Core.HostPrimitives" "Substring" 3 #f (unsafe) #f))
  (primitive $symbol-name
    (overload "IronScheme.Core.HostPrimitives" "SymbolName" 1 #f (pure unsafe) #f))
  (primitive $symbol-value-set!
    (overload "IronScheme.Core.HostPrimitives" "SymbolValueSet" 2 #f (unsafe) #f))
  (primitive $symbol?
    (overload "IronScheme.Core.HostPrimitives" "IsSymbol" 1 #f (pure unsafe) #f))
  (primitive $system-exception?
    (overload "IronScheme.Core.HostPrimitives" "IsSystemException" 1 #f (pure unsafe) #f))
  (primitive $textual-port?
    (overload "IronScheme.Core.PortPrimitives" "IsTextualPort" 1 #f (pure unsafe) #f))
  (primitive $timezone-offset-seconds
    (overload "IronScheme.Core.HostPrimitives" "TimezoneOffsetSeconds" 0 #f (unsafe) #f))
  (primitive $transcoded-port
    (overload "IronScheme.Core.PortPrimitives" "TranscodedPort" 2 #f (unsafe) #f))
  (primitive $transcoder-codec
    (overload "IronScheme.Core.PortPrimitives" "TranscoderCodec" 1 #f (pure unsafe) #f))
  (primitive $transcoder-eol-style
    (overload "IronScheme.Core.PortPrimitives" "TranscoderEolStyle" 1 #f (pure unsafe) #f))
  (primitive $transcoder-error-handling-mode
    (overload "IronScheme.Core.PortPrimitives" "TranscoderHandlingMode" 1 #f (pure unsafe) #f))
  (primitive $transcoder?
    (overload "IronScheme.Core.PortPrimitives" "IsTranscoder" 1 #f (pure unsafe) #f))
  (primitive $type-name
    (overload "IronScheme.Core.HostPrimitives" "TypeName" 1 #f (pure unsafe) #f))
  (primitive $type-of
    (overload "IronScheme.Core.HostPrimitives" "TypeOf" 1 #f (pure unsafe) #f))
  (primitive $type?
    (overload "IronScheme.Core.HostPrimitives" "IsType" 1 #f (pure unsafe) #f))
  (primitive $typed-vector?
    (overload "IronScheme.Core.HostPrimitives" "IsTypedVector" 2 #f (pure unsafe) #f))
  (primitive $uint->bytes
    (overload "IronScheme.Core.HostPrimitives" "UintToBytes" 2 #f (pure unsafe) #f))
  (primitive $uninitialized
    (overload "IronScheme.Core.Calls" "UninitializedValue" 0 #f () #f))
  (primitive $utf-16-codec
    (overload "IronScheme.Core.PortPrimitives" "Utf16Codec" 0 #f (unsafe) #f))
  (primitive $utf-8-codec
    (overload "IronScheme.Core.PortPrimitives" "Utf8Codec" 0 #f (unsafe) #f))
  (primitive $valuetype-vector?
    (overload "IronScheme.Core.HostPrimitives" "IsValueTypeVector" 1 #f (pure unsafe) #f))
  (primitive $vector->list
    (overload "IronScheme.Core.HostPrimitives" "VectorToList" 1 #f (unsafe) #f))
  (primitive $vector-clone
    (overload "IronScheme.Core.HostPrimitives" "VectorClone" 1 #f (unsafe) #f))
  (primitive $vector-index-of
    (overload "IronScheme.Core.HostPrimitives" "VectorIndexOf" 2 #f (unsafe) #f))
  (primitive $vector-length
    (overload "IronScheme.Core.HostPrimitives" "VectorLength" 1 #f (pure unsafe) #f))
  (primitive $vector-ref
    (overload "IronScheme.Core.Unsafe" "VectorRef" 2 #f (pure unsafe) $vector-ref))
  (primitive $vector-reverse!
    (overload "IronScheme.Core.HostPrimitives" "VectorReverse" 1 #f (unsafe) #f))
  (primitive $vector-set!
    (overload "IronScheme.Core.Unsafe" "VectorSet" 3 #f (unsafe) $vector-set!))
  (primitive $vector-sort!
    (overload "IronScheme.Core.HostPrimitives" "VectorSort" 2 #f (unsafe) #f))
  (primitive $vector?
    (overload "IronScheme.Core.HostPrimitives" "IsVector" 1 #f (pure unsafe) #f))
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
  (primitive host-type
    (overload "IronScheme.Core.HostPrimitives" "HostType" 0 #f (pure) #f))
  (primitive host-version
    (overload "IronScheme.Core.HostPrimitives" "HostVersion" 0 #f (pure) #f))
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
  (primitive load-fasl
    (overload "IronScheme.Core.ModuleLoader" "LoadFasl" 1 #f () #f))
  (primitive load-library-dll
    (overload "IronScheme.Core.ModuleLoader" "LoadLibraryDll" 1 #f () #f))
  (primitive lw-debug-mode?
    (overload "IronScheme.Core.Builtins" "IsLightWeightDebugMode" 0 #f () #f)
    (overload "IronScheme.Core.Builtins" "IsLightWeightDebugMode" 1 #f () #f))
  (primitive machine-type
    (overload "IronScheme.Core.HostPrimitives" "MachineType" 0 #f (pure) #f))
  (primitive make-annotation
    (overload "IronScheme.Core.Builtins" "MakeAnnotation" 3 #f () #f))
  (primitive make-record-constructor-descriptor
    (overload "IronScheme.Core.Records" "MakeRecordConstructorDescriptor" 3 #f () #f))
  (primitive make-record-type-descriptor
    (overload "IronScheme.Core.Records" "MakeRecordTypeDescriptor" 6 #f () #f)
    (overload "IronScheme.Core.Records" "MakeRecordTypeDescriptorTyped" 7 #f () #f))
  (primitive make-task-source
    (overload "IronScheme.Core.Tasks" "MakeSource" 0 #f () #f))
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
  (primitive target-host-type
    (overload "IronScheme.Core.HostPrimitives" "TargetHostType" 0 #f () #f))
  (primitive task-completed?
    (overload "IronScheme.Core.Tasks" "IsCompleted" 1 #f () #f))
  (primitive task-delay
    (overload "IronScheme.Core.Tasks" "Delay" 1 #f () #f))
  (primitive task-faulted?
    (overload "IronScheme.Core.Tasks" "IsFaulted" 1 #f () #f))
  (primitive task-from-exception
    (overload "IronScheme.Core.Tasks" "FromException" 1 #f () #f))
  (primitive task-from-result
    (overload "IronScheme.Core.Tasks" "FromResult" 1 #f () #f))
  (primitive task-result
    (overload "IronScheme.Core.Tasks" "Result" 1 #f () #f))
  (primitive task-run
    (overload "IronScheme.Core.Tasks" "Run" 1 #f () #f))
  (primitive task-source-set-exception!
    (overload "IronScheme.Core.Tasks" "SourceSetException" 2 #f () #f))
  (primitive task-source-set-result!
    (overload "IronScheme.Core.Tasks" "SourceSetResult" 2 #f () #f))
  (primitive task-source-task
    (overload "IronScheme.Core.Tasks" "SourceTask" 1 #f () #f))
  (primitive task-then
    (overload "IronScheme.Core.Tasks" "Then" 2 #f () #f))
  (primitive task-when-all
    (overload "IronScheme.Core.Tasks" "WhenAll" 1 #f () #f))
  (primitive task-when-any
    (overload "IronScheme.Core.Tasks" "WhenAny" 1 #f () #f))
  (primitive task-yield
    (overload "IronScheme.Core.Tasks" "Yield" 0 #f () #f))
  (primitive task?
    (overload "IronScheme.Core.Tasks" "IsTask" 1 #f (pure) #f))
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
  (special await await)   ; (await e)：只能在 async-lambda 体内，等待 task 完成并取结果（designs/10-async.md）
  (special call-with-current-continuation escape-frame)   ; 同 call/cc
  (special call-with-values call-with-values)   ; 消费者为字面 lambda 时可内联
  (special call/cc escape-frame)   ; 逃逸续延捕获帧（02 §6）
  (special values values)   ; 在 Scheme 中定义（boot/exceptions.sls）；作为原语出现时编译为多值构造
)
