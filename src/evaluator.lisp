;;;; src/evaluator.lisp

(in-package #:cell-zero)

(define-condition evaluation-error (cell-zero-error)
  ((expression :initarg :expression :reader evaluation-error-expression)
   (reason :initarg :reason :reader evaluation-error-reason))
  (:report (lambda (condition stream)
             (format stream "Evaluation error: ~A" (evaluation-error-reason condition)))))

(define-condition evaluation-budget-exhausted (evaluation-error)
  ((kind :initarg :kind :reader exhausted-budget-kind))
  (:report (lambda (condition stream)
             (format stream "Evaluation ~A budget exhausted"
                     (exhausted-budget-kind condition)))))

(defstruct (evaluation-limits
             (:constructor make-evaluation-limits
                 (&key (max-steps 10000) (max-depth 256) (max-output-size 100000))))
  (max-steps 10000 :type (integer 1 *))
  (max-depth 256 :type (integer 1 *))
  (max-output-size 100000 :type (integer 1 *)))

(defstruct (evaluation-usage
             (:conc-name usage-)
             (:constructor make-evaluation-usage
                 (&key steps max-depth output-size)))
  (steps 0 :type (integer 0 *))
  (max-depth 0 :type (integer 0 *))
  (output-size 0 :type (integer 0 *)))

(defstruct evaluator-state
  limits
  (steps 0)
  (max-depth 0))

(defstruct (evaluator-closure
             (:constructor make-evaluator-closure (parameters body environment)))
  parameters
  body
  environment)

(defparameter +primitive-signatures+
  '(("equal" 2 2) ("not" 1 1) ("present?" 1 1) ("nonempty?" 1 1)
    ("integer+" 2 2) ("integer<" 2 2) ("integer<=" 2 2)
    ("list" 0 nil) ("append" 2 2)
    ("field" 2 2) ("put-field" 3 3) ("append-field" 3 3) ("tag" 1 1)
    ("hash" 1 1) ("first" 1 1) ("second" 1 1) ("third" 1 1) ("rest" 1 1)
    ("length" 1 1) ("find-by-field" 3 3) ("remove-by-field" 3 3)
     ("all-checks-pass" 2 2) ("first-failed-check" 2 2) ("subset?" 2 2)
     ("term-size" 1 1) ("string-concat" 2 2) ("parse-term" 1 1)
     ("apply-primitive" 2 2)))

