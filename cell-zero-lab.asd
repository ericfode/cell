;;;; cell-zero-lab.asd

(asdf:defsystem "cell-zero-lab"
  :description "External ecological challenge laboratory for Cell-zero"
  :version "0.1.0"
  :depends-on ("cell-zero")
  :serial t
  :components ((:file "lab/package")
               (:file "lab/protocol")
               (:file "lab/c0-event-eater"))
  :in-order-to ((test-op (test-op "cell-zero-lab/tests"))))

(asdf:defsystem "cell-zero-lab/tests"
  :depends-on ("cell-zero-lab")
  :serial t
  :components ((:file "lab/tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cell-zero-lab-tests :run-tests)
               (error "Cell-zero laboratory tests failed"))))
