;;;; src/homoiconic.lisp

(in-package #:cell-zero)

;;; The host evaluator is the immutable reduction kernel. This evaluator is an
;;; ordinary Cell Zero program term. Capsules carry it as hereditary state and
;;; use it to interpret every behavior-producing program, including itself.

(defun make-homoiconic-evaluator-program ()
  (sexp->term
   '(program
     (parameters (program arguments))
     (body
      (letrec
       ((make-binding
         (lambda (name value)
          (call list
                (quote binding)
                (call list (quote name) (var name))
                (call list (quote value) (var value)))))
        (bind-parameters
         (lambda (parameters arguments environment)
          (if (call nonempty? (var parameters))
               (apply (var bind-parameters)
                     (call rest (var parameters))
                     (call rest (var arguments))
                     (call append
                           (call list
                                  (apply (var make-binding)
                                        (call first (var parameters))
                                        (call first (var arguments))))
                           (var environment)))
              (var environment))))
        (find-definition
         (lambda (definitions name)
          (if (call nonempty? (var definitions))
              (if (call equal
                        (call first (call first (var definitions)))
                        (var name))
                  (call first (var definitions))
                   (apply (var find-definition)
                         (call rest (var definitions))
                         (var name)))
              (quote nil))))
        (make-closure
         (lambda (lambda-expression environment scope)
          (call list
                (quote closure)
                (call list
                      (quote parameters)
                      (call second (var lambda-expression)))
                (call list
                      (quote body)
                      (call third (var lambda-expression)))
                (call list (quote environment) (var environment))
                (call list (quote scope) (var scope)))))
        (lookup-scope
         (lambda (name scope)
          (if (call present? (var scope))
              (let* ((definition
                        (apply (var find-definition)
                              (call field (var scope) (quote bindings))
                              (var name))))
                (if (call present? (var definition))
                     (apply (var make-closure)
                           (call second (var definition))
                           (call field (var scope) (quote environment))
                           (var scope))
                     (apply (var lookup-scope)
                           (var name)
                           (call field (var scope) (quote parent)))))
              (quote absent))))
        (lookup
         (lambda (name environment scope)
          (let* ((binding
                   (call find-by-field
                         (var environment)
                         (quote name)
                         (var name))))
            (if (call present? (var binding))
                (call field (var binding) (quote value))
                 (apply (var lookup-scope) (var name) (var scope))))))
        (eval-list
         (lambda (expressions environment scope)
          (if (call nonempty? (var expressions))
              (call append
                    (call list
                           (apply (var eval)
                                 (call first (var expressions))
                                 (var environment)
                                 (var scope)))
                     (apply (var eval-list)
                           (call rest (var expressions))
                           (var environment)
                           (var scope)))
              (quote nil))))
        (eval-bindings
         (lambda (bindings body environment scope)
          (if (call nonempty? (var bindings))
              (let* ((binding (call first (var bindings)))
                     (value
                        (apply (var eval)
                              (call second (var binding))
                              (var environment)
                              (var scope)))
                     (next-environment
                       (call append
                             (call list
                                    (apply (var make-binding)
                                          (call first (var binding))
                                          (var value)))
                             (var environment))))
                 (apply (var eval-bindings)
                       (call rest (var bindings))
                       (var body)
                       (var next-environment)
                       (var scope)))
               (apply (var eval) (var body) (var environment) (var scope)))))
        (apply-closure
         (lambda (closure arguments)
          (let* ((environment
                    (apply (var bind-parameters)
                          (call field (var closure) (quote parameters))
                          (var arguments)
                          (call field (var closure) (quote environment)))))
             (apply (var eval)
                   (call field (var closure) (quote body))
                   (var environment)
                   (call field (var closure) (quote scope))))))
        (eval
         (lambda (expression environment scope)
          (let* ((form (call tag (var expression))))
            (if (call equal (var form) (quote quote))
                (call second (var expression))
                (if (call equal (var form) (quote var))
                     (apply (var lookup)
                           (call second (var expression))
                           (var environment)
                           (var scope))
                    (if (call equal (var form) (quote if))
                         (if (apply (var eval)
                                   (call second (var expression))
                                   (var environment)
                                   (var scope))
                             (apply (var eval)
                                   (call third (var expression))
                                   (var environment)
                                   (var scope))
                             (apply (var eval)
                                   (call first
                                         (call rest
                                               (call rest
                                                     (call rest
                                                           (var expression)))))
                                   (var environment)
                                   (var scope)))
                        (if (call equal (var form) (quote let*))
                             (apply (var eval-bindings)
                                   (call second (var expression))
                                   (call third (var expression))
                                   (var environment)
                                   (var scope))
                            (if (call equal (var form) (quote lambda))
                                 (apply (var make-closure)
                                       (var expression)
                                       (var environment)
                                       (var scope))
                                (if (call equal (var form) (quote letrec))
                                    (let* ((next-scope
                                             (call list
                                                   (quote scope)
                                                   (call list
                                                         (quote bindings)
                                                         (call second
                                                               (var expression)))
                                                   (call list
                                                         (quote environment)
                                                         (var environment))
                                                   (call list
                                                         (quote parent)
                                                         (var scope)))))
                                       (apply (var eval)
                                             (call third (var expression))
                                             (var environment)
                                             (var next-scope)))
                                    (if (call equal (var form) (quote apply))
                                         (apply (var apply-closure)
                                                (apply (var eval)
                                                      (call second
                                                            (var expression))
                                                      (var environment)
                                                      (var scope))
                                                (apply (var eval-list)
                                                      (call rest
                                                            (call rest
                                                                  (var expression)))
                                                      (var environment)
                                                      (var scope)))
                                        (if (call equal (var form) (quote call))
                                            (call apply-primitive
                                                  (call second (var expression))
                                                   (apply (var eval-list)
                                                         (call rest
                                                               (call rest
                                                                     (var expression)))
                                                         (var environment)
                                                         (var scope)))
                                            (call list
                                                  (quote evaluation-error)
                                                  (call list
                                                        (quote expression)
                                                        (var expression)))))))))))))))
       (let* ((parameters (call field (var program) (quote parameters)))
              (body (call field (var program) (quote body)))
              (environment
                 (apply (var bind-parameters)
                       (var parameters)
                       (var arguments)
                       (quote nil))))
          (apply (var eval) (var body) (var environment) (quote nil))))))))

