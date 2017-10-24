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

(import
 (swish mat)
 (swish osi)
 (swish string-utils)
 (except (chezscheme) define-record sleep))

(define-syntax (assert-error-pair x)
  (syntax-case x ()
    [(_ who what e) #`($assert-error-pair who what e #'#,x)]))

(define ($assert-error-pair who what x src)
  (unless (and (pair? x) (eq? (car x) who) (equal? (cdr x) what))
    (raise
     (condition (make-assertion-violation)
       (make-source-condition src)
       (make-format-condition)
       (make-message-condition "~s did not match expected ~s")
       (make-irritants-condition (list x (cons who what)))))))

(define-syntax (assert-callback x)
  (syntax-case x ()
    [(_ timeout callback args ...)
     #`($assert-callback timeout callback (list args ...) #'#,x)]))

(define ($assert-callback timeout callback args src)
  (let ([x (GetCompletionPacket timeout)])
    (unless x
      (raise
       (condition (make-assertion-violation)
         (make-source-condition src)
         (make-format-condition)
         (make-message-condition "no callback fired within ~a ms")
         (make-irritants-condition (list timeout)))))
    (unless (pair? x)
      (raise
       (condition (make-assertion-violation)
         (make-source-condition src)
         (make-format-condition)
         (make-message-condition "GetCompletionPacket returned invalid value ~s")
         (make-irritants-condition (list x)))))
    (unless (eq? (car x) callback)
      (raise
       (condition (make-assertion-violation)
         (make-source-condition src)
         (make-format-condition)
         (make-message-condition "unexpected callback ~s fired")
         (make-irritants-condition (list x)))))
    (unless (and (= (length (cdr x)) (length args))
                 (andmap equal? (cdr x) args))
      (raise
       (condition (make-assertion-violation)
         (make-source-condition src)
         (make-format-condition)
         (make-message-condition "~s did not match expected ~s")
         (make-irritants-condition (list (cdr x) args)))))))

(unless (foreign-entry? "Sleep")
  (load-shared-object "kernel32.dll"))

(define-syntax windows-procedure
  (case (machine-type)
    [(a6nt)
     (syntax-rules ()
       [(_ name (arg ...) ret)
        (foreign-procedure name (arg ...) ret)])]
    [(i3nt)
     (syntax-rules ()
       [(_ name (arg ...) ret)
        (foreign-procedure __stdcall name (arg ...) ret)])]
    [else syntax-error]))

(define-syntax windows-callable
  (case (machine-type)
    [(a6nt)
     (syntax-rules ()
       [(_ name (arg ...) ret)
        (foreign-callable name (arg ...) ret)])]
    [(i3nt)
     (syntax-rules ()
       [(_ name (arg ...) ret)
        (foreign-callable __stdcall name (arg ...) ret)])]
    [else syntax-error]))

(define Sleep
  (windows-procedure "Sleep" (unsigned-32) void))

(define SetLastError
  (windows-procedure "SetLastError" (unsigned-32) void))

(define (gc)
  (collect (collect-maximum-generation)))

(define (make-last-error-proc error-code return-value)
  (lambda args
    (SetLastError error-code)
    return-value))

(define-syntax (unhooked x) (syntax-error x "misplaced construct"))

(define-syntax with-hook
  (syntax-rules (foreign)
    [(_ name (foreign hook-func (arg-type ...) ret-type) body ...)
     (let* ([hook-name
             (foreign-procedure (string-append "(debug)Hook" name)
               (uptr) uptr)]
            [prev 0]
            [hook
             (fluid-let-syntax
              ([unhooked
                (identifier-syntax
                 (windows-procedure prev (arg-type ...) ret-type))])
              hook-func)]
            [hook-fc (windows-callable hook (arg-type ...) ret-type)])
       (dynamic-wind
         (lambda ()
           (disable-interrupts)
           (lock-object hook-fc)
           (set! prev (hook-name (foreign-callable-entry-point hook-fc))))
         (lambda () body ...)
         (lambda ()
           (hook-name prev)
           (unlock-object hook-fc)
           (enable-interrupts))))]))

(define-syntax with-c-hook
  (syntax-rules ()
    [(_ name case body ...)
     (let ([hook
            (foreign-procedure (string-append "(debug)Hook" name) (int) void)]
           [x case])
       (dynamic-wind
         (lambda () (hook x))
         (lambda () body ...)
         (lambda () (hook 0))))]))

(define (standard-reporter name tags result)
  (when (pair? result)
    (printf "mat ~a failed: " name)
    (display-condition (cdr result))
    (newline)
    (exit)))

(define (silent-runner name)
  (run-mat name standard-reporter))

(define (loud-runner name)
  (printf "running mat ~a\n" name)
  (run-mat name standard-reporter))

(define (run-tag tag runner)
  (for-each-mat
   (lambda (name tags)
     (when (memq tag tags)
       (runner name)))))

(define (loop-report name n)
  (gc)
  (printf "~13:D Scheme bytes ~13:D C bytes ~13:D private bytes\n"
    (bytes-allocated)
    (GetBytesUsed)
    (vector-ref (GetMemoryInfo) 10)))

(define (loop-mat name)
  (let lp ([n 0])
    (when (= (modulo n 1000) 0)
      (loop-report name n))
    (run-mat name standard-reporter)
    (lp (+ n 1))))

(define (limited-loop name count report-freq)
  (let lp ([n 0])
    (unless (> n count)
      (when (= (modulo n report-freq) 0)
        (loop-report name n))
      (run-mat name standard-reporter)
      (lp (+ n 1)))))

(define (get-stats)
  (gc)
  (values (bytes-allocated) (GetBytesUsed)))

(define (make-leak-runner)
  (let-values ([(base-scheme-bytes base-c-bytes) (get-stats)])
    (lambda (name)
      (printf "leak testing mat ~25a" name)
      (flush-output-port)
      (let ([target (+ (GetTickCount) 1000)])
        (let lp ()
          (run-mat name standard-reporter)
          (when (< (GetTickCount) target)
            (lp)))
        (let-values ([(scheme-bytes c-bytes) (get-stats)])
          (printf " ~11:D Scheme ~11:D C\n"
            (- scheme-bytes base-scheme-bytes)
            (- c-bytes base-c-bytes)))))))

(define (run-osi runner)
  (run-tag 'common runner))

(define (go)
  (run-osi loud-runner)
  (run-osi (make-leak-runner)))

(define (go2 outdir)
  (reset-handler (lambda () (display "\nTest Failed\n") (abort 1)))
  (let ([outfile (string-append outdir "/osi.mo")])
    (run-mats-to-file outfile)
    (let-values ([(pass fail) (summarize (list outfile))])
      (printf "Tests run: ~s   Pass: ~s   Fail: ~s\n\n"
        (+ pass fail) pass fail))))

(define (overnight)
  (run-osi loud-runner)
  (let ([leak-runner (make-leak-runner)])
    (define (runner name)
      (when (call/cc
             (lambda (failed?)
               (guard (c [#t (display-condition c) (failed? #t)])
                 (leak-runner name))
               #f))
        (drain-callbacks 30000)))
    (let lp ()
      (printf "~a\n" (date-and-time))
      (run-osi runner)
      (lp))))

(define (drain-callbacks wait-time)
  (when (GetCompletionPacket wait-time)
    (drain-callbacks wait-time)))

(define U64-values
  '(#xFEDCBA9876543210
    #xFEDCBA98765432
    #xFEDCBA987654
    #xFEDCBA9876
    #xFEDCBA98
    #xFEDCBA
    #xFEDC
    #xFE))

(define (poke-U64! addr x) (foreign-set! 'unsigned-64 addr 0 x))

(define (unsigned? x)
  (and (or (fixnum? x) (bignum? x)) (>= x 0)))

(define (starts-with? str pre)
  (let ([slen (string-length str)]
        [plen (string-length pre)])
    (and (>= slen plen)
         (let lp ([n 0])
           (cond
            [(= n plen) #t]
            [(char-ci=? (string-ref str n) (string-ref pre n)) (lp (+ n 1))]
            [else #f])))))

(mat pipe (common)
  (define pipe-name "\\\\.\\pipe\\osi.ms")

  (assert-error-pair 'osi::CreateServerPipe 160 (CreateServerPipe* #f #f))
  (assert-error-pair 'osi::CreateServerPipe 160
    (CreateServerPipe* pipe-name #f))
  (assert-error-pair 'CreateNamedPipeW 123 (CreateServerPipe* "*" void))
  (assert-error-pair 'osi::CreateClientPipe 160 (CreateClientPipe* #f))
  (assert-error-pair 'CreateFileW 123 (CreateClientPipe* "*"))
  (with-hook "CreateIoCompletionPort"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr unsigned-32)
     uptr)
    (assert-error-pair 'CreateIoCompletionPort 2
      (CreateServerPipe* pipe-name void)))
  (with-hook "ConnectNamedPipe"
    (foreign (make-last-error-proc 2 0)
      (uptr uptr)
      int)
    (assert-error-pair 'ConnectNamedPipe 2
      (CreateServerPipe* pipe-name void)))
  (with-hook "ConnectNamedPipe"
    (foreign
     (lambda args
       (apply unhooked args)
       (SetLastError 535)
       0)
     (uptr uptr)
     int)
    (ClosePort (CreateServerPipe pipe-name void)))
  (assert-callback 1000 void 0 109)
  (let* ([callback (lambda (count errno) errno)]
         [server
          (with-hook "ConnectNamedPipe"
            (foreign
             (lambda args
               (apply unhooked args)
               1)
             (uptr uptr)
             int)
            (CreateServerPipe pipe-name callback))])
    (with-hook "CreateIoCompletionPort"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr uptr unsigned-32)
       uptr)
      (assert-error-pair 'CreateIoCompletionPort 2
        (CreateClientPipe* pipe-name)))
    (assert-callback 1000 callback 0 0)
    (ClosePort server))
  (let* ([callback (lambda (count errno) errno)]
         [server (CreateServerPipe pipe-name callback)]
         [client (CreateClientPipe pipe-name)]
         [bv (make-test-bytevector 4096)]
         [n (bytevector-length bv)])
    (assert-callback 1000 callback 0 0)
    (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* server))
    (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* server))
    (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* client))
    (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* client))
    (assert-error-pair 'osi::WritePort 160
      (WritePort* server bv 0 n 0 callback))
    (write-test server bv n #f)
    (assert-error-pair 'osi::ReadPort 160
      (ReadPort* client bv 0 n 0 callback))
    (read-test client bv n #f)
    (write-test client bv n #f)
    (read-test server bv n #f)
    (writefile-test server bv n #f)
    (readfile-test client bv n #f)
    (ClosePort client)
    (ClosePort server)))

(mat process (common)
  ;; Be careful not to leak handles from CreateWatchedProcess.

  (define (process? x)
    (and (vector? x) (eq? (vector-ref x 0) '<process>)))
  (define (process-id x)
    (vector-ref x 1))
  (define (process-iport x)
    (vector-ref x 2))
  (define (process-oport x)
    (vector-ref x 3))

  ;; CreateDetachedWatchedProcess argument errors
  (assert-error-pair 'osi::CreateDetachedWatchedProcess 160
    (CreateDetachedWatchedProcess* #f void))
  (assert-error-pair 'osi::CreateDetachedWatchedProcess 160
    (CreateDetachedWatchedProcess* "swish/sleep 10 321" #f))

  ;; CreateDetachedWatchedProcess success
  (let* ([callback (lambda args 0)]
         [id (CreateDetachedWatchedProcess "swish/sleep 10 321" callback)])
    (assert-callback 1000 callback id 321))

  ;; CreateDetachedWatchedProcess: error in CreateProcess
  (assert-error-pair 'CreateProcessW 2
    (CreateDetachedWatchedProcess* "bad-notepad" void))

  ;; CreateDetachedWatchedProcess: error in RegisterWaitForSingleObject
  (with-hook "RegisterWaitForSingleObject"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr uptr unsigned-32 unsigned-32)
     int)
    (assert-error-pair 'RegisterWaitForSingleObject 2
      (CreateDetachedWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess argument errors
  (assert-error-pair 'osi::CreateWatchedProcess 160
    (CreateWatchedProcess* #f void))
  (assert-error-pair 'osi::CreateWatchedProcess 160
    (CreateWatchedProcess* "swish/sleep 10 321" #f))

  ;; CreateWatchedProcess success
  (let* ([callback (lambda args 0)]
         [proc (CreateWatchedProcess "swish/sleep 100 321" callback)]
         [len 4096]
         [bv (make-test-bytevector len)])
    (assert (process? proc))
    (let ([p (process-iport proc)])
      (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* p))
      (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* p))
      (assert-error-pair 'osi::ReadPort 160 (ReadPort* p bv 0 len 0 void))
      (assert-error-pair 'osi::WritePort 5 (WritePort* p bv 0 len #f void))
      (ClosePort p))
    (let ([p (process-oport proc)])
      (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* p))
      (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* p))
      (assert-error-pair 'osi::ReadPort 5 (ReadPort* p bv 0 len #f void))
      (assert-error-pair 'osi::WritePort 160 (WritePort* p bv 0 len 0 void))
      (with-hook "WriteFile"
        (foreign
         (lambda args
           (cond
            [(= (apply unhooked args) 0) 0]
            [else (SetLastError 997) 0]))
         (uptr uptr unsigned-32 uptr uptr)
         int)
        (WritePort p bv 0 1 #f callback))
      (assert-callback 1000 callback 1 0)
      (assert-callback 1000 callback (process-id proc) 321)
      (assert-error-pair 'WriteFile 232 (WritePort* p bv 1 (- len 1) #f void))
      (ClosePort p)))

  ;; CreateWatchedProcess, TerminateProcess success
  (let* ([callback (lambda args 0)]
         [p (CreateWatchedProcess "swish/sleep 2000 321" callback)])
    (ClosePort (process-iport p))
    (ClosePort (process-oport p))
    (TerminateProcess (process-id p) 123)
    (assert-callback 1000 callback (process-id p) 123))

  ;; CreateWatchedProcess: error in CreateNamedPipe (first call)
  (with-hook "CreateNamedPipeW"
    (foreign
     (make-last-error-proc 2 -1)
     (uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32 uptr)
     uptr)
    (assert-error-pair 'CreateNamedPipeW 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: error in CreateIoCompletionPort (first call)
  (with-hook "CreateIoCompletionPort"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr unsigned-32)
     uptr)
    (assert-error-pair 'CreateIoCompletionPort 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: error in CreateFile (first call)
  (with-hook "CreateFileW"
    (foreign
     (make-last-error-proc 2 -1)
     (uptr unsigned-32 unsigned-32 uptr unsigned-32 unsigned-32 uptr)
     uptr)
    (assert-error-pair 'CreateFileW 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: error in CreateNamedPipe (second call)
  (with-hook "CreateNamedPipeW"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           (apply unhooked args)]
          [else
           (SetLastError 2)
           -1])))
     (uptr unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32 unsigned-32 uptr)
     uptr)
    (assert-error-pair 'CreateNamedPipeW 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: error in CreateIoCompletionPort (second call)
  (with-hook "CreateIoCompletionPort"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           (apply unhooked args)]
          [else
           (SetLastError 2)
           0])))
     (uptr uptr uptr unsigned-32)
     uptr)
    (assert-error-pair 'CreateIoCompletionPort 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: error in CreateFile (second call)
  (with-hook "CreateFileW"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           (apply unhooked args)]
          [else
           (SetLastError 2)
           -1])))
     (uptr unsigned-32 unsigned-32 uptr unsigned-32 unsigned-32 uptr)
     uptr)
    (assert-error-pair 'CreateFileW 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; CreateWatchedProcess: very long command line
  (assert-error-pair 'CreateProcessW 2
    (CreateWatchedProcess* (make-string 4096 #\b) void))

  ;; CreateWatchedProcess: error in CreateProcess
  (assert-error-pair 'CreateProcessW 2
    (CreateWatchedProcess* "bad-notepad" void))

  ;; CreateWatchedProcess: error in RegisterWaitForSingleObject
  (with-hook "RegisterWaitForSingleObject"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr uptr unsigned-32 unsigned-32)
     int)
    (assert-error-pair 'RegisterWaitForSingleObject 2
      (CreateWatchedProcess* "swish/sleep" void)))

  ;; TerminateProcess: error in TerminateProcess
  (let* ([callback (lambda args 0)]
         [p (CreateWatchedProcess "swish/sleep 2000 321" callback)])
    (ClosePort (process-iport p))
    (ClosePort (process-oport p))
    (assert-error-pair 'osi::TerminateProcess 6 (TerminateProcess* 0 123))
    (with-hook "TerminateProcess"
      (foreign
       (make-last-error-proc 2 0)
       (uptr unsigned-32)
       int)
      (assert-error-pair 'TerminateProcess 2
        (TerminateProcess* (process-id p) 123)))
    (TerminateProcess (process-id p) 123)
    (assert-callback 1000 callback (process-id p) 123))

  ;; SetMainThreadPriority
  (assert-error-pair 'SetThreadPriority 87
    (SetMainThreadPriority* -3))
  (SetMainThreadPriority 0)

  ;; SetPriorityClass
  (assert-error-pair 'SetPriorityClass 87
    (SetPriorityClass* 1))
  (SetPriorityClass #x20)
  )

(mat sqlite (common)
  ;; busy database errors
  (assert-error-pair 'osi::OpenDatabase 160 (OpenDatabase* #f 0))
  (assert-error-pair 'sqlite3_open_v2 600000021 (OpenDatabase* "*" 0))
  (let* ([db (OpenDatabase ":memory:" 6)]
         [sql "select null as c1, 0 as c2, 1000000000000 as c3, 1.25 as c4, 'text' as c5, x'010203' as c6"]
         [stmt (PrepareStatement db sql)]
         [cb (lambda args 0)])
    (assert-error-pair 'osi::PrepareStatement 160 (PrepareStatement* db #f))
    (assert-error-pair 'sqlite3_prepare_v2 600000001
      (PrepareStatement* db "bad sql"))
    (assert-error-pair 'sqlite3_bind_null 600000025 (BindStatement* stmt 0 #f))
    (assert-error-pair 'sqlite3_bind_int64 600000025 (BindStatement* stmt 0 0))
    (assert-error-pair 'sqlite3_bind_int64 600000025
      (BindStatement* stmt 0 1000000000000))
    (guard (c [(and (message-condition? c)
                    (string=? (condition-message c) "~s is out of range")) #t])
      (BindStatement* stmt 0 #e1e100)
      (error 'BindStatement "no Int64 overflow"))
    (assert-error-pair 'sqlite3_bind_double 600000025
      (BindStatement* stmt 0 1.25))
    (assert-error-pair 'sqlite3_bind_text 600000025
      (BindStatement* stmt 0 "text"))
    (assert-error-pair 'sqlite3_bind_blob 600000025
      (BindStatement* stmt 0 #vu8(1 2 3)))
    (assert-error-pair 'osi::BindStatement 160 (BindStatement* stmt 0 'symbol))
    (assert-error-pair 'osi::StepStatement 160 (StepStatement* stmt 0))
    (StepStatement stmt cb)
    (assert-error-pair 'osi::BindStatement 5 (BindStatement* stmt 0 0))
    (assert-error-pair 'osi::ClearStatementBindings 5
      (ClearStatementBindings* stmt))
    (assert-error-pair 'osi::CloseDatabase 5 (CloseDatabase* db))
    (assert-error-pair 'osi::FinalizeStatement 5 (FinalizeStatement* stmt))
    (assert-error-pair 'osi::GetLastInsertRowid 5 (GetLastInsertRowid* db))
    (assert-error-pair 'sqlite3_status 600000021 (GetSQLiteStatus* -1 #f))
    (GetSQLiteStatus 0 0)
    (assert-error-pair 'osi::GetStatementColumns 5 (GetStatementColumns* stmt))
    (assert-error-pair 'osi::GetStatementSQL 5 (GetStatementSQL* stmt))
    (assert-error-pair 'osi::PrepareStatement 5 (PrepareStatement* db ""))
    (assert-error-pair 'osi::ResetStatement 5 (ResetStatement* stmt))
    (assert-error-pair 'osi::StepStatement 5 (StepStatement* stmt cb))
    (assert-callback 1000 cb '#(#f 0 1000000000000 1.25 "text" #vu8(1 2 3)))
    (ClearStatementBindings stmt)
    (GetLastInsertRowid db)
    (assert (equal? (GetStatementColumns stmt)
              '#("c1" "c2" "c3" "c4" "c5" "c6")))
    (assert (string=? (GetStatementSQL stmt) sql))
    (StepStatement stmt cb)
    (assert-callback 1000 cb #f)
    (let* ([db2 (OpenDatabase ":memory:" 6)]
           [stmt2 (PrepareStatement db2 "select cast(? as text)")]
           [bad-utf8
            '(#vu8(#x80)
               #vu8(#xC0) #vu8(#xC0 0)
               #vu8(#xE0) #vu8(#xE0 0 0) #vu8(#xE0 #x80 0)
               #vu8(#xF0) #vu8(#xF8 0 0 0) #vu8(#xF0 0 0 0)
               #vu8(#xF0 #x80 0 0) #vu8(#xF0 #x80 #x80 0)
               #vu8(#xED #xA0 #xBF))])
      (CloseDatabase db)
      (for-each
       (lambda (blob)
         (BindStatement stmt2 1 blob)
         (StepStatement stmt2 cb)
         (assert-callback 1000 cb '(MakeSchemeString . 582))
         (ResetStatement stmt2))
       bad-utf8)
      (FinalizeStatement stmt2)
      (CloseDatabase db2))
    (assert-error-pair 'osi::BindStatement 6 (BindStatement* stmt 0 0))
    (assert-error-pair 'osi::ClearStatementBindings 6
      (ClearStatementBindings* stmt))
    (assert-error-pair 'osi::GetLastInsertRowid 6 (GetLastInsertRowid* db))
    (assert-error-pair 'osi::GetStatementColumns 6 (GetStatementColumns* stmt))
    (assert-error-pair 'osi::GetStatementSQL 6 (GetStatementSQL* stmt))
    (assert-error-pair 'osi::FinalizeStatement 6 (FinalizeStatement* stmt))
    (assert-error-pair 'osi::PrepareStatement 6 (PrepareStatement* db "*"))
    (assert-error-pair 'osi::ResetStatement 6 (ResetStatement* stmt))
    (assert-error-pair 'osi::StepStatement 6 (StepStatement* stmt cb))
    (assert-error-pair 'osi::CloseDatabase 6 (CloseDatabase* db))
    )
  )

(define GENERIC_WRITE #x40000000)
(define GENERIC_READ #x80000000)
(define FILE_SHARE_READ 1)

(define (make-test-bytevector size)
  (let ([bv (make-bytevector size)])
    (do ([i 0 (+ i 1)]
         [j 0 (modulo (+ j 1) 256)])
        ((= i size) bv)
      (bytevector-u8-set! bv i j))))

(define (write-test p bv len fp)
  ;; argument failures
  (assert-error-pair 'osi::WritePort 6 (WritePort* 0 #f 0 0 fp #f))
  (assert-error-pair 'osi::WritePort 160 (WritePort* p #f 0 0 fp #f))
  (assert-error-pair 'osi::WritePort 160 (WritePort* p #vu8() 0 1 fp #f))
  (assert-error-pair 'osi::WritePort 160 (WritePort* p #vu8() 0 0 fp #f))
  (assert-error-pair 'osi::WritePort 160 (WritePort* p #vu8(1) 0 1 fp #f))
  ;; success
  (let ([callback (lambda args p)])
    (WritePort p bv 0 len fp callback)
    (gc)
    (assert-callback 1000 callback len 0)))

(define (writefile-test p bv len fp)
  (let ([callback (lambda args p)])
    (with-hook "WriteFile"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr unsigned-32 uptr uptr)
       int)
      (assert-error-pair 'WriteFile 2
        (WritePort* p bv 0 len fp callback)))
    (with-hook "WriteFile"
      (foreign
       (lambda args
         (cond
          [(= (apply unhooked args) 1)
           (SetLastError 997) ; ERROR_IO_PENDING
           0]
          [else 1]))
       (uptr uptr unsigned-32 uptr uptr)
       int)
      (WritePort p bv 0 len fp callback))
    (assert-callback 1000 callback len 0)))

(define (read-test p expected len fp)
  ;; argument failures
  (assert-error-pair 'osi::ReadPort 6 (ReadPort* -1 #f 0 0 fp #f))
  (assert-error-pair 'osi::ReadPort 160 (ReadPort* p #f 0 0 fp #f))
  (assert-error-pair 'osi::ReadPort 160 (ReadPort* p #vu8() 0 1 fp #f))
  (assert-error-pair 'osi::ReadPort 160 (ReadPort* p #vu8() 0 0 fp #f))
  (assert-error-pair 'osi::ReadPort 160
    (ReadPort* p (make-bytevector 1) 0 1 fp #f))

  ;; success
  (let* ([bv (make-bytevector len)]
         [callback (lambda args bv)])
    (ReadPort p bv 0 len fp callback)
    (gc)
    (assert-callback 1000 callback len 0)
    (assert (bytevector=? bv expected))))

(define (readfile-test p expected len fp)
  (let* ([bv (make-bytevector len)]
         [callback (lambda args bv)])
    (with-hook "ReadFile"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr unsigned-32 uptr uptr)
       int)
      (assert-error-pair 'ReadFile 2
        (ReadPort* p bv 0 len fp callback)))
    (with-hook "ReadFile"
      (foreign
       (lambda args
         (cond
          [(= (apply unhooked args) 1)
           (SetLastError 997) ; ERROR_IO_PENDING
           0]
          [else 1]))
       (uptr uptr unsigned-32 uptr uptr)
       int)
      (ReadPort p bv 0 len fp callback))
    (assert-callback 1000 callback len 0)
    (assert (bytevector=? bv expected))))

(mat files (common)
  (define CREATE_NEW 1)
  (define CREATE_ALWAYS 2)
  (define OPEN_EXISTING 3)
  (define OPEN_ALWAYS 4)
  (define TRUNCATE_EXISTING 5)

  (define noodles "\x9762;\x6761;")
  (define bullet "\x2022;")

  (define test-dir (string-append bullet "files-test" bullet))

  (define path-combine
    (case-lambda
     [(x y)
      (let ([n (string-length x)])
        (cond
         [(eqv? n 0) y]
         [(memv (string-ref x (fx- n 1)) '(#\/ #\\))
          (string-append x y)]
         [else (string-append x "\\" y)]))]
     [(x) x]
     [(x y . rest) (apply path-combine (path-combine x y) rest)]))

  (define (error-code=? x code)
    (and (pair? x) (= (cdr x) code)))

  ;; DeleteFile and RemoveDirectory return before the deletion is
  ;; finished.

  (define (sync-delete-file* path)
    (let ([r (DeleteFile* path)])
      (cond
       [(eq? r #t)
        ;; Check for it to really be gone.
        (let loop ([n 1])
          (let ([r (DeleteFile* path)])
            (cond
             [(error-code=? r 2) #t]    ; ERROR_FILE_NOT_FOUND
             [(and (< n 1000) (error-code=? r 5)) ; ERROR_ACCESS_DENIED
              (Sleep 10)
              (loop (+ n 1))]
             [else
              (errorf 'sync-delete-file* "failed to delete ~a: ~a" path r)])))]
       [else r])))

  (define (sync-delete-file path)
    (let ([r (sync-delete-file* path)])
      (when (pair? r)
        (errorf 'sync-delete-file "failed to delete ~a: ~a" path r))))

  (define (sync-remove-directory* path)
    (let ([r (RemoveDirectory* path)])
      (cond
       [(eq? r #t)
        ;; Check for it to really be gone.
        (let loop ([n 1])
          (let ([r (RemoveDirectory* path)])
            (cond
             [(error-code=? r 2) #t]    ; ERROR_FILE_NOT_FOUND
             [(and (< n 1000) (error-code=? r 5)) ; ERROR_ACCESS_DENIED
              (Sleep 10)
              (loop (+ n 1))]
             [else
              (errorf 'sync-remove-directory*-file
                "failed to delete ~a: ~a" path r)])))]
       [else r])))

  (define (sync-remove-directory path)
    (let ([r (sync-remove-directory* path)])
      (when (pair? r)
        (errorf 'sync-remove-directory
          "failed to remove directory ~a: ~a" path r))))

  (define (nuke path)
    (if (error-code=? (sync-remove-directory* path) 145) ; ERROR_DIR_NOT_EMPTY
        (when (eq? (FindFiles* (path-combine path "*") void) #t)
          (let ([x (GetCompletionPacket 1000)])
            (when (and (list? x) (= (length x) 2))
              (let ([names (cadr x)])
                (when (list? names)
                  (for-each (lambda (name) (nuke (path-combine path name)))
                    names)
                  (sync-remove-directory* path))))))
        (sync-delete-file* path)))

  (nuke test-dir)

  ;; CreateDirectory, RemoveDirectory, WatchDirectory, CreateFile,
  ;; CreateHardLink, ReadPort, WritePort, ClosePort, DeleteFile, MoveFile,
  ;; CloseDirectoryWatcher success
  (CreateDirectory test-dir)
  (let* ([watch-cb (lambda args args)]
         [watcher (WatchDirectory test-dir #t watch-cb)]
         [fn (path-combine test-dir "basic")]
         [linked "\x1d175;linked\x1d176;"]
         [fn2 (path-combine test-dir linked)]
         [fn3 (path-combine test-dir "moved")])
    (define-syntax (assert-watch-cbs x)
      (syntax-case x ()
        [(_ ls) #`($assert-watch-cbs watch-cb ls #'#,x)]))
    (define ($assert-watch-cbs callback ls src)
      (unless (null? ls)
        (let ([x (GetCompletionPacket 1000)])
          (unless x
            (raise
             (condition (make-assertion-violation)
               (make-source-condition src)
               (make-format-condition)
               (make-message-condition "no callback fired within ~a ms")
               (make-irritants-condition (list timeout)))))
          (unless (eq? (car x) callback)
            (raise
             (condition (make-assertion-violation)
               (make-source-condition src)
               (make-format-condition)
               (make-message-condition "unexpected callback ~s fired")
               (make-irritants-condition (list x)))))
          (unless (= (length x) 2)
            (raise
             (condition (make-assertion-violation)
               (make-source-condition src)
               (make-format-condition)
               (make-message-condition "~s did not match expected ~s")
               (make-irritants-condition (list (cdr x) ls)))))
          ($check-ls (cadr x) watch-cb ls src))))
    (define ($check-ls actual watch-cb expected src)
      (cond
       [(null? actual) ($assert-watch-cbs watch-cb expected src)]
       [(and (pair? (car actual)) (= (caar actual) 3)) ; ignore file modified
        ($check-ls (cdr actual) watch-cb expected src)]
       [(and (pair? expected) (equal? (car actual) (car expected)))
        ($check-ls (cdr actual) watch-cb (cdr expected) src)]
       [else
        (raise
         (condition (make-assertion-violation)
           (make-source-condition src)
           (make-format-condition)
           (make-message-condition "~s did not match expected ~s")
           (make-irritants-condition (list actual expected))))]))

    (let ([p (CreateFile fn GENERIC_WRITE FILE_SHARE_READ CREATE_NEW)]
          [bv (make-test-bytevector 4096)])
      (assert-callback 1000 watch-cb '((1 . "basic")))
      (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* p))
      (write-test p bv (bytevector-length bv) 0)
      (assert (eqv? (GetFileSize* p) 4096))
      (ClosePort p))
    (assert-callback 1000 watch-cb '((3 . "basic")))
    (CreateHardLink fn fn2)
    (assert-watch-cbs `((1 . ,linked)))

    (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* 0))
    (assert-error-pair 'osi::GetFullPath 160 (GetFullPath* #f))
    (let ([p (CreateFile fn GENERIC_READ FILE_SHARE_READ OPEN_EXISTING)]
          [bv (make-test-bytevector 4096)])
      (assert (eqv? (GetFileSize* p) 4096))
      (read-test p bv (bytevector-length bv) 0)
      (ClosePort p))
    (sync-delete-file fn)
    (assert-watch-cbs '((2 . "basic")))

    (let ([p (CreateFile fn2 GENERIC_READ FILE_SHARE_READ OPEN_EXISTING)]
          [bv (make-test-bytevector 4096)])
      (assert (eqv? (GetFileSize* p) 4096))
      (read-test p bv (bytevector-length bv) 0)
      (ClosePort p))
    (MoveFile fn2 fn3 0)
    (sync-delete-file fn3)
    (assert-watch-cbs `((4 . ,linked) (5 . "moved") (2 . "moved")))

    (CloseDirectoryWatcher watcher)
    (assert-callback 1000 watch-cb 0))
  (sync-remove-directory test-dir)

  ;; CreateFile errors
  (assert-error-pair 'osi::CreateFile 160
    (CreateFile* #f GENERIC_READ FILE_SHARE_READ OPEN_EXISTING))
  (assert-error-pair 'CreateFileW 2
    (CreateFile* "bad-file" GENERIC_READ FILE_SHARE_READ OPEN_EXISTING))

  ;; CreateHardLink errors
  (assert-error-pair 'osi::CreateHardLink 160
    (CreateHardLink* #f "foo"))
  (assert-error-pair 'osi::CreateHardLink 160
    (CreateHardLink* "foo" #f))
  (assert-error-pair 'CreateHardLinkW 2
    (CreateHardLink* "bad-file" "bad-file2"))

  ;; CreateFile: error in CreateIoCompletionPort
  (CreateDirectory test-dir)
  (let ([fn (path-combine test-dir "basic")])
    (with-hook "CreateIoCompletionPort"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr uptr unsigned-32)
       uptr)
      (let ([x (CreateFile* fn GENERIC_WRITE FILE_SHARE_READ CREATE_NEW)])
        (sync-delete-file fn)
        (sync-remove-directory test-dir)
        (assert-error-pair 'CreateIoCompletionPort 2 x))))

  ;; DeleteFile errors
  (assert-error-pair 'osi::DeleteFile 160 (DeleteFile* #f))
  (assert-error-pair 'DeleteFileW 2 (DeleteFile* "bad-file"))

  ;; MoveFile errors
  (assert-error-pair 'osi::MoveFile 160 (MoveFile* #f "*" 0))
  (assert-error-pair 'osi::MoveFile 160 (MoveFile* "*" #f 0))
  (assert-error-pair 'MoveFileExW 123 (MoveFile* "*" "*" 0))

  ;; ClosePort: error in ClosePort
  (assert-error-pair 'osi::ClosePort 6 (ClosePort* -1))

  ;; CreateDirectory errors
  (assert-error-pair 'osi::CreateDirectory 160 (CreateDirectory* #f))
  (CreateDirectory test-dir)
  (assert-error-pair 'CreateDirectoryW 183
    (CreateDirectory* test-dir))
  (sync-remove-directory test-dir)

  ;; RemoveDirectory errors
  (assert-error-pair 'osi::RemoveDirectory 160 (RemoveDirectory* #f))
  (assert-error-pair 'RemoveDirectoryW 2 (sync-remove-directory* "bad-dir"))

  ;; WatchDirectory errors
  (assert-error-pair 'osi::WatchDirectory 160 (WatchDirectory* #f #f #f))
  (assert-error-pair 'osi::WatchDirectory 160 (WatchDirectory* "*" #f #f))
  (assert-error-pair 'CreateFileW 2
    (WatchDirectory* "bad-dir" #t (lambda args args)))

  (CreateDirectory test-dir)
  (with-hook "CreateIoCompletionPort"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr unsigned-32)
     uptr)
    (assert-error-pair 'CreateIoCompletionPort 2
      (WatchDirectory* test-dir #t (lambda args args))))

  (with-hook "ReadDirectoryChangesW"
    (foreign
     (make-last-error-proc 2 #f)
     (uptr uptr unsigned-32 boolean unsigned-32 uptr uptr uptr)
     boolean)
    (assert-error-pair 'ReadDirectoryChangesW 2
      (WatchDirectory* test-dir #t (lambda args args))))

  ;; First call to ReadDirectoryChangesW success, subsequent calls fail.
  ;; Cause 2 changes. First callback contains a change. Second callback contains
  ;; an error 2.
  (with-hook "ReadDirectoryChangesW"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           (apply unhooked args)]
          [else
           (SetLastError 2)
           #f])))
     (uptr uptr unsigned-32 boolean unsigned-32 uptr uptr uptr)
     boolean)
    (let* ([watch-cb (lambda args args)]
           [watcher (WatchDirectory test-dir #t watch-cb)]
           [fn (path-combine test-dir "basic")])
      (ClosePort (CreateFile fn GENERIC_WRITE FILE_SHARE_READ CREATE_NEW))
      (sync-delete-file fn)
      (assert-callback 1000 watch-cb '((1 . "basic")))
      (assert-callback 1000 watch-cb 2)
      (CloseDirectoryWatcher watcher)))

  ;; First call to ReadDirectoryChangesW success, subsequent calls fail.
  ;; Cause 1 change. Close the watcher. First callback contains a change. Second
  ;; callback contains an error 0.
  (with-hook "ReadDirectoryChangesW"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           (apply unhooked args)]
          [else
           (SetLastError 2)
           #f])))
     (uptr uptr unsigned-32 boolean unsigned-32 uptr uptr uptr)
     boolean)
    (let* ([watch-cb (lambda args args)]
           [watcher (WatchDirectory test-dir #t watch-cb)]
           [fn (path-combine test-dir "basic")])
      (ClosePort (CreateFile fn GENERIC_WRITE FILE_SHARE_READ CREATE_NEW))
      (CloseDirectoryWatcher watcher)
      (sync-delete-file fn)
      (assert-callback 1000 watch-cb '((1 . "basic")))
      (assert-callback 1000 watch-cb 0)))

  (sync-remove-directory test-dir)

  ;; CloseDirectoryWatcher errors
  (assert-error-pair 'osi::CloseDirectoryWatcher 6 (CloseDirectoryWatcher* -1))

  ;; WritePort, ReadPort: error in WriteFile, ReadFile
  (CreateDirectory test-dir)
  (let ([fn (path-combine test-dir "api")])
    (let ([p (CreateFile fn (+ GENERIC_READ GENERIC_WRITE)
               FILE_SHARE_READ CREATE_NEW)]
          [bv (make-test-bytevector 1)]
          [callback (lambda args (void))])
      (writefile-test p bv 1 0)
      (readfile-test p bv 1 0)
      (with-hook "GetFileSizeEx"
        (foreign
         (make-last-error-proc 2 0)
         (uptr uptr)
         int)
        (assert-error-pair 'GetFileSizeEx 2
          (GetFileSize* p)))
      (ClosePort p))
    (sync-delete-file fn))
  (sync-remove-directory test-dir)

  ;; FindFiles argument failure
  (assert-error-pair 'osi::FindFiles 160 (FindFiles* #f #f))
  (assert-error-pair 'osi::FindFiles 160 (FindFiles* "" #f))

  ;; FindFiles: directory not found
  (FindFiles (path-combine test-dir "*") FindFiles)
  (assert-callback 1000 FindFiles '(FindFirstFileW . 3))

  ;; FindFiles: long spec
  (FindFiles (make-string 256 #\x) FindFiles)
  (assert-callback 1000 FindFiles '(FindFirstFileW . 3))

  ;; FindFiles: error in QueueUserWorkItem
  (with-hook "QueueUserWorkItem"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr unsigned-32)
     int)
    (assert-error-pair 'QueueUserWorkItem 2 (FindFiles* "*" void)))

  ;; FindFiles: success
  (CreateDirectory test-dir)
  (let ([ls `("foo" "BAR" "baz" ".foo" "..bar" ,noodles ,bullet "\x12345;")])
    (for-each
     (lambda (fn)
       (let ([p (CreateFile (path-combine test-dir fn)
                  GENERIC_WRITE FILE_SHARE_READ CREATE_NEW)])
         (ClosePort p)))
     ls)
    (FindFiles (path-combine test-dir "*") FindFiles)
    (let ([x (GetCompletionPacket 1000)])
      (assert x)
      (assert (list? x))
      (assert (eq? (car x) FindFiles))
      (assert (equal? (sort string<? (cadr x)) (sort string<? ls))))
    (for-each
     (lambda (fn) (sync-delete-file (path-combine test-dir fn)))
     ls))
  (sync-remove-directory test-dir)
  )

(mat console (common)
  (let ([p (OpenConsole)]
        [bv (make-bytevector 1)])
    (assert-error-pair 'osi::ReadPort 160
      (ReadPort* p bv 0 1 0 void))
    (with-hook "GetStdHandle"
      (foreign
       (make-last-error-proc 2 -1)
       (unsigned-32)
       uptr)
      (assert-error-pair 'GetStdHandle 2
        (ReadPort* p bv 0 1 #f void)))
    (assert-error-pair 'osi::WritePort 5
      (WritePort* p bv 0 1 #f void))
    (ClosePort p))
  )

(define tcp-initialized? #f)

(mat tcp (common)
  ;; Be careful not to leak handles from AcceptTCP's callback and
  ;; ConnectTCP's callback.

  (define (get-callbacks count timeout/callback)
    ;; returns: ((callback . args) ...)
    (if (= count 0)
        '()
        (let ([x (GetCompletionPacket timeout/callback)])
          (assert x)
          (cons x (get-callbacks (- count 1) timeout/callback)))))

  (define (lookup-callback-args cb ls)
    (cond
     [(assq cb ls) => cdr]
     [else (error 'lookup-callback-args "failed to find callback")]))

  (define (issue-accept server)
    (let ([callback (lambda args server)])
      (assert-error-pair 'osi::AcceptTCP 160 (AcceptTCP* server #f))
      (AcceptTCP server callback)
      (gc)
      callback))

  (define (issue-connect host port)
    (let ([callback (lambda args host)])
      (ConnectTCP host (number->string port) callback)
      (gc)
      callback))

  (define (extract-port args)
    (apply
     (case-lambda
      [(ioport) ioport]
      [(who errno)
       (error 'extract-port "unexpected value: ~s" (cons who errno))])
     args))

  ;; Failures
  (assert-error-pair 'osi::ConnectTCP 160 (ConnectTCP* #f "80" void))
  (assert-error-pair 'osi::ConnectTCP 160 (ConnectTCP* "127.0.0.1" #f void))
  (assert-error-pair 'osi::ConnectTCP 160 (ConnectTCP* "127.0.0.1" "80" #f))
  (unless tcp-initialized?
    (with-hook "WSAStartup"
      (foreign
       (lambda (version ptr) 2)
       (int uptr)
       int)
      (assert-error-pair 'WSAStartup 2 (ConnectTCP* "127.0.0.1" "80" void)))
    (with-hook "WSAStartup"
      (foreign
       (lambda (version ptr) 0)
       (int uptr)
       int)
      (assert-error-pair 'WSAStartup 10092 (ListenTCP* 1234)))
    (set! tcp-initialized? #t))
  (assert-callback 10000 (issue-connect "" 0) '(connect . 10049))

  ;; ListenTCP, AcceptTCP, ConnectTCP, CloseTCPListener, GetIPAddress success
  (let* ([server (ListenTCP 0)]
         [test-port (GetListenerPortNumber server)]
         [accept-cb (issue-accept server)]
         [connect-cb (issue-connect "::1" test-port)]
         [callbacks (get-callbacks 2 1000)]
         [accepted-port
          (extract-port (lookup-callback-args accept-cb callbacks))]
         [connected-port
          (extract-port (lookup-callback-args connect-cb callbacks))]
         [len 4096]
         [bv (make-test-bytevector len)])
    (with-hook "getpeername"
      (foreign
       (make-last-error-proc 2 1)
       (uptr uptr uptr)
       int)
      (assert-error-pair 'getpeername 2 (GetIPAddress* accepted-port))
      (assert-error-pair 'getpeername 2 (GetIPAddress* connected-port)))
    (with-hook "getsockname"
      (foreign
       (make-last-error-proc 2 1)
       (uptr uptr uptr)
       int)
      (assert-error-pair 'getsockname 2 (GetListenerPortNumber* server)))
    (with-hook "WSAAddressToStringW"
      (foreign
       (make-last-error-proc 2 1)
       (uptr unsigned-32 uptr uptr uptr)
       int)
      (assert-error-pair 'WSAAddressToStringW 2 (GetIPAddress* accepted-port))
      (assert-error-pair 'WSAAddressToStringW 2 (GetIPAddress* connected-port)))
    (assert (starts-with? (GetIPAddress accepted-port) "[::1]:"))
    (assert (string=? (GetIPAddress connected-port)
              (format "[::1]:~d" test-port)))
    (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* accepted-port))
    (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* connected-port))
    (assert-error-pair 'osi::ReadPort 160
      (ReadPort* connected-port bv 0 1 0 void))
    (assert-error-pair 'osi::WritePort 160
      (WritePort* accepted-port bv 0 1 0 void))
    (write-test accepted-port bv len #f)
    (read-test connected-port bv len #f)
    (with-hook "WSASend"
      (foreign
       (make-last-error-proc 2 -1)
       (uptr uptr unsigned-32 uptr unsigned-32 uptr uptr)
       int)
      (assert-error-pair 'WSASend 2
        (WritePort* accepted-port bv 0 1 #f void)))
    (with-hook "WSASend"
      (foreign
       (lambda args
         (cond
          [(= (apply unhooked args) 0)
           (SetLastError 997)
           -1]
          [else -1]))
       (uptr uptr unsigned-32 uptr unsigned-32 uptr uptr)
       int)
      (WritePort accepted-port bv 0 1 #f accept-cb))
    (assert-callback 1000 accept-cb 1 0)
    (with-hook "WSARecv"
      (foreign
       (make-last-error-proc 2 -1)
       (uptr uptr unsigned-32 uptr uptr uptr uptr)
       int)
      (assert-error-pair 'WSARecv 2
        (ReadPort* connected-port bv 0 1 #f void)))
    (with-hook "WSARecv"
      (foreign
       (lambda args
         (cond
          [(= (apply unhooked args) 0)
           (SetLastError 997)
           -1]
          [else -1]))
       (uptr uptr unsigned-32 uptr uptr uptr uptr)
       int)
      (ReadPort connected-port bv 0 1 #f connect-cb))
    (assert-callback 1000 connect-cb 1 0)
    (ClosePort connected-port)
    (ClosePort accepted-port)
    (CloseTCPListener server))

  ;; AcceptTCP & ConnectTCP: error in CreateIoCompletionPort
  (let* ([server (ListenTCP 0)]
         [test-port (GetListenerPortNumber server)]
         [accept-cb (issue-accept server)]
         [connect-cb (issue-connect "127.0.0.1" test-port)]
         [callbacks
          (with-hook "CreateIoCompletionPort"
            (foreign
             (make-last-error-proc 2 0)
             (uptr uptr uptr unsigned-32)
             uptr)
            (get-callbacks 2 1000))])
    (CloseTCPListener server)
    (assert (equal? (lookup-callback-args accept-cb callbacks)
              '((CreateIoCompletionPort . 2))))
    (assert (equal? (lookup-callback-args connect-cb callbacks)
              '((CreateIoCompletionPort . 2)))))

  ;; argument failures
  (assert-error-pair 'osi::AcceptTCP 6 (AcceptTCP* -1 #f))
  (assert-error-pair 'osi::CloseTCPListener 6 (CloseTCPListener* -1))
  (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* -1))
  (assert-error-pair 'osi::GetListenerPortNumber 6 (GetListenerPortNumber* -1))

  ;; ListenTCP: error in socket for IPv6
  (with-hook "socket"
    (foreign
     (lambda (af type protocol)
       (if (eqv? af 23) ;; AF_INET6
           (begin
             (SetLastError 10047)
             -1)
           (unhooked af type protocol)))
     (int int int)
     uptr)
    (CloseTCPListener (ListenTCP 0)))

  ;; ListenTCP: error in setsockopt
  (with-hook "setsockopt"
    (foreign
     (make-last-error-proc 10047 -1)
     (uptr int int uptr int)
     int)
    (assert-error-pair 'setsockopt 10047 (ListenTCP* 0)))
  (with-hook "setsockopt"
    (foreign
     (lambda (socket level name val len)
       (cond
        [(= level 41)                   ; IPPROTO_IPV6
         (SetLastError 10047)
         -1]
        [else (unhooked socket level name val len)]))
     (uptr int int uptr int)
     int)
    (CloseTCPListener (ListenTCP 0)))
  (with-hook "setsockopt"
    (foreign
     (lambda (socket level name val len)
       (cond
        [(= level #xFFFF)               ; SOL_SOCKET
         (SetLastError 10047)
         -1]
        [else (unhooked socket level name val len)]))
     (uptr int int uptr int)
     int)
    (assert-error-pair 'setsockopt 10047 (ListenTCP* 0)))

  ;; ListenTCP: error in socket
  (with-hook "socket"
    (foreign
     (make-last-error-proc 2 -1)
     (int int int)
     uptr)
    (assert-error-pair 'socket 2 (ListenTCP* 0)))

  ;; ListenTCP: error in bind
  (let* ([server (ListenTCP 0)]
         [test-port (GetListenerPortNumber server)])
    (assert-error-pair 'bind 10048 (ListenTCP* test-port))
    (CloseTCPListener server))

  ;; ListenTCP: error in listen
  (with-hook "listen"
    (foreign
     (make-last-error-proc 2 -1)
     (uptr int)
     int)
    (assert-error-pair 'listen 2 (ListenTCP* 0)))

  ;; ConnectTCP: error looking up hostname (slow)
  (let ([callback (lambda args (gensym))])
    (ConnectTCP "1.2.3.4.5" "80" callback)
    (assert-callback 10000 callback '(GetAddrInfoW . 11001)))
  )

(mat info (common)
  (define (drive-letter? x)
    (or (char<=? #\A x #\Z)
        (char<=? #\a x #\z)))

  (assert-error-pair 'osi::CompareStringLogical 160
    (CompareStringLogical* #f ""))
  (assert-error-pair 'osi::CompareStringLogical 160
    (CompareStringLogical* "" #f))
  (assert (= (CompareStringLogical "a100" "A100") 0))
  (assert (= (CompareStringLogical "a99" "A100") -1))
  (assert (= (CompareStringLogical "a100" "A99") 1))

  ;; GetBytesUsed success (does not fail)
  (assert (unsigned? (GetBytesUsed)))

  ;; GetMemoryInfo success
  (let ([x (GetMemoryInfo)])
    (assert (vector? x))
    (assert (= (vector-length x) 11))
    (assert (eq? (vector-ref x 0) '<memory-info>))
    (do ([i 1 (+ i 1)]) ((= i 11))
      (assert (unsigned? (vector-ref x i)))))

  ;; GetComputerName success
  (assert (string? (GetComputerName)))

  ;; GetComputerName: error in GetComputerName
  (with-hook "GetComputerNameW"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr)
     int)
    (assert-error-pair 'GetComputerNameW 2
      (GetComputerName*)))

  ;; GetDiskFreeSpace success
  (assert (unsigned? (GetDiskFreeSpace ".")))

  ;; GetDiskFreeSpace bad arguments
  (assert-error-pair 'osi::GetDiskFreeSpace 160 (GetDiskFreeSpace* #f))
  (assert-error-pair 'GetDiskFreeSpaceExW 3 (GetDiskFreeSpace* "::"))

  (for-each
   (lambda (target)
     (with-hook "GetDiskFreeSpaceExW"
       (foreign
        (lambda (path caller-free total-size total-free)
          (poke-U64! caller-free target)
          #t)
        (uptr uptr uptr uptr)
        boolean)
       (assert (= (GetDiskFreeSpace ".") target))))
   U64-values)

  ;; GetExecutablePath success
  (let ([x (GetExecutablePath)])
    (assert (string? x))
    (assert (>= (string-length x) 23))
    (assert (drive-letter? (string-ref x 0)))
    (assert (char=? (string-ref x 1) #\:))
    (assert (char=? (string-ref x 2) #\\))
    (assert (ends-with? x ".exe")))
  (with-hook "GetModuleFileNameW"
    (foreign
     (let ([first? #t])
       (lambda args
         (cond
          [first?
           (set! first? #f)
           1000000]
          [else
           (apply unhooked args)])))
     (uptr uptr unsigned-32)
     unsigned-32)
    (GetExecutablePath))

  ;; GetExecutablePath: error in GetModuleFileName
  (with-hook "GetModuleFileNameW"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr unsigned-32)
     unsigned-32)
    (assert-error-pair 'GetModuleFileNameW 2
      (GetExecutablePath*)))

  ;; GetFolderPath success
  (let ([x (GetFolderPath 5)])          ; CSIDL_PERSONAL
    (assert (string? x))
    (assert (>= (string-length x) 3))
    (assert (drive-letter? (string-ref x 0)))
    (assert (char=? (string-ref x 1) #\:))
    (assert (char=? (string-ref x 2) #\\)))

  ;; GetFolderPath failure
  (assert-error-pair 'SHGetFolderPathW 2147942487 ; E_INVALIDARG
    (GetFolderPath* -1))

  ;; GetFullPath success
  (let ([x (GetFullPath "filename")])
    (assert (string? x))
    (assert (>= (string-length x) 3))
    (assert (drive-letter? (string-ref x 0)))
    (assert (char=? (string-ref x 1) #\:))
    (assert (char=? (string-ref x 2) #\\))
    (assert (ends-with? x "\\filename")))

  ;; GetFullPath success with Allocation
  (let* ([bees (make-string 2048 #\b)]
         [x (GetFullPath bees)])
    (assert (string? x))
    (assert (>= (string-length x) 3))
    (assert (drive-letter? (string-ref x 0)))
    (assert (char=? (string-ref x 1) #\:))
    (assert (char=? (string-ref x 2) #\\))
    (assert (ends-with? x bees)))

  ;; GetFullPath error in GetFullPathName
  (with-hook "GetFullPathNameW"
    (foreign
     (make-last-error-proc 2 0)
     (uptr unsigned-32 uptr uptr)
     unsigned-32)
    (assert-error-pair 'GetFullPathNameW 2
      (GetFullPath* ".")))

  ;; GetFullPath error in GetFullPathName (second call)
  (with-hook "GetFullPathNameW"
    (foreign
     (let ([count 0])
       (lambda args
         (set! count (+ count 1))
         (case count
           [(1)
            (SetLastError 0)
            4096]
           [else
            (SetLastError 2)
            0])))
     (uptr unsigned-32 uptr uptr)
     unsigned-32)
    (assert-error-pair 'GetFullPathNameW 2
      (GetFullPath* ".")))

  ;; GetTickCount
  ;; C++ side holds the epoch
  (let ([base (with-hook "timeGetTime"
                (foreign
                 (lambda () 0)
                 ()
                 unsigned-32)
                (let ([base (GetTickCount)])
                  (assert (unsigned? base))
                  (assert (= (GetTickCount) base))
                  base))])
    (with-hook "timeGetTime"
      (foreign
       (let ([t 0])
         (lambda ()
           (set! t (modulo (+ t 99999999) #x100000000))
           t))
       ()
       unsigned-32)
      (let lp ([expected (+ base 99999999)])
        (assert (= (GetTickCount) expected))
        (when (< expected 999999990000)
          (lp (+ expected 99999999))))))

  ;; GetPerformanceFrequency success
  (for-each
   (lambda (target)
     (with-hook "QueryPerformanceFrequency"
       (foreign
        (lambda (addr)
          (poke-U64! addr target)
          #t)
        (uptr)
        boolean)
       (assert (= (GetPerformanceFrequency) target))))
   U64-values)

  ;; GetPerformanceFrequency: error in QueryPerformanceFrequency
  (with-hook "QueryPerformanceFrequency"
    (foreign
     (make-last-error-proc 2 0)
     (uptr)
     int)
    (assert-error-pair 'QueryPerformanceFrequency 2
      (GetPerformanceFrequency*)))

  ;; GetPerformanceCounter success
  (for-each
   (lambda (target)
     (with-hook "QueryPerformanceCounter"
       (foreign
        (lambda (addr)
          (poke-U64! addr target)
          #t)
        (uptr)
        boolean)
       (assert (= (GetPerformanceCounter) target))))
   U64-values)

  ;; GetPerformanceCounter: error in QueryPerformanceCounter
  (with-hook "QueryPerformanceCounter"
    (foreign
     (make-last-error-proc 2 0)
     (uptr)
     int)
    (assert-error-pair 'QueryPerformanceCounter 2
      (GetPerformanceCounter*)))

  ;; GetErrorString success
  (assert (string=? (GetErrorString 0)
            "The operation completed successfully.\r\n"))
  (assert (string=? (GetErrorString 6) "The handle is invalid.\r\n"))
  (assert (not (GetErrorString -1)))
  (do ([i 600000000 (+ i 1)])
      ((> i 600000101))
    (GetErrorString i))
  (do ([i 610065537 (+ i 1)])
      ((> i 610065568))
    (GetErrorString i))

  ;; GetErrorString: error in FormatMessage
  (with-hook "FormatMessageW"
    (foreign
     (make-last-error-proc 2 0)
     (unsigned-32 uptr unsigned-32 unsigned-32 uptr unsigned-32 uptr)
     unsigned-32)
    (assert-error-pair 'FormatMessageW 2
      (GetErrorString* 0)))

  ;; GetHandleCounts
  (let ([x (GetHandleCounts)])
    (assert (and (vector? x) (= (vector-length x) 7)
                 (eq? (vector-ref x 0) '<handle-counts>))))

  ;; GetMemoryInfo
  (let ([x (GetMemoryInfo)])
    (assert (and (vector? x) (= (vector-length x) 11)
                 (eq? (vector-ref x 0) '<memory-info>))))

  ;; CreateGUID
  (let ([x (CreateGUID)])
    (assert (and (bytevector? x) (= (bytevector-length x) 16))))

  (let ([primes #vu8(2 3 5 7 11 13 17 23 27 29 31 37 41 43 47 53)])
    (with-hook "UuidCreate"
      (foreign
       (lambda (uuid)
         (do ([i 0 (+ i 1)]) ((= i 16) 0)
           (foreign-set! 'unsigned-8 uuid i (bytevector-u8-ref primes i))))
       (uptr)
       int)
      (assert (equal? (CreateGUID) primes))))

  (with-hook "UuidCreate"
    (foreign
     (lambda (uuid) 2)
     (uptr)
     unsigned-32)
    (assert-error-pair 'UuidCreate 2
      (CreateGUID*)))

  ;; IsService
  (assert (not (IsService)))
  )

(define hash-initialized? #f)

(mat hash (common)
  (define sample (string->utf8 "The quick brown fox jumps over the lazy dog."))
  (define sample-md5
    #vu8(228 217 9 194 144 208 251 28 160 104 255 173 223 34 203 208))
  (define sample-sha1
    #vu8(64 141 148 56 66 22 248 144 255 122 12 53 40 232 190 209 224 176 22 33))
  (define sample-sha256
    #vu8(239 83 127 37 200 149 191 167 130 82 101 41 169 182 61 151 170 99 21 100 213 215 137 194 183 101 68 140 134 53 251 108))
  (define sample-sha384
    #vu8(237 137 36 129 216 39 44 166 223 55 11 247 6 228 215 188 27 87 57 250 33 119 170 230 197 14 148 102 120 113 143 198 122 122 242 129 154 2 28 47 195 78 145 189 182 52 9 215))
  (define sample-sha512
    #vu8(145 234 18 69 242 13 70 174 154 3 122 152 159 84 241 247 144 240 164 118 7 238 184 161 77 18 137 12 234 119 161 187 198 199 237 156 242 5 230 123 127 43 143 212 199 223 211 167 168 97 126 69 243 196 99 212 129 199 229 134 195 154 193 237))

  (define maxint
    (case (machine-type)
      [(a6nt) (- (expt 2 64) 1)]
      [(i3nt) (- (expt 2 32) 1)]))
  (define (get-hash-count) (vector-ref (GetHandleCounts) 6))
  (define (smoke alg expected)
    (let ([hash (OpenHash alg)])
      (assert (= (get-hash-count) 1))
      (HashData hash sample 0 10)
      (HashData hash sample 10 (- (bytevector-length sample) 10))
      (assert (equal? (GetHashValue hash) expected))
      (CloseHash hash)))
  (unless hash-initialized?
    (with-hook "CryptAcquireContextW"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr uptr unsigned-32 unsigned-32)
       int)
      (assert-error-pair 'CryptAcquireContextW 2 (OpenHash* 0)))
    (set! hash-initialized? #t))
  (assert-error-pair 'CryptCreateHash 2148073480 (OpenHash* 0))
  (let ([hash (OpenHash ALG_MD5)])
    (assert (= (get-hash-count) 1))
    (assert-error-pair 'osi::HashData 6 (HashData* 0 sample 0 1))
    (assert-error-pair 'osi::HashData 160 (HashData* hash #f 0 1))
    (assert-error-pair 'osi::HashData 160 (HashData* hash sample maxint 1))
    (assert-error-pair 'osi::HashData 160
      (HashData* hash sample (bytevector-length sample) 1))
    (HashData hash sample 0 (bytevector-length sample))
    (assert-error-pair 'osi::GetHashValue 6 (GetHashValue* 0))
    (assert (equal? (GetHashValue hash) sample-md5))
    (assert-error-pair 'CryptHashData 2148073484 (HashData* hash sample 0 1))
    (with-hook "CryptGetHashParam"
      (foreign
       (let ([n 0])
         (lambda args
           (set! n (+ n 1))
           (case n
             [(1) (SetLastError 1) 0]
             [(3) (SetLastError 3) 0]
             [else (apply unhooked args)])))
       (uptr unsigned-32 uptr uptr unsigned-32)
       int)
      (assert-error-pair 'CryptGetHashParam 1 (GetHashValue* hash))
      (assert-error-pair 'CryptGetHashParam 3 (GetHashValue* hash)))
    (assert-error-pair 'osi::CloseHash 6 (CloseHash* 0))
    (CloseHash hash))
  (smoke ALG_SHA1 sample-sha1)
  (smoke ALG_SHA_256 sample-sha256)
  (smoke ALG_SHA_384 sample-sha384)
  (smoke ALG_SHA_512 sample-sha512)
  (assert (= (get-hash-count) 0))
  )

;; WinUSB tests with an ACE controller

(define ace-guid (string->guid "271fdf77-0390-4855-a27e-d4f0c70266b4"))

(mat ace (common)
  (define ace-name
    (let ([x (GetDeviceNames ace-guid)])
      (and (pair? x) (car x))))

  ;; GetDeviceNames: bad GUID
  (assert-error-pair 'osi::GetDeviceNames 160 (GetDeviceNames* "ACE"))
  (assert-error-pair 'osi::GetDeviceNames 160
    (GetDeviceNames* (make-bytevector 156)))

  ;; GetDeviceNames: SetupDiGetClassDevsW fails
  (with-hook "SetupDiGetClassDevsW"
    (foreign
     (make-last-error-proc 2 -1)
     (uptr uptr uptr unsigned-32)
     int)
    (assert-error-pair 'SetupDiGetClassDevsW 2
      (GetDeviceNames* ace-guid)))

  ;; GetDeviceNames: SetupDiEnumDeviceInterfaces fails
  (with-hook "SetupDiEnumDeviceInterfaces"
    (foreign
     (make-last-error-proc 2 0)
     (uptr uptr uptr unsigned-32 uptr)
     int)
    (assert-error-pair 'SetupDiEnumDeviceInterfaces 2
      (GetDeviceNames* ace-guid)))

  ;; ConnectWinUSB: bad device name
  (assert-error-pair 'osi::ConnectWinUSB 160 (ConnectWinUSB* #f #x84 #x02))

  ;; ConnectWinUSB: error in CreateFile
  (assert-error-pair 'CreateFileW 123 (ConnectWinUSB* "*" #x84 #x02))

  (when ace-name
    ;; GetDeviceNames: SetupDiGetDeviceInterfaceDetailW fails
    (with-hook "SetupDiGetDeviceInterfaceDetailW"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr uptr unsigned-32 uptr uptr)
       int)
      (assert-error-pair 'SetupDiGetDeviceInterfaceDetailW 2
        (GetDeviceNames* ace-guid)))

    ;; GetDeviceNames: SetupDiGetDeviceInterfaceDetailW needs more buffer
    (with-hook "SetupDiGetDeviceInterfaceDetailW"
      (foreign
       (lambda (infoset interface detail size required info)
         (cond
          [(eqv? required 0)
           (unhooked infoset interface detail size required info)]
          [else
           (foreign-set! 'unsigned-32 required 0 1025)
           (SetLastError 122)
           0]))
       (uptr uptr uptr unsigned-32 uptr uptr)
       int)
      (assert (= (length (GetDeviceNames ace-guid)) 1)))

    ;; GetDeviceNames: SetupDiGetDeviceInterfaceDetailW needs more buffer and then fails
    (with-hook "SetupDiGetDeviceInterfaceDetailW"
      (foreign
       (lambda (infoset interface detail size required info)
         (cond
          [(eqv? required 0)
           (SetLastError 2)
           0]
          [else
           (foreign-set! 'unsigned-32 required 0 1025)
           (SetLastError 122)
           0]))
       (uptr uptr uptr unsigned-32 uptr uptr)
       int)
      (assert-error-pair 'SetupDiGetDeviceInterfaceDetailW 2
        (GetDeviceNames* ace-guid)))

    ;; ConnectWinUSB success
    (let ([p (ConnectWinUSB ace-name #x81 #x02)])
      (assert-error-pair 'osi::GetFileSize 6 (GetFileSize* p))
      (assert-error-pair 'osi::GetIPAddress 6 (GetIPAddress* p))
      (let* ([bv #vu8(5 6 7 8 9 10)]
             [len (bytevector-length bv)]
             [callback (lambda args p)])
        (assert-error-pair 'osi::WritePort 160
          (WritePort* p bv 0 len 0 callback))
        (WritePort p bv 0 len #f callback)
        (assert-callback 1000 callback len 0))
      (let* ([bv (make-bytevector 64)]
             [len (bytevector-length bv)]
             [callback (lambda args p)])
        (assert-error-pair 'osi::ReadPort 160
          (ReadPort* p bv 0 len 0 callback))
        (ReadPort p bv 0 len #f callback)
        ;; make sure we read back *something*
        (let ([x (GetCompletionPacket 1000)])
          (assert x)
          (assert (pair? x))
          (assert (eq? (car x) callback))
          (assert (> (cadr x) 0))
          (assert (= (caddr x) 0))))
      (ClosePort p))

    ;; ConnectWinUSB: WinUsb_ReadPipe and WinUsb_WritePipe succeed
    (let ([p (ConnectWinUSB ace-name #x81 #x02)])
      (let* ([bv #vu8(5 1 2 3 4)]
             [len (bytevector-length bv)]
             [callback (lambda args p)])
        (with-hook "WinUsb_WritePipe"
          (foreign
           (lambda args (apply unhooked args) 1)
           (uptr char uptr unsigned-32 uptr uptr)
           int)
          (WritePort p bv 0 len #f callback))
        (assert-callback 1000 callback len 0))
      (let* ([bv (make-bytevector 64)]
             [len (bytevector-length bv)]
             [callback (lambda args p)])
        (with-hook "WinUsb_ReadPipe"
          (foreign
           (lambda args (apply unhooked args) 1)
           (uptr char uptr unsigned-32 uptr uptr)
           int)
          (ReadPort p bv 0 len #f callback))
        ;; make sure we read back *something*
        (let ([x (GetCompletionPacket 1000)])
          (assert x)
          (assert (pair? x))
          (assert (eq? (car x) callback))
          (assert (> (cadr x) 0))
          (assert (= (caddr x) 0))))
      (ClosePort p))

    ;; ConnectWinUSB: error in CreateIoCompletionPort
    (with-hook "CreateIoCompletionPort"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr uptr unsigned-32)
       uptr)
      (assert-error-pair 'CreateIoCompletionPort 2
        (ConnectWinUSB* ace-name #x84 #x02)))

    ;; ConnectWinUSB: error in WinUsb_Initialize
    (with-hook "WinUsb_Initialize"
      (foreign
       (make-last-error-proc 2 0)
       (uptr uptr)
       int)
      (assert-error-pair 'WinUsb_Initialize 2
        (ConnectWinUSB* ace-name #x81 #x02)))

    ;; WritePort, ReadPort: error in WinUsb_WritePipe, WinUsb_ReadPipe
    (let ([p (ConnectWinUSB ace-name #x81 #x02)]
          [bv (bytevector 1)])
      (with-hook "WinUsb_WritePipe"
        (foreign
         (make-last-error-proc 2 0)
         (uptr char uptr unsigned-32 uptr uptr)
         int)
        (assert-error-pair 'WinUsb_WritePipe 2
          (WritePort* p bv 0 1 #f void)))
      (with-hook "WinUsb_ReadPipe"
        (foreign
         (make-last-error-proc 2 0)
         (uptr char uptr unsigned-32 uptr uptr)
         int)
        (assert-error-pair 'WinUsb_ReadPipe 2
          (ReadPort* p bv 0 1 #f void)))
      (ClosePort p)))
  )
