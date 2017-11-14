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

(library (swish testing)
  (export
   capture-events
   isolate-mat
   match-prefix
   process-alive?
   sleep
   start-event-mgr
   start-silent-event-mgr
   system-mat
   )
  (import
   (swish app)
   (swish app-io)
   (swish erlang)
   (swish event-mgr)
   (swish gatekeeper)
   (swish gen-server)
   (swish io)
   (swish log-db)
   (swish mat)
   (swish osi)
   (swish string-utils)
   (swish supervisor)
   (swish watcher)
   (except (chezscheme) define-record exit sleep)
   )
  (define (sleep t) (receive (after t 'ok)))

  (define (start-event-mgr)
    (unless (whereis 'event-mgr)
      (let* ([caller self]
             [pid (spawn
                   (lambda ()
                     (event-mgr:start&link)
                     (send caller 'ready)
                     (receive)))])
        (receive (after 1000 (exit 'timeout-starting-event-mgr))
          [ready 'ok]))))

  (define (start-silent-event-mgr)
    (start-event-mgr)
    (event-mgr:set-log-handler (lambda (x) x) (spawn (lambda () (receive))))
    (event-mgr:flush-buffer))

  (define (capture-events)
    (let ([me self])
      (event-mgr:add-handler (lambda (event) (send me event)))))

  (define ($isolate-mat thunk)
    (let* ([pid (spawn thunk)]
           [m (monitor pid)])
      (receive (after 60000
                 (kill pid 'kill)
                 (exit 'timeout))
        [#(DOWN ,@m ,@pid normal) (void)]
        [#(DOWN ,@m ,@pid ,reason) (exit reason)])))

  (define-syntax isolate-mat
    (syntax-rules ()
      [(_ name tags e1 e2 ...)
       (mat name tags ($isolate-mat (lambda () e1 e2 ...)))]))

  (define (match-prefix lines pattern)
    (match lines
      [() (exit `#(pattern-not-found ,pattern))]
      [(,line . ,rest)
       (if (starts-with? line pattern)
           line
           (match-prefix rest pattern))]))

  (define (process-alive? x timeout)
    (let ([m (monitor x)])
      (demonitor m)
      (receive
       (after timeout #t)
       [#(DOWN ,@m ,@x ,_) #f])))

  (define (boot-system)
    (log-path (path-combine data-dir "TestLog.db3"))
    (match (init-main-sup)
      [#(ok ,pid) pid]))

  (define (shutdown-system)
    (cond
     [(whereis 'main-sup) =>
      (lambda (pid)
        (monitor pid)
        (receive (after 60000 (exit 'main-sup-still-running))
          [#(DOWN ,_ ,@pid ,_) 'ok]))]))

  (define-syntax system-mat
    (syntax-rules ()
      [(_ name tags e1 e2 ...)
       (mat name tags ($system-mat (lambda () (boot-system) e1 e2 ...)))]))

  (define ($system-mat thunk)
    (let* ([pid (spawn thunk)]
           [m (monitor pid)])
      (on-exit (shutdown-system)
        (receive (after 300000 (kill pid 'shutdown) (exit 'timeout))
          [#(DOWN ,_ ,@pid normal) 'ok]
          [#(DOWN ,_ ,@pid ,reason) (exit reason)]))))
  )
