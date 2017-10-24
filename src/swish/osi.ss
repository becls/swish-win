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
(library (swish osi)
  (export
   ;; Completion Packet Functions
   IsCompletionPacketReady
   GetCompletionPacket

   ;; Port Functions
   ReadPort ReadPort*
   WritePort WritePort*
   ClosePort ClosePort*

   ;; USB Functions
   GetDeviceNames GetDeviceNames*
   ConnectWinUSB ConnectWinUSB*

   ;; Pipe Functions
   CreateServerPipe CreateServerPipe*
   CreateClientPipe CreateClientPipe*

   ;; Process Functions
   CreateDetachedWatchedProcess CreateDetachedWatchedProcess*
   CreateWatchedProcess CreateWatchedProcess*
   ExitProcess
   TerminateProcess TerminateProcess*
   SetMainThreadPriority SetMainThreadPriority*
   SetPriorityClass SetPriorityClass*

   ;; SQLite Functions
   OpenDatabase OpenDatabase*
   CloseDatabase CloseDatabase*
   PrepareStatement PrepareStatement*
   FinalizeStatement FinalizeStatement*
   BindStatement BindStatement*
   ClearStatementBindings ClearStatementBindings*
   GetLastInsertRowid GetLastInsertRowid*
   GetStatementColumns GetStatementColumns*
   GetStatementSQL GetStatementSQL*
   ResetStatement ResetStatement*
   StepStatement StepStatement*
   GetSQLiteStatus GetSQLiteStatus*

   ;; File System Functions
   CreateFile CreateFile*
   CreateHardLink CreateHardLink*
   DeleteFile DeleteFile*
   MoveFile MoveFile*
   CreateDirectory CreateDirectory*
   RemoveDirectory RemoveDirectory*
   FindFiles FindFiles*
   GetDiskFreeSpace GetDiskFreeSpace*
   GetExecutablePath GetExecutablePath*
   GetFileSize GetFileSize*
   GetFolderPath GetFolderPath*
   GetFullPath GetFullPath*
   WatchDirectory WatchDirectory*
   CloseDirectoryWatcher CloseDirectoryWatcher*

   ;; Console Functions
   OpenConsole

   ;; TCP/IP Functions
   ConnectTCP ConnectTCP*
   ListenTCP ListenTCP*
   CloseTCPListener CloseTCPListener*
   AcceptTCP AcceptTCP*
   GetIPAddress GetIPAddress*
   GetListenerPortNumber GetListenerPortNumber*

   ;; Information Functions
   CompareStringLogical CompareStringLogical*
   CreateGUID CreateGUID*
   guid->string
   string->guid
   GetBytesUsed
   GetComputerName GetComputerName*
   GetErrorString GetErrorString*
   GetHandleCounts
   GetMemoryInfo GetMemoryInfo*
   GetPerformanceCounter GetPerformanceCounter*
   GetPerformanceFrequency GetPerformanceFrequency*
   GetTickCount
   SetTick
   IsTickOver
   IsService

   ;; Hash Functions
   ALG_MD5
   ALG_SHA1
   ALG_SHA_256
   ALG_SHA_384
   ALG_SHA_512
   OpenHash OpenHash*
   HashData HashData*
   GetHashValue GetHashValue*
   CloseHash CloseHash*
   )
  (import (chezscheme))

  (define-syntax (define-osi x)
    (syntax-case x ()
      [(_ name (arg-name arg-type) ...)
       (with-syntax
        ([name*
          (datum->syntax #'name
            (string->symbol
             (string-append (symbol->string (datum name)) "*")))]
         [foreign-name
          (datum->syntax #'name
            (string-append "osi::" (symbol->string (datum name))))])
        #'(begin
            (define name*
              (foreign-procedure foreign-name (arg-type ...) ptr))
            (define (name arg-name ...)
              (let ([x (name* arg-name ...)])
                (if (not (and (pair? x) (symbol? (car x))))
                    x
                    (raise `#(osi-error name ,(car x) ,(cdr x))))))))]))

  ;; Completion Packet Functions
  (define IsCompletionPacketReady
    (foreign-procedure "osi::IsCompletionPacketReady" () boolean))
  (define GetCompletionPacket
    (foreign-procedure "osi::GetCompletionPacket" (unsigned-32) ptr))

  ;; Port Functions
  (define-osi ReadPort (port fixnum) (buffer ptr) (start-index size_t)
    (size unsigned-32) (file-position ptr) (callback ptr))
  (define-osi WritePort (port fixnum) (buffer ptr) (start-index size_t)
    (size unsigned-32) (file-position ptr) (callback ptr))
  (define-osi ClosePort (port fixnum))

  ;; USB Functions
  (define-osi GetDeviceNames (device-interface ptr))
  (define-osi ConnectWinUSB (device-name ptr) (read-address fixnum)
    (write-address fixnum))

  ;; Pipe Functions
  (define-osi CreateServerPipe (name ptr) (callback ptr))
  (define-osi CreateClientPipe (name ptr))

  ;; Process Functions
  (define-osi CreateDetachedWatchedProcess (command-line ptr) (callback ptr))
  (define-osi CreateWatchedProcess (command-line ptr) (callback ptr))
  (define ExitProcess (foreign-procedure "osi::ExitProcess" (unsigned-32) void))
  (define-osi TerminateProcess (process fixnum) (exit-code unsigned-32))
  (define-osi SetMainThreadPriority (priority int))
  (define-osi SetPriorityClass (priorityClass unsigned-32))

  ;; SQLite Functions
  (define-osi OpenDatabase (filename ptr) (flags int))
  (define-osi CloseDatabase (database fixnum))
  (define-osi PrepareStatement (database fixnum) (sql ptr))
  (define-osi FinalizeStatement (statement fixnum))
  (define-osi BindStatement (statement fixnum) (index unsigned-32) (datum ptr))
  (define-osi ClearStatementBindings (statement fixnum))
  (define-osi GetLastInsertRowid (database fixnum))
  (define-osi GetStatementColumns (statement fixnum))
  (define-osi GetStatementSQL (statement fixnum))
  (define-osi ResetStatement (statement fixnum))
  (define-osi StepStatement (statement fixnum) (callback ptr))
  (define-osi GetSQLiteStatus (operation int) (reset? boolean))

  ;; File System Functions
  (define-osi CreateFile (name ptr) (desired-access unsigned-32)
    (share-mode unsigned-32) (creation-disposition unsigned-32))
  (define-osi CreateHardLink (from-path ptr) (to-path ptr))
  (define-osi DeleteFile (name ptr))
  (define-osi MoveFile (existing-path ptr) (new-path ptr) (flags unsigned-32))
  (define-osi CreateDirectory (path ptr))
  (define-osi RemoveDirectory (path ptr))
  (define-osi FindFiles (spec ptr) (callback ptr))
  (define-osi GetDiskFreeSpace (path ptr))
  (define-osi GetExecutablePath)
  (define-osi GetFileSize (port fixnum))
  (define-osi GetFolderPath (folder int))
  (define-osi GetFullPath (path ptr))
  (define-osi WatchDirectory (path ptr) (subtree boolean) (callback ptr))
  (define-osi CloseDirectoryWatcher (watcher fixnum))

  ;; Console Functions
  (define OpenConsole (foreign-procedure "osi::OpenConsole" () fixnum))

  ;; TCP/IP Functions
  (define-osi ConnectTCP (nodename ptr) (servname ptr) (callback ptr))
  (define-osi ListenTCP (port-number unsigned-16))
  (define-osi CloseTCPListener (listener fixnum))
  (define-osi AcceptTCP (listener fixnum) (callback ptr))
  (define-osi GetIPAddress (port fixnum))
  (define-osi GetListenerPortNumber (listener fixnum))

  ;; Information Functions
  (define-osi CompareStringLogical (s1 ptr) (s2 ptr))
  (define-osi CreateGUID)

  (define (guid->string guid)
    (unless (and (bytevector? guid) (= (bytevector-length guid) 16))
      (raise `#(bad-arg guid->string ,guid)))
    (format "~8,'0X-~4,'0X-~4,'0X-~4,'0X-~2,'0X~2,'0X~2,'0X~2,'0X~2,'0X~2,'0X"
      (#3%bytevector-u32-ref guid 0 'little)
      (#3%bytevector-u16-ref guid 4 'little)
      (#3%bytevector-u16-ref guid 6 'little)
      (#3%bytevector-u16-ref guid 8 'big)
      (#3%bytevector-u8-ref guid 10)
      (#3%bytevector-u8-ref guid 11)
      (#3%bytevector-u8-ref guid 12)
      (#3%bytevector-u8-ref guid 13)
      (#3%bytevector-u8-ref guid 14)
      (#3%bytevector-u8-ref guid 15)))

  (define (string->guid s)
    (define (err) (raise `#(bad-arg string->guid ,s)))
    (define (decode-digit c)
      (cond
       [(#3%char<=? #\0 c #\9)
        (#3%fx- (#3%char->integer c) (char->integer #\0))]
       [(#3%char<=? #\A c #\F)
        (#3%fx- (#3%char->integer c) (fx- (char->integer #\A) 10))]
       [(#3%char<=? #\a c #\f)
        (#3%fx- (#3%char->integer c) (fx- (char->integer #\a) 10))]
       [else (err)]))
    (define-syntax decode
      (syntax-rules ()
        [(_ i) (decode-digit (#3%string-ref s i))]))
    (define-syntax build
      (syntax-rules ()
        [(_ i ...)
         (bytevector
          (#3%fx+ (#3%fx* (decode i) 16) (decode (#3%fx+ i 1)))
          ...)]))
    (unless (and (string? s)
                 (#3%fx= (#3%string-length s) 36)
                 (#3%char=? (#3%string-ref s 8) #\-)
                 (#3%char=? (#3%string-ref s 13) #\-)
                 (#3%char=? (#3%string-ref s 18) #\-)
                 (#3%char=? (#3%string-ref s 23) #\-))
      (err))
    (build 6 4 2 0 11 9 16 14 19 21 24 26 28 30 32 34))

  (define GetBytesUsed (foreign-procedure "osi::GetBytesUsed" () size_t))
  (define-osi GetComputerName)
  (define-osi GetErrorString (error-number unsigned-32))
  (define GetHandleCounts (foreign-procedure "osi::GetHandleCounts" () ptr))
  (define-osi GetMemoryInfo)
  (define-osi GetPerformanceCounter)
  (define-osi GetPerformanceFrequency)
  (define GetTickCount (foreign-procedure "osi::GetTickCount" () ptr))
  (define SetTick (foreign-procedure "osi::SetTick" () void))
  (define IsTickOver (foreign-procedure "osi::IsTickOver" () boolean))
  (define IsService (foreign-procedure "osi::IsService" () boolean))

  ;; Hash Functions

  (define ALG_MD5 #x8003)
  (define ALG_SHA1 #x8004)
  (define ALG_SHA_256 #x800c)
  (define ALG_SHA_384 #x800d)
  (define ALG_SHA_512 #x800e)
  (define-osi OpenHash (alg unsigned-32))
  (define-osi HashData (hash fixnum) (buffer ptr) (start-index size_t)
    (size unsigned-32))
  (define-osi GetHashValue (hash fixnum))
  (define-osi CloseHash (hash fixnum))
  )
