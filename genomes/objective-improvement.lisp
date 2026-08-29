;;;; genomes/objective-improvement.lisp

(in-package #:cell-zero.stage0.genome)

(defun react-with-objective-probe (state event data world)
  "Extend Stage 0 with the objective-probe behavior used by selection tests."
  (if (string= (symbol-name-of (required event "kind")) "objective-probe")
      (reaction
       (record-event state event)
       (list
        (tagged "objective-result"
                (field-pair "status" (cell-zero:make-symbol-atom "pass"))))
       nil)
      (react state event data world)))
