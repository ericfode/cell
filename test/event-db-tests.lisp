;;;; test/event-db-tests.lisp

(in-package #:cell-zero.tests)

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
                  (sexp->term '(event (kind evolve) (objective "visible nested trial"))))
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
