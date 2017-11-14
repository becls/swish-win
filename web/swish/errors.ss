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

(http:include "components.ss")

(define (nice-duration x)
  (let* ([milliseconds (remainder x 1000)]
         [x (quotient x 1000)]
         [seconds (remainder x 60)]
         [x (quotient x 60)]
         [minutes (remainder x 60)]
         [x (quotient x 60)]
         [hours x])
    (if (> hours 0)
        (format "~d:~2,'0d:~2,'0d.~3,'0d" hours minutes seconds milliseconds)
        (format "~2,'0d:~2,'0d.~3,'0d" minutes seconds milliseconds))))

(define (data->html-table border columns rows f)
  (table
   `(tbody
     (tr ,@(map (lambda (c) `(th ,c)) (vector->list columns)))
     ,@(map
        (lambda (row)
          `(tr ,@(map (lambda (r) `(td ,(format "~a" r)))
                   (apply f (vector->list row)))))
        rows))))

(define (sql->html-table db border sql f)
  (let ([stmt (sqlite:prepare db sql)])
    (match (cons (sqlite:columns stmt) (sqlite:execute stmt '()))
      [(,cols . ,rows) (data->html-table border cols rows f)])))

(define (english-reason x)
  (match (catch (exit-reason->english (read (open-input-string x))))
    [#(EXIT ,_) x]
    [,english english]))

(with-db [db (log-path) SQLITE_OPEN_READONLY]
  (match (get-param "type")
    ["child"
     (hosted-page "Child Errors" '()
       (sql->html-table db 1 "
SELECT id
  ,name
  ,supervisor
  ,restart_type
  ,type
  ,shutdown
  ,datetime(start/1000,'unixepoch','localtime') as start
  ,duration
  ,killed
  ,reason
FROM child
WHERE reason IS NOT NULL AND reason NOT IN ('normal','shutdown')
ORDER BY id DESC
LIMIT 100"
         (lambda (id name supervisor restart-type type shutdown start duration killed reason)
           (list id name supervisor restart-type type shutdown start
             (nice-duration duration)
             (if (eqv? killed 1) "Y" "n")
             (english-reason reason)))))]
    ["gen-server"
     (hosted-page "Gen-Server Errors" '()
       (sql->html-table db 1 "
SELECT datetime(timestamp/1000,'unixepoch','localtime') as timestamp
  ,name
  ,last_message
  ,state
  ,reason
FROM gen_server_terminating
ORDER BY ROWID DESC
LIMIT 100"
         (lambda (timestamp name last-message state reason)
           (list timestamp name last-message state
             (english-reason reason)))))]
    ["supervisor"
     (hosted-page "Supervisor Errors" '()
       (sql->html-table db 1 "
SELECT datetime(timestamp/1000,'unixepoch','localtime') as timestamp
  ,supervisor
  ,error_context
  ,reason
  ,child_pid
  ,child_name
FROM supervisor_error
ORDER BY ROWID DESC
LIMIT 100"
         (lambda (timestamp supervisor error-context reason child-pid child-name)
           (list timestamp supervisor error-context
             (english-reason reason)
             (or child-pid "None")
             child-name))))]))
