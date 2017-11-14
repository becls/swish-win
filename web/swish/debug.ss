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

(define (uptime)
  (let* ([x (real-time)]
         [milliseconds (remainder x 1000)]
         [x (quotient x 1000)]
         [seconds (remainder x 60)]
         [x (quotient x 60)]
         [minutes (remainder x 60)]
         [x (quotient x 60)]
         [hours (remainder x 24)]
         [x (quotient x 24)]
         [days x])
    (format "~a day~:p, ~a hour~:p, ~a minute~:p, ~a second~:p"
      days hours minutes seconds)))

(hosted-page "Debug" '()
  `(pre
    ,(let-values ([(op get) (open-string-output-port)])
       (fprintf op "Uptime: ~a\n" (uptime))
       (newline op)
       (fprintf op "  Scheme bytes: ~15:D\n" (bytes-allocated))
       (fprintf op "       C bytes: ~15:D\n" (GetBytesUsed))
       (fprintf op " private bytes: ~15:D\n"
         (<memory-info> private-usage (GetMemoryInfo)))
       (match (GetSQLiteStatus* SQLITE_STATUS_MEMORY_USED #f)
         [#(,current ,highwater)
          (fprintf op "   SQLite size: ~15:D\n" current)
          (fprintf op "   SQLite high: ~15:D\n" highwater)]
         [,err
          (fprintf op "SQLite status error: ~a\n" err)])
       (newline op)
       (match (GetHandleCounts)
         [`(<handle-counts> ,ports ,processes ,databases ,statements
             ,listeners)
          (fprintf op "         Ports: ~a\n" ports)
          (fprintf op "     Processes: ~a\n" processes)
          (fprintf op "     Databases: ~a\n" databases)
          (fprintf op "    Statements: ~a\n" statements)
          (fprintf op "     Listeners: ~a\n" listeners)])
       (newline op)
       (display-statistics op)
       (newline op)
       (pps op)
       (get))))
