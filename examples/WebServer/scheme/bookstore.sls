;;; 书店示例的业务逻辑（iron-039）：用 .NET 的 Microsoft.Data.Sqlite 读写 SQLite，结果以关联表返回给 C#。
(library (bookstore)
  (export open-store init-store! all-books find-books book-by-id add-book! stats)
  (import (rnrs) (ironscheme clr))

  (clr-reference Microsoft.Data.Sqlite)
  (clr-using Microsoft.Data.Sqlite)

  (define connection-string #f)

  ;; 打开（或创建）数据库文件
  (define (open-store path)
    (set! connection-string (string-append "Data Source=" path)))

  (define (with-connection proc)
    (unless connection-string
      (assertion-violation 'bookstore "store not opened; call open-store first"))
    (let ((conn (clr-new SqliteConnection connection-string)))
      (clr-call SqliteConnection Open conn)
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc conn))
        (lambda () (clr-call SqliteConnection Dispose conn)))))

  ;; SQL 命令；params 为交替的 参数名 值
  (define (command conn sql params)
    (let ((cmd (clr-call SqliteConnection CreateCommand conn)))
      (clr-prop-set! SqliteCommand CommandText cmd sql)
      (let loop ((ps params))
        (unless (null? ps)
          (clr-call SqliteParameterCollection (AddWithValue String Object)
                    (clr-prop-get SqliteCommand Parameters cmd) (car ps) (cadr ps))
          (loop (cddr ps))))
      cmd))

  (define (execute! conn sql . params)
    (clr-call SqliteCommand ExecuteNonQuery (command conn sql params)))

  (define (scalar conn sql . params)
    (clr-call SqliteCommand ExecuteScalar (command conn sql params)))

  ;; 查询 → 每行一个关联表 ((列名 . 值) …)；NULL 为 #f
  (define (query conn sql . params)
    (let ((reader (clr-call SqliteCommand ExecuteReader (command conn sql params))))
      (let loop ((rows '()))
        (if (clr-call SqliteDataReader Read reader)
            (loop (cons (read-row reader) rows))
            (begin
              (clr-call SqliteDataReader Dispose reader)
              (reverse rows))))))

  (define (read-row reader)
    (let ((n (clr-prop-get SqliteDataReader FieldCount reader)))
      (let loop ((i (- n 1)) (row '()))
        (if (< i 0)
            row
            (loop (- i 1)
                  (cons (cons (string->symbol (clr-call SqliteDataReader GetName reader i))
                              (let ((v (clr-call SqliteDataReader GetValue reader i)))
                                (if (clr-is DBNull v) #f v)))
                        row))))))

  (define sample-books
    '(("Structure and Interpretation of Computer Programs" "Harold Abelson, Gerald Jay Sussman" 1985)
      ("The Scheme Programming Language" "R. Kent Dybvig" 1987)
      ("The Little Schemer" "Daniel P. Friedman, Matthias Felleisen" 1974)
      ("Essentials of Programming Languages" "Daniel P. Friedman, Mitchell Wand" 1992)
      ("How to Design Programs" "Matthias Felleisen et al." 2001)
      ("Lisp in Small Pieces" "Christian Queinnec" 1996)
      ("Paradigms of Artificial Intelligence Programming" "Peter Norvig" 1992)))

  ;; 建表；空表时写入示例数据
  (define (init-store!)
    (with-connection
      (lambda (conn)
        (execute! conn "CREATE TABLE IF NOT EXISTS books (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, author TEXT NOT NULL, year INTEGER)")
        (when (zero? (scalar conn "SELECT COUNT(*) FROM books"))
          (for-each (lambda (b) (insert! conn (car b) (cadr b) (caddr b))) sample-books)))))

  (define (insert! conn title author year)
    (execute! conn "INSERT INTO books (title, author, year) VALUES ($title, $author, $year)"
              "$title" title "$author" author "$year" year)
    (scalar conn "SELECT last_insert_rowid()"))

  (define (all-books)
    (with-connection
      (lambda (conn) (query conn "SELECT id, title, author, year FROM books ORDER BY year, id"))))

  ;; 标题或作者包含 text 的书
  (define (find-books text)
    (with-connection
      (lambda (conn)
        (query conn "SELECT id, title, author, year FROM books WHERE title LIKE $p OR author LIKE $p ORDER BY year, id"
               "$p" (string-append "%" text "%")))))

  (define (book-by-id id)
    (let ((rows (with-connection
                  (lambda (conn) (query conn "SELECT id, title, author, year FROM books WHERE id = $id" "$id" id)))))
      (if (null? rows) #f (car rows))))

  ;; 加入一本书，返回新书
  (define (add-book! title author year)
    (unless (and (string? title) (> (string-length title) 0))
      (assertion-violation 'add-book! "title is required" title))
    (book-by-id (with-connection (lambda (conn) (insert! conn title author year)))))

  ;; 统计在 Scheme 中完成：总数、最早与最晚的年份、按年代分组的数量
  (define (stats)
    (let* ((books (all-books))
           (years (filter integer? (map (lambda (b) (cdr (assq 'year b))) books)))
           (decades (make-eqv-hashtable)))
      (for-each (lambda (y) (hashtable-update! decades (* 10 (div y 10)) (lambda (n) (+ n 1)) 0)) years)
      (list (cons 'count (length books))
            (cons 'earliest (if (null? years) #f (apply min years)))
            (cons 'latest (if (null? years) #f (apply max years)))
            (cons 'byDecade
                  (map (lambda (d) (list (cons 'decade d) (cons 'count (hashtable-ref decades d 0))))
                       (list-sort < (vector->list (hashtable-keys decades)))))))))
