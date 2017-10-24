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
 (swish erlang)
 (swish mat)
 (swish osi)
 (swish io)
 (swish testing)
 (except (chezscheme) define-record exit sleep)
 )
(define (make-byte-stream prime)
  (let ([next 0])
    (lambda ()
      (set! next (modulo (+ next prime) 256))
      next)))

(define (build-buffer size stream)
  (let ([bv (make-bytevector size)])
    (do ([i 0 (+ i 1)]) ((= i size))
      (bytevector-u8-set! bv i (stream)))
    bv))

(define (start-watchdog timeout reason)
  (spawn&link
   (lambda ()
     (receive (after timeout (exit reason))))))

(define (stop-watchdog x) (unlink x))

(define (get-bv ip len)
  (let* ([me self]
         [reader (spawn&link
                  (lambda ()
                    (let ([x (get-bytevector-n ip len)])
                      (send me `#(read ,self ,x)))))])
    (receive [#(read ,@reader ,x) x])))

(define (writer op)
  (receive
   [flush
    (flush-output-port op)
    (writer op)]
   [#(put-bv ,data ,flush?)
    (put-bytevector op data)
    (when flush? (flush-output-port op))
    (writer op)]))

(define (put-bv who data flush?)
  (send who `#(put-bv ,data ,flush?)))

(define (send/expect ip op data timeout)
  (let ([dog (start-watchdog timeout
               `#(send/expect-timeout ,timeout ,(bytevector-length data)))])
    (on-exit (stop-watchdog dog)
      (let ([w (spawn&link (lambda () (writer op)))])
        (put-bv w data #t)
        (let ([new (get-bv ip (bytevector-length data))])
          (assert (equal? new data)))))))

(define primes '(7 11 13 239 241 251))
(define buffer-sizes '(1 127 256 1024 2048 4096 8192))

(define (check-loopback ip op)
  (for-each
   (lambda (prime)
     (for-each
      (lambda (size)
        (send/expect ip op (build-buffer size (make-byte-stream prime)) 4000))
      buffer-sizes))
   primes))

(define (make-char-stream prime)
  (let ([next 0])
    (lambda ()
      (let lp ([n next])
        (let ([candidate (modulo (+ n prime) #x110000)])
          (if (or (<= candidate #xD7FF) (<= #xE000 candidate))
              (set! next candidate)
              (lp candidate))))
      (integer->char next))))

(define (gc)
  (collect (collect-maximum-generation))
  (receive (after 10 'ok)))

(define (delete-tree path)
  (if (file-directory? path)
      (or (delete-directory path)
          (begin
            (for-each (lambda (p) (delete-tree (path-combine path p)))
              (find-files (path-combine path "*")))
            (receive (after 10 'ok))
            (delete-directory path)))
      (delete-file path)))

(isolate-mat pipes ()
  (define pid self)
  (define pipe-name (gensym->unique-string (gensym)))
  (define-values (sip sop)
    (create-server-pipe pipe-name
      (lambda (count errno)
        (send pid `#(pipe-connected ,errno)))))
  (on-exit (force-close-output-port sop)
    (define-values (cip cop) (create-client-pipe pipe-name))
    (on-exit (force-close-output-port cop)
      (receive (after 5000 (exit 'timeout-starting-pipes))
        [#(pipe-connected ,errno)
         (unless (eqv? errno 0)
           (exit `#(pipe-connect-failure ,errno)))])
      (check-loopback sip cop)
      (check-loopback cip sop))))

(isolate-mat force-close ()
  (define pid self)
  (define pipe-name (gensym->unique-string (gensym)))
  (define-values (sip sop)
    (create-server-pipe pipe-name
      (lambda (count errno)
        (send pid `#(pipe-connected ,errno)))))
  (put-u8 sop 3)
  (force-close-output-port sop)
  (receive (after 1000 (exit 'timeout-closing-pipe))
    [#(pipe-connected ,errno)
     (when (eqv? errno 0) (exit `pipe-connected))])
  (match-let*
   ([#(EXIT #(io-error ,_ ReadPort 6)) (catch (get-u8 sip))]
    [#(EXIT boom)
     (catch
      (force-close-output-port
       (make-custom-binary-output-port "boom"
         (lambda (bytevector start n) 'ok) #f #f
         (lambda () (exit 'boom)))))])
   'ok))

(isolate-mat tcp ()
  (define pid self)
  (define (run hostname)
    (let* ([listener (listen-tcp 0)]
           [test-port (listener-port-number listener)])
      (on-exit (close-tcp-listener listener)
        (spawn&link
         (lambda ()
           (define-values (sip sop)
             (accept-tcp listener))
           (send pid `#(connected ,sip ,sop))))
        (let-values ([(cip cop) (connect-tcp hostname test-port)])
          (receive (after 5000 (exit 'timeout-connecting-tcp))
            [#(connected ,sip ,sop)
             (on-exit (force-close-output-port sop)
               (check-loopback sip cop)
               (check-loopback cip sop))])))))
  (run "127.0.0.1")
  (run "::1")
  ;; Test the listener guardian
  (let ([test-port (listener-port-number (listen-tcp 0))])
    (gc)
    (close-tcp-listener (listen-tcp test-port))))

(isolate-mat tcp-bad ()
  (define pid self)
  (define (run hostname)
    (match-let*
     ([#(EXIT #(bad-arg accept-tcp #f)) (catch (accept-tcp #f))]
      [#(EXIT #(bad-arg close-tcp-listener #f)) (catch (close-tcp-listener #f))]
      [#(EXIT #(bad-arg connect-tcp #f)) (catch (connect-tcp #f 0))]
      [#(EXIT #(bad-arg connect-tcp #f)) (catch (connect-tcp "" #f))]
      [#(EXIT #(bad-arg connect-tcp #f)) (catch (connect-tcp "" 0 #f))]
      [#(EXIT #(connect-tcp-failed "" "*nope*" GetAddrInfoW 10109))
       (catch (connect-tcp "" "*nope*"))]
      [#(EXIT #(bad-arg listen-tcp #f)) (catch (listen-tcp #f))])
     'ok)
    (let* ([listener (listen-tcp 0)]
           [test-port (listener-port-number listener)])
      (match (catch (accept-tcp listener #f))
        [#(EXIT #(bad-arg accept-tcp #f)) 'ok])
      (on-exit (close-tcp-listener listener)
        (match (catch (listen-tcp test-port))
          [#(EXIT #(listen-tcp-failed ,@test-port bind 10048)) 'ok])
        (spawn&link
         (lambda ()
           (send pid
             `#(callback
                ,(catch
                  (let-values ([(sip sop) (accept-tcp listener)])
                    (list sip sop)))))))
        (receive (after 10 (close-tcp-listener listener)))
        (match (catch (accept-tcp listener))
          [#(EXIT #(bad-arg accept-tcp ,@listener)) 'ok])
        (match (catch (connect-tcp hostname test-port))
          [#(EXIT #(connect-tcp-failed ,@hostname ,@test-port connect 10061))
           'ok])
        (receive (after 1000 (exit 'timeout-accept))
          [#(callback #(EXIT #(accept-tcp-failed ,@test-port accept 10004)))
           'ok]
          [#(callback ,x) (exit `#(accept-tcp-failed ,x))]))))
  (run "127.0.0.1")
  (run "::1"))

(isolate-mat pipes-bad ()
  (define name "no-pipe-here")
  (define full (string-append "\\\\.\\pipe\\" name))
  (match-let*
   ([#(EXIT #(io-error ,@full osi::CreateServerPipe 160))
     (catch (create-server-pipe name 12))]
    [#(EXIT #(io-error ,@full CreateFileW 2))
     (catch (create-client-pipe name))])
   'ok))

(isolate-mat process-bad ()
  (match-let*
   ([#(EXIT #(create-watched-process-failed "*!*" CreateProcessW 2))
     (catch (create-watched-process "*!*" (lambda (os-id exit-code) 'ok)))])
   'ok))

(isolate-mat path ()
  (match-let*
   (["q:\\b" (absolute-path "q:\\b" "q:\\a")]
    ["q:\\a\\c" (absolute-path "b\\..\\c" "q:\\a")]
    ["a" (path-combine "a")]
    ["a" (path-combine "" "a")]
    ["a\\b" (path-combine "a" "b")]
    ["a\\b\\c" (path-combine "a" "b" "c")]
    ["a\\b\\c" (path-combine "a" "b\\" "c")]
    ["a\\b/c" (path-combine "a" "b/" "c")]
    [,fn (create-directory-path
          (path-combine (gensym->unique-string (gensym))
            "deep\\test\\foo.txt"))])
   (do ([n 3 (- n 1)] [dir (path-parent fn) (path-parent dir)])
       ((= n 0))
     (RemoveDirectory dir)
     (receive (after 10 'ok)))
   'ok))

(isolate-mat files ()
  (define (make-buffers)
    (fold-left
     (lambda (acc prime)
       (fold-left
        (lambda (acc size)
          (cons (build-buffer size (make-byte-stream prime)) acc))
        acc
        primes))
     '()
     buffer-sizes))
  (define (watch-callback ls)
    (receive (after 1000 (exit 'watch-callback-timeout))
      [#(watch ,x)
       (when (fixnum? x)
         (exit `#(watch-callback-unexpected ,x)))
       (let lp ([actual x] [expected ls])
         (cond
          [(null? actual)
           (if (null? expected)
               'ok
               (watch-callback expected))]
          [(= (caar actual) 3) ; skip file modified
           (lp (cdr actual) expected)]
          [(and (pair? expected) (equal? (car actual) (car expected)))
           (lp (cdr actual) (cdr expected))]
          [else
           (exit `#(watch-unexpected ,actual ,expected))]))]))

  (define bullet "\x2022;")
  (define test-dir (string-append bullet "files-test" bullet "/"))
  (match-let*
   ([#(EXIT #(bad-arg create-file bad-type))
     (catch (create-file "foo.bar" 0 0 0 'bad-type))]
    [#(EXIT #(bad-arg move-file 1)) (catch (move-file 1 2 3))]
    [#(EXIT #(bad-arg move-file 2)) (catch (move-file "foo" 2 3))]
    [#(EXIT #(bad-arg move-file 3)) (catch (move-file "foo" "bar" 3))]
    [#(EXIT #(bad-arg close-directory-watcher #f))
     (catch (close-directory-watcher #f))])
   'ok)
  (delete-tree test-dir)
  (create-directory-path test-dir)
  (on-exit (delete-tree test-dir)
    (let ([watcher (watch-directory test-dir #t
                     (let ([me self]) (lambda (x) (send me `#(watch ,x)))))]
          [fn (path-combine test-dir "basic")]
          [fn2 (path-combine test-dir "moved")])
      (define (write-file fn)
        (let ([op (create-file fn
                    GENERIC_WRITE FILE_SHARE_READ CREATE_ALWAYS
                    'binary-output)])
          (on-exit (force-close-output-port op)
            (put-bytevector op (build-buffer 4096 (make-byte-stream 7)))
            (assert (= (file-position op) 4096))
            (file-position op 0)
            (assert (= (file-position op) 0))
            (put-bytevector op (build-buffer 4096 (make-byte-stream 7))))))
      (write-file fn)
      (watch-callback `((1 . "basic")))
      (move-file fn fn2)
      (assert (not (file-exists? fn)))
      (assert (file-exists? fn2))
      (watch-callback `((4 . "basic") (5 . "moved")))
      (write-file fn)
      (watch-callback `((1 . "basic")))
      (match (catch (move-file fn fn2))
        [#(EXIT #(osi-error MoveFile MoveFileExW 183)) 'ok])
      (assert (file-exists? fn))
      (assert (file-exists? fn2))
      (move-file fn fn2 'replace)
      (assert (not (file-exists? fn)))
      (assert (file-exists? fn2))
      (watch-callback `((2 . "basic")))
      (DeleteFile fn2)
      (watch-callback `((2 . "moved")))
      (close-directory-watcher watcher)
      (receive (after 1000 (exit 'watch-callback-timeout))
        [#(watch 0) 'ok]
        [#(watch ,x) (exit `#(watch-unexpected ,x 0))]))

    (let* ([buffers (make-buffers)]
           [filenames (map (lambda (bv) (guid->string (CreateGUID))) buffers)])
      (for-each
       (lambda (data fn)
         (let ([op (create-file (path-combine test-dir fn)
                     GENERIC_WRITE FILE_SHARE_READ CREATE_ALWAYS
                     'binary-output)])
           (on-exit (force-close-output-port op)
             (put-bytevector op data))))
       buffers filenames)
      (for-each
       (lambda (data fn)
         (let ([ip (create-file (path-combine test-dir fn)
                     GENERIC_READ FILE_SHARE_READ OPEN_EXISTING
                     'binary-input)])
           (on-exit (close-input-port ip)
             (let ([new (get-bytevector-all ip)])
               (assert (equal? new data))))))
       buffers filenames)
      ;; Look for files on disk, if they are one of ours, delete
      ;; it. This will clear out the directory for cleanup.
      (assert
       (null?
        (fold-left
         (lambda (filenames file)
           (cond
            [(find (lambda (x) (string=? x file)) filenames)
             (DeleteFile (path-combine test-dir file))
             (remove file filenames)]
            [else filenames]))
         filenames
         (find-files (string-append test-dir "*"))))))
    ;; Test the osi-port guardian
    (let ([fn (path-combine test-dir "guardian")])
      (create-file-port fn GENERIC_WRITE 0 CREATE_ALWAYS)
      (gc)
      (assert (delete-file fn)))
    ;; Test the directory-watcher guardian
    (let ([id (gensym)])
      (watch-directory test-dir #t
        (let ([me self]) (lambda (x) (send me `#(watch ,id ,x)))))
      (gc)
      (receive (after 100 (exit 'watcher-gc-timeout))
        [#(watch ,@id 0) 'ok]))))

(isolate-mat files-bad ()
  (match-let*
   ([#(EXIT #(find-files-failed "" FindFirstFileW 3)) (catch (find-files ""))]
    [#(EXIT #(find-files-failed #f osi::FindFiles 160))
     (catch (find-files #f))]
    [#(EXIT #(watch-directory-failed #f osi::WatchDirectory 160))
     (catch (watch-directory #f #f #f))])
   'ok))

(isolate-mat read ()
  (read-bytevector "swish/io.ms" (read-file "swish/io.ms")))

(isolate-mat unicode ()
  (define fn (gensym->unique-string (gensym)))
  (define prime 32783)
  (match (catch (open-file-to-read fn))
    [#(EXIT #(io-error ,@fn CreateFileW 2)) 'ok])
  (let ([stream (make-char-stream prime)])
    (let ([op (open-file-to-write fn)])
      (on-exit (force-close-output-port op)
        (do ([n #x88000 (- n 1)]) ((= n 0))
          (write-char (stream) op))))
    (match (catch (open-file-to-write fn))
      [#(EXIT #(io-error ,@fn CreateFileW 80)) 'ok])
    (let ([op (open-file-to-append fn)])
      (on-exit (force-close-output-port op)
        (do ([n #x88000 (- n 1)]) ((= n 0))
          (write-char (stream) op)))))
  (let ([stream (make-char-stream prime)]
        [ip (open-file-to-read fn)])
    (on-exit (close-input-port ip)
      (do ([n #x110000 (- n 1)]) ((= n 0))
        (unless (eqv? (read-char ip) (stream))
          (exit 'wrong-char)))))
  (let ([op (open-file-to-replace fn)])
    (on-exit (force-close-output-port op)
      (display "nothing here" op)))
  (let ([ip (create-file fn GENERIC_READ FILE_SHARE_READ OPEN_EXISTING
              'binary-input)])
    (on-exit (close-input-port ip)
      (match (get-string-all (open-utf8-bytevector (get-bytevector-all ip)))
        ["nothing here" 'ok])))
  (DeleteFile fn))

(hook-console-input)
