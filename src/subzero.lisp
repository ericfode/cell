;;;; src/subzero.lisp

(in-package #:cell-zero)

(define-condition protocol-error (cell-zero-error)
  ((reason :initarg :reason :reader protocol-error-reason)
   (datum :initarg :datum :initform nil :reader protocol-error-datum))
  (:report (lambda (condition stream)
             (format stream "Cell-zero protocol error: ~A" (protocol-error-reason condition)))))


(define-condition resource-budget-exhausted (protocol-error)
  ((kind :initarg :kind :reader resource-budget-kind))
  (:report (lambda (condition stream)
             (format stream "Cell-zero ~A resource budget exhausted"
                     (resource-budget-kind condition)))))

(defun tagged-term-p (term tag)
  (and (cell-p term) (symbol-atom-name= (term-tag term) tag)))

(defun required-field (term name)
  (let ((value (term-field term name (make-symbol-atom "absent"))))
    (when (symbol-atom-name= value "absent")
      (error 'protocol-error :datum term
             :reason (format nil "missing field ~A" name)))
    value))

(defun string-term-value (term)
  (unless (and (atom-p term) (eq (atom-kind term) :string))
    (error 'protocol-error :datum term :reason "expected a string atom"))
  (atom-value term))

(defun integer-term-value/protocol (term)
  (unless (and (atom-p term) (eq (atom-kind term) :integer))
    (error 'protocol-error :datum term :reason "expected an integer atom"))
  (atom-value term))

(defun symbol-term-value (term)
  (unless (and (atom-p term) (eq (atom-kind term) :symbol))
    (error 'protocol-error :datum term :reason "expected a symbol atom"))
  (atom-value term))

(defun make-field (name value)
  (term-list (make-symbol-atom name) value))

(defun make-tagged-term (tag &rest fields)
  (apply #'term-list (make-symbol-atom tag) fields))

(defun make-list-term (terms)
  (apply #'term-list terms))

(defun status-pair (name status)
  (term-list (make-symbol-atom name) (make-symbol-atom status)))

(defun checks-term (&rest checks)
  (make-list-term
   (mapcar (lambda (check)
             (status-pair (first check) (second check)))
           checks)))

(defun term-list-names (term)
  (mapcar #'symbol-term-value (term-list-elements term)))

(defun names-term (names)
  (make-list-term (mapcar #'make-symbol-atom names)))

(defun world-genome (world)
  (required-field world "genome"))

(defun world-state (world)
  (required-field world "state"))

(defun genome-abi-name (genome)
  (symbol-term-value (required-field genome "abi")))

(defun genome-react (genome)
  (if (string= (genome-abi-name genome) "genome/v1")
      (source-genome-react-entry-point genome)
      (required-field genome "react")))

(defun genome-admit (genome)
  (if (string= (genome-abi-name genome) "genome/v1")
      (source-genome-admit-entry-point genome)
      (required-field genome "admit")))

(defun genome-data (genome)
  (required-field genome "data"))

(defun genome-hash (genome)
  (term-hash genome))

(defun world-capability-names (world)
  (handler-case
      (term-list-names (term-field (genome-data (world-genome world)) "capabilities"))
    (cell-zero-error () nil)))

(defun world-valid-p (world &key (load-p t))
  "Return true when WORLD satisfies a supported immutable genome envelope."
  (handler-case
      (progn
        (unless (tagged-term-p world "world")
          (error 'protocol-error :datum world :reason "world tag is missing"))
        (let* ((genome (world-genome world))
               (state (world-state world))
               (abi (genome-abi-name genome))
               (data (genome-data genome)))
          (declare (ignore state data))
          (unless (tagged-term-p genome "genome")
            (error 'protocol-error :datum genome :reason "genome tag is missing"))
          (cond
            ((string= abi "cell-zero/1")
             (validate-program (genome-react genome))
             (validate-program (genome-admit genome)))
            ((string= abi "genome/v1")
             (unless (source-genome-valid-p genome)
               (error 'protocol-error :datum genome
                      :reason "invalid genome/v1 source bundle"))
             (when (and load-p (not (source-genome-loads-p genome)))
               (error 'protocol-error :datum genome
                      :reason "genome/v1 source bundle failed to load")))
            (t
             (error 'protocol-error :datum genome :reason "unsupported genome ABI")))
          t))
    (cell-zero-error () nil)
    (error () nil)))

(defun replace-world-state (world state)
  (make-tagged-term
   "world"
   (make-field "genome" (world-genome world))
   (make-field "state" state)))

(defclass subzero ()
  ((store :initarg :store :reader subzero-store)
   (event-database :initarg :event-database :initform nil
                   :reader subzero-event-database)
   (event-scope :initarg :event-scope :reader subzero-event-scope)
   (event-parent-scope :initarg :event-parent-scope :initform nil
                       :reader subzero-event-parent-scope)
   (initial-root :initarg :initial-root :reader subzero-initial-root)
   (current-root :initarg :current-root :accessor subzero-current-root)
   (entries :initform nil :accessor subzero-entries)
   (lineage :initform nil :accessor subzero-lineage)
   (traces :initform nil :accessor subzero-trace-roots)
   (trace-registry :initform (make-hash-table :test #'equal)
                   :reader subzero-trace-registry)
   (handlers :initform (make-hash-table :test #'equal)
             :reader subzero-handlers)
   (capability-grant :initarg :capability-grant :reader subzero-capability-grant)
   (effect-queue :initform nil :accessor subzero-effect-queue)
     (pending-effect :initform nil :accessor subzero-pending-effect)
   (outputs :initform nil :accessor subzero-outputs)
   (violations :initform nil :accessor subzero-violations)
   (handler-calls :initform 0 :accessor subzero-handler-calls)
   (effect-count :initform 0 :accessor subzero-effect-count)
   (evaluation-steps :initform 0 :accessor subzero-evaluation-steps)
   (max-effects :initarg :max-effects :initform most-positive-fixnum
                :reader subzero-max-effects)
   (max-events :initarg :max-events :initform most-positive-fixnum
               :reader subzero-max-events)
   (max-eval-steps :initarg :max-eval-steps :initform most-positive-fixnum
                   :reader subzero-max-eval-steps)
   (ref-name :initarg :name :initform nil :reader subzero-ref-name)
   (manifest-root :initform nil :accessor subzero-manifest-root)
   (manifest-generation :initform 0 :accessor subzero-manifest-generation)
   (mode :initarg :mode :initform :live :reader subzero-mode)))

(defun ensure-subzero-event-database-store (store database)
  (when database
    (unless (typep database 'event-database)
      (error 'protocol-error :datum database :reason "EVENT-DATABASE is not an event database"))
    (unless (eq store (event-db-store database))
      (error 'protocol-error :datum database
             :reason "Subzero and its event database must share the same term store")))
  database)

(defun call-event-database-observer (operation thunk)
  (handler-case
      (funcall thunk)
    (error (condition)
      (warn "Event database observer ~A failed without altering Subzero authority: ~A"
            operation condition)
      nil)))

(defun make-subzero (store world-or-root
                     &key capabilities handlers (mode :live) name
                        event-database event-scope event-parent-scope
                       (max-effects most-positive-fixnum)
                       (max-events most-positive-fixnum)
                       (max-eval-steps most-positive-fixnum))
  (ensure-subzero-event-database-store store event-database)
  (let* ((world (if (stringp world-or-root)
                    (store-get store world-or-root)
                    world-or-root)))
    (unless (world-valid-p world)
      (error 'protocol-error :datum world :reason "initial world has no supported genome ABI"))
    (let* ((root (store-put store world))
           (grant (mapcar #'canonical-symbol-name
                          (or capabilities (world-capability-names world))))
           (scope (or event-scope
                      (format nil "subzero/~A~@[/~A~]" root name)))
           (subzero (make-instance 'subzero
                                   :store store
                                   :event-database event-database
                                   :event-scope scope
                                   :event-parent-scope event-parent-scope
                                   :initial-root root
                                   :current-root root
                                   :capability-grant grant
                                   :max-effects max-effects
                                   :max-events max-events
                                   :max-eval-steps max-eval-steps
                                   :name name
                                   :mode mode)))
      (dolist (binding handlers)
        (register-capability-handler subzero (car binding) (cdr binding)))
      (when event-database
        (call-event-database-observer
         "run registration"
         (lambda ()
           (event-db-register-subzero-run event-database scope root mode
                                          event-parent-scope))))
      (when (and name (eq mode :live))
        (persist-subzero subzero))
      subzero)))

(defun ensure-resource-room (subzero &key (effects 0) (events 0) (eval-steps 0))
  (when (> (+ (subzero-effect-count subzero) effects)
           (subzero-max-effects subzero))
    (error 'resource-budget-exhausted :datum subzero
           :reason "effect limit" :kind :effects))
  (when (> (+ (length (subzero-entries subzero)) events)
           (subzero-max-events subzero))
    (error 'resource-budget-exhausted :datum subzero
           :reason "event log limit" :kind :events))
  (when (> (+ (subzero-evaluation-steps subzero) eval-steps)
           (subzero-max-eval-steps subzero))
    (error 'resource-budget-exhausted :datum subzero
           :reason "evaluation step limit" :kind :eval-steps))
  t)

(defun remaining-evaluation-steps (subzero)
  (max 0 (- (subzero-max-eval-steps subzero)
            (subzero-evaluation-steps subzero))))

(defun resource-limits-term (subzero)
  (make-tagged-term
   "resource-limits"
   (make-field "max-effects" (make-integer-atom (subzero-max-effects subzero)))
   (make-field "max-events" (make-integer-atom (subzero-max-events subzero)))
   (make-field "max-eval-steps" (make-integer-atom (subzero-max-eval-steps subzero)))))

(defun subzero-current-world (subzero)
  (store-get (subzero-store subzero) (subzero-current-root subzero)))

(defun register-capability-handler (subzero capability function)
  (unless (functionp function)
    (error 'protocol-error :datum function :reason "capability handler is not a function"))
  (setf (gethash (canonical-symbol-name capability) (subzero-handlers subzero)) function)
  subzero)

(defun current-genome-hash (subzero)
  (genome-hash (world-genome (subzero-current-world subzero))))

(defun previous-entry-hash (subzero)
  (if (subzero-entries subzero)
      (term-hash (car (last (subzero-entries subzero))))
      nil))

(defun append-log-entry (subzero type payload)
  (let* ((sequence (length (subzero-entries subzero)))
         (previous (previous-entry-hash subzero))
         (entry
           (make-tagged-term
            "log-entry"
            (make-field "sequence" (make-integer-atom sequence))
            (make-field "previous" (if previous
                                         (make-string-atom previous)
                                         (empty-term)))
            (make-field "type" (make-symbol-atom type))
            (make-field "payload" payload))))
    (store-put (subzero-store subzero) entry)
    (setf (subzero-entries subzero)
          (append (subzero-entries subzero) (list entry)))
    (when (subzero-event-database subzero)
      (call-event-database-observer
       "log projection"
       (lambda ()
         (event-db-project-subzero-entry
          (subzero-event-database subzero) (subzero-event-scope subzero) entry
          :parent-scope (subzero-event-parent-scope subzero)))))
    entry))

(defun subzero-log-root (subzero)
  (let ((root
          (make-tagged-term
           "event-log"
           (make-field "initial" (make-string-atom (subzero-initial-root subzero)))
           (make-field "capabilities" (names-term (subzero-capability-grant subzero)))
           (make-field "limits" (resource-limits-term subzero))
           (make-field "entries" (make-list-term (subzero-entries subzero))))))
    (store-put (subzero-store subzero) root)))

(defun subzero-lineage-root (subzero)
  (let ((root
          (make-tagged-term
           "lineage-log"
           (make-field "initial" (make-string-atom (subzero-initial-root subzero)))
           (make-field "entries" (make-list-term (subzero-lineage subzero))))))
    (store-put (subzero-store subzero) root)))

(defun subzero-snapshot-root (subzero)
  (let ((root
          (make-tagged-term
           "subzero-snapshot"
           (make-field "initial" (make-string-atom (subzero-initial-root subzero)))
           (make-field "current" (make-string-atom (subzero-current-root subzero)))
           (make-field "event-log" (make-string-atom (subzero-log-root subzero)))
           (make-field "lineage" (make-string-atom (subzero-lineage-root subzero))))))
    (store-put (subzero-store subzero) root)))


(defun valid-ref-name-p (name)
  (and (stringp name)
       (<= 1 (length name) 128)
       (every (lambda (character)
                (or (alphanumericp character)
                    (find character "-_.")))
              name)))

(defun subzero-ref-pathname (store name)
  (unless (valid-ref-name-p name)
    (error 'protocol-error :datum name :reason "invalid durable ref name"))
  (let ((directory (store-directory store)))
    (unless directory
      (error 'protocol-error :datum store
             :reason "durable refs require a filesystem-backed term store"))
    (merge-pathnames (format nil "refs/~A.ref" name) directory)))

(defun read-subzero-ref (store name)
  (let ((pathname (subzero-ref-pathname store name)))
    (when (probe-file pathname)
      (with-open-file (stream pathname :direction :input :external-format :utf-8)
        (let ((root (string-trim '(#\Space #\Tab #\Newline #\Return)
                                 (read-line stream nil ""))))
          (ensure-canonical-hash root))))))

(defun write-subzero-ref-atomically (store name root)
  (ensure-canonical-hash root)
  (let* ((target (subzero-ref-pathname store name))
         (temporary
           (merge-pathnames
            (format nil "refs/.~A.~A.tmp" name (subseq root 0 16))
            (store-directory store))))
    (ensure-directories-exist target)
    (uiop:delete-file-if-exists temporary)
    (with-open-file (stream temporary :direction :output
                                     :if-does-not-exist :create
                                     :if-exists :supersede
                                     :external-format :utf-8)
      (write-line root stream)
      (finish-output stream))
    (uiop:rename-file-overwriting-target temporary target)
    root))

(defun subzero-manifest-term (subzero generation)
  (make-tagged-term
   "subzero-manifest"
   (make-field "name" (make-string-atom (subzero-ref-name subzero)))
   (make-field "generation" (make-integer-atom generation))
   (make-field "initial" (make-string-atom (subzero-initial-root subzero)))
   (make-field "current" (make-string-atom (subzero-current-root subzero)))
   (make-field "event-log" (make-string-atom (subzero-log-root subzero)))
   (make-field "lineage" (make-string-atom (subzero-lineage-root subzero)))
   (make-field "limits" (resource-limits-term subzero))))

(defun persist-subzero (subzero)
  "Atomically compare-and-swap a named durable manifest to SUBZERO's state."
  (let ((name (subzero-ref-name subzero)))
    (unless name
      (return-from persist-subzero nil))
    (let* ((store (subzero-store subzero))
           (generation (1+ (subzero-manifest-generation subzero)))
           (manifest (subzero-manifest-term subzero generation))
           (root (store-put store manifest)))
      (with-store-lock (store)
        (let ((observed (read-subzero-ref store name))
              (expected (subzero-manifest-root subzero)))
          (unless (if expected
                      (and observed (string= observed expected))
                      (null observed))
            (error 'protocol-error :datum subzero
                   :reason "durable ref compare-and-swap failed"))
          (write-subzero-ref-atomically store name root)
          (setf (subzero-manifest-root subzero) root
                (subzero-manifest-generation subzero) generation)
          root)))))

(defun reopen-subzero (store name &key event-database)
  "Reconstruct a stable named world from its durable manifest and raw roots."
  (ensure-subzero-event-database-store store event-database)
  (let ((manifest-root (read-subzero-ref store name)))
    (unless manifest-root
      (error 'protocol-error :datum name :reason "durable ref does not exist"))
    (let* ((manifest (store-get store manifest-root))
           (manifest-name (string-term-value (required-field manifest "name")))
           (generation
             (integer-term-value/protocol (required-field manifest "generation")))
           (initial-root (string-term-value (required-field manifest "initial")))
           (current-root (string-term-value (required-field manifest "current")))
           (log-root (string-term-value (required-field manifest "event-log")))
           (lineage-root (string-term-value (required-field manifest "lineage")))
            (reopened (replay-from-roots store initial-root log-root
                                         :allow-unresolved t)))
      (unless (and (tagged-term-p manifest "subzero-manifest")
                   (string= name manifest-name)
                   (string= current-root (subzero-current-root reopened))
                   (string= lineage-root (subzero-lineage-root reopened)))
        (error 'protocol-error :datum manifest
               :reason "durable manifest does not match deterministic replay"))
      (setf (slot-value reopened 'ref-name) name
            (slot-value reopened 'mode) :live
            (subzero-manifest-root reopened) manifest-root
            (subzero-manifest-generation reopened) generation)
      (when event-database
        (let ((scope (format nil "subzero/~A/~A" initial-root name)))
          (setf (slot-value reopened 'event-database) event-database
                (slot-value reopened 'event-scope) scope)
          (call-event-database-observer
           "durable log import"
           (lambda ()
             (event-db-register-subzero-run event-database scope initial-root :live)
             (event-db-project-log-root event-database log-root :scope scope)))))
      reopened)))

(defun valid-event-p (event)
  (and (tagged-term-p event "event")
       (not (symbol-atom-name= (term-field event "kind") "nil"))))

(defun valid-effect-p (effect)
  (handler-case
      (and (tagged-term-p effect "effect")
           (integerp (integer-term-value/protocol (required-field effect "id")))
           (symbol-term-value (required-field effect "capability"))
           (term-p (required-field effect "request"))
           (term-p (required-field effect "budget")))
    (cell-zero-error () nil)))

(defun valid-reaction-p (reaction)
  (handler-case
      (and (tagged-term-p reaction "reaction")
           (term-p (required-field reaction "state"))
           (progn (term-list-elements (required-field reaction "outputs")) t)
           (every #'valid-effect-p
                  (term-list-elements (required-field reaction "effects"))))
    (cell-zero-error () nil)))

(defun seal-effect (subzero effect)
  (let* ((world (subzero-current-world subzero))
         (context
           (make-tagged-term
            "effect-context"
            (make-field "world" (make-string-atom (subzero-current-root subzero)))
            (make-field "genome" (make-string-atom (genome-hash (world-genome world)))))))
    (put-term-field effect "context" context)))

(defun queue-sealed-effects (subzero effects)
  (setf (subzero-effect-queue subzero)
        (append (subzero-effect-queue subzero)
                (mapcar (lambda (effect) (seal-effect subzero effect)) effects))))

(defun evaluate-genome-react (genome state event world remaining)
  (cond
    ((string= (genome-abi-name genome) "cell-zero/1")
     (handler-case
         (evaluate-program
          (genome-react genome)
          (list (cons "state" state)
                (cons "event" event)
                (cons "data" (genome-data genome))
                (cons "world" world))
          :limits (make-evaluation-limits :max-steps (min 50000 remaining)
                                          :max-depth 512
                                          :max-output-size 200000))
       (evaluation-budget-exhausted ()
         (error 'resource-budget-exhausted :datum genome
                :reason "evaluation step limit" :kind :eval-steps))))
    ((string= (genome-abi-name genome) "genome/v1")
     (invoke-source-genome-react genome state event world))
    (t
     (error 'protocol-error :datum genome :reason "unsupported genome ABI"))))

(defun react-to-event (subzero event)
  (unless (valid-event-p event)
    (error 'protocol-error :datum event :reason "malformed event"))
  (let ((remaining (remaining-evaluation-steps subzero)))
    (when (zerop remaining)
      (error 'resource-budget-exhausted :datum subzero
             :reason "evaluation step limit" :kind :eval-steps))
    (let* ((world (subzero-current-world subzero))
           (genome (world-genome world))
           (state (world-state world)))
      (multiple-value-bind (reaction usage)
          (evaluate-genome-react genome state event world remaining)
        (unless (valid-reaction-p reaction)
          (error 'protocol-error :datum reaction :reason "react returned a malformed reaction"))
        (ensure-resource-room subzero :eval-steps (usage-steps usage))
        (incf (subzero-evaluation-steps subzero) (usage-steps usage))
        (let* ((next-world (replace-world-state world (required-field reaction "state")))
               (outputs (term-list-elements (required-field reaction "outputs")))
               (effects (term-list-elements (required-field reaction "effects"))))
          (setf (subzero-current-root subzero)
                (store-put (subzero-store subzero) next-world))
          (setf (subzero-outputs subzero)
                (append (subzero-outputs subzero) outputs))
          (queue-sealed-effects subzero effects)
          (values reaction usage))))))

(defun submit-event (subzero event)
  "Validate and append EVENT before delivering it to the current genome."
  (unless (eq (subzero-mode subzero) :live)
    (error 'protocol-error :datum subzero :reason "cannot submit live events during replay"))
  (unless (valid-event-p event)
    (error 'protocol-error :datum event :reason "malformed event"))
  (when (or (subzero-effect-queue subzero)
            (subzero-pending-effect subzero))
    (error 'protocol-error :datum subzero
           :reason "drain queued effects before submitting another input"))
  (ensure-resource-room subzero :events 1)
  (append-log-entry subzero "input" event)
  (multiple-value-prog1 (react-to-event subzero event)
    (persist-subzero subzero)))

(defun effect-capability-name (effect)
  (symbol-term-value (required-field effect "capability")))

(defun effect-id (effect)
  (integer-term-value/protocol (required-field effect "id")))

(defun effect-context-world (effect)
  (string-term-value (required-field (required-field effect "context") "world")))

(defun current-world-allows-capability-p (subzero capability)
  (and (member capability (subzero-capability-grant subzero) :test #'string=)
       (member capability
               (world-capability-names (subzero-current-world subzero))
               :test #'string=)))


(defun effective-capability-names (subzero)
  (intersection (subzero-capability-grant subzero)
                (world-capability-names (subzero-current-world subzero))
                :test #'string=))

(defun usage-term (&key (effects 0) (eval-steps 0) (events 0))
  (make-tagged-term
   "resource-usage"
   (make-field "effects" (make-integer-atom effects))
   (make-field "eval-steps" (make-integer-atom eval-steps))
   (make-field "events" (make-integer-atom events))))

(defun make-effect-result-event (effect status response usage)
  (make-tagged-term
   "event"
   (make-field "kind" (make-symbol-atom "effect-result"))
   (make-field "effect-id" (make-integer-atom (effect-id effect)))
   (make-field "request-hash" (make-string-atom (term-hash effect)))
   (make-field "capability" (make-symbol-atom (effect-capability-name effect)))
   (make-field "status" (make-symbol-atom status))
   (make-field "response" response)
   (make-field "usage" usage)))

(defun denied-effect-result (effect reason)
  (make-effect-result-event
   effect "denied"
   (make-tagged-term "failure" (make-field "reason" (make-symbol-atom reason)))
   (usage-term :effects 1)))

(defun invoke-capability-handler (subzero effect)
  (let* ((capability (effect-capability-name effect))
         (budget (required-field effect "budget"))
         (handler (gethash capability (subzero-handlers subzero))))
    (when (< (budget-integer budget "max-effects" 1) 1)
      (return-from invoke-capability-handler
        (denied-effect-result effect "effect-budget-exhausted")))
    (unless handler
      (return-from invoke-capability-handler
        (denied-effect-result effect "no-handler")))
    (incf (subzero-handler-calls subzero))
    (multiple-value-bind (status response usage)
        (funcall handler subzero
                 (required-field effect "request")
                 budget
                 effect)
      (unless (term-p response)
        (error 'protocol-error :datum response :reason "handler response is not a term"))
      (make-effect-result-event
       effect
       (canonical-symbol-name (or status "ok"))
       response
       (if (term-p usage) usage (usage-term :effects 1))))))


(defun budget-integer (budget name default)
  (let ((value (term-field budget name (make-integer-atom default))))
    (if (and (atom-p value) (eq (atom-kind value) :integer))
        (atom-value value)
        default)))

(defun budget-capabilities (budget)
  (handler-case
      (term-list-names (term-field budget "capabilities"))
    (cell-zero-error () nil)))

(defun copy-allowed-handlers (source target capabilities)
  (dolist (capability capabilities)
    (let ((handler (gethash capability (subzero-handlers source))))
      (when handler
        (register-capability-handler target capability handler))))
  target)

(defun resolve-candidate (subzero candidate-reference)
  (cond
    ((and (atom-p candidate-reference)
          (eq (atom-kind candidate-reference) :string))
     (store-get (subzero-store subzero) (atom-value candidate-reference)))
    ((term-p candidate-reference)
     (store-put (subzero-store subzero) candidate-reference)
     candidate-reference)
    (t
     (error 'protocol-error :datum candidate-reference
            :reason "candidate reference is neither a root string nor a term"))))

(defun candidate-abi-valid-p (candidate &optional parent)
  (handler-case
      (let* ((genome (world-genome candidate))
             (abi (genome-abi-name genome)))
        (and (tagged-term-p candidate "world")
             (tagged-term-p genome "genome")
             (member abi '("cell-zero/1" "genome/v1") :test #'string=)
             (or (null parent)
                 (string= abi (genome-abi-name (world-genome parent))))
             (world-valid-p candidate :load-p nil)))
    (cell-zero-error () nil)))

(defun candidate-loads-p (candidate)
  (world-valid-p candidate :load-p t))

(defun output-slice (outputs start)
  (subseq outputs start))

(defun trial-checks (abi-valid loads liveness regression replayable
                      capability-policy resource-policy)
  (checks-term
   (list "abi-valid" (if abi-valid "pass" "fail"))
   (list "loads" (if loads "pass" "fail"))
   (list "liveness-probe" (if liveness "pass" "fail"))
   (list "regression-suite" (if regression "pass" "fail"))
   (list "replay-compatible" (if replayable "pass" "fail"))
   (list "capability-policy" (if capability-policy "pass" "fail"))
   (list "resource-policy" (if resource-policy "pass" "fail"))))

(defun trace-check-pass-p (trace check-name)
  (symbol-atom-name=
   (check-status (required-field trace "checks") (make-symbol-atom check-name))
   "pass"))

(defun trace-resource-integer (trace name)
  (budget-integer (required-field trace "resource-usage") name 0))

(defun register-attested-trace (subzero trace)
  (unless (tagged-term-p trace "trial-result")
    (error 'protocol-error :datum trace :reason "attested trace is malformed"))
  (let ((root (store-put (subzero-store subzero) trace)))
    (setf (gethash root (subzero-trace-registry subzero)) trace)
    (unless (member root (subzero-trace-roots subzero) :test #'string=)
      (setf (subzero-trace-roots subzero)
            (append (subzero-trace-roots subzero) (list root))))
    root))

(defun trial-request-selection-plan (request)
  (ensure-selection-plan (required-field request "plan")))

(defun run-trial-probe (trial probe max-effects)
  (let* ((event (trial-probe-event probe))
         (expected (trial-probe-expected-outputs probe))
         (output-start (length (subzero-outputs trial))))
    (submit-event trial event)
    (run-until-idle trial :max-effects (1+ max-effects))
    (let ((actual (output-slice (subzero-outputs trial) output-start)))
      (and (= (length expected) (length actual))
           (every #'term-equal expected actual)))))

(defun run-trial-probe-suite (trial probes max-effects)
  (let ((passed 0))
    (dolist (probe probes passed)
      (when (run-trial-probe trial probe max-effects)
        (incf passed)))))

(defun perform-trial (subzero effect)
  (let* ((request (required-field effect "request"))
         (parent (subzero-current-world subzero))
         (candidate-reference (required-field request "candidate"))
         (candidate (resolve-candidate subzero candidate-reference))
         (candidate-root (store-put (subzero-store subzero) candidate))
         (plan (trial-request-selection-plan request))
         (plan-root (selection-plan-hash plan))
         (regression-probes (selection-plan-regression-probes plan))
         (objective-probes (selection-plan-objective-probes plan))
         (budget (required-field effect "budget"))
         (requested-capabilities (budget-capabilities budget))
         (parent-capabilities (effective-capability-names subzero))
         (overbroad-capabilities
           (set-difference requested-capabilities parent-capabilities :test #'string=))
         (trial-capabilities
           (intersection requested-capabilities parent-capabilities :test #'string=))
         (max-effects (budget-integer budget "max-effects" 100))
         (max-events (budget-integer budget "max-events" 1000))
         (max-eval-steps (budget-integer budget "max-eval-steps" 1000000))
         (abi-valid (candidate-abi-valid-p candidate parent))
         (loads (candidate-loads-p candidate))
         (completed (and abi-valid loads))
         (resource-exhausted nil)
         (liveness nil)
         (regression nil)
         (objective-score 0)
         (replayable nil)
         (trial nil)
         (log-root nil)
         (final-root candidate-root)
         (outputs nil)
         (violations
           (mapcar (lambda (capability)
                     (make-tagged-term
                      "violation"
                      (make-field "kind" (make-symbol-atom "trial-envelope-capability"))
                      (make-field "capability" (make-symbol-atom capability))))
                   overbroad-capabilities))
         (effect-count 0)
         (eval-steps 0))
    (when completed
      (setf trial (make-subzero (subzero-store subzero) candidate
                                :capabilities trial-capabilities
                                :event-database (subzero-event-database subzero)
                                :event-scope
                                (event-db-trial-scope
                                 (subzero-event-scope subzero) (term-hash effect))
                                :event-parent-scope (subzero-event-scope subzero)
                                :max-effects max-effects
                                :max-events max-events
                                :max-eval-steps max-eval-steps
                                :mode :live))
      (copy-allowed-handlers subzero trial trial-capabilities)
      (handler-case
          (let ((regression-score
                  (run-trial-probe-suite trial regression-probes max-effects)))
            (setf regression (= regression-score (length regression-probes))
                  objective-score
                  (run-trial-probe-suite trial objective-probes max-effects)))
        (resource-budget-exhausted (condition)
          (setf completed nil
                resource-exhausted t)
          (push (make-tagged-term
                 "violation"
                 (make-field "kind" (make-symbol-atom "resource-budget"))
                 (make-field "resource"
                             (make-symbol-atom (resource-budget-kind condition))))
                violations))
        (error (condition)
          (setf completed nil)
          (push (make-tagged-term
                 "violation"
                 (make-field "kind" (make-symbol-atom "trial-error"))
                 (make-field "detail" (make-string-atom (princ-to-string condition))))
                violations)))
      (setf outputs (subzero-outputs trial)
            liveness (and completed (plusp (length outputs)))
            log-root (subzero-log-root trial)
            final-root (subzero-current-root trial)
            effect-count (subzero-effect-count trial)
            eval-steps (subzero-evaluation-steps trial)
            violations (append violations (subzero-violations trial)))
      (when completed
        (handler-case
            (let ((replayed
                    (replay-from-roots (subzero-store subzero)
                                       candidate-root log-root)))
              (setf replayable
                    (and (string= final-root (subzero-current-root replayed))
                         (= (length outputs) (length (subzero-outputs replayed)))
                         (every #'term-equal outputs (subzero-outputs replayed))
                         (zerop (subzero-handler-calls replayed)))))
          (error (condition)
            (push (make-tagged-term
                   "violation"
                   (make-field "kind" (make-symbol-atom "replay-error"))
                   (make-field "detail" (make-string-atom (princ-to-string condition))))
                  violations)
            (setf replayable nil)))))
      (when (and completed (not replayable))
        (setf completed nil
              objective-score 0))
    (let* ((event-count (if trial (length (subzero-entries trial)) 0))
           (resource-policy (and (not resource-exhausted)
                                 (<= effect-count max-effects)
                                 (<= event-count max-events)
                                 (<= eval-steps max-eval-steps)))
           (capability-policy
             (and (null overbroad-capabilities)
                  (or (null trial) (null (subzero-violations trial)))))
           (checks (trial-checks abi-valid loads
                                 (and completed liveness)
                                 (and completed regression)
                                 (and completed replayable)
                                 capability-policy resource-policy))
           (fitness (make-selection-fitness plan objective-score))
            (trace
              (make-tagged-term
               "trial-result"
               (make-field "abi" (make-symbol-atom (selection-v1-abi)))
               (make-field "parent"
                           (required-field (required-field effect "context") "world"))
               (make-field "candidate" (make-string-atom candidate-root))
               (make-field "parent-genome"
                           (required-field (required-field effect "context") "genome"))
               (make-field "plan" (make-string-atom plan-root))
               (make-field "objective-hash"
                           (make-string-atom (selection-plan-objective-hash plan)))
               (make-field "regression-probes-hash"
                           (make-string-atom
                            (selection-plan-regression-probes-hash plan)))
               (make-field "objective-probes-hash"
                           (make-string-atom
                            (selection-plan-objective-probes-hash plan)))
               (make-field "metric-hash"
                           (make-string-atom (selection-plan-metric-hash plan)))
               (make-field "completed" (if completed (true-term) (false-term)))
               (make-field "outputs" (make-list-term outputs))
               (make-field "event-log" (if log-root
                                              (make-string-atom log-root)
                                              (empty-term)))
               (make-field "final-root" (make-string-atom final-root))
               (make-field "fitness" fitness)
               (make-field "resource-usage"
                           (usage-term :effects effect-count
                                       :eval-steps eval-steps
                                       :events event-count))
               (make-field "checks" checks)
               (make-field "violations" (make-list-term violations))))
            (trace-root (register-attested-trace subzero trace))
            (response
              (make-tagged-term
               "trial-result"
               (make-field "trace" (make-string-atom trace-root))
               (make-field "candidate" (make-string-atom candidate-root))
               (make-field "plan" (make-string-atom plan-root))
               (make-field "completed" (if completed (true-term) (false-term)))
               (make-field "fitness" fitness)
               (make-field "checks" checks))))
      (make-effect-result-event
       effect "ok" response
       (usage-term :effects (1+ effect-count)
                   :eval-steps eval-steps
                   :events event-count)))))

(defun trace-reference-root (request name)
  (let ((reference (required-field request name)))
    (unless (selection-hash-string-p reference)
      (error 'protocol-error :datum reference
             :reason (format nil "~A is not a canonical trace root" name)))
    (string-term-value reference)))

(defun resolve-attested-trace (subzero root)
  (or (gethash root (subzero-trace-registry subzero))
      (error 'protocol-error :datum root
             :reason "evidence references an unattested trace")))

(defun trace-bound-to-selection-p (trace plan parent-genome-root candidate-root)
  (handler-case
      (and (tagged-term-p trace "trial-result")
           (selection-symbol-name-p (required-field trace "abi")
                                    (selection-v1-abi))
           (string= parent-genome-root
                    (string-term-value (required-field trace "parent-genome")))
           (string= candidate-root
                    (string-term-value (required-field trace "candidate")))
           (string= (selection-plan-hash plan)
                    (string-term-value (required-field trace "plan")))
           (string= (selection-plan-objective-hash plan)
                    (string-term-value (required-field trace "objective-hash")))
           (string= (selection-plan-regression-probes-hash plan)
                    (string-term-value
                     (required-field trace "regression-probes-hash")))
           (string= (selection-plan-objective-probes-hash plan)
                    (string-term-value
                     (required-field trace "objective-probes-hash")))
           (string= (selection-plan-metric-hash plan)
                    (string-term-value (required-field trace "metric-hash")))
           (selection-fitness-valid-p (required-field trace "fitness") plan))
    (cell-zero-error () nil)))

(defun trial-safety-gates-pass-p (trace)
  (and (term-truth-p (required-field trace "completed"))
       (every (lambda (check) (trace-check-pass-p trace check))
              '("abi-valid" "loads" "liveness-probe" "regression-suite"
                "replay-compatible" "capability-policy" "resource-policy"))))

(defun claims-automatic-checkable-p (claims checks)
  (handler-case
      (every
       (lambda (claim)
         (let ((parts (term-list-elements claim)))
           (and (= (length parts) 2)
                (atom-p (second parts))
                (eq (atom-kind (second parts)) :symbol)
                (symbol-atom-name=
                 (check-status checks (second parts)) "pass"))))
       (term-list-elements (term-field claims "automatic")))
    (cell-zero-error () nil)))

(defun candidate-capabilities-valid-p (parent candidate)
  (let ((parent-capabilities (world-capability-names parent))
        (candidate-capabilities (world-capability-names candidate)))
    (every (lambda (capability)
             (member capability parent-capabilities :test #'string=))
           candidate-capabilities)))

(defun aggregate-resources (traces)
  (usage-term
   :effects (reduce #'+ traces :key (lambda (trace)
                                      (trace-resource-integer trace "effects"))
                    :initial-value 0)
   :eval-steps (reduce #'+ traces :key (lambda (trace)
                                         (trace-resource-integer trace "eval-steps"))
                       :initial-value 0)
   :events (reduce #'+ traces :key (lambda (trace)
                                     (trace-resource-integer trace "events"))
                   :initial-value 0)))

(defun make-selection-comparison (plan baseline-root baseline-fitness
                                   candidate-root candidate-fitness improved)
  (make-tagged-term
   "selection-comparison"
   (make-field "abi" (make-symbol-atom (selection-v1-abi)))
   (make-field "plan" (make-string-atom (selection-plan-hash plan)))
   (make-field "metric-hash"
               (make-string-atom (selection-plan-metric-hash plan)))
   (make-field "baseline-trace" (make-string-atom baseline-root))
   (make-field "baseline-fitness"
               (make-string-atom (term-hash baseline-fitness)))
   (make-field "candidate-trace" (make-string-atom candidate-root))
   (make-field "candidate-fitness"
               (make-string-atom (term-hash candidate-fitness)))
   (make-field "improved" (if improved (true-term) (false-term)))))

(defun construct-evidence (subzero parent request)
  (let* ((candidate (resolve-candidate subzero (required-field request "candidate")))
         (candidate-root (store-put (subzero-store subzero) candidate))
         (parent-root (subzero-current-root subzero))
         (parent-genome-root (genome-hash (world-genome parent)))
         (plan (ensure-selection-plan (required-field request "plan")))
         (plan-root (store-put (subzero-store subzero) plan))
         (baseline-root (trace-reference-root request "baseline"))
          (baseline-candidate-root (trace-reference-root request "baseline-candidate"))
          (baseline-candidate
            (store-get (subzero-store subzero) baseline-candidate-root))
         (candidate-trace-root (trace-reference-root request "candidate-trace"))
         (baseline-trace (resolve-attested-trace subzero baseline-root))
         (candidate-trace (resolve-attested-trace subzero candidate-trace-root))
         (baseline-fitness (required-field baseline-trace "fitness"))
         (candidate-fitness (required-field candidate-trace "fitness"))
         (claims (term-field request "claims"
                             (make-tagged-term
                              "claims"
                              (make-field "automatic" (empty-term))
                              (make-field "semantic" (empty-term)))))
          (baseline-binding-valid
            (and (world-valid-p baseline-candidate :load-p nil)
                 (string= parent-genome-root
                          (genome-hash (world-genome baseline-candidate)))
                 (trace-bound-to-selection-p baseline-trace plan
                                             parent-genome-root
                                             baseline-candidate-root)))
          (candidate-binding-valid
            (trace-bound-to-selection-p candidate-trace plan
                                        parent-genome-root candidate-root))
         (baseline-valid
           (and baseline-binding-valid
                (trial-safety-gates-pass-p baseline-trace)))
         (abi-valid
           (and (candidate-abi-valid-p candidate parent)
                (trace-check-pass-p candidate-trace "abi-valid")))
         (loads
           (and (candidate-loads-p candidate)
                (trace-check-pass-p candidate-trace "loads")))
         (liveness (trace-check-pass-p candidate-trace "liveness-probe"))
         (regression (trace-check-pass-p candidate-trace "regression-suite"))
         (replayable (trace-check-pass-p candidate-trace "replay-compatible"))
         (capability-policy
           (and (trace-check-pass-p candidate-trace "capability-policy")
                (candidate-capabilities-valid-p parent candidate)))
         (resource-policy (trace-check-pass-p candidate-trace "resource-policy"))
         (objective-improvement
           (and baseline-valid candidate-binding-valid
                (selection-fitness-improves-p candidate-fitness
                                              baseline-fitness plan)))
         (evidence-complete
           (and (string= plan-root (selection-plan-hash plan))
                baseline-valid candidate-binding-valid
                (selection-fitness-valid-p baseline-fitness plan)
                (selection-fitness-valid-p candidate-fitness plan)))
         (preliminary-checks
           (checks-term
            (list "abi-valid" (if abi-valid "pass" "fail"))
            (list "loads" (if loads "pass" "fail"))
            (list "liveness-probe" (if liveness "pass" "fail"))
            (list "regression-suite" (if regression "pass" "fail"))
            (list "replay-compatible" (if replayable "pass" "fail"))
            (list "capability-policy" (if capability-policy "pass" "fail"))
            (list "resource-policy" (if resource-policy "pass" "fail"))
            (list "objective-improvement"
                  (if objective-improvement "pass" "fail"))))
         (automatic-checkable (claims-automatic-checkable-p claims preliminary-checks))
         (checks
           (make-list-term
            (append (term-list-elements preliminary-checks)
                    (list (status-pair "automatic-properties-checkable"
                                       (if automatic-checkable "pass" "fail"))
                          (status-pair "evidence-complete"
                                       (if evidence-complete "pass" "fail"))))))
         (comparison
           (make-selection-comparison plan baseline-root baseline-fitness
                                      candidate-trace-root candidate-fitness
                                      objective-improvement))
         (evidence
           (make-tagged-term
            "evidence"
            (make-field "abi" (make-symbol-atom (selection-v1-abi)))
            (make-field "parent" (make-string-atom parent-root))
            (make-field "parent-genome" (make-string-atom parent-genome-root))
            (make-field "candidate" (make-string-atom candidate-root))
            (make-field "plan" (make-string-atom plan-root))
            (make-field "objective-hash"
                        (make-string-atom (selection-plan-objective-hash plan)))
            (make-field "regression-probes-hash"
                        (make-string-atom
                         (selection-plan-regression-probes-hash plan)))
            (make-field "objective-probes-hash"
                        (make-string-atom
                         (selection-plan-objective-probes-hash plan)))
            (make-field "metric-hash"
                        (make-string-atom (selection-plan-metric-hash plan)))
            (make-field "baseline" (make-string-atom baseline-root))
             (make-field "baseline-candidate"
                         (make-string-atom baseline-candidate-root))
            (make-field "candidate-trace" (make-string-atom candidate-trace-root))
            (make-field "comparison" comparison)
            (make-field "checks" checks)
            (make-field "resources"
                        (aggregate-resources (list baseline-trace candidate-trace)))
            (make-field "claims" claims)))
         (hard-valid (and abi-valid loads capability-policy evidence-complete)))
    (store-put (subzero-store subzero) evidence)
    (values candidate evidence hard-valid
            (cond
              ((not abi-valid) (make-symbol-atom "abi-invalid"))
              ((not loads) (make-symbol-atom "program-load-failed"))
              ((not capability-policy) (make-symbol-atom "capability-policy-failed"))
              ((not evidence-complete) (make-symbol-atom "evidence-incomplete"))
              (t (make-symbol-atom "hard-viability-pass"))))))

(defun make-admission (decision reason)
  (make-tagged-term
   "admission"
   (make-field "decision" (make-symbol-atom decision))
   (make-field "reason" reason)))

(defun valid-admission-p (admission)
  (and (tagged-term-p admission "admission")
       (member (symbol-term-value (required-field admission "decision"))
               '("accept" "reject" "defer") :test #'string=)
       (term-p (required-field admission "reason"))))

(defun invoke-parent-admission (parent candidate evidence)
  (let ((genome (world-genome parent)))
    (cond
      ((string= (genome-abi-name genome) "cell-zero/1")
       (evaluate-program
        (genome-admit genome)
        (list (cons "candidate" candidate)
              (cons "evidence" evidence)
              (cons "data" (genome-data genome)))
        :limits (make-evaluation-limits :max-steps 20000
                                        :max-depth 256
                                        :max-output-size 10000)))
      ((string= (genome-abi-name genome) "genome/v1")
       (invoke-source-genome-admit genome candidate evidence))
      (t
       (error 'protocol-error :datum genome :reason "unsupported genome ABI")))))

(defun evaluate-parent-admission (parent candidate evidence)
  (handler-case
      (multiple-value-bind (admission usage)
          (invoke-parent-admission parent candidate evidence)
        (unless (valid-admission-p admission)
          (error 'protocol-error :datum admission
                 :reason "parent admit returned a malformed admission"))
        (values admission usage))
    (evaluation-budget-exhausted ()
      (values (make-admission "reject" (make-symbol-atom "parent-admit-budget-exhausted"))
              (make-evaluation-usage :steps 20000 :max-depth 0 :output-size 0)))
    (cell-zero-error (condition)
      (values (make-admission "reject"
                              (make-tagged-term
                               "parent-admit-error"
                               (make-field "detail"
                                           (make-string-atom (princ-to-string condition)))))
              (make-evaluation-usage :steps 0 :max-depth 0 :output-size 0)))))

(defun append-lineage-entry (subzero parent-root candidate-root evidence-root decision reason)
  (let ((entry
          (make-tagged-term
           "lineage"
           (make-field "sequence" (make-integer-atom (length (subzero-lineage subzero))))
           (make-field "parent" (make-string-atom parent-root))
           (make-field "parent-genome"
                       (make-string-atom
                        (genome-hash
                         (world-genome
                          (store-get (subzero-store subzero) parent-root)))))
           (make-field "candidate" (make-string-atom candidate-root))
           (make-field "evidence" (if evidence-root
                                         (make-string-atom evidence-root)
                                         (empty-term)))
           (make-field "decision" (make-symbol-atom decision))
           (make-field "reason" reason))))
    (store-put (subzero-store subzero) entry)
    (setf (subzero-lineage subzero)
          (append (subzero-lineage subzero) (list entry)))
    entry))

(defun promotion-result-event (effect parent-root candidate-root evidence-root
                                decision reason lineage-root usage)
  (make-tagged-term
   "event"
   (make-field "kind" (make-symbol-atom "promotion-result"))
   (make-field "effect-id" (make-integer-atom (effect-id effect)))
   (make-field "request-hash" (make-string-atom (term-hash effect)))
   (make-field "capability" (make-symbol-atom "promote"))
   (make-field "status" (make-symbol-atom "ok"))
   (make-field "parent" (make-string-atom parent-root))
   (make-field "candidate" (make-string-atom candidate-root))
   (make-field "evidence" (if evidence-root
                                 (make-string-atom evidence-root)
                                 (empty-term)))
   (make-field "decision" (make-symbol-atom decision))
   (make-field "reason" reason)
   (make-field "lineage" (make-string-atom lineage-root))
   (make-field "usage" usage)))

(defun perform-promotion (subzero effect)
  (let* ((parent-root (subzero-current-root subzero))
         (parent (subzero-current-world subzero))
         (request (required-field effect "request"))
         (candidate-reference (term-field request "candidate" (empty-term)))
         (candidate-root (if (and (atom-p candidate-reference)
                                  (eq (atom-kind candidate-reference) :string))
                             (atom-value candidate-reference)
                             (if (term-p candidate-reference)
                                 (term-hash candidate-reference)
                                 (term-hash (empty-term)))))
         (evidence nil)
         (candidate nil)
         (admission nil)
         (usage (make-evaluation-usage :steps 0 :max-depth 0 :output-size 0)))
    (cond
      ((not (string= (effect-context-world effect) parent-root))
       (setf admission (make-admission "reject" (make-symbol-atom "stale-parent-context"))))
      (t
       (handler-case
           (multiple-value-bind (resolved-candidate constructed-evidence hard-valid hard-reason)
               (construct-evidence subzero parent request)
             (setf candidate resolved-candidate
                   candidate-root (term-hash candidate)
                   evidence constructed-evidence)
             (if hard-valid
                 (multiple-value-setq (admission usage)
                   (evaluate-parent-admission parent candidate evidence))
                 (setf admission (make-admission "reject" hard-reason))))
         (cell-zero-error (condition)
           (setf admission
                 (make-admission
                  "reject"
                  (make-tagged-term
                   "invalid-evidence"
                   (make-field "detail" (make-string-atom (princ-to-string condition))))))))))
    (let* ((decision (symbol-term-value (required-field admission "decision")))
           (reason (required-field admission "reason"))
           (evidence-root (and evidence (term-hash evidence))))
      (when (and (string= decision "accept")
                 (not (string= parent-root (subzero-current-root subzero))))
        (setf decision "reject"
              reason (make-symbol-atom "stale-parent-root")))
      (let* ((lineage (append-lineage-entry subzero parent-root candidate-root
                                            evidence-root decision reason))
             (lineage-root (term-hash lineage)))
        (when (string= decision "accept")
          (unless (and candidate (world-valid-p candidate))
            (error 'protocol-error :datum candidate
                   :reason "accepted candidate failed final viability check"))
          (setf (subzero-current-root subzero) candidate-root))
        (incf (subzero-evaluation-steps subzero) (usage-steps usage))
        (promotion-result-event
         effect parent-root candidate-root evidence-root decision reason lineage-root
         (usage-term :effects 1 :eval-steps (usage-steps usage) :events 1))))))


(defun denied-promotion-result (subzero effect reason)
  (let* ((parent-root (subzero-current-root subzero))
         (request (required-field effect "request"))
         (candidate-reference (term-field request "candidate" (empty-term)))
         (candidate-root
           (cond
             ((and (atom-p candidate-reference)
                   (eq (atom-kind candidate-reference) :string))
              (atom-value candidate-reference))
             ((term-p candidate-reference) (term-hash candidate-reference))
             (t (term-hash (empty-term)))))
         (reason-term (make-symbol-atom reason))
         (lineage (append-lineage-entry subzero parent-root candidate-root nil
                                        "reject" reason-term)))
    (promotion-result-event
     effect parent-root candidate-root nil "reject" reason-term (term-hash lineage)
     (usage-term :effects 1 :events 1))))

(defun note-capability-violation (subzero effect reason)
  (let ((violation
          (make-tagged-term
           "violation"
           (make-field "kind" (make-symbol-atom "capability"))
           (make-field "capability" (make-symbol-atom (effect-capability-name effect)))
           (make-field "effect" (make-string-atom (term-hash effect)))
           (make-field "reason" (make-symbol-atom reason)))))
    (setf (subzero-violations subzero)
          (append (subzero-violations subzero) (list violation)))
    violation))

(defun effect-denial-reason (subzero effect)
  (let ((capability (effect-capability-name effect)))
    (cond
      ((not (string= (effect-context-world effect) (subzero-current-root subzero)))
       "stale-context")
      ((not (current-world-allows-capability-p subzero capability))
       "capability-denied")
      (t nil))))

(defun denied-result-for-effect (subzero effect reason)
  (if (string= (effect-capability-name effect) "promote")
      (denied-promotion-result subzero effect reason)
      (denied-effect-result effect reason)))

(defun execute-live-effect (subzero effect)
  (let* ((capability (effect-capability-name effect))
         (denial (effect-denial-reason subzero effect)))
    (cond
      (denial
       (note-capability-violation subzero effect denial)
       (denied-result-for-effect subzero effect denial))
      ((string= capability "trial")
       (perform-trial subzero effect))
      ((string= capability "promote")
       (perform-promotion subzero effect))
      (t
       (invoke-capability-handler subzero effect)))))

(defun complete-pending-effect (subzero)
  (let ((effect (subzero-pending-effect subzero)))
    (unless effect
      (return-from complete-pending-effect nil))
    (let ((event (execute-live-effect subzero effect)))
      ;; The request remains pending until its result has been recorded and reacted to.
      (append-log-entry subzero "effect-result" event)
      (react-to-event subzero event)
      (setf (subzero-pending-effect subzero) nil)
      (persist-subzero subzero)
      event)))

(defun reserve-next-effect (subzero)
  "Durably record the next queued request without invoking its capability."
  (when (subzero-pending-effect subzero)
    (return-from reserve-next-effect (subzero-pending-effect subzero)))
  (unless (subzero-effect-queue subzero)
    (return-from reserve-next-effect nil))
  (ensure-resource-room subzero :effects 1 :events 2)
  (let ((effect (first (subzero-effect-queue subzero))))
    (setf (subzero-effect-queue subzero) (rest (subzero-effect-queue subzero))
          (subzero-pending-effect subzero) effect)
    (append-log-entry subzero "effect-request" effect)
    (incf (subzero-effect-count subzero))
    (persist-subzero subzero)
    effect))

(defun process-next-effect (subzero)
  (or (subzero-pending-effect subzero)
      (reserve-next-effect subzero))
  (complete-pending-effect subzero))

(defun run-until-idle (subzero &key (max-effects 1000))
  "Execute queued or durably pending effects serially until none remain."
  (unless (eq (subzero-mode subzero) :live)
    (error 'protocol-error :datum subzero :reason "cannot execute effects during replay"))
  (loop repeat max-effects
        while (or (subzero-pending-effect subzero)
                  (subzero-effect-queue subzero))
        do (process-next-effect subzero)
        finally
           (when (or (subzero-pending-effect subzero)
                     (subzero-effect-queue subzero))
             (error 'protocol-error :datum subzero
                    :reason "effect drain exceeded its bound")))
  subzero)

(defun validate-log-chain (entries)
  (loop with previous = nil
        for entry in entries
        for sequence from 0
        do (unless (and (tagged-term-p entry "log-entry")
                        (= sequence
                           (integer-term-value/protocol
                            (required-field entry "sequence"))))
             (error 'protocol-error :datum entry :reason "invalid log sequence"))
           (let ((recorded-previous (required-field entry "previous")))
             (if previous
                 (unless (and (atom-p recorded-previous)
                              (eq (atom-kind recorded-previous) :string)
                              (string= previous (atom-value recorded-previous)))
                   (error 'protocol-error :datum entry :reason "broken log hash chain"))
                 (unless (symbol-atom-name= recorded-previous "nil")
                   (error 'protocol-error :datum entry
                          :reason "first log entry has a predecessor"))))
           (setf previous (term-hash entry)))
  t)

(defun pop-expected-effect (subzero recorded-effect)
  (unless (subzero-effect-queue subzero)
    (error 'protocol-error :datum recorded-effect
           :reason "recorded effect was not requested by react"))
  (let ((expected (first (subzero-effect-queue subzero))))
    (setf (subzero-effect-queue subzero) (rest (subzero-effect-queue subzero)))
    (unless (term-equal expected recorded-effect)
      (error 'protocol-error :datum recorded-effect
             :reason "recorded effect does not match deterministic react output"))
    expected))

(defun verify-effect-result-binding (effect event)
  (unless (and (valid-event-p event)
               (= (effect-id effect)
                  (integer-term-value/protocol (required-field event "effect-id")))
               (string= (term-hash effect)
                        (string-term-value (required-field event "request-hash")))
               (string= (effect-capability-name effect)
                        (symbol-term-value (required-field event "capability"))))
    (error 'protocol-error :datum event
           :reason "effect result does not bind its exact request"))
  t)

(defun same-term-list-p (left right)
  (and (= (length left) (length right))
       (every #'term-equal left right)))

(defun same-string-set-p (left right)
  (and (null (set-difference left right :test #'string=))
       (null (set-difference right left :test #'string=))))

(defun trial-probe-slice-pass-p (probe slice)
  (and (term-equal (trial-probe-event probe) (car slice))
       (same-term-list-p (trial-probe-expected-outputs probe) (cdr slice))))

(defun selection-plan-replay-scores (plan input-slices)
  (let* ((regression-probes (selection-plan-regression-probes plan))
         (objective-probes (selection-plan-objective-probes plan))
         (probes (append regression-probes objective-probes)))
    (unless (= (length probes) (length input-slices))
      (error 'protocol-error :datum input-slices
             :reason "recorded trial input count differs from its selection plan"))
    (let* ((passes (mapcar #'trial-probe-slice-pass-p probes input-slices))
           (regression-count (length regression-probes))
           (regression-passes (subseq passes 0 regression-count))
           (objective-passes (subseq passes regression-count)))
      (values (every #'identity regression-passes)
              (count t objective-passes)))))

(defun register-recorded-trial-result (subzero effect event)
  (let* ((request (required-field effect "request"))
         (response (required-field event "response"))
         (trace-root (string-term-value (required-field response "trace")))
         (trace (store-get (subzero-store subzero) trace-root))
         (candidate (resolve-candidate subzero (required-field request "candidate")))
         (candidate-root (store-put (subzero-store subzero) candidate))
         (parent (subzero-current-world subzero))
         (parent-genome-root (genome-hash (world-genome parent)))
         (plan (trial-request-selection-plan request))
         (plan-root (selection-plan-hash plan))
         (completed (required-field trace "completed"))
         (fitness (required-field trace "fitness"))
         (checks (required-field trace "checks"))
         (expected-event
           (make-effect-result-event
            effect "ok" response
            (usage-term
             :effects (1+ (trace-resource-integer trace "effects"))
             :eval-steps (trace-resource-integer trace "eval-steps")
             :events (trace-resource-integer trace "events")))))
    (unless (and (term-equal event expected-event)
                 (tagged-term-p response "trial-result")
                 (string= trace-root (term-hash trace))
                 (trace-bound-to-selection-p trace plan
                                             parent-genome-root candidate-root)
                 (string= (effect-context-world effect)
                          (string-term-value (required-field trace "parent")))
                 (string= (string-term-value
                           (required-field (required-field effect "context") "genome"))
                          (string-term-value (required-field trace "parent-genome")))
                 (string= candidate-root
                          (string-term-value (required-field response "candidate")))
                 (string= plan-root
                          (string-term-value (required-field response "plan")))
                 (term-equal completed (required-field response "completed"))
                 (term-equal fitness (required-field response "fitness"))
                 (term-equal checks (required-field response "checks")))
      (error 'protocol-error :datum trace
             :reason "recorded trial trace is not bound to its exact selection request"))
    (if (term-truth-p completed)
        (let* ((log-root (string-term-value (required-field trace "event-log")))
               (log (store-get (subzero-store subzero) log-root))
               (budget (required-field effect "budget"))
               (requested-capabilities (budget-capabilities budget))
               (parent-capabilities (effective-capability-names subzero))
               (trial-capabilities
                 (intersection requested-capabilities parent-capabilities
                               :test #'string=))
               (recorded-capabilities
                 (term-list-names (required-field log "capabilities")))
               (overbroad
                 (set-difference requested-capabilities parent-capabilities
                                 :test #'string=))
               (max-effects (budget-integer budget "max-effects" 100))
               (max-events (budget-integer budget "max-events" 1000))
               (max-eval-steps (budget-integer budget "max-eval-steps" 1000000)))
          (unless (same-string-set-p recorded-capabilities trial-capabilities)
            (error 'protocol-error :datum trace
                   :reason "recorded trial used a different capability grant"))
          (multiple-value-bind (replayed input-slices)
              (replay-from-roots (subzero-store subzero) candidate-root log-root
                                 :collect-input-slices t)
            (multiple-value-bind (regression objective-score)
                (selection-plan-replay-scores plan input-slices)
              (let* ((outputs (subzero-outputs replayed))
                     (effect-count (subzero-effect-count replayed))
                     (event-count (length (subzero-entries replayed)))
                     (eval-steps (subzero-evaluation-steps replayed))
                     (capability-policy
                       (and (null overbroad) (null (subzero-violations replayed))))
                     (resource-policy
                       (and (<= effect-count max-effects)
                            (<= event-count max-events)
                            (<= eval-steps max-eval-steps)))
                     (expected-checks
                       (trial-checks (candidate-abi-valid-p candidate parent)
                                     (candidate-loads-p candidate)
                                     (plusp (length outputs))
                                     regression t capability-policy resource-policy))
                     (expected-fitness (make-selection-fitness plan objective-score)))
                (unless (and (string= (subzero-current-root replayed)
                                      (string-term-value
                                       (required-field trace "final-root")))
                             (same-term-list-p outputs
                                               (term-list-elements
                                                (required-field trace "outputs")))
                             (= effect-count (trace-resource-integer trace "effects"))
                             (= event-count (trace-resource-integer trace "events"))
                             (= eval-steps (trace-resource-integer trace "eval-steps"))
                             (term-equal checks expected-checks)
                             (term-equal fitness expected-fitness)
                             (zerop (subzero-handler-calls replayed)))
                  (error 'protocol-error :datum trace
                         :reason "recorded trial trace differs from deterministic replay"))))))
        (when (or (trace-check-pass-p trace "liveness-probe")
                  (trace-check-pass-p trace "regression-suite")
                  (trace-check-pass-p trace "replay-compatible")
                  (not (term-equal fitness (make-selection-fitness plan 0))))
          (error 'protocol-error :datum trace
                 :reason "incomplete recorded trial claims successful checks or fitness")))
    (register-attested-trace subzero trace)))

(defun replay-effect-result (subzero effect event)
  (verify-effect-result-binding effect event)
  (let* ((capability (effect-capability-name effect))
         (denial (effect-denial-reason subzero effect)))
    (cond
      (denial
       (note-capability-violation subzero effect denial)
       (let ((recomputed (denied-result-for-effect subzero effect denial)))
         (unless (term-equal recomputed event)
           (error 'protocol-error :datum event
                  :reason "recorded denial differs from deterministic replay"))))
      ((string= capability "trial")
       (unless (symbol-atom-name= (required-field event "status") "ok")
         (error 'protocol-error :datum event
                :reason "recorded internal trial result has non-ok status"))
       (register-recorded-trial-result subzero effect event))
      ((string= capability "promote")
       (let ((recomputed (perform-promotion subzero effect)))
         (unless (term-equal recomputed event)
           (error 'protocol-error :datum event
                  :reason "recorded promotion differs from parent admission replay")))))
    (react-to-event subzero event)))

(defun replay-from-roots (store initial-root log-root
                          &key allow-unresolved collect-input-slices)
  "Replay LOG-ROOT from INITIAL-ROOT without invoking any capability handler.
When ALLOW-UNRESOLVED is true, return resumable queued or pending work.
When COLLECT-INPUT-SLICES is true, return each input and its resulting outputs
as a second value."
  (let* ((log (store-get store log-root))
         (recorded-initial (string-term-value (required-field log "initial")))
         (capabilities (term-list-names (required-field log "capabilities")))
         (limits (required-field log "limits"))
         (max-effects (budget-integer limits "max-effects" most-positive-fixnum))
         (max-events (budget-integer limits "max-events" most-positive-fixnum))
         (max-eval-steps (budget-integer limits "max-eval-steps" most-positive-fixnum))
         (entries (term-list-elements (required-field log "entries"))))
    (unless (and (tagged-term-p log "event-log")
                 (string= initial-root recorded-initial)
                 (<= (length entries) max-events))
      (error 'protocol-error :datum log :reason "event log initial root or limits mismatch"))
    (validate-log-chain entries)
    (let ((replay (make-subzero store initial-root
                                :capabilities capabilities
                                :max-effects max-effects
                                :max-events max-events
                                :max-eval-steps max-eval-steps
                                :mode :replay))
          (outstanding (make-hash-table :test #'equal))
          (current-input nil)
          (output-start 0)
          (input-slices nil))
      (labels ((finish-input-slice ()
                 (when (and collect-input-slices current-input)
                   (push (cons current-input
                               (copy-list
                                (subseq (subzero-outputs replay) output-start)))
                         input-slices))))
        (dolist (entry entries)
          (let ((type (symbol-term-value (required-field entry "type")))
                (payload (required-field entry "payload")))
            (cond
              ((string= type "input")
               (when (or (subzero-effect-queue replay)
                         (plusp (hash-table-count outstanding)))
                 (error 'protocol-error :datum entry
                        :reason "input interleaves with an unresolved effect"))
               (finish-input-slice)
               (setf current-input payload
                     output-start (length (subzero-outputs replay)))
               (react-to-event replay payload))
              ((string= type "effect-request")
               (ensure-resource-room replay :effects 1)
               (incf (subzero-effect-count replay))
               (when (subzero-pending-effect replay)
                 (error 'protocol-error :datum payload
                        :reason "effect requests overlap"))
               (let ((effect (pop-expected-effect replay payload)))
                 (when (gethash (term-hash effect) outstanding)
                   (error 'protocol-error :datum effect :reason "duplicate effect request"))
                 (setf (gethash (term-hash effect) outstanding) effect
                       (subzero-pending-effect replay) effect)))
              ((string= type "effect-result")
               (let* ((request-hash
                        (string-term-value (required-field payload "request-hash")))
                      (effect (gethash request-hash outstanding)))
                 (unless effect
                   (error 'protocol-error :datum payload
                          :reason "effect result has no outstanding request"))
                 (unless (and (subzero-pending-effect replay)
                              (term-equal effect (subzero-pending-effect replay)))
                   (error 'protocol-error :datum payload
                          :reason "effect result does not match the pending request"))
                 (remhash request-hash outstanding)
                 (setf (subzero-pending-effect replay) nil)
                 (replay-effect-result replay effect payload)))
              (t
               (error 'protocol-error :datum entry :reason "unknown log entry type")))))
        (finish-input-slice))
      (unless allow-unresolved
        (when (or (subzero-effect-queue replay)
                  (subzero-pending-effect replay)
                  (plusp (hash-table-count outstanding)))
          (error 'protocol-error :datum log :reason "event log ends with unresolved effects")))
      (when (> (hash-table-count outstanding) 1)
        (error 'protocol-error :datum log :reason "multiple effects are outstanding"))
      (setf (subzero-entries replay) entries)
      (values replay (nreverse input-slices)))))
