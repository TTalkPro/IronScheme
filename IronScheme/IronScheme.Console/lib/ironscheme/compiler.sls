#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; 编译驱动（designs/03-compiler.md §8，iron-027）。
;;;
;;;   (compile-forms->lcil forms 程序集名 模块类型名) → Lcil 的 S 表达式
;;;   (compile->lcil-text forms 程序集名 模块类型名)  → Lcil 文本
;;;   (compile-core e)            eval：发射到内存，返回执行它的无参过程
;;;   (compile-library 文件 e)    e 求值得到 13 元素的库描述列表；生成库 dll，入口返回该列表
;;;   (compile-bootfile forms [文件]) 核心形式列表 → boot 镜像 dll（入口 #Module::Initialize）
;;;
;;; 编译器只读 Lcore 与原语表，不读运行时状态（03 §1）。发射器（IronScheme.Emit）在同一进程中以库 API 调用。
(library (ironscheme compiler)
  (export
    compile-forms->lcil compile->lcil-text compile->lcil-text-from-sexpr
    compile-core compile-library compile-bootfile
    front-end
    primitive-table-file)
  (import
    (rnrs)
    (only (ironscheme) make-parameter)
    (ironscheme clr)
    (ironscheme compiler primitives)
    (ironscheme compiler parse)
    (ironscheme compiler front)
    (ironscheme compiler closures)
    (ironscheme compiler codegen)
    (ironscheme compiler lcil))

  (clr-reference IronScheme.Emit)

  ;; Lcore → L3；返回 (values L3 analysis)
  (define (front-end x)
    (let* ((l0 (parse-core x))
           (an (analyze l0))
           (l1 (cp0-lite (check-forward (simplify-letrec l0 an) an)))
           (l2 (convert-assignments l1 an)))
      (values (uncover-free l2) an)))

  (define (compile-forms->lcil forms assembly-name module-name)
    (let-values (((lcil consts) (compile-forms->lcil* forms assembly-name module-name #f)))
      lcil))

  ;; 返回 (values Lcil 常量列表)；live? 见 generate-unit
  (define (compile-forms->lcil* forms assembly-name module-name live?)
    (let ((massigned (make-eq-hashtable)))
      (let ((l3s (map (lambda (f)
                        (let-values (((l3 an) (front-end f)))
                          (let-values (((ks vs) (hashtable-entries (analysis-massigned an))))
                            (vector-for-each (lambda (k) (hashtable-set! massigned k #t)) ks))
                          l3))
                      forms)))
        (generate-unit l3s assembly-name module-name massigned live?))))

  (define (compile->lcil-text forms assembly-name module-name)
    (lcil->string (compile-forms->lcil forms assembly-name module-name)))

  (define (compile->lcil-text-from-sexpr lcil) (lcil->string lcil))

  (define eval-counter 0)

  (define (compile-core e)
    (set! eval-counter (+ eval-counter 1))
    (let*-values (((name) (string-append "eval$" (number->string eval-counter)))
                  ((lcil consts) (compile-forms->lcil* (list e) name "#Module" #t))
                  ((asm) (clr-static-call IronScheme.Emit.LcilEmitter (EmitInMemory String String Object[])
                                          (lcil->string lcil) name (list->vector consts))))
      (lambda ()
        (clr-static-call IronScheme.Core.ModuleLoader Run asm))))

  (define (assembly-name-of filename)
    (let* ((f (clr-static-call System.IO.Path GetFileNameWithoutExtension filename)))
      f))

  (define (compile-library filename e)
    (let ((text (compile->lcil-text (list e) (assembly-name-of filename) "#Module")))
      (clr-static-call IronScheme.Emit.LcilEmitter (Save String String String Boolean) text filename filename #f)
      #t))

  (define compile-bootfile
    (case-lambda
      ((forms) (compile-bootfile forms "ironscheme.boot.dll"))
      ((forms filename)
       (let ((text (compile->lcil-text forms (assembly-name-of filename) "#Module")))
         (clr-static-call IronScheme.Emit.LcilEmitter (Save String String String Boolean) text filename filename #f)
         #t)))))