(defun homoiconic-program-parameter-names (program)
  (mapcar #'symbol-term-name
          (term-list-elements (required-field program "parameters"))
          (make-list (length (term-list-elements
                              (required-field program "parameters")))
                     :initial-element program)))

(defun homoiconic-argument-values (program arguments)
  (let ((parameters (homoiconic-program-parameter-names program)))
    (mapcar
     (lambda (name)
       (let ((binding (assoc name arguments
                             :test (lambda (left right)
                                     (string= left (canonical-symbol-name right))))))
         (unless (and binding (term-p (cdr binding)))
           (error 'evaluation-error :expression program
                  :reason (format nil "missing term argument ~A" name)))
         (cdr binding)))
     parameters)))

(defun evaluate-homoiconic-program
    (evaluator program arguments
     &key (limits (make-evaluation-limits
                   :max-steps 1000000
                   :max-depth 1024
                   :max-output-size 1000000)))
  "Use the hereditary EVALUATOR term to execute PROGRAM.
PROGRAM and EVALUATOR share one homoiconic syntax. ARGUMENTS is an alist."
  (evaluate-program
   evaluator
   (list (cons 'program program)
         (cons 'arguments
               (term-list-from-elements
                (homoiconic-argument-values program arguments))))
   :limits limits))

(defun homoiconic-evaluator-self-check ()
  "Return true when the evaluator produces the same result directly and through itself."
  (let* ((evaluator (make-homoiconic-evaluator-program))
         (sample
           (sexp->term
            '(program
              (parameters (x))
              (body (call integer+ (var x) (quote 1))))))
         (argument (make-integer-atom 4))
         (argument-values (term-list argument))
         (direct
           (evaluate-homoiconic-program
            evaluator sample (list (cons 'x argument))))
         (self-interpreted
           (evaluate-homoiconic-program
            evaluator evaluator
            (list (cons 'program sample)
                  (cons 'arguments argument-values)))))
    (and (term-equal direct self-interpreted)
         (= 5 (integer-term-value/protocol direct)))))


;;; Cell-zero/2 capsule protocol

(defun %h-effect (id capability request budget)
  (%tagged 'effect
           (list 'id id)
           (list 'capability (%q capability))
           (list 'request request)
           (list 'budget budget)))

(defun %h-pending (id kind &rest fields)
  (apply #'%tagged 'pending
         (append (list (list 'id id)
                       (list 'kind (%q kind)))
                 fields)))

(defun %h-transition (capsule outputs effects successor)
  (%tagged 'transition
           (list 'capsule capsule)
           (list 'outputs outputs)
           (list 'effects effects)
           (list 'successor successor)))

(defun %h-replace-capsule-state (capsule state)
  (%put-field capsule 'state state))

(defun %h-record-event (state event)
  (%append-field state 'history event))

(defun %h-remove-pending (state event effect-id)
  (%put-field
   (%h-record-event state event)
   'pending
   (%call 'remove-by-field (%field state 'pending) (%q 'id) effect-id)))

(defun %h-task-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (policy ,(%field (%v 'capsule) 'policy))
     (id ,(%field (%v 'state) 'next-effect-id))
     (pending ,(%h-pending (%v 'id) 'task))
     (next-state
      ,(%put-field
        (%append-field (%h-record-event (%v 'state) (%v 'event))
                       'pending (%v 'pending))
        'next-effect-id
        (%call 'integer+ (%v 'id) (%q 1))))
     (next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'next-state)))
     (request
       ,(%tagged 'solve
                 (list 'instruction (%field (%v 'event) 'instruction))
                 (list 'self (%v 'capsule))
                 (list 'context (%field (%v 'policy) 'task-context))
                 (list 'prompt
                       (%call 'string-concat
                              (%field (%v 'policy) 'task-context)
                              (%call 'string-concat
                                     (%q (format nil "~%~%Task:~%"))
                                    (%field (%v 'event) 'instruction))))))
     (effect
      ,(%h-effect (%v 'id) 'model (%v 'request)
                  (%field (%v 'policy) 'model-budget))))
    (%h-transition (%v 'next-capsule) (%q nil) (%list (%v 'effect)) (%q nil))))

(defun %h-evolve-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (policy ,(%field (%v 'capsule) 'policy))
     (id ,(%field (%v 'state) 'next-effect-id))
     (pending
      ,(%h-pending (%v 'id) 'proposal
                   (list 'parent (%v 'capsule))
                   (list 'objective (%field (%v 'event) 'objective))))
     (next-state
      ,(%put-field
        (%append-field (%h-record-event (%v 'state) (%v 'event))
                       'pending (%v 'pending))
        'next-effect-id
        (%call 'integer+ (%v 'id) (%q 1))))
     (next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'next-state)))
     (request
      ,(%tagged 'propose-successor
                (list 'self (%v 'capsule))
                (list 'objective (%field (%v 'event) 'objective))
                (list 'probe (%field (%v 'policy) 'probe))
                (list 'abi (%q 'cell-zero/2))))
     (effect
      ,(%h-effect (%v 'id) 'model (%v 'request)
                  (%field (%v 'policy) 'model-budget))))
    (%h-transition (%v 'next-capsule) (%q nil) (%list (%v 'effect)) (%q nil))))

(defun %h-task-result-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (effect-id ,(%field (%v 'event) 'effect-id))
     (next-state ,(%h-remove-pending (%v 'state) (%v 'event) (%v 'effect-id)))
     (next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'next-state))))
   (%h-transition (%v 'next-capsule)
                  (%list (%field (%v 'event) 'response))
                  (%q nil)
                  (%q nil))))

(defun %h-proposal-result-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (policy ,(%field (%v 'capsule) 'policy))
     (effect-id ,(%field (%v 'event) 'effect-id))
     (pending
      ,(%call 'find-by-field (%field (%v 'state) 'pending)
              (%q 'id) (%v 'effect-id)))
     (parent ,(%field (%v 'pending) 'parent))
     (candidate ,(%field (%field (%v 'event) 'response) 'candidate))
     (base-state ,(%h-remove-pending (%v 'state) (%v 'event) (%v 'effect-id))))
   (%if
    (%call 'present? (%v 'candidate))
    (%let*
     `((parent-id ,(%field (%v 'base-state) 'next-effect-id))
       (candidate-id ,(%call 'integer+ (%v 'parent-id) (%q 1)))
       (parent-pending
        ,(%h-pending (%v 'parent-id) 'trial
                     (list 'role (%q 'parent))))
       (candidate-pending
        ,(%h-pending (%v 'candidate-id) 'trial
                     (list 'role (%q 'candidate))))
       (next-state-1
        ,(%append-field
          (%append-field (%v 'base-state) 'pending (%v 'parent-pending))
          'pending (%v 'candidate-pending)))
       (next-state-2 ,(%put-field (%v 'next-state-1) 'candidate (%v 'candidate)))
       (next-state-3 ,(%put-field (%v 'next-state-2) 'evolution-parent (%v 'parent)))
       (next-state-4 ,(%put-field (%v 'next-state-3) 'parent-trace (%q 'absent)))
       (next-state-5 ,(%put-field (%v 'next-state-4) 'candidate-trace (%q 'absent)))
       (next-state
        ,(%put-field (%v 'next-state-5) 'next-effect-id
                     (%call 'integer+ (%v 'parent-id) (%q 2))))
       (next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'next-state)))
       (parent-request
        ,(%tagged 'run
                  (list 'capsule (%v 'parent))
                  (list 'event (%field (%v 'policy) 'probe))))
       (candidate-request
        ,(%tagged 'run
                  (list 'capsule (%v 'candidate))
                  (list 'event (%field (%v 'policy) 'probe))))
       (parent-effect
        ,(%h-effect (%v 'parent-id) 'runner (%v 'parent-request)
                    (%field (%v 'policy) 'runner-budget)))
       (candidate-effect
        ,(%h-effect (%v 'candidate-id) 'runner (%v 'candidate-request)
                    (%field (%v 'policy) 'runner-budget))))
     (%h-transition (%v 'next-capsule) (%q nil)
                    (%list (%v 'parent-effect) (%v 'candidate-effect))
                    (%q nil)))
    (%let*
     `((next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'base-state)))
       (rejection ,(%tagged 'selection
                            (list 'decision (%q 'retain))
                            (list 'reason (%q 'missing-candidate)))))
     (%h-transition (%v 'next-capsule) (%list (%v 'rejection))
                    (%q nil) (%v 'next-capsule))))))

(defun %h-trial-result-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (policy ,(%field (%v 'capsule) 'policy))
     (effect-id ,(%field (%v 'event) 'effect-id))
     (pending
      ,(%call 'find-by-field (%field (%v 'state) 'pending)
              (%q 'id) (%v 'effect-id)))
     (role ,(%field (%v 'pending) 'role))
     (trace ,(%field (%v 'event) 'response))
     (base-state ,(%h-remove-pending (%v 'state) (%v 'event) (%v 'effect-id)))
     (next-state
      ,(%if (%call 'equal (%v 'role) (%q 'parent))
            (%put-field (%v 'base-state) 'parent-trace (%v 'trace))
            (%put-field (%v 'base-state) 'candidate-trace (%v 'trace))))
     (parent-trace ,(%field (%v 'next-state) 'parent-trace))
     (candidate-trace ,(%field (%v 'next-state) 'candidate-trace)))
   (%if
    (%if (%call 'present? (%v 'parent-trace))
         (%call 'present? (%v 'candidate-trace))
         (%q 'false))
    (%let*
     `((candidate ,(%field (%v 'next-state) 'candidate))
       (parent-score ,(%field (%v 'parent-trace) 'score))
       (candidate-score ,(%field (%v 'candidate-trace) 'score))
       (completed ,(%field (%v 'candidate-trace) 'completed))
       (better
        ,(%if (%field (%v 'policy) 'accept-equal)
              (%call 'integer<= (%v 'parent-score) (%v 'candidate-score))
              (%call 'integer< (%v 'parent-score) (%v 'candidate-score))))
       (accepted ,(%if (%v 'completed) (%v 'better) (%q 'false)))
       (cleared-1 ,(%put-field (%v 'next-state) 'candidate (%q 'absent)))
       (cleared-2 ,(%put-field (%v 'cleared-1) 'evolution-parent (%q 'absent)))
       (cleared-3 ,(%put-field (%v 'cleared-2) 'parent-trace (%q 'absent)))
       (cleared-state ,(%put-field (%v 'cleared-3) 'candidate-trace (%q 'absent)))
       (parent-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'cleared-state)))
       (successor ,(%if (%v 'accepted) (%v 'candidate) (%v 'parent-capsule)))
       (selection
        ,(%tagged 'selection
                  (list 'decision (%if (%v 'accepted) (%q 'promote) (%q 'retain)))
                  (list 'parent-score (%v 'parent-score))
                  (list 'candidate-score (%v 'candidate-score)))))
     (%h-transition (%v 'parent-capsule) (%list (%v 'selection))
                    (%q nil) (%v 'successor)))
    (%let*
     `((next-capsule ,(%h-replace-capsule-state (%v 'capsule) (%v 'next-state))))
      (%h-transition (%v 'next-capsule) (%q nil) (%q nil) (%q nil))))))

(defun %h-effect-result-expression ()
  (%let*
   `((state ,(%field (%v 'capsule) 'state))
     (effect-id ,(%field (%v 'event) 'effect-id))
     (pending
      ,(%call 'find-by-field (%field (%v 'state) 'pending)
              (%q 'id) (%v 'effect-id)))
     (kind ,(%field (%v 'pending) 'kind)))
   (%if (%call 'equal (%v 'kind) (%q 'task))
        (%h-task-result-expression)
        (%if (%call 'equal (%v 'kind) (%q 'proposal))
             (%h-proposal-result-expression)
             (%if (%call 'equal (%v 'kind) (%q 'trial))
                  (%h-trial-result-expression)
                  (%h-transition (%v 'capsule) (%q nil) (%q nil) (%q nil)))))))

(defun make-homoiconic-step-program ()
  (sexp->term
   `(program
     (parameters (capsule event))
     (body
      ,(%let*
        `((kind ,(%field (%v 'event) 'kind)))
        (%if (%call 'equal (%v 'kind) (%q 'task))
             (%h-task-expression)
             (%if (%call 'equal (%v 'kind) (%q 'evolve))
                  (%h-evolve-expression)
                  (%if (%call 'equal (%v 'kind) (%q 'effect-result))
                       (%h-effect-result-expression)
                       (%h-transition (%v 'capsule) (%q nil)
                                      (%q nil) (%q nil))))))))))

(defun make-homoiconic-genesis-capsule
    (&key (accept-equal nil)
          (task-context "Solve the task in the attached environment."))
  (let ((evaluator (make-homoiconic-evaluator-program))
        (step (make-homoiconic-step-program)))
    (sexp->term
     `(capsule
       (abi cell-zero/2)
       (evaluator ,(term->sexp evaluator))
       (step ,(term->sexp step))
       (state
        (state
         (next-effect-id 0)
         (pending ())
         (history ())
         (candidate absent)
         (evolution-parent absent)
         (parent-trace absent)
         (candidate-trace absent)))
       (policy
        (policy
         (task-context ,task-context)
         (probe (event (kind task) (instruction "probe")))
         (model-budget (budget (max-effects 1)))
         (runner-budget
          (budget (max-effects 32) (max-events 256) (max-eval-steps 5000000)))
         (accept-equal ,(if accept-equal 'true 'false))))
       (capabilities (model runner))))))


(defun capsule-evaluator (capsule)
  (required-field capsule "evaluator"))

(defun capsule-step-program (capsule)
  (required-field capsule "step"))

(defun capsule-state (capsule)
  (required-field capsule "state"))

(defun capsule-policy (capsule)
  (required-field capsule "policy"))

(defun capsule-capability-names (capsule)
  (term-list-names (required-field capsule "capabilities")))

(defun capsule-valid-p (capsule)
  "Return true when CAPSULE is a closed, loadable Cell-zero/2 organism."
  (handler-case
      (let* ((abi (required-field capsule "abi"))
             (evaluator (capsule-evaluator capsule))
             (step (capsule-step-program capsule))
             (evaluator-parameters
               (homoiconic-program-parameter-names evaluator))
             (step-parameters (homoiconic-program-parameter-names step)))
        (unless (and (tagged-term-p capsule "capsule")
                     (symbol-atom-name= abi "cell-zero/2")
                     (tagged-term-p evaluator "program")
                     (equal evaluator-parameters '("program" "arguments"))
                     (tagged-term-p step "program")
                     (equal step-parameters '("capsule" "event")))
          (error 'protocol-error :datum capsule :reason "invalid Cell-zero/2 envelope"))
        (capsule-state capsule)
        (capsule-policy capsule)
        (capsule-capability-names capsule)
        (validate-program
         evaluator
         :limits (make-evaluation-limits
                  :max-steps 2000000
                  :max-depth 2048
                  :max-output-size 2000000))
        t)
    (cell-zero-error () nil)
    (error () nil)))

(defclass homoiconic-cell ()
  ((store :initarg :store :reader homoiconic-cell-store)
   (initial-root :initarg :initial-root :reader homoiconic-cell-initial-root)
   (current-root :initarg :current-root :accessor homoiconic-cell-current-root)
   (handlers :initform (make-hash-table :test #'equal)
             :reader homoiconic-cell-handlers)
   (capability-grant :initarg :capability-grant
                     :reader homoiconic-cell-capability-grant)
   (effect-queue :initform nil :accessor homoiconic-cell-effect-queue)
   (outputs :initform nil :accessor homoiconic-cell-outputs)
   (trace :initform nil :accessor homoiconic-cell-trace)
   (lineage :initform nil :accessor homoiconic-cell-lineage)
   (evaluation-steps :initform 0 :accessor homoiconic-cell-evaluation-steps)
   (limits :initarg :limits :reader homoiconic-cell-limits)))

(defun homoiconic-cell-current-capsule (cell)
  (store-get (homoiconic-cell-store cell)
             (homoiconic-cell-current-root cell)))

(defun make-homoiconic-cell
    (store capsule-or-root
     &key capabilities handlers
       (limits (make-evaluation-limits
                :max-steps 5000000
                :max-depth 2048
                :max-output-size 2000000)))
  (let ((capsule (if (stringp capsule-or-root)
                     (store-get store capsule-or-root)
                     capsule-or-root)))
    (unless (capsule-valid-p capsule)
      (error 'protocol-error :datum capsule :reason "invalid Cell-zero/2 capsule"))
    (let* ((root (store-put store capsule))
           (cell
             (make-instance
              'homoiconic-cell
              :store store
              :initial-root root
              :current-root root
              :capability-grant
              (mapcar #'canonical-symbol-name
                      (or capabilities (capsule-capability-names capsule)))
              :limits limits)))
      (dolist (binding handlers)
        (register-homoiconic-handler cell (car binding) (cdr binding)))
      cell)))

(defun register-homoiconic-handler (cell capability function)
  (unless (functionp function)
    (error 'protocol-error :datum function :reason "handler is not callable"))
  (setf (gethash (canonical-symbol-name capability)
                 (homoiconic-cell-handlers cell))
        function)
  cell)

(defun homoiconic-capability-allowed-p (cell capsule capability)
  (and (member capability (homoiconic-cell-capability-grant cell) :test #'string=)
       (member capability (capsule-capability-names capsule) :test #'string=)))

(defun valid-homoiconic-effect-p (effect)
  (handler-case
      (progn
        (unless (tagged-term-p effect "effect")
          (error 'protocol-error :datum effect :reason "effect tag is missing"))
        (integer-term-value/protocol (required-field effect "id"))
        (symbol-term-value (required-field effect "capability"))
        (required-field effect "request")
        (required-field effect "budget")
        t)
    (cell-zero-error () nil)))

(defun seal-homoiconic-effect (capsule-root capsule effect)
  (unless (valid-homoiconic-effect-p effect)
    (error 'protocol-error :datum effect :reason "malformed capsule effect"))
  (put-term-field
   effect
   "context"
   (make-tagged-term
    "context"
    (make-field "capsule" (make-string-atom capsule-root))
    (make-field "evaluator"
                (make-string-atom (term-hash (capsule-evaluator capsule)))))))

(defun valid-homoiconic-transition-p (transition)
  (handler-case
      (progn
        (unless (tagged-term-p transition "transition")
          (error 'protocol-error :datum transition :reason "transition tag is missing"))
        (required-field transition "capsule")
        (term-list-elements (required-field transition "outputs"))
        (term-list-elements (required-field transition "effects"))
        (required-field transition "successor")
        t)
    (cell-zero-error () nil)))

(defun append-homoiconic-trace (cell type datum)
  (let ((entry
          (make-tagged-term
           "trace-entry"
           (make-field "type" (make-symbol-atom type))
           (make-field "datum" datum)
           (make-field "hash" (make-string-atom (term-hash datum))))))
    (store-put (homoiconic-cell-store cell) entry)
    (setf (homoiconic-cell-trace cell)
          (append (homoiconic-cell-trace cell) (list entry)))
    entry))

(defun append-homoiconic-lineage (cell parent-root successor-root decision)
  (let ((entry
          (make-tagged-term
           "generation"
           (make-field "parent" (make-string-atom parent-root))
           (make-field "successor" (make-string-atom successor-root))
           (make-field "decision" (make-symbol-atom decision)))))
    (store-put (homoiconic-cell-store cell) entry)
    (setf (homoiconic-cell-lineage cell)
          (append (homoiconic-cell-lineage cell) (list entry)))
    entry))

(defun invoke-homoiconic-step (capsule event limits)
  (evaluate-homoiconic-program
   (capsule-evaluator capsule)
   (capsule-step-program capsule)
   (list (cons 'capsule capsule)
         (cons 'event event))
   :limits limits))

(defun submit-homoiconic-event (cell event)
  "Run EVENT through the evaluator and step program carried by the active capsule."
  (unless (tagged-term-p event "event")
    (error 'protocol-error :datum event :reason "event tag is missing"))
  (let* ((store (homoiconic-cell-store cell))
         (parent-root (homoiconic-cell-current-root cell))
         (capsule (homoiconic-cell-current-capsule cell)))
    (multiple-value-bind (transition usage)
        (invoke-homoiconic-step capsule event (homoiconic-cell-limits cell))
      (incf (homoiconic-cell-evaluation-steps cell) (usage-steps usage))
      (unless (valid-homoiconic-transition-p transition)
        (error 'protocol-error :datum transition :reason "malformed capsule transition"))
      (let* ((updated (required-field transition "capsule"))
             (outputs (term-list-elements (required-field transition "outputs")))
             (effects (term-list-elements (required-field transition "effects")))
             (successor (required-field transition "successor")))
        (unless (capsule-valid-p updated)
          (error 'protocol-error :datum updated :reason "transition returned invalid capsule"))
        (let ((updated-root (store-put store updated)))
          (setf (homoiconic-cell-current-root cell) updated-root)
          (setf (homoiconic-cell-outputs cell)
                (append (homoiconic-cell-outputs cell) outputs))
          (setf (homoiconic-cell-effect-queue cell)
                (append
                 (homoiconic-cell-effect-queue cell)
                 (mapcar (lambda (effect)
                           (seal-homoiconic-effect updated-root updated effect))
                         effects)))
          (append-homoiconic-trace cell "event" event)
          (append-homoiconic-trace cell "transition" transition)
          (when (term-truth-p successor)
            (if (capsule-valid-p successor)
                (let ((successor-root (store-put store successor)))
                  (setf (homoiconic-cell-current-root cell) successor-root)
                  (append-homoiconic-lineage
                   cell parent-root successor-root "selected"))
                (append-homoiconic-lineage
                 cell parent-root updated-root "structurally-rejected")))
          transition)))))

(defun homoiconic-effect-result-event (effect status response)
  (make-tagged-term
   "event"
   (make-field "kind" (make-symbol-atom "effect-result"))
   (make-field "effect-id" (required-field effect "id"))
   (make-field "request-hash" (make-string-atom (term-hash effect)))
   (make-field "capability" (required-field effect "capability"))
   (make-field "status" (make-symbol-atom status))
   (make-field "response" response)))

(defun process-next-homoiconic-effect (cell)
  (let ((effect (pop (homoiconic-cell-effect-queue cell))))
    (when effect
      (let* ((capsule (homoiconic-cell-current-capsule cell))
             (capability (symbol-term-value (required-field effect "capability")))
             (handler (gethash capability (homoiconic-cell-handlers cell))))
        (cond
          ((not (homoiconic-capability-allowed-p cell capsule capability))
           (submit-homoiconic-event
            cell
            (homoiconic-effect-result-event
             effect "denied"
             (make-tagged-term
              "failure"
              (make-field "reason" (make-symbol-atom "capability-denied"))))))
          ((null handler)
           (submit-homoiconic-event
            cell
            (homoiconic-effect-result-event
             effect "denied"
             (make-tagged-term
              "failure"
              (make-field "reason" (make-symbol-atom "no-handler"))))))
          (t
           (multiple-value-bind (status response ignored-usage)
               (funcall handler
                        cell
                        (required-field effect "request")
                        (required-field effect "budget")
                        effect)
             (declare (ignore ignored-usage))
             (unless (term-p response)
               (error 'protocol-error :datum response
                      :reason "handler response is not a term"))
             (submit-homoiconic-event
              cell
              (homoiconic-effect-result-event
               effect (canonical-symbol-name (or status "ok")) response))))))
      t)))

(defun run-homoiconic-until-idle (cell &key (max-effects 1000))
  (loop repeat max-effects
        while (homoiconic-cell-effect-queue cell)
        do (process-next-homoiconic-effect cell)
        finally
           (when (homoiconic-cell-effect-queue cell)
             (error 'resource-budget-exhausted :datum cell
                    :reason "homoiconic effect limit" :kind :effects)))
  cell)

(defun make-scripted-homoiconic-model-handler
    (candidate &key (answer (sexp->term '(answer (status completed)))))
  (lambda (cell request budget effect)
    (declare (ignore cell budget effect))
    (cond
      ((tagged-term-p request "propose-successor")
       (values "ok"
               (make-tagged-term
                "proposal"
                (make-field "candidate" candidate))))
      ((tagged-term-p request "solve")
       (values "ok" answer))
      (t
       (values "error"
               (make-tagged-term
                "failure"
                (make-field "reason" (make-symbol-atom "unknown-request"))))))))

(defun make-scripted-homoiconic-runner-handler (score-function)
  (lambda (cell request budget effect)
    (declare (ignore cell budget effect))
    (let ((capsule (required-field request "capsule"))
          (event (required-field request "event")))
      (multiple-value-bind (completed score output)
          (funcall score-function capsule event)
        (values
         "ok"
         (make-tagged-term
          "runner-trace"
          (make-field "completed"
                      (if completed (true-term) (false-term)))
          (make-field "score" (make-integer-atom score))
          (make-field "output" (if (term-p output) output (empty-term)))))))))


(defun homoiconic-task-request (capsule instruction)
  "Return the model capability request authored by CAPSULE for INSTRUCTION."
  (let ((event
          (make-tagged-term
           "event"
           (make-field "kind" (make-symbol-atom "task"))
           (make-field "instruction" (make-string-atom instruction)))))
    (multiple-value-bind (transition usage)
        (invoke-homoiconic-step
         capsule event
         (make-evaluation-limits
          :max-steps 5000000
          :max-depth 2048
          :max-output-size 2000000))
      (declare (ignore usage))
      (let* ((effects (term-list-elements (required-field transition "effects")))
             (effect (first effects)))
        (unless effect
          (error 'protocol-error :datum transition
                 :reason "task transition did not request a capability"))
        (required-field effect "request")))))

(defun homoiconic-task-prompt (capsule instruction)
  "Return the prompt string generated inside CAPSULE for INSTRUCTION."
  (string-term-value
   (required-field (homoiconic-task-request capsule instruction) "prompt")))
