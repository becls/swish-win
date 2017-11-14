;;; Copyright 2017 Beckman Coulter, Inc.
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

#!chezscheme
(library (swish log-db)
  (export
   <event-logger>
   create-table
   define-simple-events
   log-db:get-instance-id
   log-db:setup
   log-db:start&link
   log-db:version
   swish-event-logger
   )
  (import
   (software-info)
   (swish app-io)
   (swish db)
   (swish erlang)
   (swish event-mgr)
   (swish events)
   (swish io)
   (swish osi)
   (swish string-utils)
   (except (chezscheme) define-record exit)
   )

  (define-record <event-logger> setup log)

  (define (log-db:start&link)
    (db:start&link 'log-db
      (create-directory-path (log-path))
      'create))

  (define (log-db:setup loggers)
    (match (db:transaction 'log-db (lambda () (setup-db loggers)))
      [#(ok ,_)
       (match (event-mgr:set-log-handler
               (lambda (event) (log-event loggers event))
               (whereis 'log-db))
         [ok
          (let ([now (current-date)])
            (event-mgr:flush-buffer)
            (system-detail <system-attributes>
              [date (current-date)]
              [software-version software-version]
              [computer-name (GetComputerName)])
            'ignore)]
         [,error error])]
      [,error error]))

  (define log-db:version
    (case-lambda
     [(name)
      (match (execute "select version from version where name=? limit 1"
               (symbol->string name))
        [(#(,version)) version]
        [() #f])]
     [(name version)
      (execute "insert or replace into version (name, version) values (?, ?)"
        (symbol->string name) version)]))

  (define next-child-id 1)

  (define get-child-id
    (let ([ht (make-weak-eq-hashtable)])
      (lambda (x)
        (if (process? x)
            (let ([id (cdr (eq-hashtable-cell ht x next-child-id))])
              (when (= next-child-id id)
                (set! next-child-id (+ id 1)))
              id)
            x))))

  (define log-db:instance-id #f)

  (define (log-db:get-instance-id)
    log-db:instance-id)

  (define (create-instance-id!)
    (let ([id (guid->string (CreateGUID))])
      (log-db:version 'instance id)
      (set! log-db:instance-id id)))

  (define (setup-db loggers)
    (create-table version
      (name text primary key)
      (version text))
    (match (log-db:version 'instance)
      [#f (create-instance-id!)]
      [,id (set! log-db:instance-id id)])
    (for-each (lambda (l) ((<event-logger> setup l))) loggers)
    'ok)

  (define (log-event loggers e)
    (for-each (lambda (l) ((<event-logger> log l) e)) loggers))

  (meta define (make-sql-name x)
    (let ([ip (open-input-string (symbol->string (syntax->datum x)))]
          [op (open-output-string)])
      (write-char #\[ op)
      (let lp ()
        (let ([c (read-char ip)])
          (cond
           [(eof-object? c)]
           [(or (char<=? #\A c #\Z)
                (char<=? #\a c #\z)
                (char<=? #\0 c #\9)
                (char=? c #\_))
            (write-char c op)
            (lp)]
           [(char=? c #\-)
            (write-char #\_ op)
            (lp)]
           [else (lp)])))
      (write-char #\] op)
      (get-output-string op)))

  (define-syntax define-simple-events
    (syntax-rules ()
      [(_ create handle (name clause ...) ...)
       (andmap identifier? #'(name ...))
       (begin
         (define (create)
           (create-table name clause ...)
           ...)
         (define (handle r)
           (cond
            [(name is? r) (insert-table r name clause ...)]
            ...
            [else #f])))]))

  (define-syntax (create-table x)
    (define (create-table-clause clause)
      (syntax-case clause ()
        [(field type . inline)
         (identifier? #'field)
         (join
          (cons*
           (make-sql-name #'field)
           (datum type)
           (datum inline))
          #\space)]))
    (syntax-case x ()
      [(k name clause ...)
       #`(execute
          #,(datum->syntax #'k
              (format "create table if not exists ~a(~a)"
                (make-sql-name #'name)
                (join (map create-table-clause #'(clause ...)) ", "))))]))

  (define-syntax (insert-table x)
    (define (parse-clauses r name clauses)
      (syntax-case clauses ()
        [() #'()]
        [((field type . inline) . rest)
         #`([#,(datum->syntax-object name
                 (string->symbol (make-sql-name #'field)))
             ,(#,name no-check field #,r)]
            . #,(parse-clauses r name #'rest))]))
    (syntax-case x ()
      [(k r name clause ...)
       #`(log-sql
          (insert #,(datum->syntax-object #'k
                      (string->symbol (make-sql-name #'name)))
            #,(parse-clauses #'r #'name #'(clause ...))))]))

  (define (coerce x)
    (cond
     [(string? x) x]
     [(fixnum? x) x]
     [(and (bignum? x) (< (integer-length x) 64)) x]
     [(flonum? x) x]
     [(eq? x #f) x]
     [(real? x) (inexact x)]
     [(bytevector? x) x]
     [(symbol? x) (symbol->string x)]
     [(process? x) (get-child-id x)]
     [(date? x) (format-rfc2822 x)]
     [(condition? x)
      (let ([op (open-output-string)])
        (display-condition x op)
        (write-char #\. op)
        (format "~s" `#(error ,(get-output-string op))))]
     [else (format "~s" x)]))

  (define-syntax (log-sql x)
    (syntax-case x ()
      [(k sql)
       (let-values ([(query args) (parse-sql #'sql)])
         (with-syntax ([query (datum->syntax-object #'k query)]
                       [(arg ...) args])
           #'(db:log 'log-db query (coerce arg) ...)))]))

  (module (swish-event-logger)
    (define schema-name 'swish)
    (define schema-version "l2icz69tb6toyr48uf90nlbm3")

    (define-simple-events create-simple-tables log-simple-event
      (<child-end>
       (timestamp integer)
       (pid integer)
       (killed integer)
       (reason text))
      (<child-start>
       (timestamp integer)
       (supervisor integer)
       (pid integer)
       (name text)
       (restart-type text)
       (type text)
       (shutdown integer))
      (<gen-server-debug>
       (timestamp integer)
       (duration integer)
       (type integer)
       (client integer)
       (server integer)
       (message text)
       (state text)
       (reply text))
      (<gen-server-terminating>
       (timestamp integer)
       (name text)
       (last-message text)
       (state text)
       (reason text))
      (<http-request>
       (timestamp integer)
       (pid integer)
       (host text)
       (method text)
       (path text)
       (header text)
       (params text))
      (<statistics>
       (timestamp integer)
       (date text)
       (reason text)
       (bytes-allocated integer)
       (osi-bytes-used integer)
       (sqlite-memory integer)
       (sqlite-memory-highwater integer)
       (ports integer)
       (processes integer)
       (databases integer)
       (statements integer)
       (listeners integer)
       (hashes integer)
       (working-set-size integer)
       (pagefile-usage integer)
       (private-usage integer)
       (cpu real)
       (real real)
       (bytes integer)
       (gc-count integer)
       (gc-cpu real)
       (gc-real real)
       (gc-bytes integer))
      (<supervisor-error>
       (timestamp integer)
       (supervisor integer)
       (error-context text)
       (reason text)
       (child-pid integer)
       (child-name text))
      (<system-attributes>
       (timestamp integer)
       (date text)
       (software-version text)
       (computer-name text))
      (<transaction-retry>
       (timestamp integer)
       (database text)
       (duration integer)
       (count integer)
       (sql text))
      )

    (define (create-db)
      (define max-days 90)
      (define (create-prune-on-insert-trigger table column)
        (execute
         (format "create temporary trigger prune_~a after insert on ~:*~a begin delete from ~:*~a where rowid in (select rowid from ~:*~a where ~a < new.~:*~a - ~d limit 10); end"
           table column (* max-days 24 60 60 1000))))

      (define-syntax create-prune-on-insert-triggers
        (syntax-rules ()
          [(_ (table column) ...)
           (begin (create-prune-on-insert-trigger 'table 'column) ...)]))

      (define (create-index name sql)
        (execute (format "create index if not exists ~a on ~a" name sql)))

      (create-simple-tables)

      ;; next-child-id
      (match-let* ([(#(,id)) (execute "select max(pid) from child_start")])
        (set! next-child-id (+ (or id 0) 1)))

      (execute "drop view if exists child")
      (execute "create view child as select T1.pid as id, T1.name, T1.supervisor, T1.restart_type, T1.type, T1.shutdown, T1.timestamp as start, T2.timestamp - T1.timestamp as duration, T2.killed, T2.reason from child_start T1 left outer join child_end T2 on T1.pid=T2.pid")

      (create-prune-on-insert-triggers
       (child_end timestamp)
       (child_start timestamp)
       (gen_server_debug timestamp)
       (gen_server_terminating timestamp)
       (http_request timestamp)
       (statistics timestamp)
       (supervisor_error timestamp)
       (system_attributes timestamp)
       (transaction_retry timestamp)
       )

      ;; indexes
      (create-index 'child_start_pid
        "child_start(pid)")
      (create-index 'child_start_timestamp
        "child_start(timestamp)")
      (create-index 'child_end_pid
        "child_end(pid)")
      (create-index 'child_end_timestamp
        "child_end(timestamp)")
      (create-index 'gen_server_debug_timestamp
        "gen_server_debug(timestamp)")
      (create-index 'gen_server_terminating_timestamp
        "gen_server_terminating(timestamp)")
      (create-index 'http_request_timestamp
        "http_request(timestamp)")
      (create-index 'statistics_timestamp
        "statistics(timestamp)")
      (create-index 'supervisor_error_timestamp
        "supervisor_error(timestamp)")
      (create-index 'system_attributes_timestamp
        "system_attributes(timestamp)")
      (create-index 'transaction_retry_timestamp
        "transaction_retry(timestamp)")
      'ok)

    (define (upgrade-db)
      (match (log-db:version schema-name)
        [,@schema-version (create-db)]
        [#f
         (log-db:version schema-name schema-version)
         (create-db)]
        [,version (exit `#(unsupported-db-version ,schema-name ,version))]))

    (define swish-event-logger
      (<event-logger> make [setup upgrade-db] [log log-simple-event]))
    )
  )
