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
(library (swish app-io)
  (export
   base-dir
   bin-dir
   data-dir
   http-port-number
   log-path
   tmp-path
   web-path
   )
  (import
   (software-info)
   (swish erlang)
   (swish io)
   (swish osi)
   (except (chezscheme) define-record exit))

  (define bin-dir (path-parent (GetExecutablePath)))

  (define self-contained?
    (string-ci=? (path-last bin-dir) (symbol->string (machine-type))))

  (define base-dir
    (if self-contained?
        (path-parent (path-parent bin-dir))
        bin-dir))

  (define data-dir
    (if self-contained?
        (path-combine base-dir "data")
        (path-combine (GetFolderPath 35)    ; CSIDL_COMMON_APPDATA
          software-company-dir software-product-name)))

  (define http-port-number (make-parameter 54221))

  (define log-path (make-parameter (path-combine data-dir "Log.db3")))

  (define tmp-path (make-parameter (path-combine data-dir "tmp")))

  (define web-path (make-parameter (path-combine base-dir "web")))
  )
