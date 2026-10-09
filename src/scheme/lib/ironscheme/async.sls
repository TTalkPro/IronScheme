#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme async)：async-lambda / await 与 .NET Task（designs/10-async.md §1 D5，iron-053）。
;;;
;;;   (async-lambda (x …) body …)   体编译成状态机，调用返回 Task<object>；(await t) 等待 t 完成并取结果，
;;;   (define-async (f x …) body …)  期间不占线程。await 只能写在 async-lambda 的体里（含命名 let / do 的循环体、
;;;                                  dynamic-wind / parameterize / guard / with-exception-handler 的体），
;;;                                  不能写在 for-each 等的回调 lambda 里——用 for-each-async / map-async。
;;;   task 过程是 C# 原语（IronScheme.Core.Tasks）：.NET 的 Task<T> 进入 Scheme 时自动变成 Task<object>，
;;;   返回 task 的 Scheme 过程可以 clr-cast 成 Func<Task<T>> 交给 .NET。
;;;   task 里没接住的条件让 task 失败，await / task-result 在等待方重新 raise（10 §4）。
(library (ironscheme async)
  (export
    async-lambda
    define-async
    await
    task?
    task-completed?
    task-faulted?
    task-result
    task-from-result
    task-from-exception
    task-delay
    task-yield
    task-run
    task-then
    task-when-all
    task-when-any
    make-task-source
    task-source-task
    task-source-set-result!
    task-source-set-exception!
    for-each-async
    map-async)
  (import
    (rnrs)
    (only (ironscheme) async-lambda define-async await)
    (only (ironscheme core)
          task? task-completed? task-faulted? task-result task-from-result task-from-exception
          task-delay task-yield task-run task-then task-when-all task-when-any
          make-task-source task-source-task task-source-set-result! task-source-set-exception!))

  ;; (for-each-async f list)：对每个元素调用 f（返回 task 的过程），依次等待；结果为未指定值的 task。
  ;; 要并发地跑就用 (task-when-all (map f list))。
  (define-async (for-each-async f l)
    (let loop ((l l))
      (unless (null? l)
        (await (f (car l)))
        (loop (cdr l)))))

  ;; (map-async f list)：同上，结果为各结果组成的列表的 task。
  (define-async (map-async f l)
    (let loop ((l l) (acc '()))
      (if (null? l)
          (reverse acc)
          (loop (cdr l) (cons (await (f (car l))) acc))))))
