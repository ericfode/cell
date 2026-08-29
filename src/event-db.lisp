;;;; src/event-db.lisp

(in-package #:cell-zero)

(define-condition event-database-error (cell-zero-error)
  ((reason :initarg :reason :reader event-database-error-reason)
   (datum :initarg :datum :initform nil :reader event-database-error-datum))
  (:report (lambda (condition stream)
             (format stream "Cell Zero event database error: ~A"
                     (event-database-error-reason condition)))))

(defclass event-database ()
  ((store :initarg :store :reader event-db-store)
   (name :initarg :name :initform nil :reader event-db-name)
   (transactions :initarg :transactions :initform nil
                 :accessor %event-db-transactions)
   (head :initarg :head :initform nil :accessor event-db-head)
   (manifest-root :initarg :manifest-root :initform nil
                  :accessor %event-db-manifest-root)
   (sources :initform (make-hash-table :test #'equal)
            :reader %event-db-sources)
   (subscriptions :initform nil :accessor %event-db-subscriptions)
   (next-subscription-id :initform 0 :accessor %event-db-next-subscription-id)
   (lock :initform #+sb-thread (sb-thread:make-mutex :name "cell-zero-event-db")
                   #-sb-thread nil
         :reader %event-db-lock)))

(defclass event-database-view ()
  ((database :initarg :database :reader %event-db-view-database)
   (as-of :initarg :as-of :reader %event-db-view-as-of)))

(defclass event-db-subscription ()
  ((database :initarg :database :reader %event-db-subscription-database)
   (id :initarg :id :reader event-db-subscription-id)
   (kind :initarg :kind :reader %event-db-subscription-kind)
   (clauses :initarg :clauses :initform nil :reader %event-db-subscription-clauses)
   (find :initarg :find :initform nil :reader %event-db-subscription-find)
   (raw :initarg :raw :initform nil :reader %event-db-subscription-raw)
   (history :initarg :history :initform nil :reader %event-db-subscription-history)
   (callback :initarg :callback :reader %event-db-subscription-callback)
   (active-p :initform t :accessor event-db-subscription-active-p)))

(defmacro with-event-db-lock ((database) &body body)
  #+sb-thread `(sb-thread:with-mutex ((%event-db-lock ,database)) ,@body)
  #-sb-thread `(progn ,@body))

(defun %event-db-field (name value)
  (term-list (make-symbol-atom name) value))

(defun %event-db-tagged-term (tag &rest fields)
  (apply #'term-list (make-symbol-atom tag) fields))

(defun %event-db-tag-p (term tag)
  (let ((actual (and (term-p term) (term-tag term))))
    (and actual
         (atom-p actual)
         (eq (atom-kind actual) :symbol)
         (string= (atom-value actual) (canonical-symbol-name tag)))))

(defun %event-db-required-field (term name)
  (let ((value (term-field term name nil)))
    (unless value
      (error 'event-database-error :datum term
             :reason (format nil "missing field ~A" name)))
    value))

(defun %event-db-string-value (term)
  (unless (and (atom-p term) (eq (atom-kind term) :string))
    (error 'event-database-error :datum term :reason "expected a string atom"))
  (atom-value term))

(defun %event-db-integer-value (term)
  (unless (and (atom-p term) (eq (atom-kind term) :integer))
    (error 'event-database-error :datum term :reason "expected an integer atom"))
  (atom-value term))

(defun %event-db-symbol-value (term)
  (unless (and (atom-p term) (eq (atom-kind term) :symbol))
    (error 'event-database-error :datum term :reason "expected a symbol atom"))
  (atom-value term))

(defun %event-db-value-term (value)
  (cond
    ((term-p value) value)
    ((stringp value) (make-string-atom value))
    ((integerp value) (make-integer-atom value))
    ((symbolp value) (make-symbol-atom value))
    ((and (vectorp value)
          (every (lambda (octet) (typep octet '(unsigned-byte 8))) value))
     (make-bytes-atom value))
    ((consp value) (sexp->term value))
    (t
     (error 'event-database-error :datum value
            :reason "database values must be canonical terms or Lisp term projections"))))

(defun %event-db-attribute-term (attribute)
  (cond
    ((and (atom-p attribute) (eq (atom-kind attribute) :symbol)) attribute)
    ((or (symbolp attribute) (stringp attribute)) (make-symbol-atom attribute))
    (t
     (error 'event-database-error :datum attribute
            :reason "datom attributes must be symbols or strings"))))

(defun %event-db-operation-name (operation)
  (let ((name (canonical-symbol-name operation)))
    (unless (member name '("assert" "retract") :test #'string=)
      (error 'event-database-error :datum operation
             :reason "datom operation must be ASSERT or RETRACT"))
    name))

(defun event-datom-entity (datom)
  (%event-db-required-field datom "entity"))

(defun event-datom-attribute (datom)
  (%event-db-required-field datom "attribute"))

(defun event-datom-value (datom)
  (%event-db-required-field datom "value"))

(defun event-datom-transaction (datom)
  (%event-db-integer-value (%event-db-required-field datom "transaction")))

(defun event-datom-operation (datom)
  (%event-db-symbol-value (%event-db-required-field datom "operation")))

(defun event-db-transaction-sequence (transaction)
  (%event-db-integer-value (%event-db-required-field transaction "sequence")))

(defun event-db-transaction-previous (transaction)
  (let ((previous (%event-db-required-field transaction "previous")))
    (if (and (atom-p previous) (eq (atom-kind previous) :string))
        (atom-value previous)
        nil)))

(defun event-db-transaction-source (transaction)
  (let ((source (%event-db-required-field transaction "source")))
    (unless (and (atom-p source)
                 (eq (atom-kind source) :symbol)
                 (string= (atom-value source) "nil"))
      source)))

(defun event-db-transaction-datoms (transaction)
  (term-list-elements (%event-db-required-field transaction "datoms")))

(defun event-db-transactions (database)
  (let ((database (if (typep database 'event-database-view)
                      (%event-db-view-database database)
                      database)))
    (unless (typep database 'event-database)
      (error 'event-database-error :datum database :reason "not an event database"))
    (with-event-db-lock (database)
      (copy-list (%event-db-transactions database)))))

(defun event-db-transaction-count (database)
  (length (event-db-transactions database)))

(defun %event-db-ref-name-p (name)
  (and (stringp name)
       (<= 1 (length name) 128)
       (every (lambda (character)
                (or (alphanumericp character)
                    (find character "-_.")))
              name)))

(defun %event-db-ref-pathname (store name)
  (unless (%event-db-ref-name-p name)
    (error 'event-database-error :datum name :reason "invalid event database ref name"))
  (let ((directory (store-directory store)))
    (unless directory
      (error 'event-database-error :datum store
             :reason "durable event databases require a filesystem-backed term store"))
    (merge-pathnames (format nil "refs/event-db/~A.ref" name) directory)))

(defun %read-event-db-ref (store name)
  (let ((pathname (%event-db-ref-pathname store name)))
    (when (probe-file pathname)
      (let ((root (string-trim '(#\Space #\Tab #\Newline #\Return)
                               (utf8-octets-string (read-file-octets pathname)))))
        (ensure-canonical-hash root)))))

(defun %write-event-db-ref (store name root)
  (ensure-canonical-hash root)
  (write-file-octets-atomically
   (%event-db-ref-pathname store name)
   (string-utf8-octets (format nil "~A~%" root)))
  root)

(defun %event-db-root-term (database)
  (%event-db-tagged-term
   "event-database"
   (%event-db-field "version" (make-symbol-atom "event-db/1"))
   (%event-db-field "name" (if (event-db-name database)
                                (make-string-atom (event-db-name database))
                                (empty-term)))
   (%event-db-field "count" (make-integer-atom
                              (length (%event-db-transactions database))))
   (%event-db-field "head" (if (event-db-head database)
                                (make-string-atom (event-db-head database))
                                (empty-term)))))

(defun event-db-root (database)
  (with-event-db-lock (database)
    (store-put (event-db-store database) (%event-db-root-term database))))

(defun %persist-event-database-unlocked (database)
  (let* ((store (event-db-store database))
         (name (event-db-name database))
         (root (store-put store (%event-db-root-term database))))
    (when name
      (with-store-lock (store)
        (let ((observed (%read-event-db-ref store name))
              (expected (%event-db-manifest-root database)))
          (unless (if expected
                      (and observed (string= observed expected))
                      (null observed))
            (error 'event-database-error :datum database
                   :reason "event database ref compare-and-swap failed"))
          (%write-event-db-ref store name root))))
    (setf (%event-db-manifest-root database) root)
    root))

(defun persist-event-database (database)
  "Persist DATABASE's immutable head and atomically advance its named ref."
  (with-event-db-lock (database)
    (%persist-event-database-unlocked database)))

(defun %event-db-source-key (source)
  (and source (term-hash (%event-db-value-term source))))

(defun %index-event-db-sources (database)
  (clrhash (%event-db-sources database))
  (dolist (transaction (%event-db-transactions database))
    (let ((source (event-db-transaction-source transaction)))
      (when source
        (setf (gethash (term-hash source) (%event-db-sources database)) transaction))))
  database)

(defun make-event-database (store &key name (if-exists :open))
  "Create an immutable temporal event database over STORE.
A named database persists after every transaction. IF-EXISTS is :OPEN or :ERROR."
  (unless (typep store 'term-store)
    (error 'event-database-error :datum store :reason "STORE is not a term store"))
  (when (and name (%read-event-db-ref store name))
    (ecase if-exists
      (:open (return-from make-event-database (reopen-event-database store name)))
      (:error
       (error 'event-database-error :datum name
              :reason "event database ref already exists"))))
  (let ((database (make-instance 'event-database :store store :name name)))
    (when name (persist-event-database database))
    database))

(defun %validate-event-db-transaction (transaction expected-sequence expected-previous)
  (unless (%event-db-tag-p transaction "event-db-transaction")
    (error 'event-database-error :datum transaction
           :reason "invalid event database transaction tag"))
  (unless (= expected-sequence (event-db-transaction-sequence transaction))
    (error 'event-database-error :datum transaction
           :reason "invalid event database transaction sequence"))
  (let ((recorded (event-db-transaction-previous transaction)))
    (unless (if expected-previous
                (and recorded (string= expected-previous recorded))
                (null recorded))
      (error 'event-database-error :datum transaction
             :reason "broken event database transaction hash chain")))
  (dolist (datom (event-db-transaction-datoms transaction))
    (unless (and (%event-db-tag-p datom "datom")
                 (= expected-sequence (event-datom-transaction datom))
                 (member (event-datom-operation datom)
                         '("assert" "retract") :test #'string=))
      (error 'event-database-error :datum datom :reason "invalid immutable datom")))
  t)

(defun reopen-event-database (store name)
  "Reopen and validate a named database from its canonical head and transaction chain."
  (let ((root (%read-event-db-ref store name)))
    (unless root
      (error 'event-database-error :datum name :reason "event database ref does not exist"))
    (let* ((manifest (store-get store root))
           (version (%event-db-symbol-value (%event-db-required-field manifest "version")))
           (manifest-name (%event-db-string-value (%event-db-required-field manifest "name")))
           (count (%event-db-integer-value (%event-db-required-field manifest "count")))
           (head-term (%event-db-required-field manifest "head"))
           (head (and (atom-p head-term) (eq (atom-kind head-term) :string)
                      (atom-value head-term)))
           (transactions nil)
           (cursor head))
      (unless (and (%event-db-tag-p manifest "event-database")
                   (string= version "event-db/1")
                   (string= name manifest-name))
        (error 'event-database-error :datum manifest
               :reason "invalid event database manifest"))
      (loop while cursor
            for transaction = (store-get store cursor)
            do (push transaction transactions)
               (setf cursor (event-db-transaction-previous transaction)))
      (unless (= count (length transactions))
        (error 'event-database-error :datum manifest
               :reason "event database transaction count does not match its chain"))
      (loop with previous = nil
            for transaction in transactions
            for sequence from 0
            do (%validate-event-db-transaction transaction sequence previous)
               (setf previous (term-hash transaction)))
      (let ((database (make-instance 'event-database
                                     :store store :name name
                                     :transactions transactions
                                     :head head :manifest-root root)))
        (%index-event-db-sources database)
        database))))

(defun %make-event-datom (sequence specification)
  (unless (and (listp specification) (<= 3 (length specification) 4))
    (error 'event-database-error :datum specification
           :reason "a datom specification is (entity attribute value &optional operation)"))
  (destructuring-bind (entity attribute value &optional (operation :assert)) specification
    (%event-db-tagged-term
     "datom"
     (%event-db-field "entity" (%event-db-value-term entity))
     (%event-db-field "attribute" (%event-db-attribute-term attribute))
     (%event-db-field "value" (%event-db-value-term value))
     (%event-db-field "transaction" (make-integer-atom sequence))
     (%event-db-field "operation" (make-symbol-atom (%event-db-operation-name operation))))))

(defun %make-event-db-transaction (database specifications source)
  (let* ((sequence (length (%event-db-transactions database)))
         (previous (event-db-head database))
         (datoms (mapcar (lambda (specification)
                           (%make-event-datom sequence specification))
                         specifications)))
    (unless datoms
      (error 'event-database-error :datum specifications
             :reason "event database transactions cannot be empty"))
    (%event-db-tagged-term
     "event-db-transaction"
     (%event-db-field "sequence" (make-integer-atom sequence))
     (%event-db-field "previous" (if previous
                                      (make-string-atom previous)
                                      (empty-term)))
     (%event-db-field "source" (if source
                                    (%event-db-value-term source)
                                    (empty-term)))
     (%event-db-field "datoms" (term-list-from-elements datoms)))))

(defun %notify-event-db-subscriptions (database transaction subscriptions)
  (dolist (subscription subscriptions)
    (when (event-db-subscription-active-p subscription)
      (handler-case
          (ecase (%event-db-subscription-kind subscription)
            (:tail
             (funcall (%event-db-subscription-callback subscription)
                      transaction database))
            (:query
             (funcall (%event-db-subscription-callback subscription)
                      (event-db-query
                       database
                       (%event-db-subscription-clauses subscription)
                       :find (%event-db-subscription-find subscription)
                       :raw (%event-db-subscription-raw subscription)
                       :history (%event-db-subscription-history subscription))
                      transaction database)))
        (error (condition)
          (warn "Event database subscription ~D failed: ~A"
                (event-db-subscription-id subscription) condition))))))

(defun event-db-transact (database specifications &key source)
  "Atomically append immutable EAV datoms and return TRANSACTION, CREATED-P.
Each specification is (ENTITY ATTRIBUTE VALUE &optional ASSERT|RETRACT). SOURCE
makes projection transactions idempotent."
  (unless (typep database 'event-database)
    (error 'event-database-error :datum database :reason "not an event database"))
  (let ((transaction nil)
        (created-p nil)
        (subscriptions nil))
    (with-event-db-lock (database)
      (let* ((source-key (%event-db-source-key source))
             (existing (and source-key
                            (gethash source-key (%event-db-sources database)))))
        (if existing
            (setf transaction existing)
            (let* ((new-transaction
                     (%make-event-db-transaction database specifications source))
                   (root (store-put (event-db-store database) new-transaction)))
              (setf (%event-db-transactions database)
                    (append (%event-db-transactions database)
                            (list new-transaction))
                    (event-db-head database) root
                    transaction new-transaction
                    created-p t)
              (when source-key
                (setf (gethash source-key (%event-db-sources database)) new-transaction))
              (when (event-db-name database)
                (%persist-event-database-unlocked database))
              (setf subscriptions (copy-list (%event-db-subscriptions database)))))))
    (when created-p
      (%notify-event-db-subscriptions database transaction subscriptions))
    (values transaction created-p)))

(defun %event-db-as-of-sequence (database as-of)
  (cond
    ((null as-of) (1- (length (%event-db-transactions database))))
    ((integerp as-of)
     (unless (<= -1 as-of (1- (length (%event-db-transactions database))))
       (error 'event-database-error :datum as-of :reason "AS-OF sequence is out of range"))
     as-of)
    ((stringp as-of)
     (or (loop for transaction in (%event-db-transactions database)
               when (string= as-of (term-hash transaction))
                 return (event-db-transaction-sequence transaction))
         (error 'event-database-error :datum as-of
                :reason "AS-OF transaction root is not in this database")))
    ((%event-db-tag-p as-of "event-db-transaction")
     (%event-db-as-of-sequence database (term-hash as-of)))
    (t
     (error 'event-database-error :datum as-of
            :reason "AS-OF must be a transaction sequence, root, or transaction"))))

(defun event-db-as-of (database transaction)
  "Return an immutable query view ending at TRANSACTION, inclusive."
  (when (typep database 'event-database-view)
    (setf database (%event-db-view-database database)))
  (with-event-db-lock (database)
    (%event-db-as-of-sequence database transaction))
  (make-instance 'event-database-view :database database :as-of transaction))

(defun %event-db-visible-datoms-unlocked (database limit history)
  (let ((all nil))
    (dolist (transaction (%event-db-transactions database))
      (when (> (event-db-transaction-sequence transaction) limit)
        (return))
      (setf all (nconc all (copy-list (event-db-transaction-datoms transaction)))))
    (if history
        all
        (let ((active (make-hash-table :test #'equal)))
          (dolist (datom all)
            (let ((key (list (term-hash (event-datom-entity datom))
                             (term-hash (event-datom-attribute datom))
                             (term-hash (event-datom-value datom)))))
              (if (string= (event-datom-operation datom) "assert")
                  (setf (gethash key active) datom)
                  (remhash key active))))
          (remove-if-not
           (lambda (datom)
             (let* ((key (list (term-hash (event-datom-entity datom))
                               (term-hash (event-datom-attribute datom))
                               (term-hash (event-datom-value datom))))
                    (current (gethash key active)))
               (and current (term-equal current datom))))
           all)))))

(defun event-db-datoms (database &key as-of history)
  "Return canonical datom terms visible in DATABASE, optionally including history."
  (when (typep database 'event-database-view)
    (unless as-of (setf as-of (%event-db-view-as-of database)))
    (setf database (%event-db-view-database database)))
  (with-event-db-lock (database)
    (%event-db-visible-datoms-unlocked
     database (%event-db-as-of-sequence database as-of) history)))

(defun %event-db-query-variable-p (value)
  (and (symbolp value)
       (plusp (length (symbol-name value)))
       (char= (char (symbol-name value) 0) #\?)))

(defun %event-db-query-wildcard-p (value)
  (and (symbolp value) (string= (symbol-name value) "_")))

(defun %event-db-unify (pattern value bindings)
  (cond
    ((%event-db-query-wildcard-p pattern) (values bindings t))
    ((%event-db-query-variable-p pattern)
     (let ((binding (assoc pattern bindings)))
       (cond
         ((null binding) (values (acons pattern value bindings) t))
         ((term-equal (cdr binding) value) (values bindings t))
         (t (values nil nil)))))
    ((term-equal (%event-db-value-term pattern) value) (values bindings t))
    (t (values nil nil))))

(defun %event-db-match-clause (clause datom bindings)
  (unless (and (listp clause) (member (length clause) '(3 5)))
    (error 'event-database-error :datum clause
           :reason "query clauses are (E A V) or (E A V TX OP)"))
  (let ((values (list (event-datom-entity datom)
                      (event-datom-attribute datom)
                      (event-datom-value datom)
                      (make-integer-atom (event-datom-transaction datom))
                      (make-symbol-atom (event-datom-operation datom)))))
    (loop with current = bindings
          for pattern in clause
          for value in values
          do (multiple-value-bind (next matched-p)
                 (%event-db-unify pattern value current)
               (unless matched-p (return (values nil nil)))
               (setf current next))
          finally (return (values current t)))))

(defun %event-db-query-value (term raw)
  (if raw
      term
      (if (atom-p term)
          (atom-value term)
          term)))

(defun %event-db-row-key (row)
  (mapcar (lambda (value)
            (if (term-p value) (term-hash value) value))
          (if (listp row) row (list row))))

(defun %event-db-deduplicate (rows)
  (let ((seen (make-hash-table :test #'equal))
        (result nil))
    (dolist (row rows (nreverse result))
      (let ((key (%event-db-row-key row)))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push row result))))))

(defun event-db-query (database clauses &key find as-of raw history)
  "Run compact Datalog-style EAV clauses with joins.
Variables are symbols beginning with ?. FIND is a variable or list of variables.
Without FIND, return binding alists. Atomic values are projected to Lisp unless
RAW is true. HISTORY includes retracted datoms and enables TX/OP clauses."
  (let* ((datoms (event-db-datoms database :as-of as-of :history history))
         (bindings (list nil)))
    (dolist (clause clauses)
      (let ((next nil))
        (dolist (binding bindings)
          (dolist (datom datoms)
            (multiple-value-bind (unified matched-p)
                (%event-db-match-clause clause datom binding)
              (when matched-p (push unified next)))))
        (setf bindings (nreverse next))))
    (let ((rows
            (cond
              ((null find)
               (mapcar
                (lambda (binding)
                  (mapcar (lambda (pair)
                            (cons (car pair)
                                  (%event-db-query-value (cdr pair) raw)))
                          (reverse binding)))
                bindings))
              ((symbolp find)
               (mapcar (lambda (binding)
                         (%event-db-query-value
                          (or (cdr (assoc find binding))
                              (error 'event-database-error :datum find
                                     :reason "FIND variable is unbound"))
                          raw))
                       bindings))
              (t
               (mapcar
                (lambda (binding)
                  (mapcar
                   (lambda (variable)
                     (%event-db-query-value
                      (or (cdr (assoc variable binding))
                          (error 'event-database-error :datum variable
                                 :reason "FIND variable is unbound"))
                      raw))
                   find))
                bindings)))))
      (%event-db-deduplicate rows))))

(defun event-db-subscribe (database clauses callback
                           &key find raw history (emit-initial t))
  "Subscribe CALLBACK to query results after each committed transaction.
CALLBACK receives (ROWS TRANSACTION DATABASE); TRANSACTION is NIL initially."
  (unless (functionp callback)
    (error 'event-database-error :datum callback :reason "subscription callback is not a function"))
  (let ((subscription nil))
    (with-event-db-lock (database)
      (setf subscription
            (make-instance 'event-db-subscription
                           :database database
                           :id (incf (%event-db-next-subscription-id database))
                           :kind :query :clauses clauses :find find :raw raw
                           :history history :callback callback))
      (setf (%event-db-subscriptions database)
            (append (%event-db-subscriptions database) (list subscription))))
    (when emit-initial
      (funcall callback
               (event-db-query database clauses :find find :raw raw :history history)
               nil database))
    subscription))

(defun event-db-tail (database callback &key (from 0))
  "Deliver existing transactions from FROM, then each new transaction live.
CALLBACK receives (TRANSACTION DATABASE)."
  (unless (and (integerp from) (<= 0 from))
    (error 'event-database-error :datum from :reason "tail offset must be nonnegative"))
  (unless (functionp callback)
    (error 'event-database-error :datum callback :reason "tail callback is not a function"))
  (let ((subscription nil)
        (existing nil))
    (with-event-db-lock (database)
      (setf existing (subseq (%event-db-transactions database)
                             (min from (length (%event-db-transactions database))))
            subscription
            (make-instance 'event-db-subscription
                           :database database
                           :id (incf (%event-db-next-subscription-id database))
                           :kind :tail :callback callback))
      (setf (%event-db-subscriptions database)
            (append (%event-db-subscriptions database) (list subscription))))
    (dolist (transaction existing)
      (funcall callback transaction database))
    subscription))

(defun event-db-unsubscribe (subscription)
  (unless (typep subscription 'event-db-subscription)
    (error 'event-database-error :datum subscription :reason "not an event database subscription"))
  (let ((database (%event-db-subscription-database subscription)))
    (with-event-db-lock (database)
      (setf (event-db-subscription-active-p subscription) nil
            (%event-db-subscriptions database)
            (remove subscription (%event-db-subscriptions database)))))
  t)

;;; Subzero projection

(defun event-db-trial-scope (parent-scope effect-root)
  (format nil "~A/trial/~A" parent-scope effect-root))

(defun %event-db-term-native (term)
  (and term (atom-p term) (atom-value term)))

(defun %event-db-optional-field (term name)
  (and (term-p term) (term-field term name nil)))

(defun %event-db-model-request-p (request)
  (and (%event-db-tag-p request "model-request")
       (let ((abi (%event-db-optional-field request "abi")))
         (and abi (atom-p abi) (eq (atom-kind abi) :symbol)
              (string= (atom-value abi) "model/v1")))))

(defun %event-db-render-model-prompt (request)
  (if (fboundp 'render-model-prompt)
      (funcall (symbol-function 'render-model-prompt) request)
      (with-output-to-string (stream) (write-term request stream))))

(defun %event-db-add-usage-facts (facts entity prefix usage)
  (dolist (name '("effects" "eval-steps" "events"))
    (let ((value (%event-db-optional-field usage name)))
      (when value
        (push (list entity (format nil "~A/~A" prefix name) value) facts))))
  facts)

(defun event-db-register-subzero-run (database scope initial-root mode &optional parent-scope)
  (let ((facts (list (list scope :db/type :subzero-run)
                     (list scope :run/initial-root initial-root)
                     (list scope :run/mode mode)
                     (list scope :replay/authority :subzero-log))))
    (when parent-scope
      (push (list scope :run/parent parent-scope) facts)
      (push (list parent-scope :run/child scope) facts))
    (event-db-transact database (nreverse facts)
                       :source (format nil "subzero-run:~A" scope))))

(defun %event-db-project-effect-request (scope entry-root effect facts)
  (let* ((call (term-hash effect))
         (capability (%event-db-term-native (%event-db-optional-field effect "capability")))
         (request (%event-db-optional-field effect "request"))
         (context (%event-db-optional-field effect "context")))
    (setf facts
          (append
           facts
           (list (list call :db/type :effect-call)
                 (list call :subzero/run scope)
                 (list call :effect/log-entry entry-root)
                 (list call :effect/capability (or capability :unknown))
                 (list call :effect/request-root (if request (term-hash request) (term-hash (empty-term)))))))
    (let ((id (%event-db-optional-field effect "id"))
          (world (and context (%event-db-optional-field context "world"))))
      (when id (push (list call :effect/id id) facts))
      (when world (push (list call :effect/context-world world) facts)))
    (cond
      ((and capability (string= capability "model") request
            (%event-db-model-request-p request))
       (setf facts
             (append
              facts
              (list (list call :db/type :model-call)
                    (list call :model/request-hash (term-hash request))
                    (list call :model/prompt (%event-db-render-model-prompt request))
                    (list call :model/request request)
                    (list call :model/status :pending))))
       (let* ((limits (%event-db-optional-field request "limits"))
              (maximum (and limits (%event-db-optional-field limits "max-output-bytes"))))
         (when maximum (push (list call :model/max-output-bytes maximum) facts))))
      ((and capability (string= capability "trial"))
       (let ((child-scope (event-db-trial-scope scope call)))
         (push (list call :db/type :trial-call) facts)
         (push (list call :trial/run child-scope) facts)
         (push (list child-scope :run/parent scope) facts))))
    facts))

(defun %event-db-project-model-response (call response facts)
  (cond
    ((%event-db-tag-p response "model-result")
     (let* ((text (%event-db-optional-field response "text"))
            (finish (%event-db-optional-field response "finish-reason"))
            (usage (%event-db-optional-field response "usage"))
            (telemetry (format nil "~A/provider-telemetry" call)))
       (when text (push (list call :model/result-text text) facts))
       (when finish (push (list call :model/finish-reason finish) facts))
       (when usage
         (push (list call :model/provider-telemetry telemetry) facts)
         (push (list telemetry :db/type :provider-telemetry) facts)
         (push (list telemetry :projection/only :true) facts)
         (push (list telemetry :telemetry/source :provider-response) facts)
         (dolist (name '("input-tokens" "output-tokens"))
           (let ((value (%event-db-optional-field usage name)))
             (when value
               (push (list telemetry (format nil "telemetry/~A" name) value) facts)))))))
    ((%event-db-tag-p response "model-failure")
     (let ((kind (%event-db-optional-field response "kind"))
           (message (%event-db-optional-field response "message")))
       (when kind (push (list call :model/failure-kind kind) facts))
       (when message (push (list call :model/failure-message message) facts)))))
  facts)

(defun %event-db-project-effect-result (database scope event facts)
  (declare (ignore database))
  (let* ((call-term (%event-db-optional-field event "request-hash"))
         (call (%event-db-term-native call-term))
         (capability (%event-db-term-native (%event-db-optional-field event "capability")))
         (status (%event-db-optional-field event "status"))
         (response (%event-db-optional-field event "response"))
         (usage (%event-db-optional-field event "usage"))
         (nested-log nil))
    (when call
      (when status
        (push (list call :effect/status status) facts)
        (when (and capability (string= capability "model"))
          (push (list call :model/status :pending :retract) facts)
          (push (list call :model/status status) facts)))
      (when response
        (push (list call :effect/response-root (term-hash response)) facts)
        (push (list call :effect/response response) facts))
      (when usage
        (setf facts (%event-db-add-usage-facts facts call "resource" usage)))
      (cond
        ((and capability (string= capability "model") response)
         (setf facts (%event-db-project-model-response call response facts)))
        ((and capability (string= capability "trial") response
              (%event-db-tag-p response "trial-result"))
         (let ((candidate (%event-db-optional-field response "candidate"))
               (completed (%event-db-optional-field response "completed"))
               (final-root (%event-db-optional-field response "final-root"))
               (event-log (%event-db-optional-field response "event-log"))
               (child-scope (event-db-trial-scope scope call)))
           (push (list call :trial/run child-scope) facts)
           (when candidate (push (list call :trial/candidate candidate) facts))
           (when completed (push (list call :trial/completed completed) facts))
           (when final-root (push (list call :trial/final-root final-root) facts))
           (when (and event-log (atom-p event-log)
                      (eq (atom-kind event-log) :string))
             (setf nested-log (atom-value event-log))
             (push (list call :trial/event-log nested-log) facts))))))
    (values facts nested-log)))

(defun event-db-project-subzero-entry (database scope entry &key parent-scope)
  "Project one authoritative hash-chained Subzero log entry into DATABASE."
  (unless (%event-db-tag-p entry "log-entry")
    (error 'event-database-error :datum entry :reason "not a Subzero log entry"))
  (let* ((entry-root (term-hash entry))
         (sequence (%event-db-required-field entry "sequence"))
         (previous (%event-db-required-field entry "previous"))
         (type (%event-db-required-field entry "type"))
         (type-name (%event-db-symbol-value type))
         (payload (%event-db-required-field entry "payload"))
         (payload-root (term-hash payload))
         (facts (list (list entry-root :db/type :subzero-log-entry)
                      (list entry-root :subzero/run scope)
                      (list entry-root :log/sequence sequence)
                      (list entry-root :log/type type)
                      (list entry-root :log/payload-root payload-root)
                      (list entry-root :log/payload payload)
                      (list entry-root :replay/authority :subzero-log)))
         (nested-log nil))
    (when parent-scope
      (push (list scope :run/parent parent-scope) facts))
    (when (and (atom-p previous) (eq (atom-kind previous) :string))
      (push (list entry-root :log/previous previous) facts))
    (cond
      ((string= type-name "input")
       (push (list payload-root :db/type :subzero-event) facts)
       (push (list payload-root :subzero/run scope) facts)
       (let ((kind (%event-db-optional-field payload "kind")))
         (when kind (push (list payload-root :event/kind kind) facts))))
      ((string= type-name "effect-request")
       (setf facts (%event-db-project-effect-request scope entry-root payload facts)))
      ((string= type-name "effect-result")
       (multiple-value-setq (facts nested-log)
         (%event-db-project-effect-result database scope payload facts))))
    (multiple-value-bind (transaction created-p)
        (event-db-transact database (nreverse facts) :source entry-root)
      (declare (ignore created-p))
      (when (and nested-log (store-exists-p (event-db-store database) nested-log))
        (let* ((call (%event-db-term-native (%event-db-optional-field payload "request-hash")))
               (child-scope (event-db-trial-scope scope call)))
          (event-db-project-log-root database nested-log
                                     :scope child-scope :parent-scope scope)))
      transaction)))

(defun event-db-project-log-root (database log-root &key scope parent-scope)
  "Project a stored Subzero event log, recursively including nested trial logs."
  (let* ((log (store-get (event-db-store database) log-root))
         (initial (%event-db-string-value (%event-db-required-field log "initial")))
         (scope (or scope (format nil "subzero/~A" initial))))
    (unless (%event-db-tag-p log "event-log")
      (error 'event-database-error :datum log :reason "not a Subzero event log"))
    (event-db-register-subzero-run database scope initial :import parent-scope)
    (dolist (entry (term-list-elements (%event-db-required-field log "entries")))
      (event-db-project-subzero-entry database scope entry :parent-scope parent-scope))
    database))
