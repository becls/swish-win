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
(library (swish io)
  (export
   CREATE_ALWAYS
   CREATE_NEW
   FILE_SHARE_DELETE
   FILE_SHARE_NONE
   FILE_SHARE_READ
   FILE_SHARE_WRITE
   GENERIC_READ
   GENERIC_WRITE
   OPEN_ALWAYS
   OPEN_EXISTING
   TRUNCATE_EXISTING
   absolute-path
   accept-tcp
   binary->utf8
   close-directory-watcher
   close-osi-port
   close-tcp-listener
   connect-tcp
   connect-usb
   create-client-pipe
   create-directory-path
   create-file
   create-file-port
   create-server-pipe
   create-watched-process
   directory-watcher-path
   find-files
   force-close-output-port
   get-file-size
   hook-console-input
   io-error
   listen-tcp
   listener-port-number
   make-utf8-transcoder
   move-file
   open-file-to-append
   open-file-to-read
   open-file-to-replace
   open-file-to-write
   open-utf8-bytevector
   path-combine
   read-bytevector
   read-file
   read-osi-port
   watch-directory
   write-osi-port
   )
  (import
   (swish erlang)
   (swish osi)
   (except (chezscheme) define-record exit))

  ;; Procedures starting with @ must be called with interrupts disabled.

  (define-record-type osi-port
    (nongenerative)
    (fields
     (immutable name)
     (mutable handle)))

  (define (read-osi-port port bv start n fp)
    (let-values ([(count errno)
                  (sync-io ReadPort* (osi-port-handle port) bv start n fp)])
      (case errno
        [(0) count]
        [(38 109 995 10053)
         ;; 38 = Reached the end of file.
         ;; 109 = The pipe has been ended.
         ;; 995 = The I/O operation has been aborted because of either a
         ;;       thread exit or an application request.
         ;; 10053 = An established connection was aborted by the
         ;;         software in your host machine.
         0]
        [else (io-error (osi-port-name port) 'ReadPort errno)])))

  (define (write-osi-port port bv start n fp)
    (let-values ([(count errno)
                  (sync-io WritePort* (osi-port-handle port) bv start n fp)])
      (if (eqv? errno 0)
          count
          (io-error (osi-port-name port) 'WritePort errno))))

  (define (close-osi-port port)
    (with-interrupts-disabled
     (let ([handle (osi-port-handle port)])
       (when handle
         (match (ClosePort* handle)
           [#t (osi-port-handle-set! port #f)]
           [(,who . ,errno) (io-error (osi-port-name port) who errno)])))))

  (define (get-file-size port)
    (match (GetFileSize* (osi-port-handle port))
      [(,who . ,errno) (io-error (osi-port-name port) who errno)]
      [,size size]))

  (define osi-port-guardian (make-guardian))

  (define (@make-osi-port name handle)
    (let ([port (make-osi-port name handle)])
      (osi-port-guardian port)
      port))

  (define (close-dead-osi-ports)
    ;; This procedure runs in the finalizer process.
    (let ([port (osi-port-guardian)])
      (when port
        (close-osi-port port)
        (close-dead-osi-ports))))

  (define (force-close-output-port op)
    (unless (port-closed? op)
      (match (catch (close-output-port op))
        [#(EXIT #(io-error ,_ WritePort ,_))
         (clear-output-port op)
         (close-output-port op)]
        [#(EXIT ,reason) (exit reason)]
        [,_ (void)])))

  (define (io-error name who errno)
    (exit `#(io-error ,name ,who ,errno)))

  (define (sync-io operation handle bv start n fp)
    (if handle
        (match (operation handle bv start n fp
                 (let ([pid self])
                   (lambda (count error)
                     ;; This procedure runs in the event loop.
                     (send pid `#(sync-io ,count ,error)))))
          [#t (receive [#(sync-io ,count ,errno) (values count errno)])]
          [(,_ . ,errno) (values 0 errno)])
        ;; 6 = The handle is invalid.
        (values 0 6)))

  (define (make-r! port)
    (lambda (bv start n)
      (read-osi-port port bv start n #f)))

  (define (make-w! port)
    (lambda (bv start n)
      (write-osi-port port bv start n #f)))

  (define (make-close port)
    (lambda ()
      (close-osi-port port)))

  (define (make-utf8-transcoder)
    (make-transcoder (utf-8-codec)
      (eol-style none)
      (error-handling-mode raise)))

  (define (binary->utf8 bp)
    (transcoded-port bp (make-utf8-transcoder)))

  (define (make-iport name port close?)
    (make-custom-binary-input-port name (make-r! port) #f #f
      (and close? (make-close port))))

  (define (make-oport name port)
    (make-custom-binary-output-port name (make-w! port) #f #f
      (make-close port)))

  ;; USB Ports

  (define (connect-usb-port name in out)
    (with-interrupts-disabled
     (match (ConnectWinUSB* name in out)
       [(,who . ,errno) (io-error name who errno)]
       [,handle (@make-osi-port name handle)])))

  (define (connect-usb name in out)
    (let ([port (connect-usb-port name in out)])
      (values (make-iport name port #f) (make-oport name port))))

  ;; Pipe Ports

  (define (full-pipe-name name)
    (string-append "\\\\.\\pipe\\" name))

  (define (create-server-pipe-port name callback)
    (with-interrupts-disabled
     (match (CreateServerPipe* name callback)
       [(,who . ,errno) (io-error name who errno)]
       [,handle (@make-osi-port name handle)])))

  (define (create-server-pipe name callback)
    (let* ([name (full-pipe-name name)]
           [port (create-server-pipe-port name callback)])
      (values (make-iport name port #f) (make-oport name port))))

  (define (create-client-pipe-port name)
    (with-interrupts-disabled
     (match (CreateClientPipe* name)
       [(,who . ,errno) (io-error name who errno)]
       [,handle (@make-osi-port name handle)])))

  (define (create-client-pipe name)
    (let* ([name (full-pipe-name name)]
           [port (create-client-pipe-port name)])
      (values (make-iport name port #f) (make-oport name port))))

  ;; Process Ports

  (define (create-watched-process command-line callback)
    (with-interrupts-disabled
     (match (CreateWatchedProcess* command-line callback)
       [#(<process> ,process ,ihandle ,ohandle)
        (let ([name (format "process:~d" process)])
          (values process
            (make-iport name (@make-osi-port name ihandle) #t)
            (make-oport name (@make-osi-port name ohandle))))]
       [(,who . ,errno)
        (exit `#(create-watched-process-failed ,command-line ,who ,errno))])))

  ;; File Ports

  (define-syntax GENERIC_WRITE (identifier-syntax #x40000000))
  (define-syntax GENERIC_READ (identifier-syntax #x80000000))
  (define-syntax FILE_SHARE_NONE (identifier-syntax 0))
  (define-syntax FILE_SHARE_READ (identifier-syntax 1))
  (define-syntax FILE_SHARE_WRITE (identifier-syntax 2))
  (define-syntax FILE_SHARE_DELETE (identifier-syntax 4))
  (define-syntax CREATE_NEW (identifier-syntax 1))
  (define-syntax CREATE_ALWAYS (identifier-syntax 2))
  (define-syntax OPEN_EXISTING (identifier-syntax 3))
  (define-syntax OPEN_ALWAYS (identifier-syntax 4))
  (define-syntax TRUNCATE_EXISTING (identifier-syntax 5))

  (define (create-file-port name desired-access share-mode creation-disposition)
    (with-interrupts-disabled
     (match (CreateFile* name desired-access share-mode creation-disposition)
       [(,who . ,errno) (io-error name who errno)]
       [,handle (@make-osi-port name handle)])))

  (define (create-file name desired-access share-mode creation-disposition type)
    (unless (memq type '(binary-input binary-output input output append))
      (bad-arg 'create-file type))
    (let ([port (create-file-port name desired-access share-mode
                  creation-disposition)])
      (define fp 0)
      (define (r! bv start n)
        (let ([x (read-osi-port port bv start n fp)])
          (unless (eof-object? x)
            (set! fp (+ fp x)))
          x))
      (define (w! bv start n)
        (let ([count (write-osi-port port bv start n fp)])
          (set! fp (+ fp count))
          count))
      (define (gp) fp)
      (define (sp! pos) (set! fp pos))
      (when (eq? type 'append)
        (sp! (get-file-size port)))
      (case type
        [(binary-input)
         (make-custom-binary-input-port name r! gp sp! (make-close port))]
        [(binary-output)
         (make-custom-binary-output-port name w! gp sp! (make-close port))]
        [(input)
         (binary->utf8
          (make-custom-binary-input-port name r! gp sp! (make-close port)))]
        [(output append)
         (binary->utf8
          (make-custom-binary-output-port name w! gp sp! (make-close port)))])))

  (define (open-file-to-read name)
    (create-file name GENERIC_READ FILE_SHARE_READ OPEN_EXISTING 'input))

  (define (open-file-to-write name)
    (create-file name GENERIC_WRITE FILE_SHARE_READ CREATE_NEW 'output))

  (define (open-file-to-append name)
    (create-file name GENERIC_WRITE FILE_SHARE_READ OPEN_ALWAYS 'append))

  (define (open-file-to-replace name)
    (create-file name GENERIC_WRITE FILE_SHARE_READ CREATE_ALWAYS 'output))

  (define (open-utf8-bytevector bv)
    (binary->utf8 (open-bytevector-input-port bv)))

  (define (read-bytevector name contents)
    (let* ([ip (open-bytevector-input-port contents)]
           [sfd (make-source-file-descriptor name ip #t)]
           [ip (transcoded-port ip (make-utf8-transcoder))])
      (let f ([offset 0])
        (let-values ([(x offset) (get-datum/annotations ip sfd offset)])
          (if (eof-object? x)
              '()
              (cons x (f offset)))))))

  (define (read-file name)
    (let ([port
           (create-file-port name GENERIC_READ FILE_SHARE_READ OPEN_EXISTING)])
      (on-exit (close-osi-port port)
        (let ([n (get-file-size port)])
          (if (> n 0)
              (let* ([bv (make-bytevector n)]
                     [count (read-osi-port port bv 0 n 0)])
                (unless (eqv? count n)
                  (exit `#(unexpected-eof ,name)))
                bv)
              #vu8())))))

  (define (absolute-path path root)
    (GetFullPath
     (if (path-absolute? path)
         path
         (path-combine root path))))

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

  (define (create-directory-path path)
    (let loop ([path (GetFullPath path)])
      (let ([dir (path-parent path)])
        (unless (or (string=? dir path) (string=? dir ""))
          (match (CreateDirectory* dir)
            [(CreateDirectoryW . 3)
             (loop dir)
             (CreateDirectory* dir)]
            [,_ (void)]))))
    path)

  (define (find-files spec)
    (match (FindFiles* spec
             (let ([pid self])
               (lambda (x) ;; This procedure runs in the event loop.
                 (send pid (cons 'find-files x)))))
      [#t
       (receive
        [(find-files ,who . ,errno)
         (guard (symbol? who))
         (exit `#(find-files-failed ,spec ,who ,errno))]
        [(find-files . ,ls) ls])]
      [(,who . ,errno) (exit `#(find-files-failed ,spec ,who ,errno))]))

  (define move-file
    (case-lambda
     [(old new) (move-file old new 'error)]
     [(old new option)
      (unless (string? old) (bad-arg 'move-file old))
      (unless (string? new) (bad-arg 'move-file new))
      (MoveFile old new
        (case option
          [error 0]
          [replace 1]
          [else (bad-arg 'move-file option)]))]))

  ;; Directory watching

  (define-record-type directory-watcher
    (nongenerative)
    (fields
     (mutable handle)
     (immutable path)))

  (define directory-watcher-guardian (make-guardian))

  (define (close-dead-directory-watchers)
    ;; This procedure runs in the finalizer process.
    (let ([w (directory-watcher-guardian)])
      (when w
        (close-directory-watcher w)
        (close-dead-directory-watchers))))

  (define (close-directory-watcher watcher)
    (unless (directory-watcher? watcher)
      (bad-arg 'close-directory-watcher watcher))
    (with-interrupts-disabled
     (let ([handle (directory-watcher-handle watcher)])
       (when handle
         (CloseDirectoryWatcher handle)
         (directory-watcher-handle-set! watcher #f)))))

  (define (watch-directory path subtree? callback)
    (with-interrupts-disabled
     (match (WatchDirectory* path subtree? callback)
       [(,who . ,errno) (exit `#(watch-directory-failed ,path ,who ,errno))]
       [,handle
        (let ([w (make-directory-watcher handle path)])
          (directory-watcher-guardian w)
          w)])))

  ;; Console Ports

  (define hook-console-input
    (let ([hooked? #f]
          [name "console input"])
      (lambda ()
        (unless hooked?
          (with-interrupts-disabled
           (let ([ip (binary->utf8
                      (make-iport name (@make-osi-port name (OpenConsole)) #t))])
             ;; Chez Scheme 9.5 uses $console-input-port to do smart
             ;; flushing of console I/O.
             (set! hooked? #t)
             (#%$set-top-level-value! '$console-input-port ip)
             (console-input-port ip)
             (current-input-port ip)))))))

  ;; TCP/IP Ports

  (define-record-type listener
    (nongenerative)
    (fields
     (mutable handle)
     (immutable port-number)))

  (define listener-guardian (make-guardian))

  (define (port-number? x) (and (fixnum? x) (fx<= 0 x 65535)))

  (define (close-dead-listeners)
    ;; This procedure runs in the finalizer process.
    (let ([l (listener-guardian)])
      (when l
        (close-tcp-listener l)
        (close-dead-listeners))))

  (define (listen-tcp port-number)
    (unless (port-number? port-number)
      (bad-arg 'listen-tcp port-number))
    (with-interrupts-disabled
     (match (ListenTCP* port-number)
       [(,who . ,errno) (exit `#(listen-tcp-failed ,port-number ,who ,errno))]
       [,handle
        (let ([l (make-listener handle
                   (let ([n (GetListenerPortNumber* handle)])
                     (if (fixnum? n)
                         n
                         port-number)))])
          (listener-guardian l)
          l)])))

  (define (close-tcp-listener listener)
    ;; This procedure may run in the finalizer process.
    (unless (listener? listener)
      (bad-arg 'close-tcp-listener listener))
    (with-interrupts-disabled
     (let ([handle (listener-handle listener)])
       (when handle
         (CloseTCPListener handle)
         (listener-handle-set! listener #f)))))

  (define accept-tcp
    (case-lambda
     [(listener process)
      (unless (listener? listener)
        (bad-arg 'accept-tcp listener))
      (unless (process? process)
        (bad-arg 'accept-tcp process))
      (let ([handle (listener-handle listener)])
        (unless handle
          (bad-arg 'accept-tcp listener))
        (AcceptTCP handle
          (lambda (x) ;; This procedure runs in the event loop.
            (match x
              [(,who . ,errno)
               (send process `#(accept-tcp-failed ,listener ,who ,errno))]
              [,handle
               (let* ([name (let ([addr (GetIPAddress* handle)])
                              (if (string? addr)
                                  (format "TCP:~a" addr)
                                  (format "TCP::~a"
                                    (listener-port-number listener))))]
                      [port (@make-osi-port name handle)])
                 (send process
                   `#(accept-tcp ,listener
                       ,(make-iport name port #f)
                       ,(make-oport name port))))])))
        listener)]
     [(listener)
      (accept-tcp listener self)
      (receive
       [#(accept-tcp ,@listener ,ip ,op) (values ip op)]
       [#(accept-tcp-failed ,@listener ,who ,errno)
        (exit `#(accept-tcp-failed ,(listener-port-number listener)
                  ,who ,errno))])]))

  (define connect-tcp
    (case-lambda
     [(hostname port-spec process)
      (unless (string? hostname)
        (bad-arg 'connect-tcp hostname))
      (unless (or (port-number? port-spec) (string? port-spec))
        (bad-arg 'connect-tcp port-spec))
      (unless (process? process)
        (bad-arg 'connect-tcp process))
      (ConnectTCP hostname (format "~a" port-spec)
        (lambda (x) ;; This procedure runs in the event loop.
          (match x
            [(,who . ,errno)
             (send process
               `#(connect-tcp-failed ,hostname ,port-spec ,who ,errno))]
            [,handle
             (let* ([name (format "TCP:~a:~a" hostname port-spec)]
                    [port (@make-osi-port name handle)])
               (send process
                 `#(connect-tcp ,hostname ,port-spec
                     ,(make-iport name port #f)
                     ,(make-oport name port))))])))]
     [(hostname port-spec)
      (connect-tcp hostname port-spec self)
      (receive
       [#(connect-tcp ,@hostname ,@port-spec ,ip ,op) (values ip op)]
       [#(connect-tcp-failed ,@hostname ,@port-spec ,who ,errno)
        (exit `#(connect-tcp-failed ,hostname ,port-spec ,who ,errno))])]))

  (add-finalizer close-dead-osi-ports)
  (add-finalizer close-dead-listeners)
  (add-finalizer close-dead-directory-watchers))
