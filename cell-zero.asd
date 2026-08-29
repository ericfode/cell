;;;; cell-zero.asd

(asdf:defsystem "cell-zero"
  :description "Cell-zero/2: homoiconic, parent-selected evolutionary capsules"
  :version "0.2.0"
  :author "Eric Fode and Autolith"
  :license "MIT"
  :depends-on ("uiop")
  :serial t
  :components ((:file "src/package")
               (:file "src/sha256")
               (:file "src/term")
               (:file "src/evaluator")
               (:file "src/subzero")
               (:file "src/model")
               (:file "src/genesis")
               (:file "src/homoiconic"))
  :in-order-to ((test-op (test-op "cell-zero/tests"))))

(asdf:defsystem "cell-zero/tests"
  :depends-on ("cell-zero")
  :serial t
  :components ((:file "test/tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cell-zero.tests :run-tests)
               (error "Cell-zero tests failed"))))
