;;;; test/event-db-tests.lisp

(in-package #:cell-zero.tests)

(defun make-inert-legacy-world ()
  (cell-zero::make-world
   (cell-zero::make-inert-react-program)
   (cell-zero::make-always-accept-admit-program)
   (sexp->term '(data (capabilities ())))))

(deftest temporal-event-database-joins-retractions-and-as-of
  (let ((database (make-event-database (make-term-store))))
    (multiple-value-bind (first created-p)
        (event-db-transact
         database
         '(("ada" :person/name "Ada")
           ("bob" :person/name "Bob")
           ("ada" :person/knows "bob"))
         :source "fixture/first")
      (is created-p)
      (is (= 0 (event-db-transaction-sequence first)))
      (is (null (event-db-transaction-previous first)))
      (is (equal '(("ada" "Bob"))
                 (event-db-query
                  database
                  '((?person :person/knows ?friend)
                    (?friend :person/name ?name))
                  :find '(?person ?name))))
      (multiple-value-bind (second second-created-p)
          (event-db-transact
           database
           '(("bob" :person/name "Bob" :retract)
             ("bob" :person/name "Robert"))
           :source "fixture/second")
        (is second-created-p)
        (is (string= (term-hash first)
                     (event-db-transaction-previous second)))
        (is (equal '(("ada" "Robert"))
                   (event-db-query
                    database
                    '((?person :person/knows ?friend)
                      (?friend :person/name ?name))
                    :find '(?person ?name))))
        (is (equal '(("ada" "Bob"))
                   (event-db-query
                    (event-db-as-of database first)
                    '((?person :person/knows ?friend)
                      (?friend :person/name ?name))
                    :find '(?person ?name))))
        (is (= 3
               (length
                (event-db-query
                 database
                 '(("bob" :person/name ?name ?tx ?operation))
                 :find '(?name ?operation)
                 :history t))))
        (multiple-value-bind (same created-again-p)
            (event-db-transact database '(("ignored" :value 1))
                               :source "fixture/second")
          (is (not created-again-p))
          (is (term-equal second same))
          (is (= 2 (event-db-transaction-count database))))))))

(deftest event-database-persists-reopens-subscribes-and-tails
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((store (make-term-store :directory directory))
                (database (make-event-database store :name "requests"))
                (query-updates nil)
                (tailed nil)
                (query-subscription
                  (event-db-subscribe
                   database '((?entity :status ?status))
                   (lambda (rows transaction ignored-database)
                     (declare (ignore ignored-database))
                     (push (list rows (and transaction
                                           (event-db-transaction-sequence transaction)))
                           query-updates))
                   :find '(?entity ?status)))
                (tail-subscription
                  (event-db-tail
                   database
                   (lambda (transaction ignored-database)
                     (declare (ignore ignored-database))
                     (push (event-db-transaction-sequence transaction) tailed)))))
           (event-db-transact database '(("call/1" :status :pending)))
           (event-db-transact database
                              '(("call/1" :status :pending :retract)
                                ("call/1" :status :ok)))
           (is (equal '(0 1) (reverse tailed)))
           (is (= 3 (length query-updates)))
           (is (event-db-subscription-active-p query-subscription))
           (is (event-db-unsubscribe query-subscription))
           (is (not (event-db-subscription-active-p query-subscription)))
           (is (event-db-unsubscribe tail-subscription))
           (let* ((reopened-store (make-term-store :directory directory))
                  (reopened (reopen-event-database reopened-store "requests")))
             (is (= 2 (event-db-transaction-count reopened)))
             (is (string= (event-db-head database) (event-db-head reopened)))
             (is (equal '(("call/1" "ok"))
                        (event-db-query reopened '((?call :status ?status))
                                        :find '(?call ?status))))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(deftest subzero-projects-exact-model-exchanges
  (let* ((store (make-term-store))
         (database (make-event-database store))
         (subzero (make-subzero store (make-genesis-world)
                                :event-database database))
         (captured-request nil))
    (register-capability-handler
     subzero "model"
     (lambda (ignored-subzero request budget effect)
       (declare (ignore ignored-subzero budget effect))
       (setf captured-request request)
       (values "ok"
               (make-model-result
                request "VISIBLE_RESULT"
                :usage (make-model-usage :input-tokens 11 :output-tokens 5))
               (cell-zero::usage-term :effects 1 :events 1))))
    (submit-event subzero
                  (sexp->term '(event (kind task) (task "show the induced request"))))
    (run-until-idle subzero)
    (let ((before-import (event-db-transaction-count database)))
      (event-db-project-log-root database (subzero-log-root subzero)
                                 :scope (subzero-event-scope subzero))
      (is (= before-import (event-db-transaction-count database))))
    (let* ((rows
             (event-db-query
              database
              '((?call :db/type :model-call)
                (?call :model/request-hash ?request-hash)
                (?call :model/prompt ?prompt)
                (?call :model/status ?status)
                (?call :model/result-text ?result))
              :find '(?call ?request-hash ?prompt ?status ?result)))
           (row (first rows))
           (telemetry
             (event-db-query
              database
              '((?call :model/provider-telemetry ?telemetry)
                (?telemetry :projection/only :true)
                (?telemetry :telemetry/input-tokens ?input)
                (?telemetry :telemetry/output-tokens ?output))
              :find '(?input ?output))))
      (is (= 1 (length rows)))
      (is (string= (model-request-hash captured-request) (second row)))
      (is (string= (render-model-prompt captured-request) (third row)))
      (is (string= "ok" (fourth row)))
      (is (string= "VISIBLE_RESULT" (fifth row)))
      (is (equal '((11 5)) telemetry))
      (is (null
           (event-db-query database
                           '((?call :model/status :pending))
                           :find '?call))))))

(deftest nested-trials-share-visible-event-history
  (let* ((store (make-term-store))
         (database (make-event-database store))
         (subzero (make-subzero store (make-genesis-world)
                                :event-database database))
         (candidate (make-compatible-candidate)))
    (register-capability-handler subzero "model" (make-scripted-model-handler))
    (register-capability-handler subzero "tutor"
                                 (make-scripted-tutor-handler candidate))
    (submit-event subzero
                  (sexp->term
                   `(event
                      (kind evolve)
                      (objective "visible nested trial")
                      (objective-probes ,(objective-improvement-probes)))))
    (run-until-idle subzero)
    (let ((rows
            (event-db-query
             database
             '((?trial :db/type :trial-call)
               (?trial :trial/run ?run)
               (?run :run/parent ?parent)
               (?entry :subzero/run ?run)
               (?entry :log/type :input))
             :find '(?trial ?run ?parent))))
      (is rows)
      (is (every (lambda (row)
                   (search "/trial/" (second row)))
                 rows)))))


(deftest event-database-rolls-back-after-persistence-conflict
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((store (make-term-store :directory directory))
                (stale (make-event-database store :name "rollback"))
                (initial-manifest (cell-zero::%event-db-manifest-root stale))
                (current (reopen-event-database store "rollback")))
           (event-db-transact current '(("winner" :value 1))
                              :source "winner/write")
           (is (signals event-database-error
                 (event-db-transact stale '(("loser" :value 2))
                                    :source "stale/write")))
           (is (= 0 (event-db-transaction-count stale)))
           (is (null (event-db-head stale)))
           (is (string= initial-manifest
                        (cell-zero::%event-db-manifest-root stale)))
           (is (null
                (gethash (term-hash (make-string-atom "stale/write"))
                         (cell-zero::%event-db-sources stale))))
           (is (null (event-db-query stale '((?entity :value ?value))
                                     :find '(?entity ?value))))
           (let ((reopened (reopen-event-database store "rollback")))
             (is (= 1 (event-db-transaction-count reopened)))
             (is (equal '(("winner" 1))
                        (event-db-query reopened '((?entity :value ?value))
                                        :find '(?entity ?value))))))
      (uiop:delete-directory-tree directory :validate t
                                            :if-does-not-exist :ignore))))

(deftest event-database-views-are-immutable-snapshots
  (let ((database (make-event-database (make-term-store))))
    (let* ((first (event-db-transact database '(("item" :status "old"))))
           (view (event-db-as-of database first))
           (second
             (event-db-transact
              database
              '(("item" :status "old" :retract)
                ("item" :status "new")))))
      (is (= 1 (event-db-transaction-count view)))
      (is (= 1 (length (event-db-transactions view))))
      (is (term-equal first (first (event-db-transactions view))))
      (is (equal '("old")
                 (event-db-query view '(("item" :status ?status))
                                 :find '?status)))
      (is (= 1 (event-db-transaction-count (event-db-as-of view nil))))
      (is (signals event-database-error
            (event-db-as-of view second)))
      (is (signals event-database-error
            (event-db-query view '(("item" :status ?status))
                            :find '?status :as-of second)))
      (is (equal '("new")
                 (event-db-query database '(("item" :status ?status))
                                 :find '?status))))))

(deftest event-database-subscription-snapshots-are-ordered-and-nonreentrant
  (let ((database (make-event-database (make-term-store)))
        (active-p nil)
        (reentrant-p nil)
        (trace nil))
    (event-db-subscribe
     database '((?entity :status ?status))
     (lambda (rows transaction ignored-database)
       (declare (ignore ignored-database))
       (when active-p (setf reentrant-p t))
       (setf active-p t)
       (unwind-protect
            (let ((sequence (and transaction
                                 (event-db-transaction-sequence transaction))))
              (push (list :enter sequence rows) trace)
              (unless transaction
                (event-db-transact database '(("item" :status "ready"))))
              (push (list :exit sequence rows) trace))
         (setf active-p nil)))
     :find '(?entity ?status))
    (is (not reentrant-p))
    (is (equal '((:enter nil nil)
                 (:exit nil nil)
                 (:enter 0 (("item" "ready")))
                 (:exit 0 (("item" "ready"))))
               (reverse trace)))))

(deftest event-database-disables-only-the-failed-subscription
  (let ((database (make-event-database (make-term-store)))
        (updates nil)
        (failed nil))
    (setf failed
          (event-db-subscribe
           database '((?entity :value ?value))
           (lambda (&rest ignored)
             (declare (ignore ignored))
             (error "subscription failure"))
           :find '(?entity ?value) :emit-initial nil))
    (event-db-subscribe
     database '((?entity :value ?value))
     (lambda (rows transaction ignored-database)
       (declare (ignore rows ignored-database))
       (push (event-db-transaction-sequence transaction) updates))
     :find '(?entity ?value) :emit-initial nil)
    (handler-bind ((warning #'muffle-warning))
      (event-db-transact database '(("first" :value 1)))
      (event-db-transact database '(("second" :value 2))))
    (is (not (event-db-subscription-active-p failed)))
    (is (equal '(0 1) (reverse updates)))))

(deftest subzero-projection-identities-are-scoped
  (let* ((database (make-event-database (make-term-store)))
         (entry
           (sexp->term
            '(log-entry
              (sequence 0)
              (previous nil)
              (type effect-request)
              (payload
               (effect
                (id 1)
                (capability echo)
                (request "same request")
                (budget (max-effects 1)))))))
         (effect (term-field entry "payload"))
         (effect-root (term-hash effect)))
    (cell-zero::event-db-project-subzero-entry database "scope/one" entry)
    (cell-zero::event-db-project-subzero-entry database "scope/two" entry)
    (let ((rows
            (event-db-query
             database
             '((?call :db/type :effect-call)
               (?call :subzero/run ?run)
               (?call :effect/root ?root))
             :find '(?call ?run ?root))))
      (is (= 2 (length rows)))
      (is (= 2 (length (remove-duplicates (mapcar #'first rows)
                                          :test #'string=))))
      (is (equal '("scope/one" "scope/two")
                 (sort (mapcar #'second rows) #'string<)))
      (is (every (lambda (row) (string= effect-root (third row))) rows)))))

(deftest subzero-log-import-is-replay-validated-before-projection
  (let* ((store (make-term-store))
         (subzero (make-subzero store (make-inert-legacy-world)))
         (template (store-get store (subzero-log-root subzero)))
         (entry
           (cell-zero::make-tagged-term
            "log-entry"
            (cell-zero::make-field "sequence" (make-integer-atom 0))
            (cell-zero::make-field "previous" (empty-term))
            (cell-zero::make-field "type" (make-symbol-atom "input"))
            (cell-zero::make-field
             "payload" (sexp->term '(event (kind nil))))))
         (log
           (cell-zero::make-tagged-term
            "event-log"
            (cell-zero::make-field "initial" (term-field template "initial"))
            (cell-zero::make-field "capabilities"
                                   (term-field template "capabilities"))
            (cell-zero::make-field "limits" (term-field template "limits"))
            (cell-zero::make-field "entries"
                                   (cell-zero::make-list-term (list entry)))))
         (log-root (store-put store log))
         (database (make-event-database store)))
    (is (signals protocol-error
          (event-db-project-log-root database log-root :scope "invalid/import")))
    (is (= 0 (event-db-transaction-count database)))))

(deftest nested-trace-logs-are-replay-validated-and-imported
  (let* ((store (make-term-store))
         (database (make-event-database store))
         (child (make-subzero store (make-inert-legacy-world)))
         (parent-scope "import/root"))
    (submit-event child (sexp->term '(event (kind nested-input))))
    (let* ((child-log-root (subzero-log-root child))
           (trace
             (cell-zero::make-tagged-term
              "trial-result"
              (cell-zero::make-field
               "final-root" (make-string-atom (subzero-current-root child)))
              (cell-zero::make-field
               "event-log" (make-string-atom child-log-root))))
           (trace-root (store-put store trace))
           (effect
             (sexp->term
              '(effect
                (id 1)
                (capability trial)
                (request (trial-request))
                (budget (max-effects 1)))))
           (effect-root (term-hash effect))
           (request-entry
             (cell-zero::make-tagged-term
              "log-entry"
              (cell-zero::make-field "sequence" (make-integer-atom 0))
              (cell-zero::make-field "previous" (empty-term))
              (cell-zero::make-field "type" (make-symbol-atom "effect-request"))
              (cell-zero::make-field "payload" effect)))
           (response
             (cell-zero::make-tagged-term
              "trial-result"
              (cell-zero::make-field "trace" (make-string-atom trace-root))
              (cell-zero::make-field "completed" (true-term))))
           (result
             (cell-zero::make-tagged-term
              "event"
              (cell-zero::make-field "kind" (make-symbol-atom "effect-result"))
              (cell-zero::make-field "request-hash"
                                     (make-string-atom effect-root))
              (cell-zero::make-field "capability" (make-symbol-atom "trial"))
              (cell-zero::make-field "status" (make-symbol-atom "ok"))
              (cell-zero::make-field "response" response)))
           (result-entry
             (cell-zero::make-tagged-term
              "log-entry"
              (cell-zero::make-field "sequence" (make-integer-atom 1))
              (cell-zero::make-field
               "previous" (make-string-atom (term-hash request-entry)))
              (cell-zero::make-field "type" (make-symbol-atom "effect-result"))
              (cell-zero::make-field "payload" result)))
           (child-scope
             (cell-zero::event-db-trial-scope parent-scope effect-root)))
      (cell-zero::event-db-project-subzero-entry
       database parent-scope request-entry)
      (cell-zero::event-db-project-subzero-entry
       database parent-scope result-entry)
      (let ((rows
              (event-db-query
               database
               '((?run :run/parent ?parent)
                 (?entry :subzero/run ?run)
                 (?entry :log/type :input))
               :find '(?run ?parent ?entry))))
        (is (= 1 (length rows)))
        (is (string= child-scope (first (first rows))))
        (is (string= parent-scope (second (first rows)))))
      (let ((count (event-db-transaction-count database)))
        (cell-zero::event-db-project-subzero-entry
         database parent-scope result-entry)
        (is (= count (event-db-transaction-count database)))))))

(deftest subzero-authority-survives-event-database-observer-failure
  (let ((directory (make-temp-directory)))
    (unwind-protect
         (let* ((store (make-term-store :directory directory))
                (database (make-event-database store :name "observer"))
                (subzero
                  (make-subzero store (make-inert-legacy-world)
                                :event-database database))
                (competitor (reopen-event-database store "observer"))
                (payload (sexp->term '(event (kind observer-failure)))))
           (event-db-transact competitor '(("competitor" :status "advanced"))
                              :source "competitor/write")
           (let ((entry
                   (handler-bind ((warning #'muffle-warning))
                     (cell-zero::append-log-entry subzero "input" payload))))
             (is (= 1 (length (cell-zero::subzero-entries subzero))))
             (is (term-equal payload (term-field entry "payload")))
             (is (= 1 (event-db-transaction-count database)))
             (is (= 2 (event-db-transaction-count competitor)))
             (is (= 2 (event-db-transaction-count
                       (reopen-event-database store "observer"))))))
      (uiop:delete-directory-tree directory :validate t
                                            :if-does-not-exist :ignore))))
