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
(library (swish erlang)
  (export
   add-finalizer
   bad-arg
   catch
   console-event-handler
   dbg
   define-record
   demonitor
   demonitor&flush
   erlang:now
   exit
   get-registered
   kill
   link
   make-process-parameter
   match
   match-let*
   monitor
   monitor?
   on-exit
   pps
   process-id
   process-trap-exit
   process?
   profile-me
   receive
   register
   scheme-exit
   self
   send
   spawn
   spawn&link
   unlink
   unregister
   whereis
   )
  (import
   (swish meta)
   (rename (swish osi) (GetTickCount erlang:now))
   (rename (except (chezscheme) define-record remove)
     (exit scheme-exit)
     (raise exit)))

  ;; Procedures starting with @ must be called with interrupts disabled.

  (define-syntax on-exit
    (syntax-rules ()
      [(_ finally b1 b2 ...)
       (dynamic-wind
         void
         (lambda () b1 b2 ...)
         (lambda () finally))]))

  (define-syntax no-interrupts
    (syntax-rules ()
      [(_ body ...)
       (let ([x (begin (disable-interrupts) body ...)])
         (enable-interrupts)
         x)]))

  (define-syntax (receive x)
    (syntax-case x ()
      [(_ (after timeout t1 t2 ...) (pattern b1 b2 ...) ...)
       (eq? (datum after) 'after)
       #`(receive-after
          (lambda (x) (or (match-pattern x pattern b1 b2 ...) ...))
          #,(find-source x)
          timeout
          (lambda () t1 t2 ...))]
      [(_ (until time t1 t2 ...) (pattern b1 b2 ...) ...)
       (eq? (datum until) 'until)
       #`(receive-until
          (lambda (x) (or (match-pattern x pattern b1 b2 ...) ...))
          #,(find-source x)
          time
          (lambda () t1 t2 ...))]
      [(_ (pattern b1 b2 ...) ...)
       #`($receive
          (lambda (x) (or (match-pattern x pattern b1 b2 ...) ...))
          #,(find-source x)
          #f
          #f)]))

  (define-syntax self
    (identifier-syntax
     (#3%$top-level-value '#{self lgnnu3lheosakvgyylzmvq5uw-0})))

  (define (set-self! x)
    (#3%$set-top-level-value! '#{self lgnnu3lheosakvgyylzmvq5uw-0} x))

  (define-record-type q
    (nongenerative)
    (fields
     (mutable prev)
     (mutable next))
    (protocol
     (lambda (new)
       (lambda ()
         (new #f #f)))))

  (define-record-type msg
    (nongenerative)
    (fields
     (immutable contents))
    (parent q)
    (protocol
     (lambda (new)
       (lambda (contents)
         ((new) contents)))))

  (define-record-type mon
    (nongenerative)
    (fields
     (immutable origin)
     (immutable target)))

  (define-record-type pcb
    (nongenerative)
    (fields
     (immutable id)
     (mutable name)
     (mutable cont)
     (mutable sic)
     (mutable winders)
     (mutable exception-state)
     (mutable inbox)
     (mutable precedence)
     (mutable flags)
     (mutable links)
     (mutable monitors)
     (mutable src)
     )
    (parent q)
    (protocol
     (lambda (new)
       (lambda (id cont)
         ((new) id #f cont 0 '() #f (make-queue) 0 0 '() '() #f)))))

  (define (pcb-sleeping? p)
    (logbit? 0 (pcb-flags p)))

  (define (pcb-trap-exit p)
    (logbit? 1 (pcb-flags p)))

  (define (pcb-sleeping?-set! p x)
    (pcb-flags-set! p
      (if x
          (logbit1 0 (pcb-flags p))
          (logbit0 0 (pcb-flags p)))))

  (define (pcb-trap-exit-set! p x)
    (pcb-flags-set! p
      (if x
          (logbit1 1 (pcb-flags p))
          (logbit0 1 (pcb-flags p)))))

  (define (panic event)
    (on-exit (ExitProcess 80)
      (console-event-handler event)))

  (define (@kill p reason)
    (when (eq? p event-loop-process)
      (panic `#(event-loop-process-terminated ,reason)))
    (when (eq? p finalizer-process)
      (panic `#(finalizer-process-terminated ,reason)))
    (when (enqueued? p)
      (remove p))
    (pcb-cont-set! p #f)
    (pcb-winders-set! p '())
    (pcb-exception-state-set! p reason)
    (pcb-inbox-set! p #f)
    (pcb-flags-set! p 0)
    (pcb-src-set! p #f)
    (let ([name (pcb-name p)])
      (when name
        (pcb-name-set! p #f)
        (eq-hashtable-delete! registrar name)))
    (let ([links (pcb-links p)])
      (pcb-links-set! p '())
      (@remove-links links p)
      (@kill-linked links p reason))
    (let ([monitors (pcb-monitors p)])
      (pcb-monitors-set! p '())
      (for-each
       (lambda (m)
         (let ([origin (mon-origin m)])
           (cond
            [(eq? origin p)
             (@remove-monitor m (mon-target m))]
            [else
             (@send origin `#(DOWN ,m ,p ,reason))
             (@remove-monitor m origin)])))
       monitors)))

  (define (alive? p)
    (pcb-inbox p))

  (define (@remove-links froms to)
    (unless (null? froms)
      (let ([from (car froms)])
        (@remove-link from to)
        (@remove-links (cdr froms) to))))

  (define (@remove-link from to)
    (pcb-links-set! from (remq to (pcb-links from))))

  (define (@remove-monitor m p)
    (pcb-monitors-set! p (remq m (pcb-monitors p))))

  (define-syntax catch
    (syntax-rules ()
      [(_ e1 e2 ...)
       (call/1cc
        (lambda (return)
          (with-exception-handler
           (lambda (reason) (return `#(EXIT ,reason)))
           (lambda () e1 e2 ...))))]))

  (define (bad-arg who arg)
    (exit `#(bad-arg ,who ,arg)))

  (define (kill p reason)
    (unless (pcb? p)
      (bad-arg 'kill p))
    (no-interrupts
     (when (alive? p)
       (cond
        [(eq? reason 'kill) (@kill p 'killed)]
        [(pcb-trap-exit p) (@send p `#(EXIT ,self ,reason))]
        [(not (eq? reason 'normal)) (@kill p reason)])
       (unless (alive? self)
         (yield #f 0))))
    #t)

  (define process-trap-exit
    (case-lambda
     [() (pcb-trap-exit self)]
     [(x) (pcb-trap-exit-set! self x)]))

  (define (@link p1 p2)
    (define (add-link from to)
      (pcb-links-set! from (cons to (pcb-links from))))
    (unless (memq p2 (pcb-links p1))
      (add-link p1 p2)
      (add-link p2 p1)))

  (define (link p)
    (unless (pcb? p)
      (bad-arg 'link p))
    (unless (eq? self p)
      (no-interrupts
       (cond
        [(alive? p) (@link p self)]
        [(pcb-trap-exit self)
         (@send self `#(EXIT ,p ,(pcb-exception-state p)))]
        [else
         (let ([r (pcb-exception-state p)])
           (unless (eq? r 'normal)
             (@kill self r)
             (yield #f 0)))])))
    #t)

  (define (unlink p)
    (unless (pcb? p)
      (bad-arg 'unlink p))
    (no-interrupts
     (@remove-link self p)
     (@remove-link p self))
    #t)

  (define (monitor? m) (mon? m))

  (define (monitor p)
    (define (add-monitor m p)
      (pcb-monitors-set! p (cons m (pcb-monitors p))))
    (unless (pcb? p)
      (bad-arg 'monitor p))
    (let ([m (make-mon self p)])
      (no-interrupts
       (if (alive? p)
           (begin
             (add-monitor m self)
             (add-monitor m p))
           (@send self `#(DOWN ,m ,p ,(pcb-exception-state p)))))
      m))

  (define (demonitor m)
    (unless (and (mon? m) (eq? (mon-origin m) self))
      (bad-arg 'demonitor m))
    (no-interrupts
     (@remove-monitor m self)
     (@remove-monitor m (mon-target m)))
    #t)

  (define (demonitor&flush m)
    (demonitor m)
    (receive (until 0 #t)
      [#(DOWN ,@m ,_ ,_) #t]))

  (define (make-queue)
    (let ([q (make-q)])
      (q-prev-set! q q)
      (q-next-set! q q)
      q))

  (define (queue-empty? queue)
    (eq? (q-next queue) queue))

  (define enqueued? q-prev)

  (define (@enqueue process queue precedence)
    (when (enqueued? process)
      (remove process))
    (pcb-precedence-set! process precedence)
    (let find ([next queue])
      (let ([prev (q-prev next)])
        (if (or (eq? prev queue) (<= (pcb-precedence prev) precedence))
            (insert process next)
            (find prev)))))

  (define last-process-id 0)

  (define (@make-process cont)
    (let ([id (+ last-process-id 1)])
      (set! last-process-id id)
      (let ([process (make-pcb id cont)])
        (eq-hashtable-set! process-table process id)
        process)))

  (define pps
    (case-lambda
     [() (pps (current-output-port))]
     [(op)
      (unless (output-port? op)
        (bad-arg 'pps op))
      (display-string "Processes:\n" op)
      (dump-process-table op (lambda (p) #t))]))

  (define (dump-process-table op pred)
    (vector-for-each
     (lambda (p)
       (when (pred p)
         (print-process p op)))
     (vector-sort (lambda (x y) (< (pcb-id x) (pcb-id y)))
       (no-interrupts (hashtable-keys process-table)))))

  (define dbg
    (case-lambda
     [()
      (dump-process-table (current-output-port)
        (lambda (p)
          (continuation-condition? (pcb-exception-state p))))]
     [(who)
      (define (find-match id exception base)
        (if (eqv? id who) exception base))
      (debug-condition (dbg #f find-match))
      (debug)]
     [(base proc) ;; proc is (lambda (id exception base) ...)
      (define (gather p base)
        (let ([exception (pcb-exception-state p)])
          (if (continuation-condition? exception)
              (proc (pcb-id p) exception base)
              base)))
      (fold-right gather base
        (vector->list
         (no-interrupts (hashtable-keys process-table))))]))

  (define (process? p) (pcb? p))

  (define (print-process p op)
    (define (fmt-src src)
      (if src
          (match-let* ([#(,at ,offset ,file) src])
            (format " ~a char ~d of ~a" at offset file))
          ""))
    (let-values
        ([(name precedence sleeping? enqueued? completed? src)
          (with-interrupts-disabled
           (values (pcb-name p) (pcb-precedence p) (pcb-sleeping? p)
             (enqueued? p) (not (alive? p)) (pcb-src p)))])
      (fprintf op "~6d: " (pcb-id p))
      (when name
        (fprintf op "~a " name))
      (cond
       [(eq? self p)
        (display-string "running\n" op)]
       [sleeping?
        (fprintf op "waiting for up to ~as~a\n"
          (/ (max (- precedence (erlang:now)) 0) 1000.0)
          (fmt-src src))]
       [enqueued?
        (display-string "ready to run\n" op)]
       [completed?
        (fprintf op "exited with reason ~s\n" (pcb-exception-state p))]
       [else
        (fprintf op "waiting indefinitely~a\n" (fmt-src src))])))

  (define process-id
    (case-lambda
     [() (pcb-id self)]
     [(p)
      (unless (pcb? p)
        (bad-arg 'process-id p))
      (pcb-id p)]))

  (define (spawn thunk)
    (unless (procedure? thunk)
      (bad-arg 'spawn thunk))
    (no-interrupts
     (let ([p (@make-process (@thunk->cont thunk))])
       (@enqueue p run-queue 0)
       p)))

  (define (spawn&link thunk)
    (unless (procedure? thunk)
      (bad-arg 'spawn&link thunk))
    (no-interrupts
     (let ([p (@make-process (@thunk->cont thunk))])
       (@link p self)
       (@enqueue p run-queue 0)
       p)))

  (define (@send p x)
    (let ([inbox (pcb-inbox p)])
      (when inbox
        (insert (make-msg x) inbox)
        (when (pcb-sleeping? p)
          (pcb-sleeping?-set! p #f)
          (remove p))
        (unless (enqueued? p)
          (@enqueue p run-queue 0)))))

  (define (send p x)
    (cond
     [(pcb? p) (no-interrupts (@send p x))]
     [(symbol? p)
      (let ([dest (whereis p)])
        (unless dest
          (bad-arg 'send p))
        (no-interrupts (@send dest x)))]
     [else (bad-arg 'send p)]))

  (define (receive-after matcher src timeout timeout-handler)
    (cond
     [(and (or (fixnum? timeout) (bignum? timeout)) (>= timeout 0))
      ($receive matcher src (+ (erlang:now) timeout) timeout-handler)]
     [(eq? timeout 'infinity) ($receive matcher src #f #f)]
     [else (exit `#(timeout-value ,timeout ,src))]))

  (define (receive-until matcher src time timeout-handler)
    (cond
     [(and (or (fixnum? time) (bignum? time)) (>= time 0))
      ($receive matcher src time timeout-handler)]
     [(eq? time 'infinity) ($receive matcher src #f #f)]
     [else (exit `#(timeout-value ,time ,src))]))

  (define ($receive matcher src waketime timeout-handler)
    (disable-interrupts)
    (let find ([prev (pcb-inbox self)])
      (let ([msg (q-next prev)])
        (cond
         [(eq? (pcb-inbox self) msg)
          (cond
           [(not waketime)
            (pcb-src-set! self src)
            (yield #f 0)
            (pcb-src-set! self #f)
            (find prev)]
           [(< (erlang:now) waketime)
            (pcb-src-set! self src)
            (pcb-sleeping?-set! self #t)
            (yield sleep-queue waketime)
            (pcb-src-set! self #f)
            (find prev)]
           [else
            (enable-interrupts)
            (timeout-handler)])]
         [else
          (enable-interrupts)
          (cond
           [(matcher (msg-contents msg)) =>
            (lambda (run)
              (remove msg)
              (run))]
           [else
            (disable-interrupts)
            (find msg)])]))))

  (define process-default-ticks 1000)

  (define (insert x next)
    ;; No interrupts occur within this procedure because the record
    ;; functions get inlined.
    (let ([prev (q-prev next)])
      (q-next-set! prev x)
      (q-prev-set! x prev)
      (q-next-set! x next)
      (q-prev-set! next x)))

  (define (remove x)
    ;; No interrupts occur within this procedure because the record
    ;; functions get inlined.
    (let ([prev (q-prev x)] [next (q-next x)])
      (q-next-set! prev next)
      (q-prev-set! next prev)
      (q-prev-set! x #f)
      (q-next-set! x #f))
    x)

  (define (@event-check)
    (unless (queue-empty? sleep-queue)
      (let ([rt (erlang:now)])
        (let wake ([p (q-next sleep-queue)])
          (when (and (not (eq? sleep-queue p)) (<= (pcb-precedence p) rt))
            (let ([next (q-next p)])
              (pcb-sleeping?-set! p #f)
              (@enqueue p run-queue 0)
              (wake next)))))))

  (define (@system-sleep-time)
    (cond
     [(not (queue-empty? run-queue)) 0]
     [(queue-empty? sleep-queue) #x1FFFFFFF]
     [else
      (min (max (- (pcb-precedence (q-next sleep-queue)) (erlang:now)) 0)
           #x1FFFFFFF)]))

  (define (yield queue precedence)
    (let ([prev-sic (- (disable-interrupts) 1)])
      (@event-check)
      (when (alive? self)
        (pcb-winders-set! self (#%$current-winders))
        (pcb-exception-state-set! self (current-exception-state)))
      (#%$current-winders '())

      ;; snap the continuation
      (call/1cc
       (lambda (k)
         (when (alive? self)
           (pcb-cont-set! self k)
           (cond
            [queue (@enqueue self queue precedence)]
            [(enqueued? self) (remove self)]))

         ;; context switch
         (pcb-sic-set! self prev-sic)
         (let ([p (q-next run-queue)])
           (when (eq? p run-queue)
             (panic 'run-queue-empty))
           (set-self! (remove p)))

         ;; adjust system interrupt counter for the new process
         (let loop ([sic (pcb-sic self)])
           (unless (fx= sic prev-sic)
             (cond
              [(fx> sic prev-sic)
               (disable-interrupts)
               (loop (fx- sic 1))]
              [else
               (enable-interrupts)
               (loop (fx+ sic 1))])))

         ;; Restart the process
         ((pcb-cont self) (void)))))

    ;; Restart point
    (#%$current-winders (pcb-winders self))
    (current-exception-state (pcb-exception-state self))
    (pcb-cont-set! self #f)            ;; drop ref
    (pcb-winders-set! self '())        ;; drop ref
    (pcb-exception-state-set! self #f) ;; drop ref
    (SetTick)
    (set-timer process-default-ticks)
    (enable-interrupts))

  (define @thunk->cont
    (let ([return #f])
      (lambda (thunk)
        (let ([winders (#%$current-winders)])
          (#%$current-winders '())
          (let ([k (call/1cc
                    (lambda (k)
                      ;; Don't close over k, or the new process will
                      ;; keep the current continuation alive.
                      (set! return k)
                      (#%$current-stack-link #%$null-continuation)
                      (let ([reason
                             (call/cc
                              (lambda (done)
                                (call/1cc return)
                                (current-exception-state
                                 (create-exception-state done))
                                (pcb-cont-set! self #f) ;; drop ref
                                (SetTick)
                                (set-timer process-default-ticks)
                                (enable-interrupts)
                                (thunk)
                                'normal))])
                        ;; Process finished
                        (disable-interrupts)
                        (@kill self reason)
                        (yield #f 0))))])
            (set! return #f)
            (#%$current-winders winders)
            k)))))

  (define (@kill-linked links p reason)
    (unless (null? links)
      (let ([linked (car links)])
        (cond
         [(not (alive? linked))]
         [(pcb-trap-exit linked) (@send linked `#(EXIT ,p ,reason))]
         [(not (eq? reason 'normal)) (@kill linked reason)]))
      (@kill-linked (cdr links) p reason)))

  (define (whereis name)
    (unless (symbol? name)
      (bad-arg 'whereis name))
    (no-interrupts (eq-hashtable-ref registrar name #f)))

  (define (get-registered)
    (vector->list (no-interrupts (hashtable-keys registrar))))

  (define (register name p)
    (unless (symbol? name)
      (bad-arg 'register name))
    (unless (pcb? p)
      (bad-arg 'register p))
    (with-interrupts-disabled
     (cond
      [(not (alive? p)) (exit `#(process-dead ,p))]
      [(pcb-name p) =>
       (lambda (name) (exit `#(process-already-registered ,name)))]
      [(eq-hashtable-ref registrar name #f) =>
       (lambda (pid) (exit `#(name-already-registered ,pid)))]
      [else
       (pcb-name-set! p name)
       (eq-hashtable-set! registrar name p)
       #t])))

  (define (unregister name)
    (unless (symbol? name)
      (bad-arg 'unregister name))
    (with-interrupts-disabled
     (let ([p (eq-hashtable-ref registrar name #f)])
       (unless p
         (bad-arg 'unregister name))
       (pcb-name-set! p #f)
       (eq-hashtable-delete! registrar name)
       #t)))

  (define finalizers '())

  (define (add-finalizer finalizer)
    (unless (procedure? finalizer)
      (bad-arg 'add-finalizer finalizer))
    (set! finalizers (cons finalizer finalizers)))

  (define (run-finalizers ls)
    (unless (null? ls)
      ((car ls))
      (run-finalizers (cdr ls))))

  (define (finalizer-loop)
    (receive
     [,_
      (let pump ()
        (receive (until 0 'ok)
          [,_ (pump)]))])
    (run-finalizers finalizers)
    (finalizer-loop))

  (define (do-callbacks timeout)
    (let ([x (GetCompletionPacket timeout)])
      (when x
        (apply (car x) (cdr x))
        (do-callbacks 0))))

  (define (@event-loop)
    (do-callbacks (@system-sleep-time))
    (yield run-queue 0)
    (@event-loop))

  (define process-table (make-weak-eq-hashtable))

  (define run-queue (make-queue))
  (define sleep-queue (make-queue))

  (define registrar (make-eq-hashtable))

  (define event-loop-process #f)
  (define finalizer-process #f)

  (define (console-event-handler event)
    (with-interrupts-disabled
     (let ([op (console-output-port)])
       (fprintf op "\nDate: ~a\n" (date-and-time))
       (fprintf op "Timestamp: ~a\n" (erlang:now))
       (fprintf op "Event: ~s\n\n" event)
       (flush-output-port op))))

  (define make-process-parameter
    (case-lambda
     [(initial filter)
      (unless (procedure? filter)
        (bad-arg 'make-process-parameter filter))
      (let ([ht (make-weak-eq-hashtable)]
            [initial (filter initial)])
        (case-lambda
         [() (no-interrupts (eq-hashtable-ref ht self initial))]
         [(u)
          (let ([v (filter u)])
            (no-interrupts (eq-hashtable-set! ht self v)))]))]
     [(initial)
      (let ([ht (make-weak-eq-hashtable)])
        (case-lambda
         [() (no-interrupts (eq-hashtable-ref ht self initial))]
         [(u) (no-interrupts (eq-hashtable-set! ht self u))]))]))

  (define-syntax (match x)
    (syntax-case x ()
      [(_ exp (pattern b1 b2 ...) ...)
       #`(let ([v exp])
           ((or (match-pattern v pattern b1 b2 ...) ...
                (bad-match v #,(find-source x)))))]))

  (define-syntax match-pattern
    (syntax-rules ()
      [(_ e pat (guard g) b1 b2 ...)
       (eq? (datum guard) 'guard)
       (match-one e pat fail-false (and g (lambda () b1 b2 ...)))]
      [(_ e pat b1 b2 ...)
       (match-one e pat fail-false (lambda () b1 b2 ...))]))

  (define-syntax (match-let* x)
    (syntax-case x ()
      [(_ () b1 b2 ...)
       #'(let () b1 b2 ...)]
      [(_ ([pattern exp] . rest) b1 b2 ...)
       #`(let ([v exp])
           (let-syntax ([fail
                         (syntax-rules ()
                           [(__) (bad-match v #,(find-source #'pattern))])])
             (match-one v pattern fail (match-let* rest b1 b2 ...))))]
      [(_ ([pattern (guard g) exp] . rest) b1 b2 ...)
       (eq? (datum guard) 'guard)
       #`(let ([v exp])
           (let-syntax ([fail
                         (syntax-rules ()
                           [(__) (bad-match v #,(find-source #'pattern))])])
             (match-one v pattern fail
               (if g
                   (match-let* rest b1 b2 ...)
                   (bad-match v #,(find-source #'g))))))]))

  (define-syntax fail-false
    (syntax-rules ()
      [(_) #f]))

  (define (bad-match v src)
    (exit `#(bad-match ,v ,src)))

  (define-syntax (match-one x)
    (define (bad-pattern x)
      (syntax-error x "invalid match pattern"))
    (define (add-identifier id ids)
      (if (duplicate-id? id ids)
          (syntax-error id "duplicate pattern variable")
          (cons id ids)))
    (define (duplicate-id? id ids)
      (and (not (null? ids))
           (or (bound-identifier=? (car ids) id)
               (duplicate-id? id (cdr ids)))))
    (syntax-case x ()
      [(_ e pattern fail body)
       (lambda (lookup)
         (let check ([ids '()] [x #'pattern])
           (syntax-case x (unquote unquote-splicing quasiquote)
             [(unquote (v <= pattern))
              (and (identifier? #'v) (eq? (datum <=) '<=))
              (check (add-identifier #'v ids) #'pattern)]
             [(unquote v)
              (let ([s (datum v)])
                (cond
                 [(eq? s '_) ids]
                 [(symbol? s) (add-identifier #'v ids)]
                 [else (bad-pattern x)]))]
             [(unquote-splicing var)
              (if (identifier? #'var)
                  ids
                  (bad-pattern x))]
             [(quasiquote (record spec ...))
              (identifier? #'record)
              (let ([fields (lookup #'record #'fields)])
                (unless fields
                  (syntax-error x "unknown record type in pattern"))
                (let check-specs ([ids ids] [specs #'(spec ...)])
                  (syntax-case specs (unquote)
                    [() ids]
                    [((unquote field) . rest)
                     (identifier? #'field)
                     (if (memq (datum field) fields)
                         (check-specs (add-identifier #'field ids) #'rest)
                         (syntax-error x
                           (format "unknown field ~a in pattern"
                             (datum field))))]
                    [([field pattern] . rest)
                     (identifier? #'field)
                     (if (memq (datum field) fields)
                         (check-specs (check ids #'pattern) #'rest)
                         (syntax-error x
                           (format "unknown field ~a in pattern"
                             (datum field))))]
                    [_ (bad-pattern x)])))]
             [(quasiquote _) (bad-pattern x)]
             [lit
              (let ([x (datum lit)])
                (or (symbol? x) (number? x) (boolean? x) (char? x)
                    (string? x) (bytevector? x) (null? x)))
              ids]
             [(first . rest) (check (check ids #'first) #'rest)]
             [#(element ...) (fold-left check ids #'(element ...))]
             [_ (bad-pattern x)]))
         #'(match-help e pattern fail body))]))

  (define-syntax (match-help x)
    (syntax-case x (unquote unquote-splicing quasiquote)
      [(_ e (unquote (v <= pattern)) fail body)
       #'(let ([v e]) (match-help v pattern fail body))]
      [(_ e (unquote v) fail body)
       (if (eq? (datum v) '_)
           #'(begin e body)
           #'(let ([v e]) body))]
      [(_ e (unquote-splicing var) fail body)
       #`(let ([v e])
           (if (equal? v var)
               body
               (fail)))]
      [(_ e (quasiquote (record spec ...)) fail body)
       #`(let ([v e])
           (if (record is? v)
               (match-record v (record spec ...) fail body)
               (fail)))]
      [(_ e lit fail body)
       (let ([x (datum lit)])
         (or (symbol? x) (number? x) (boolean? x) (char? x)))
       #`(let ([v e])
           (if (eqv? v 'lit)
               body
               (fail)))]
      [(_ e s fail body)
       (string? (datum s))
       #`(let ([v e])
           (if (and (string? v) (#3%string=? v s))
               body
               (fail)))]
      [(_ e bv fail body)
       (bytevector? (datum bv))
       #`(let ([v e])
           (if (and (bytevector? v) (#3%bytevector=? v bv))
               body
               (fail)))]
      [(_ e () fail body)
       #`(let ([v e])
           (if (null? v)
               body
               (fail)))]
      [(_ e (first . rest) fail body)
       #`(let ([v e])
           (if (pair? v)
               (match-help (#3%car v) first fail
                 (match-help (#3%cdr v) rest fail body))
               (fail)))]
      [(_ e #(element ...) fail body)
       #`(let ([v e])
           (if (and (vector? v)
                    (#3%fx= (#3%vector-length v) (length '(element ...))))
               (match-vector v 0 (element ...) fail body)
               (fail)))]))

  (define-syntax match-record
    (syntax-rules (unquote)
      [(_ v (record) fail body) body]
      [(_ v (record (unquote field) . rest) fail body)
       (let ([field (record no-check field v)])
         (match-record v (record . rest) fail body))]
      [(_ v (record [field pattern] . rest) fail body)
       (match-help (record no-check field v) pattern fail
         (match-record v (record . rest) fail body))]))

  (define-syntax match-vector
    (syntax-rules ()
      [(_ v i () fail body) body]
      [(_ v i (pattern . rest) fail body)
       (match-help (#3%vector-ref v i) pattern fail
         (match-vector v (fx+ i 1) rest fail body))]))

  (define-syntax (define-record x)
    (syntax-case x ()
      [(_ name field ...)
       (and (identifier? #'name)
            (let valid-fields? ([fields #'(field ...)] [seen '()])
              (syntax-case fields ()
                [(fn . rest)
                 (and (identifier? #'fn)
                      (let ([f (datum fn)])
                        (when (memq f '(make copy copy* is?))
                          (bad-syntax "invalid field" x #'fn))
                        (when (memq f seen)
                          (bad-syntax "duplicate field" x #'fn))
                        (valid-fields? #'rest (cons f seen))))]
                [() #t]
                [_ #f])))
       #'(begin
           (define-syntax (name x)
             (define (generate-name prefix fn)
               (if (not prefix) fn (compound-id fn prefix fn)))
             (define (handle-open x expr prefix field-names)
               (define (make-accessor fn)
                 (let ([new-name (generate-name prefix fn)])
                   #`(define-syntax #,new-name (identifier-syntax (name no-check #,fn tmp)))))
               (if (not (valid-field-references? field-names))
                   (syntax-case x ())
                   #`(begin
                       (define tmp
                         (let ([val #,expr])
                           (unless (name is? val)
                             (exit `#(bad-record name ,val ,#,(find-source x))))
                           val))
                       #,@(map make-accessor (syntax->list field-names)))))
             (define (handle-copy x e bindings mode)
               #`(let ([src #,e])
                   #,(case mode
                       [copy
                        #`(unless (name is? src)
                            (exit `#(bad-record name ,src ,#,(find-source x))))]
                       [copy*
                        (handle-open x #'src #f (get-binding-names bindings))])
                   (vector 'name #,@(copy-record #'(field ...) 1 bindings))))
             (define (get-binding-names bindings)
               (syntax-case bindings ()
                 [((fn fv) . rest)
                  (cons #'fn (get-binding-names #'rest))]
                 [() '()]))
             (define (valid-bindings? bindings)
               (valid-field-references?
                (get-binding-names bindings)))
             (define (valid-field-references? f*)
               (let valid? ([f* f*] [seen '()])
                 (syntax-case f* ()
                   [(fn . rest)
                    (identifier? #'fn)
                    (let ([f (datum fn)])
                      (when (memq f seen)
                        (bad-syntax "duplicate field" x #'fn))
                      (unless (memq f '(field ...))
                        (bad-syntax "unknown field" x #'fn))
                      (valid? #'rest (cons f seen)))]
                   [() #t]
                   [_ #f])))
             (define (make-record fields bindings)
               (if (snull? fields)
                   '()
                   (let* ([f (scar fields)]
                          [v (find-binding f bindings)])
                     (unless v
                       (syntax-error x
                         (format "missing field ~a in" (syntax->datum f))))
                     (cons v
                       (make-record (scdr fields) (remove-binding f bindings))))))
             (define (copy-record fields index bindings)
               (if (snull? fields)
                   '()
                   (let* ([f (scar fields)]
                          [v (find-binding f bindings)])
                     (if v
                         (cons v (copy-record (scdr fields) (+ index 1)
                                   (remove-binding f bindings)))
                         (cons #`(#3%vector-ref src #,(datum->syntax f index))
                           (copy-record (scdr fields) (+ index 1) bindings))))))
             (define (find-binding f bindings)
               (syntax-case bindings ()
                 [((fn fv) . rest)
                  (if (syntax-datum-eq? #'fn f)
                      #'fv
                      (find-binding f #'rest))]
                 [() #f]))
             (define (remove-binding f bindings)
               (syntax-case bindings ()
                 [((fn fv) . rest)
                  (if (syntax-datum-eq? #'fn f)
                      #'rest
                      #`((fn fv) #,@(remove-binding f #'rest)))]))
             (define (find-index fn fields index)
               (let ([f (scar fields)])
                 (if (syntax-datum-eq? f fn)
                     index
                     (find-index fn (scdr fields) (+ index 1)))))
             (syntax-case x ()
               [(name make . bindings)
                (and (eq? (datum make) 'make)
                     (valid-bindings? #'bindings))
                #`(vector 'name #,@(make-record #'(field ...) #'bindings))]
               [(name copy e . bindings)
                (and (eq? (datum copy) 'copy)
                     (valid-bindings? #'bindings))
                (handle-copy x #'e #'bindings 'copy)]
               [(name copy* e . bindings)
                (and (eq? (datum copy*) 'copy*)
                     (valid-bindings? #'bindings))
                (handle-copy x #'e #'bindings 'copy*)]
               [(name open expr prefix field-names)
                (and (eq? (datum open) 'open) (identifier? #'prefix))
                (handle-open x #'expr #'prefix #'field-names)]
               [(name open expr field-names)
                (eq? (datum open) 'open)
                (handle-open x #'expr #f #'field-names)]
               [(name is? e)
                (eq? (datum is?) 'is?)
                #'(let ([x e])
                    (and (vector? x)
                         (#3%fx= (#3%vector-length x) (length '(name field ...)))
                         (eq? (#3%vector-ref x 0) 'name)))]
               [(name fn e)
                (syntax-datum-eq? #'fn #'field)
                (with-annotated-syntax ([getter x (name fn)])
                  #`(getter e))]
               ...
               [(name fn)
                (syntax-datum-eq? #'fn #'field)
                #`(lambda (x)
                    (unless (name is? x)
                      (exit `#(bad-record name ,x ,#,(find-source x))))
                    (#3%vector-ref x #,(find-index #'fn #'(field ...) 1)))]
               ...
               [(name no-check fn e)
                (and (eq? (datum no-check) 'no-check)
                     (syntax-datum-eq? #'fn #'field))
                #`(#3%vector-ref e #,(find-index #'fn #'(field ...) 1))]
               ...
               [(name fn)
                (identifier? #'fn)
                (bad-syntax "unknown field" x #'fn)]
               [(name fn expr)
                (identifier? #'fn)
                (bad-syntax "unknown field" x #'fn)]
               ))
           (define-property name fields '(field ...)))]))

  (define-syntax redefine
    (syntax-rules ()
      [(_ var e) (#%$set-top-level-value! 'var e)]))

  (record-writer (record-type-descriptor pcb)
    (lambda (r p wr)
      (display-string "#<process " p)
      (wr (pcb-id r) p)
      (let ([name (pcb-name r)])
        (when name
          (write-char #\space p)
          (wr name p)))
      (write-char #\> p)))

  (record-writer (csv7:record-type-descriptor
                  (condition (make-error) (make-warning)))
    (lambda (x p wr)
      (display-string "#<compound condition: " p)
      (display-condition x p)
      (write-char #\> p)))

  (disable-interrupts)
  (set-self! (@make-process #f))
  (set! event-loop-process
    (spawn
     (lambda ()
       (disable-interrupts)
       (@event-loop))))
  (set! finalizer-process (spawn finalizer-loop))
  (timer-interrupt-handler
   (lambda ()
     (if (IsTickOver)
         (yield run-queue 0)
         (set-timer process-default-ticks))))
  (redefine collect
    (let ([system-collect (#%$top-level-value 'collect)])
      (lambda args
        (apply system-collect args)
        (send finalizer-process 'go))))

  ;; Redefine Chez Scheme parameters
  (redefine custom-port-buffer-size
    (make-process-parameter 1024
      (lambda (x)
        (unless (and (fixnum? x) (fx> x 0))
          (bad-arg 'custom-port-buffer-size x))
        x)))
  (redefine pretty-initial-indent
    (make-process-parameter 0
      (lambda (x)
        (unless (and (fixnum? x) (fx>= x 0))
          (bad-arg 'pretty-initial-indent x))
        x)))
  (redefine pretty-line-length
    (make-process-parameter 75
      (lambda (x)
        (unless (and (fixnum? x) (fx> x 0))
          (bad-arg 'pretty-line-length x))
        x)))
  (redefine pretty-maximum-lines
    (make-process-parameter #f
      (lambda (x)
        (unless (or (not x) (and (fixnum? x) (fx>= x 0)))
          (bad-arg 'pretty-maximum-lines x))
        x)))
  (redefine pretty-one-line-limit
    (make-process-parameter 60
      (lambda (x)
        (unless (and (fixnum? x) (fx> x 0))
          (bad-arg 'pretty-one-line-limit x))
        x)))
  (redefine pretty-standard-indent
    (make-process-parameter 1
      (lambda (x)
        (unless (and (fixnum? x) (fx>= x 0))
          (bad-arg 'pretty-standard-indent x))
        x)))
  (redefine print-brackets (make-process-parameter #t (lambda (x) (and x #t))))
  (redefine print-char-name (make-process-parameter #f (lambda (x) (and x #t))))
  (redefine print-gensym
    (make-process-parameter #t
      (lambda (x) (if (memq x '(pretty pretty/suffix)) x (and x #t)))))
  (redefine print-graph (make-process-parameter #f (lambda (x) (and x #t))))
  (redefine print-length
    (make-process-parameter #f
      (lambda (x)
        (unless (or (not x) (and (fixnum? x) (fx>= x 0)))
          (bad-arg 'print-length x))
        x)))
  (redefine print-level
    (make-process-parameter #f
      (lambda (x)
        (unless (or (not x) (and (fixnum? x) (fx>= x 0)))
          (bad-arg 'print-level x))
        x)))
  (redefine print-precision
    (make-process-parameter #f
      (lambda (x)
        (unless (or (not x) (and (or (fixnum? x) (bignum? x)) (> x 0)))
          (bad-arg 'print-precision x))
        x)))
  (redefine print-radix
    (make-process-parameter 10
      (lambda (x)
        (unless (and (fixnum? x) (fx<= 2 x 36))
          (bad-arg 'print-radix x))
        x)))
  (redefine print-record (make-process-parameter #t (lambda (x) (and x #t))))
  (redefine print-unicode (make-process-parameter #t (lambda (x) (and x #t))))
  (redefine print-vector-length
    (make-process-parameter #f (lambda (x) (and x #t))))

  (SetTick)
  (set-timer process-default-ticks)
  (enable-interrupts))
