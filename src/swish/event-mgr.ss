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

(library (swish event-mgr)
  (export
   event-mgr:add-handler
   event-mgr:flush-buffer
   event-mgr:notify
   event-mgr:set-log-handler
   event-mgr:start&link
   event-mgr:unregister
   system-detail
   )
  (import
   (swish erlang)
   (swish event-mgr-notify)
   (swish gen-server)
   (except (chezscheme) define-record exit)
   )

  ;; event-mgr:notify and system-detail are defined in
  ;; event-mgr-notify.ss to avoid an import cycle with gen-server.ss

  (define event-mgr:add-handler
    (case-lambda
     [(proc owner) (gen-server:call 'event-mgr `#(add-handler ,proc ,owner))]
     [(proc) (event-mgr:add-handler proc self)]))

  (define (event-mgr:flush-buffer)
    (gen-server:call 'event-mgr 'flush-buffer))

  (define (event-mgr:set-log-handler proc owner)
    (gen-server:call 'event-mgr `#(set-log-handler ,proc ,owner)))

  (define (event-mgr:start&link)
    (gen-server:start&link 'event-mgr))

  (define (event-mgr:unregister)
    (gen-server:call 'event-mgr 'unregister))

  (define-state-record <event-mgr-state>
    event-buffer                        ; #f | (event ...)
    log-handler                         ; <handler> | #f
    handlers                            ; (<handler> ...)
    )

  (define-record <handler> proc owner)

  (define (init)
    (process-trap-exit #t)
    `#(ok ,(<event-mgr-state> make
             [event-buffer '()]
             [log-handler #f]
             [handlers '()])))

  (define (terminate reason state)
    (do-flush-buffer ($state copy [log-handler #f] [handlers '()]))
    'ok)

  (define (handle-call msg from state)
    (match msg
      [#(add-handler ,proc ,owner)
       (cond
        [(not (procedure? proc))
         `#(reply #(error #(invalid-procedure ,proc)) ,state)]
        [(not (process? owner))
         `#(reply #(error #(invalid-owner ,owner)) ,state)]
        [else
         (link owner)
         `#(reply ok
             ,($state copy*
                [handlers `(,@handlers
                            ,(<handler> make [proc proc] [owner owner]))]))])]
      [flush-buffer
       `#(reply ok ,(do-flush-buffer state))]
      [#(set-log-handler ,proc ,owner)
       (cond
        [($state log-handler)
         `#(reply #(error log-handler-already-set) ,state)]
        [(not (procedure? proc))
         `#(reply #(error #(invalid-procedure ,proc)) ,state)]
        [(not (process? owner))
         `#(reply #(error #(invalid-owner ,owner)) ,state)]
        [else
         (link owner)
         `#(reply ok
             ,($state copy
                [log-handler (<handler> make [proc proc] [owner owner])]))])]
      [unregister
       (unregister 'event-mgr)
       `#(reply ok ,state)]))

  (define (handle-cast msg state) (match msg))

  (define (handle-info msg state)
    (match msg
      [#(notify ,event)
       `#(no-reply ,(do-notify event state))]
      [#(EXIT ,pid ,_)
       (let ([log-handler ($state log-handler)])
         (if (and log-handler (eq? (<handler> owner log-handler) pid))
             `#(no-reply ,($state copy [log-handler #f]))
             `#(no-reply
                ,($state copy* [handlers (remove-owner pid handlers)]))))]))

  (define (do-flush-buffer state)
    (match state
      [`(<event-mgr-state> [event-buffer #f]) state]
      [`(<event-mgr-state> ,event-buffer)
       (let ([state ($state copy [event-buffer #f])])
         (fold-right do-notify state event-buffer))]))

  (define (do-notify event state)
    (match state
      [`(<event-mgr-state> [event-buffer #f] ,log-handler ,handlers)
       (for-each
        (lambda (h)
          (match (catch ((<handler> proc h) event))
            [#(EXIT ,reason) (kill (<handler> owner h) reason)]
            [,_ (void)]))
        handlers)
       (cond
        [log-handler
         (match (catch ((<handler> proc log-handler) event))
           [#(EXIT ,reason)
            (unlink (<handler> owner log-handler))
            (kill (<handler> owner log-handler) reason)
            (console-event-handler event)
            ($state copy [log-handler #f])]
           [,_ state])]
        [else
         (console-event-handler event)
         state])]
      [`(<event-mgr-state> ,event-buffer)
       ($state copy [event-buffer (cons event event-buffer)])]))

  (define (remove-owner pid handlers)
    (remp (lambda (x) (eq? pid (<handler> owner x))) handlers))
  )