(defparameter +primitive-names+ (mapcar #'first +primitive-signatures+))

(defun expression-name (expression)
  (let ((tag (term-tag expression)))
    (when (and tag (atom-p tag) (eq (atom-kind tag) :symbol))
      (atom-value tag))))

(defun expression-elements (expression)
  (handler-case
      (term-list-elements expression)
    (malformed-term ()
      (error 'evaluation-error :expression expression
             :reason "expression is not a proper list"))))

(defun ensure-arity (expression elements minimum &optional maximum)
  (let ((arity (1- (length elements))))
    (unless (and (>= arity minimum)
                 (or (null maximum) (<= arity maximum)))
      (error 'evaluation-error :expression expression
             :reason (format nil "~A expects ~D~@[ to ~D~] arguments, got ~D"
                             (expression-name expression) minimum maximum arity)))))

(defun symbol-term-name (term expression)
  (unless (and (atom-p term) (eq (atom-kind term) :symbol))
    (error 'evaluation-error :expression expression :reason "expected a symbol atom"))
  (atom-value term))

(defun validation-step (state expression depth)
  (incf (evaluator-state-steps state))
  (setf (evaluator-state-max-depth state)
        (max depth (evaluator-state-max-depth state)))
  (when (> (evaluator-state-steps state)
           (evaluation-limits-max-steps (evaluator-state-limits state)))
    (error 'evaluation-budget-exhausted :expression expression
           :reason "validation step limit" :kind :steps))
  (when (> depth (evaluation-limits-max-depth (evaluator-state-limits state)))
    (error 'evaluation-budget-exhausted :expression expression
           :reason "validation depth limit" :kind :depth)))

(defun ensure-primitive-arity (primitive argument-count expression)
  (destructuring-bind (ignored minimum maximum)
      (or (assoc primitive +primitive-signatures+ :test #'string=)
          (error 'evaluation-error :expression expression
                 :reason (format nil "unknown primitive ~A" primitive)))
    (declare (ignore ignored))
    (unless (and (>= argument-count minimum)
                 (or (null maximum) (<= argument-count maximum)))
      (error 'evaluation-error :expression expression
             :reason (format nil "primitive ~A expects ~D~@[ to ~D~] arguments, got ~D"
                             primitive minimum maximum argument-count)))))

(defun validation-list-elements (term state expression depth)
  (loop with cursor = term
        while (cell-p cursor)
        do (validation-step state expression depth)
        collect (cell-left cursor)
        do (setf cursor (cell-right cursor))
        finally
           (unless (proper-list-tail-p cursor)
             (error 'evaluation-error :expression expression
                    :reason "expected a proper list"))))

(defun validation-record-fields (program state)
  (unless (cell-p program)
    (error 'evaluation-error :expression program
           :reason "program must be a proper tagged record"))
  (let* ((elements (validation-list-elements program state program 0))
         (tag (first elements))
         (fields (make-hash-table :test #'equal)))
    (unless (symbol-atom-name= tag "program")
      (error 'evaluation-error :expression program
             :reason "program must be tagged program"))
    (dolist (field (rest elements) fields)
      (let ((parts (validation-list-elements field state field 1)))
        (unless (and (= (length parts) 2)
                     (atom-p (first parts))
                     (eq (atom-kind (first parts)) :symbol))
          (error 'evaluation-error :expression field
                 :reason "program field must be (name value)"))
        (let ((name (atom-value (first parts))))
          (multiple-value-bind (ignored present) (gethash name fields)
            (declare (ignore ignored))
            (when present
              (error 'evaluation-error :expression program
                     :reason (format nil "duplicate program field ~A" name))))
          (setf (gethash name fields) (second parts)))))))

(defun validate-program (program &key (limits (make-evaluation-limits)) state)
  "Validate the closed Cell-zero kernel language within LIMITS.
Code and data are terms. Lambda, letrec, and apply provide the small recursive
kernel needed to execute the evaluator represented inside a Cell-zero capsule."
  (let ((state (or state (make-evaluator-state :limits limits))))
    (labels ((parameter-names (parameters expression depth)
               (let ((seen (make-hash-table :test #'equal)))
                 (mapcar
                  (lambda (parameter)
                    (let ((name (symbol-term-name parameter expression)))
                      (when (gethash name seen)
                        (error 'evaluation-error :expression expression
                               :reason "duplicate parameter"))
                      (setf (gethash name seen) t)
                      name))
                  (validation-list-elements parameters state expression depth))))
             (validate-expression (expression bound depth)
               (validation-step state expression depth)
               (unless (cell-p expression)
                 (error 'evaluation-error :expression expression
                        :reason "program expressions must be lists"))
               (let* ((elements (validation-list-elements
                                 expression state expression depth))
                      (name (expression-name expression)))
                 (cond
                   ((string= name "quote")
                    (ensure-arity expression elements 1 1))
                   ((string= name "var")
                    (ensure-arity expression elements 1 1)
                    (let ((variable (symbol-term-name (second elements) expression)))
                      (unless (member variable bound :test #'string=)
                        (error 'evaluation-error :expression expression
                               :reason (format nil "unbound variable ~A" variable)))))
                   ((string= name "if")
                    (ensure-arity expression elements 3 3)
                    (dolist (subexpression (rest elements))
                      (validate-expression subexpression bound (1+ depth))))
                   ((string= name "let*")
                    (ensure-arity expression elements 2 2)
                    (let ((extended bound))
                      (dolist (binding
                               (validation-list-elements
                                (second elements) state expression (1+ depth)))
                        (let ((binding-elements
                                (validation-list-elements
                                 binding state binding (1+ depth))))
                          (unless (= (length binding-elements) 2)
                            (error 'evaluation-error
                                   :expression binding
                                   :reason "let* binding must be (name expression)"))
                          (validate-expression
                           (second binding-elements) extended (1+ depth))
                          (push (symbol-term-name (first binding-elements) binding)
                                extended)))
                      (validate-expression (third elements) extended (1+ depth))))
                   ((string= name "lambda")
                    (ensure-arity expression elements 2 2)
                    (let ((parameters
                            (parameter-names (second elements) expression (1+ depth))))
                      (validate-expression (third elements)
                                           (append parameters bound)
                                           (1+ depth))))
                   ((string= name "letrec")
                    (ensure-arity expression elements 2 2)
                    (let* ((bindings
                             (validation-list-elements
                              (second elements) state expression (1+ depth)))
                           (names
                             (mapcar
                              (lambda (binding)
                                (let ((parts
                                        (validation-list-elements
                                         binding state binding (1+ depth))))
                                  (unless (= (length parts) 2)
                                    (error 'evaluation-error
                                           :expression binding
                                           :reason "letrec binding must be (name lambda)"))
                                  (symbol-term-name (first parts) binding)))
                              bindings))
                           (extended (append names bound)))
                      (unless (= (length names)
                                 (length (remove-duplicates names :test #'string=)))
                        (error 'evaluation-error :expression expression
                               :reason "duplicate letrec binding"))
                      (dolist (binding bindings)
                        (let* ((parts (validation-list-elements
                                      binding state binding (1+ depth)))
                               (value (second parts)))
                          (unless (string= (expression-name value) "lambda")
                            (error 'evaluation-error :expression value
                                   :reason "letrec values must be lambdas"))
                          (validate-expression value extended (1+ depth))))
                      (validate-expression (third elements) extended (1+ depth))))
                   ((string= name "apply")
                    (ensure-arity expression elements 1)
                    (dolist (subexpression (rest elements))
                      (validate-expression subexpression bound (1+ depth))))
                   ((string= name "call")
                    (ensure-arity expression elements 1)
                    (let ((primitive (symbol-term-name (second elements) expression)))
                      (ensure-primitive-arity primitive
                                              (length (cddr elements))
                                              expression))
                    (dolist (subexpression (cddr elements))
                      (validate-expression subexpression bound (1+ depth))))
                   (t
                    (error 'evaluation-error :expression expression
                           :reason (format nil "unknown expression form ~A" name)))))))
      (let ((fields (validation-record-fields program state)))
        (multiple-value-bind (parameters-term parameters-present)
            (gethash "parameters" fields)
          (multiple-value-bind (body body-present) (gethash "body" fields)
            (unless (and parameters-present body-present)
              (error 'evaluation-error :expression program
                     :reason "program requires parameters and body fields"))
            (let ((names (parameter-names parameters-term program 1)))
              (validate-expression body names 1)
              t)))))))

(defun evaluator-step (state expression depth)
  (incf (evaluator-state-steps state))
  (setf (evaluator-state-max-depth state)
        (max depth (evaluator-state-max-depth state)))
  (when (> (evaluator-state-steps state)
           (evaluation-limits-max-steps (evaluator-state-limits state)))
    (error 'evaluation-budget-exhausted :expression expression
           :reason "step limit" :kind :steps))
  (when (> depth (evaluation-limits-max-depth (evaluator-state-limits state)))
    (error 'evaluation-budget-exhausted :expression expression
           :reason "depth limit" :kind :depth)))

(defun evaluator-list-elements (term state expression depth)
  (loop with cursor = term
        while (cell-p cursor)
        do (evaluator-step state expression depth)
        collect (cell-left cursor)
        do (setf cursor (cell-right cursor))
        finally
           (unless (proper-list-tail-p cursor)
             (error 'evaluation-error :expression expression
                    :reason "expected a proper term list"))))

(defun evaluator-record-fields (program state)
  (let* ((elements (evaluator-list-elements program state program 0))
         (fields (make-hash-table :test #'equal)))
    (unless (symbol-atom-name= (first elements) "program")
      (error 'evaluation-error :expression program
             :reason "program must be tagged program"))
    (dolist (field (rest elements) fields)
      (let ((parts (evaluator-list-elements field state field 1)))
        (unless (and (= (length parts) 2)
                     (atom-p (first parts))
                     (eq (atom-kind (first parts)) :symbol))
          (error 'evaluation-error :expression field
                 :reason "program field must be (name value)"))
        (let ((name (atom-value (first parts))))
          (multiple-value-bind (ignored present) (gethash name fields)
            (declare (ignore ignored))
            (when present
              (error 'evaluation-error :expression program
                     :reason (format nil "duplicate program field ~A" name))))
          (setf (gethash name fields) (second parts)))))))

(defun environment-value (environment name expression)
  (let ((binding (assoc name environment :test #'string=)))
    (unless binding
      (error 'evaluation-error :expression expression
             :reason (format nil "unbound variable ~A" name)))
    (cdr binding)))

(defun integer-term-value (term expression)
  (unless (and (atom-p term) (eq (atom-kind term) :integer))
    (error 'evaluation-error :expression expression :reason "expected an integer atom"))
  (atom-value term))

(defun evaluator-string-value (term expression)
  (unless (and (atom-p term) (eq (atom-kind term) :string))
    (error 'evaluation-error :expression expression :reason "expected a string atom"))
  (atom-value term))

(defun proper-term-list (term expression)
  (handler-case
      (term-list-elements term)
    (malformed-term ()
      (error 'evaluation-error :expression expression :reason "expected a proper term list"))))

(defun check-status (checks requirement)
  (let ((wanted (symbol-term-name requirement requirement)))
    (dolist (check (proper-term-list checks checks) (empty-term))
      (let ((elements (proper-term-list check check)))
        (when (and (= (length elements) 2)
                   (symbol-atom-name= (first elements) wanted))
          (return (second elements)))))))

(defun make-check-status-table (checks state expression depth)
  (let ((table (make-hash-table :test #'equal)))
    (dolist (check (proper-term-list checks expression) table)
      (evaluator-step state expression depth)
      (let ((elements (proper-term-list check expression)))
        (when (= (length elements) 2)
          (setf (gethash (symbol-term-name (first elements) expression) table)
                (second elements)))))))

(defun primitive-call (name arguments expression state depth)
  (flet ((arity (minimum &optional maximum)
           (let ((count (length arguments)))
             (unless (and (>= count minimum)
                          (or (null maximum) (<= count maximum)))
               (error 'evaluation-error :expression expression
                      :reason (format nil "primitive ~A got ~D arguments" name count))))))
    (cond
      ((string= name "equal")
       (arity 2 2)
       (if (term-equal (first arguments) (second arguments)) (true-term) (false-term)))
      ((string= name "not")
       (arity 1 1)
       (if (term-truth-p (first arguments)) (false-term) (true-term)))
      ((string= name "present?")
       (arity 1 1)
       (if (or (symbol-atom-name= (first arguments) "nil")
               (symbol-atom-name= (first arguments) "absent"))
           (false-term)
           (true-term)))
      ((string= name "nonempty?")
       (arity 1 1)
       (if (null (proper-term-list (first arguments) expression))
           (false-term)
           (true-term)))
      ((string= name "integer<")
       (arity 2 2)
       (if (< (integer-term-value (first arguments) expression)
              (integer-term-value (second arguments) expression))
           (true-term)
           (false-term)))
      ((string= name "integer+")
       (arity 2 2)
       (make-integer-atom (+ (integer-term-value (first arguments) expression)
                             (integer-term-value (second arguments) expression))))
      ((string= name "integer<=")
       (arity 2 2)
       (if (<= (integer-term-value (first arguments) expression)
               (integer-term-value (second arguments) expression))
           (true-term)
           (false-term)))
      ((string= name "string-concat")
       (arity 2 2)
       (make-string-atom
        (concatenate 'string
                     (evaluator-string-value (first arguments) expression)
                     (evaluator-string-value (second arguments) expression))))
       ((string= name "parse-term")
        (arity 1 1)
        (labels ((failure ()
                   (term-list
                    (make-symbol-atom "parse-result")
                    (term-list (make-symbol-atom "status")
                               (make-symbol-atom "error"))
                    (term-list (make-symbol-atom "reason")
                               (make-symbol-atom "malformed-term")))))
          (handler-case
              (let ((parsed
                      (read-term
                       (evaluator-string-value (first arguments) expression))))
                (meter-primitive-arguments state (list parsed) expression depth)
                (term-list
                 (make-symbol-atom "parse-result")
                 (term-list (make-symbol-atom "status")
                            (make-symbol-atom "ok"))
                 (term-list (make-symbol-atom "value") parsed)))
            (malformed-term () (failure))
            (reader-error () (failure))
            (end-of-file () (failure)))))
      ((string= name "list")
       (term-list-from-elements arguments))
      ((string= name "append")
       (arity 2 2)
       (term-list-from-elements
        (append (proper-term-list (first arguments) expression)
                (proper-term-list (second arguments) expression))))
      ((string= name "field")
       (arity 2 2)
       (term-field (first arguments)
                   (symbol-term-name (second arguments) expression)))
      ((string= name "put-field")
       (arity 3 3)
       (put-term-field (first arguments)
                       (symbol-term-name (second arguments) expression)
                       (third arguments)))
      ((string= name "append-field")
       (arity 3 3)
       (append-term-field (first arguments)
                          (symbol-term-name (second arguments) expression)
                          (third arguments)))
      ((string= name "tag")
       (arity 1 1)
       (or (term-tag (first arguments)) (empty-term)))
      ((string= name "hash")
       (arity 1 1)
       (make-string-atom (term-hash (first arguments))))
      ((string= name "first")
       (arity 1 1)
       (or (first (proper-term-list (first arguments) expression)) (empty-term)))
      ((string= name "second")
       (arity 1 1)
       (or (second (proper-term-list (first arguments) expression)) (empty-term)))
      ((string= name "third")
       (arity 1 1)
       (or (third (proper-term-list (first arguments) expression)) (empty-term)))
      ((string= name "rest")
       (arity 1 1)
       (term-list-from-elements (rest (proper-term-list (first arguments) expression))))
      ((string= name "length")
       (arity 1 1)
       (make-integer-atom (length (proper-term-list (first arguments) expression))))
      ((string= name "find-by-field")
       (arity 3 3)
       (let ((field (symbol-term-name (second arguments) expression))
             (value (third arguments)))
         (block found
           (dolist (record (proper-term-list (first arguments) expression) (empty-term))
             (evaluator-step state expression depth)
             (when (term-equal value (term-field record field))
               (return-from found record))))))
      ((string= name "remove-by-field")
       (arity 3 3)
       (let ((field (symbol-term-name (second arguments) expression))
             (value (third arguments))
             (result nil))
         (dolist (record (proper-term-list (first arguments) expression)
                         (term-list-from-elements (nreverse result)))
           (evaluator-step state expression depth)
           (unless (term-equal value (term-field record field))
             (push record result)))))
      ((string= name "all-checks-pass")
       (arity 2 2)
       (let ((table (make-check-status-table
                     (first arguments) state expression depth)))
         (dolist (requirement (proper-term-list (second arguments) expression)
                              (true-term))
           (evaluator-step state expression depth)
           (unless (symbol-atom-name=
                    (gethash (symbol-term-name requirement expression) table) "pass")
             (return (false-term))))))
      ((string= name "first-failed-check")
       (arity 2 2)
       (let ((table (make-check-status-table
                     (first arguments) state expression depth)))
         (dolist (requirement (proper-term-list (second arguments) expression)
                              (empty-term))
           (evaluator-step state expression depth)
           (unless (symbol-atom-name=
                    (gethash (symbol-term-name requirement expression) table) "pass")
             (return requirement)))))
      ((string= name "subset?")
       (arity 2 2)
       (let ((right (make-hash-table :test #'equal)))
         (dolist (item (proper-term-list (second arguments) expression))
           (evaluator-step state expression depth)
           (setf (gethash (term-hash item) right) t))
         (dolist (item (proper-term-list (first arguments) expression) (true-term))
           (evaluator-step state expression depth)
           (unless (gethash (term-hash item) right)
             (return (false-term))))))
      ((string= name "apply-primitive")
       (arity 2 2)
       (let ((primitive (symbol-term-name (first arguments) expression))
             (nested-arguments (proper-term-list (second arguments) expression)))
         (meter-primitive-arguments state nested-arguments expression depth)
         (primitive-call primitive nested-arguments expression state depth)))
      ((string= name "term-size")
       (arity 1 1)
       (make-integer-atom (term-size (first arguments))))
      (t
       (error 'evaluation-error :expression expression
              :reason (format nil "unknown primitive ~A" name))))))

(defun meter-primitive-arguments (state arguments expression depth)
  "Charge one evaluator step per distinct canonical argument node."
  (let ((seen (make-hash-table :test #'equal))
        (stack (copy-list arguments)))
    (loop while stack
          for term = (pop stack)
          for hash = (term-hash term)
          unless (gethash hash seen)
            do (setf (gethash hash seen) t)
               (evaluator-step state expression depth)
               (when (cell-p term)
                 (push (cell-left term) stack)
                 (push (cell-right term) stack)))))

(defun ensure-intermediate-size (state value expression)
  (when (and (term-p value)
             (> (term-size value)
                (evaluation-limits-max-output-size (evaluator-state-limits state))))
    (error 'evaluation-budget-exhausted :expression expression
           :reason "intermediate size limit" :kind :output-size))
  value)

(defun ensure-term-value (value expression)
  (unless (term-p value)
    (error 'evaluation-error :expression expression
           :reason "primitive and conditional values must be terms"))
  value)

(defun apply-evaluator-closure (closure arguments expression state depth)
  (unless (evaluator-closure-p closure)
    (error 'evaluation-error :expression expression
           :reason "apply expects a lambda value"))
  (let ((parameters (evaluator-closure-parameters closure)))
    (unless (= (length parameters) (length arguments))
      (error 'evaluation-error :expression expression
             :reason (format nil "lambda expects ~D arguments, got ~D"
                             (length parameters) (length arguments))))
    (evaluate-expression
     (evaluator-closure-body closure)
     (append (mapcar #'cons parameters arguments)
             (evaluator-closure-environment closure))
     state
     (1+ depth))))

(defun evaluate-expression (expression environment state depth)
  (evaluator-step state expression depth)
  (let* ((elements (expression-elements expression))
         (name (expression-name expression)))
    (cond
      ((string= name "quote")
       (second elements))
      ((string= name "var")
       (environment-value environment
                          (symbol-term-name (second elements) expression)
                          expression))
      ((string= name "if")
       (if (term-truth-p
            (ensure-term-value
             (evaluate-expression (second elements) environment state (1+ depth))
             expression))
           (evaluate-expression (third elements) environment state (1+ depth))
           (evaluate-expression (fourth elements) environment state (1+ depth))))
      ((string= name "let*")
       (let ((extended environment))
         (dolist (binding (proper-term-list (second elements) expression))
           (let ((binding-elements (proper-term-list binding expression)))
             (push (cons (symbol-term-name (first binding-elements) binding)
                         (evaluate-expression (second binding-elements)
                                              extended state (1+ depth)))
                   extended)))
         (evaluate-expression (third elements) extended state (1+ depth))))
      ((string= name "lambda")
       (make-evaluator-closure
        (mapcar (lambda (parameter)
                  (symbol-term-name parameter expression))
                (proper-term-list (second elements) expression))
        (third elements)
        environment))
      ((string= name "letrec")
       (let* ((bindings (proper-term-list (second elements) expression))
              (slots
                (mapcar
                 (lambda (binding)
                   (let ((parts (proper-term-list binding expression)))
                     (cons (symbol-term-name (first parts) binding) nil)))
                 bindings))
              (extended (append slots environment)))
         (loop for binding in bindings
               for slot in slots
               for parts = (proper-term-list binding expression)
               for value = (evaluate-expression (second parts)
                                                extended state (1+ depth))
               do (unless (evaluator-closure-p value)
                    (error 'evaluation-error :expression (second parts)
                           :reason "letrec values must evaluate to lambdas"))
                  (setf (cdr slot) value))
         (evaluate-expression (third elements) extended state (1+ depth))))
      ((string= name "apply")
       (let ((function
               (evaluate-expression (second elements) environment state (1+ depth)))
             (arguments
               (mapcar (lambda (argument)
                         (evaluate-expression argument environment state (1+ depth)))
                       (cddr elements))))
         (evaluator-step state expression depth)
         (ensure-intermediate-size
          state
          (apply-evaluator-closure function arguments expression state depth)
          expression)))
      ((string= name "call")
       (let* ((primitive (symbol-term-name (second elements) expression))
              (arguments
                (mapcar (lambda (argument)
                          (ensure-term-value
                           (evaluate-expression argument environment state (1+ depth))
                           expression))
                        (cddr elements))))
         (evaluator-step state expression depth)
         (meter-primitive-arguments state arguments expression depth)
         (ensure-intermediate-size
          state (primitive-call primitive arguments expression state depth) expression)))
      (t
       (error 'evaluation-error :expression expression
              :reason (format nil "invalid expression form ~A" name))))))

(defun canonical-argument-name (name program)
  (handler-case
      (canonical-symbol-name name)
    (type-error ()
      (error 'evaluation-error :expression program
             :reason (format nil "invalid argument name ~S" name)))))

(defun normalize-program-arguments (program arguments parameter-names state)
  (let ((allowed (make-hash-table :test #'equal))
        (bindings (make-hash-table :test #'equal))
        (seen-conses (make-hash-table :test #'eq)))
    (dolist (name parameter-names)
      (setf (gethash name allowed) t))
    (labels ((consume-cons (cons)
               (unless (consp cons)
                 (error 'evaluation-error :expression program
                        :reason "arguments must be a proper alist or plist"))
               (when (gethash cons seen-conses)
                 (error 'evaluation-error :expression program
                        :reason "arguments contain a circular list"))
               (setf (gethash cons seen-conses) t)
               (evaluator-step state program 1))
             (record (name value)
               (let ((name (canonical-argument-name name program)))
                 (unless (term-p value)
                   (error 'evaluation-error :expression program
                          :reason "every argument value must be a term"))
                 (unless (gethash name allowed)
                   (error 'evaluation-error :expression program
                          :reason (format nil "unknown argument ~A" name)))
                 (multiple-value-bind (ignored present) (gethash name bindings)
                   (declare (ignore ignored))
                   (when present
                     (error 'evaluation-error :expression program
                            :reason "duplicate argument name")))
                 (setf (gethash name bindings) value))))
      (cond
        ((null arguments) nil)
        ((and (consp arguments) (consp (car arguments)))
         (loop with cursor = arguments
               while cursor
               do (consume-cons cursor)
                  (let ((binding (car cursor)))
                    (unless (consp binding)
                      (error 'evaluation-error :expression program
                             :reason "mixed alist and plist arguments"))
                    (record (car binding) (cdr binding)))
                  (setf cursor (cdr cursor))))
        (t
         (loop with cursor = arguments
               while cursor
               do (consume-cons cursor)
                  (let ((name (car cursor)))
                    (setf cursor (cdr cursor))
                    (when (null cursor)
                      (error 'evaluation-error :expression program
                             :reason "argument plist has an odd length"))
                    (consume-cons cursor)
                    (record name (car cursor))
                    (setf cursor (cdr cursor))))))
      bindings)))

(defun evaluate-program (program arguments &key (limits (make-evaluation-limits)))
  "Evaluate PROGRAM with an exact alist or plist of parameter names to terms.
Returns the result term and an EVALUATION-USAGE value."
  (let ((state (make-evaluator-state :limits limits)))
    (validate-program program :limits limits :state state)
    (let ((fields (evaluator-record-fields program state)))
      (multiple-value-bind (parameters-term parameters-present)
          (gethash "parameters" fields)
        (multiple-value-bind (body body-present) (gethash "body" fields)
          (unless (and parameters-present body-present)
            (error 'evaluation-error :expression program
                   :reason "program requires parameters and body fields"))
          (let* ((parameters
                   (evaluator-list-elements parameters-term state program 1))
                 (parameter-names
                   (mapcar (lambda (parameter)
                             (symbol-term-name parameter program))
                           parameters))
                 (argument-table
                   (normalize-program-arguments
                    program arguments parameter-names state))
                 (environment
                   (mapcar (lambda (name)
                             (multiple-value-bind (value present)
                                 (gethash name argument-table)
                               (unless present
                                 (error 'evaluation-error :expression program
                                        :reason (format nil
                                                        "missing term argument ~A" name)))
                               (cons name value)))
                           parameter-names))
                 (result
                   (ensure-term-value
                    (evaluate-expression body environment state 1)
                    program))
                 (output-size (term-size result)))
            (when (> output-size (evaluation-limits-max-output-size limits))
              (error 'evaluation-budget-exhausted :expression program
                     :reason "output size limit" :kind :output-size))
            (values result
                    (make-evaluation-usage
                     :steps (evaluator-state-steps state)
                     :max-depth (evaluator-state-max-depth state)
                     :output-size output-size))))))))
