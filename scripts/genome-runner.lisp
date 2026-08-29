;;;; scripts/genome-runner.lisp

(require :asdf)

(defpackage #:cell-zero.genome-runner
  (:use #:cl)
  (:export #:main))

(in-package #:cell-zero.genome-runner)

(defun cell-symbol (name)
  (let ((package (or (find-package "CELL-ZERO")
                     (error "CELL-ZERO is not loaded"))))
    (or (find-symbol name package)
        (error "CELL-ZERO symbol ~A is missing" name))))

(defun cell-call (name &rest arguments)
  (apply (symbol-function (cell-symbol name)) arguments))

(defun write-term-file (response term)
  (with-open-file (stream response
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (cell-call "WRITE-TERM" term stream)
    (terpri stream)))

(defun read-term-file (invocation)
  (with-open-file (stream invocation :direction :input :external-format :utf-8)
    (cell-call "READ-TERM" stream)))

(defun write-failure (response condition)
  (when (find-package "CELL-ZERO")
    (ignore-errors
      (write-term-file
       response
       (cell-call
        "MAKE-TAGGED-TERM" "genome-runner-failure"
        (cell-call "MAKE-FIELD" "detail"
                   (cell-call "MAKE-STRING-ATOM"
                              (princ-to-string condition))))))))

(defun main (asdf-file directory invocation response)
  (handler-case
      (progn
        (asdf:load-asd asdf-file)
        (asdf:load-system "cell-zero")
        (let* ((request (read-term-file invocation))
               (value
                 (cell-call "EXECUTE-MATERIALIZED-GENOME-INVOCATION"
                            (pathname directory) request))
               (result
                 (cell-call "MAKE-TAGGED-TERM" "genome-runner-result"
                            (cell-call "MAKE-FIELD" "value" value))))
          (write-term-file response result))
        t)
    (error (condition)
      (write-failure response condition)
      (uiop:quit 1))))
