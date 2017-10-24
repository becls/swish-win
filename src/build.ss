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

(compile-imported-libraries #t)
(define bin-dir (format "..\\bin\\~a\\" (machine-type)))
(define main-so (string-append bin-dir "main.so"))
(define (get-boot-files)
  (define (dfs-list libs seen order)
    (if (null? libs)
        (values seen order)
        (let-values ([(seen order) (dfs (car libs) seen order)])
          (dfs-list (cdr libs) seen order))))
  (define (dfs lib seen order)
    (if (or (not (library-object-filename lib)) (member lib seen))
        (values seen order)
        (let-values ([(seen order) (dfs-list (library-requirements lib)
                                     (cons lib seen) order)])
          (values seen (cons (library-object-filename lib) order)))))
  (let-values ([(seen order) (dfs-list (library-list) '() '())])
    (reverse (cons main-so order))))
(define buf (make-bytevector 65536))
(define (copy fn op)
  (let ([ip (open-file-input-port fn
              (file-options compressed)
              (buffer-mode block))])
    (let lp ()
      (let ([n (get-bytevector-n! ip buf 0 (bytevector-length buf))])
        (unless (eof-object? n)
          (put-bytevector op buf 0 n)
          (when (= n (bytevector-length buf))
            (lp)))))
    (close-input-port ip)))
(define (build basename)
  (define boot-filename (string-append basename ".boot"))
  (define so-filename (string-append basename ".so"))
  (time
   (begin
     ;; Concatenate the libaries and main.so
     (compile-file "main.ss" main-so)
     (let ([op (open-file-output-port
                (string-append bin-dir basename ".so")
                (file-options no-fail compressed)
                (buffer-mode block))])
       (for-each (lambda (fn) (copy fn op)) (get-boot-files))
       (close-output-port op))
     ;; Build boot file by copying petite.boot and some code that
     ;; loads the so file associated with the exe.  We can't use
     ;; make-boot-file because Chez Scheme 9.4 does not support
     ;; compiled libraries in boot files.
     (let ([op (open-file-output-port
                (string-append bin-dir basename ".boot")
                (file-options no-fail compressed)
                (buffer-mode block))])
       (copy (string-append bin-dir "petite.boot") op)
       (parameterize ([generate-inspector-information #f])
         (compile-to-port
          `((suppress-greeting #t)
            (scheme-start
             (lambda x
               (let* ([exe-path
                       ((foreign-procedure "osi::GetExecutablePath" () ptr))]
                      [n (string-length exe-path)])
                 (load (string-append
                        (substring exe-path 0 (- (string-length exe-path) 3))
                        "so")))
               (collect (collect-maximum-generation) 'static)
               (apply (top-level-value 'app:scheme-start) x))))
          op))
       (close-output-port op)))))
(let ([args (command-line-arguments)])
  (unless (eqv? (length args) 1)
    (display "Usage: build <basename>\n")
    (abort 1))
  (apply build args)
  (abort 0))
