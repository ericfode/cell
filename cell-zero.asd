;;;; cell-zero.asd

(asdf:defsystem "cell-zero"
  :description "Cell-zero/1: parent-gated, replayable evolutionary worlds"
  :version "0.1.0"
  :author "Eric Fode and Autolith"
  :license "MIT"
  :depends-on ("uiop")
  :serial t
  :components ((:file "src/package")
               (:file "src/sha256")
               (:file "src/term")
               (:file "src/evaluator")
               (:file "src/subzero")
               (:file "src/genesis"))
  :in-order-to ((test-op (test-op "cell-zero/tests"))))

(asdf:defsystem "cell-zero/tests"
  :depends-on ("cell-zero")
  :serial t
  :components ((:file "test/tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cell-zero.tests :run-tests)
               (error "Cell-zero tests failed"))))
