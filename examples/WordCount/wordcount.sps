;;; 词频统计（iron-036 的自包含发布示例）：
;;;   wordcount [-n 个数] 文件 …      没有文件时读标准输入
;;; 发布为独立可执行文件：dotnet run tools/build.cs -- publish examples/WordCount/wordcount.sps
(import (rnrs) (only (srfi :1 lists) take))

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
                   (apply string-append (map (lambda (f) (call-with-input-file f read-all)) files))))
         (counts (make-hashtable string-hash string=?)))
    (for-each (lambda (w) (hashtable-update! counts w (lambda (c) (+ c 1)) 0)) (words-of text))
    (let-values (((keys vals) (hashtable-entries counts)))
      (let ((pairs (list-sort (lambda (a b) (or (> (cdr a) (cdr b))
                                                (and (= (cdr a) (cdr b)) (string<? (car a) (car b)))))
                              (map cons (vector->list keys) (vector->list vals)))))
        (for-each (lambda (p) (display (cdr p)) (display "\t") (display (car p)) (newline))
                  (take pairs (min n (length pairs))))))))
