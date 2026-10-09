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
;;;   (compile-library-dll 文件 e) e 求值得到 13 元素的库描述列表；生成库 dll，入口返回该列表
;;;   (compile-bootfile forms [文件]) 核心形式列表 → boot 镜像 dll（入口 #Module::Initialize）
;;;
;;; 编译器只读 Lcore 与原语表，不读运行时状态（03 §1）。发射器（IronScheme.Emit）在同一进程中以库 API 调用。
(library (ironscheme compiler)
  (export
    compile-forms->lcil compile->lcil-text compile->lcil-text-from-sexpr
    compile-core compile-library-dll compile-bootfile
    front-end
    primitive-table-file
    canonical-gensyms
    current-compile-target)
  (import
    (rnrs)
    (only (ironscheme) make-parameter parameterize)
    (ironscheme clr)
    (ironscheme compiler primitives)
    (ironscheme compiler parse)
    (ironscheme compiler async)
    (ironscheme compiler languages)
    (ironscheme compiler front)
    (ironscheme compiler closures)
    (ironscheme compiler codegen)
    (ironscheme compiler targets)
    (ironscheme compiler lcil)
    (only (ironscheme unsafe) $set-compile-target!))

  (clr-reference IronScheme.Emit)

  ;; 编译目标（designs/11-portability.md §2 D6，iron-057）：符号，现在只有 clr；未知目标报错。
  ;; 设置时同步给运行时（target-host-type 原语，展开期的 cond-expand 用它）
  (define current-compile-target
    (make-parameter 'clr
      (lambda (t)
        (let ((name (target-name (target-of t))))
          ($set-compile-target! name)
          name))))

  ;; 调试：设置环境变量 IRONSCHEME_DUMP_PASSES=前缀 时，把各阶段的中间语言写到 <前缀>.l0 / .la / .l1 / .l2 / .l3
  ;; （.la 是 lower-async 的输出，10 §3.2）
  (define (dump-pass tag unparse x)
    (let ((prefix (clr-static-call System.Environment GetEnvironmentVariable "IRONSCHEME_DUMP_PASSES")))
      (when (string? prefix)
        (let ((f (string-append prefix "." tag)))
          (when (file-exists? f) (delete-file f))
          (call-with-output-file f (lambda (p) (write (unparse x) p)))))))

  ;; Lcore → L3；返回 (values L3 analysis)
  (define (front-end x)
    (let* ((l0 (parse-core x))
           (_ (dump-pass "l0" unparse-L0 l0))
           (l0 (lower-async l0))
           (_ (dump-pass "la" unparse-L0 l0))
           (an (analyze l0))
           (l1 (cp0-lite (check-forward (simplify-letrec l0 an) an)))
           (_ (dump-pass "l1" unparse-L1 l1))
           (l2 (convert-assignments l1 an))
           (_ (dump-pass "l2" unparse-L2 l2))
           (l3 (uncover-free l2)))
      (dump-pass "l3" unparse-L3 l3)
      (values l3 an)))

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
        (parameterize ((current-target (target-of (current-compile-target))))
          (generate-unit l3s assembly-name module-name massigned live?)))))

  (define (compile->lcil-text forms assembly-name module-name)
    (lcil->string (compile-forms->lcil forms assembly-name module-name)))

  (define (compile->lcil-text-from-sexpr lcil) (lcil->string lcil))

  (define eval-counter 0)

  ;; 调试：设置环境变量 IRONSCHEME_DUMP_FAILED_CORE=文件 时，编译失败的输入写到该文件
  (define (dump-failed-core e)
    (let ((f (clr-static-call System.Environment GetEnvironmentVariable "IRONSCHEME_DUMP_FAILED_CORE")))
      (when (string? f)
        (when (file-exists? f) (delete-file f))
        ;; 用 fasl 写出：输入中可能有语法对象等常量
        (let ((p (open-file-output-port f)))
          (clr-static-call IronScheme.Core.Fasl SerializePort e p)
          (close-port p)))))

  (define (compile-core e)
    (with-exception-handler
      (lambda (c) (dump-failed-core e) (raise-continuable c))
      (lambda () (compile-core* e))))

  (define (compile-core* e)
    (set! eval-counter (+ eval-counter 1))
    (let*-values (((name) (string-append "eval$" (number->string eval-counter)))
                  ((lcil consts) (compile-forms->lcil* (list e) name "#Module" #t))
                  ;; 直接交出 Lcil 的 S 表达式，不经文本（iron-033）；IRONSCHEME_DUMP_PASSES 的 .lcil 仍可用 compile->lcil-text 得到
                  ((asm) (clr-static-call IronScheme.Emit.LcilEmitter (EmitInMemoryData Object String Object[])
                                          lcil name (list->vector consts))))
      (lambda ()
        (clr-static-call IronScheme.Core.ModuleLoader Run asm))))

  (define (assembly-name-of filename)
    (let* ((f (clr-static-call System.IO.Path GetFileNameWithoutExtension filename)))
      f))

  (define (compile-library-dll filename e)
    ;; Lcil 的 S 表达式直接交给发射器，不经文本（iron-033）
    (let ((lcil (compile-forms->lcil (list e) (assembly-name-of filename) "#Module")))
      (clr-static-call IronScheme.Emit.LcilEmitter (SaveData Object String String Boolean) lcil filename filename #f)
      #t))

  (define compile-bootfile
    (case-lambda
      ((forms) (compile-bootfile forms "ironscheme.boot.dll"))
      ((forms filename)
       (let ((text (compile->lcil-text forms (assembly-name-of filename) "#Module")))
         (clr-static-call IronScheme.Emit.LcilEmitter (Save String String String Boolean) text filename filename #f)
         #t)))))
