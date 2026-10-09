;;; 词频统计（iron-036 的自包含发布示例；iron-053 起用 async 并发读文件）：
;;;   wordcount [-n 个数] 文件 …      没有文件时读标准输入
;;; 发布为独立可执行文件：dotnet run tools/build.cs -- publish examples/WordCount/wordcount.sps
(import (rnrs) (only (ironscheme std lists) take) (ironscheme clr) (ironscheme async))

(clr-using System.IO)
(clr-using System.Threading)

;; 异步读整个文件：File.ReadAllTextAsync 返回的 Task<string> 进入 Scheme 时是 task，await 期间不占线程
(define-async (read-file-async f)
  (await (clr-static-call File (ReadAllTextAsync String CancellationToken)
                          f (clr-static-prop-get CancellationToken None))))

(define (words-of text)
  ;; 字母与撇号组成词，其余字符分隔；统一小写
  (let loop ((cs (string->list text)) (cur '()) (acc '()))
    (define (flush) (if (null? cur) acc (cons (list->string (reverse cur)) acc)))
    (cond
      ((null? cs) (reverse (flush)))
      ((or (char-alphabetic? (car cs)) (char=? (car cs) #\')) (loop (cdr cs) (cons (char-downcase (car cs)) cur) acc))
      (else (loop (cdr cs) '() (flush))))))

(define (read-all port)
  (let loop ((acc '()))
    (let ((line (get-line port)))
      (if (eof-object? line)
          (apply string-append (reverse acc))
          (loop (cons " " (cons line acc)))))))

(define (parse-args args)
  (if (and (pair? args) (string=? (car args) "-n") (pair? (cdr args)))
      (values (string->number (cadr args)) (cddr args))
      (values 10 args)))

(let-values (((n files) (parse-args (cdr (command-line)))))
  (let* ((text (if (null? files)
                   (read-all (current-input-port))
                   ;; 全部文件并发读取，等它们都完成（顺序地一个个 await 用 map-async）
                   (apply string-append (task-result (task-when-all (map read-file-async files))))))
         (counts (make-hashtable string-hash string=?)))
    (for-each (lambda (w) (hashtable-update! counts w (lambda (c) (+ c 1)) 0)) (words-of text))
    (let-values (((keys vals) (hashtable-entries counts)))
      (let ((pairs (list-sort (lambda (a b) (or (> (cdr a) (cdr b))
                                                (and (= (cdr a) (cdr b)) (string<? (car a) (car b)))))
                              (map cons (vector->list keys) (vector->list vals)))))
        (for-each (lambda (p) (display (cdr p)) (display "\t") (display (car p)) (newline))
                  (take pairs (min n (length pairs))))))))
