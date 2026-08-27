;;;; scripts/render-homoiconic-task.lisp

(require :asdf)

(defparameter *script-directory*
  (uiop:pathname-directory-pathname (truename *load-truename*)))

(defparameter *root*
  (uiop:pathname-parent-directory-pathname *script-directory*))

(defparameter *arguments* (uiop:command-line-arguments))

(unless (= 4 (length *arguments*))
  (error "Usage: render-homoiconic-task.lisp CONTEXT INSTRUCTION PROMPT METADATA"))

(asdf:load-asd (merge-pathnames "cell-zero.asd" *root*))
(asdf:load-system "cell-zero")

(destructuring-bind (context-path instruction-path prompt-path metadata-path)
    *arguments*
  (let* ((context
           (string-right-trim '(#\Newline #\Return)
                              (uiop:read-file-string context-path)))
         (instruction (uiop:read-file-string instruction-path))
         (capsule
           (cell-zero:make-homoiconic-genesis-capsule
            :task-context context))
         (prompt (cell-zero:homoiconic-task-prompt capsule instruction)))
    (with-open-file (stream prompt-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string prompt stream))
    (with-open-file (stream metadata-path
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (format stream "capsule_root=~A~%" (cell-zero:term-hash capsule))
      (format stream "evaluator_root=~A~%"
              (cell-zero:term-hash (cell-zero:capsule-evaluator capsule)))
      (format stream "step_root=~A~%"
              (cell-zero:term-hash (cell-zero:capsule-step-program capsule))))))
