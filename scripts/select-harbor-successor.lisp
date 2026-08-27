;;;; scripts/select-harbor-successor.lisp

(require :asdf)

(defparameter *script-directory*
  (uiop:pathname-directory-pathname (truename *load-truename*)))

(defparameter *root*
  (uiop:pathname-parent-directory-pathname *script-directory*))

(defparameter *arguments* (uiop:command-line-arguments))

(unless (= 7 (length *arguments*))
  (error "Usage: select-harbor-successor.lisp PARENT-CONTEXT CANDIDATE-CONTEXT PARENT-SCORE CANDIDATE-SCORE ACCEPT-EQUAL RESULT CAPSULE"))

(asdf:load-asd (merge-pathnames "cell-zero.asd" *root*))
(asdf:load-system "cell-zero")

(defun parse-harbor-score (text)
  (labels ((whitespacep (character)
             (member character '(#\Space #\Tab #\Newline #\Return))))
    (handler-case
        (let ((*read-eval* nil))
          (multiple-value-bind (value position)
              (read-from-string text nil :invalid)
            (unless (and (realp value)
                         (every #'whitespacep (subseq text position)))
              (error "Invalid Harbor score ~S" text))
            (rational value)))
      (error ()
        (error "Invalid Harbor score ~S" text)))))

(destructuring-bind
    (parent-context-path candidate-context-path parent-score-text
     candidate-score-text accept-equal-text result-path capsule-path)
    *arguments*
   (let* ((parent-context
            (string-right-trim '(#\Newline #\Return)
                               (uiop:read-file-string parent-context-path)))
          (candidate-context
            (string-right-trim '(#\Newline #\Return)
                               (uiop:read-file-string candidate-context-path)))
          (parent-reward (parse-harbor-score parent-score-text))
          (candidate-reward (parse-harbor-score candidate-score-text))
          (score-scale (lcm (denominator parent-reward)
                            (denominator candidate-reward)))
          (parent-score (* (numerator parent-reward)
                           (/ score-scale (denominator parent-reward))))
          (candidate-score (* (numerator candidate-reward)
                              (/ score-scale (denominator candidate-reward))))
         (accept-equal (string-equal accept-equal-text "true"))
         (parent
           (cell-zero:make-homoiconic-genesis-capsule
            :accept-equal accept-equal
            :task-context parent-context))
         (candidate
           (cell-zero:make-homoiconic-genesis-capsule
            :task-context candidate-context))
         (store (cell-zero:make-term-store))
         (cell (cell-zero:make-homoiconic-cell store parent)))
    (cell-zero:register-homoiconic-handler
     cell "model"
     (cell-zero:make-scripted-homoiconic-model-handler candidate))
    (cell-zero:register-homoiconic-handler
     cell "runner"
     (cell-zero:make-scripted-homoiconic-runner-handler
      (lambda (capsule event)
        (declare (ignore event))
        (values t
                (if (cell-zero:term-equal capsule candidate)
                    candidate-score
                    parent-score)
                (cell-zero:empty-term)))))
    (cell-zero:submit-homoiconic-event
     cell
     (cell-zero:sexp->term
      '(event (kind evolve) (objective "Improve Terminal-Bench performance"))))
    (cell-zero:run-homoiconic-until-idle cell)
    (let* ((selected (cell-zero:homoiconic-cell-current-capsule cell))
           (selection (first (cell-zero:homoiconic-cell-outputs cell)))
           (decision (cell-zero:term-field selection "decision")))
      (with-open-file (stream result-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (write
         `(harbor-evolution
           (parent-root ,(cell-zero:term-hash parent))
           (candidate-root ,(cell-zero:term-hash candidate))
           (selected-root ,(cell-zero:term-hash selected))
            (parent-reward ,parent-score-text)
            (candidate-reward ,candidate-score-text)
            (score-scale ,score-scale)
            (parent-score ,parent-score)
            (candidate-score ,candidate-score)
           (decision ,(cell-zero:term->sexp decision))
           (evaluation-steps ,(cell-zero:homoiconic-cell-evaluation-steps cell)))
         :stream stream
         :pretty t)
        (terpri stream))
      (with-open-file (stream capsule-path
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
        (cell-zero:write-term selected stream)
        (terpri stream)))))
