;;;; cell-zero.asd

(asdf:defsystem "cell-zero"
  :description "Stage 0 source genomes with replayable parent-gated evolution"
  :version "0.3.0"
  :author "Eric Fode and Autolith"
  :license "MIT"
  :depends-on ("uiop")
  :serial t
  :components ((:file "src/package")
               (:file "src/sha256")
               (:file "src/term")
               (:file "src/evaluator")
               (:file "src/subzero")
               (:file "src/genome")
               (:file "src/model")
               (:file "src/tutor")
               (:file "src/genesis")
               (:file "src/homoiconic")
               (:static-file "genomes/stage0.lisp")
               (:static-file "genomes/inert.lisp")
               (:static-file "scripts/genome-runner.lisp"))
  :in-order-to ((test-op (test-op "cell-zero/tests"))))

(asdf:defsystem "cell-zero/tests"
  :depends-on ("cell-zero")
  :serial t
  :components ((:file "test/tests"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :cell-zero.tests :run-tests)
               (error "Cell-zero tests failed"))))
