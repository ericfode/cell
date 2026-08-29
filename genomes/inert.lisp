;;;; genomes/inert.lisp

(defpackage #:cell-zero.inert.genome
  (:use #:cl)
  (:export #:react #:admit))

(in-package #:cell-zero.inert.genome)

(defun list-term (&rest values)
  (apply #'cell-zero:term-list values))

(defun field (name value)
  (list-term (cell-zero:make-symbol-atom name) value))

(defun tagged (tag &rest fields)
  (apply #'list-term (cell-zero:make-symbol-atom tag) fields))

(defun react (state event data world)
  (declare (ignore event data world))
  (tagged "reaction"
          (field "state" state)
          (field "outputs" (cell-zero:empty-term))
          (field "effects" (cell-zero:empty-term))))

(defun admit (candidate evidence data)
  (declare (ignore candidate evidence data))
  (tagged "admission"
          (field "decision" (cell-zero:make-symbol-atom "accept"))
          (field "reason"
                 (cell-zero:make-symbol-atom "candidate-self-accepts"))))
