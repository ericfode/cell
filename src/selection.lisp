;;;; src/selection.lisp

(in-package #:cell-zero)

(defparameter +selection-v1-abi+ "selection/v1")
(defparameter +selection-v1-metric+ "passed-objective-probes")

(defun selection-v1-abi ()
  +selection-v1-abi+)

(defun selection-symbol-name-p (term name)
  (and (atom-p term)
       (eq (atom-kind term) :symbol)
       (string= (atom-value term) (canonical-symbol-name name))))

(defun selection-hash-string-p (term)
  (and (atom-p term)
       (eq (atom-kind term) :string)
       (canonical-hash-p (atom-value term))))

(defun selection-term-list (value description)
  (handler-case
      (term-list-elements value)
    (cell-zero-error ()
      (error 'protocol-error :datum value :reason description))))

(defun selection-list-term (values)
  (term-list-from-elements values))

(defun selection-metric-term ()
  (make-symbol-atom +selection-v1-metric+))

(defun make-trial-probe (event expected-outputs)
  "Construct one deterministic trial probe."
  (unless (term-p event)
    (error 'protocol-error :datum event :reason "trial probe event is not a term"))
  (let ((outputs (if (term-p expected-outputs)
                     (selection-term-list expected-outputs
                                          "trial expected outputs are not a list")
                     expected-outputs)))
    (unless (and (listp outputs) (every #'term-p outputs))
      (error 'protocol-error :datum expected-outputs
             :reason "trial expected outputs are malformed"))
    (make-tagged-term
     "probe"
     (make-field "event" event)
     (make-field "expected-outputs" (selection-list-term outputs)))))

(defun trial-probe-event (probe)
  (required-field probe "event"))

(defun trial-probe-expected-outputs (probe)
  (selection-term-list (required-field probe "expected-outputs")
                       "trial expected outputs are not a list"))

(defun trial-probe-valid-p (probe)
  (handler-case
      (and (tagged-term-p probe "probe")
           (term-p (trial-probe-event probe))
           (every #'term-p (trial-probe-expected-outputs probe)))
    (cell-zero-error () nil)))

(defun selection-probe-list (probes description)
  (let ((values (if (term-p probes)
                    (selection-term-list probes description)
                    probes)))
    (unless (and (listp values)
                 (plusp (length values))
                 (every #'trial-probe-valid-p values))
      (error 'protocol-error :datum probes :reason description))
    values))

(defun make-selection-plan (objective regression-probes objective-probes)
  "Construct a content-bound selection/v1 plan before candidate generation."
  (unless (term-p objective)
    (error 'protocol-error :datum objective :reason "selection objective is not a term"))
  (let* ((regression
           (selection-probe-list regression-probes
                                 "selection regression probes are malformed or empty"))
         (objective-values
           (selection-probe-list objective-probes
                                 "selection objective probes are malformed or empty"))
         (regression-term (selection-list-term regression))
         (objective-probes-term (selection-list-term objective-values))
         (metric (selection-metric-term)))
    (make-tagged-term
     "selection-plan"
     (make-field "abi" (make-symbol-atom +selection-v1-abi+))
     (make-field "objective" objective)
     (make-field "objective-hash" (make-string-atom (term-hash objective)))
     (make-field "regression-probes" regression-term)
     (make-field "regression-probes-hash"
                 (make-string-atom (term-hash regression-term)))
     (make-field "objective-probes" objective-probes-term)
     (make-field "objective-probes-hash"
                 (make-string-atom (term-hash objective-probes-term)))
     (make-field "metric" metric)
     (make-field "metric-hash" (make-string-atom (term-hash metric))))))

(defun selection-plan-objective (plan)
  (required-field plan "objective"))

(defun selection-plan-regression-probes-term (plan)
  (required-field plan "regression-probes"))

(defun selection-plan-objective-probes-term (plan)
  (required-field plan "objective-probes"))

(defun selection-plan-regression-probes (plan)
  (selection-term-list (selection-plan-regression-probes-term plan)
                       "selection regression probes are not a list"))

(defun selection-plan-objective-probes (plan)
  (selection-term-list (selection-plan-objective-probes-term plan)
                       "selection objective probes are not a list"))

(defun selection-plan-metric (plan)
  (required-field plan "metric"))

(defun selection-plan-binding-hash (plan field)
  (string-term-value (required-field plan field)))

(defun selection-plan-objective-hash (plan)
  (selection-plan-binding-hash plan "objective-hash"))

(defun selection-plan-regression-probes-hash (plan)
  (selection-plan-binding-hash plan "regression-probes-hash"))

(defun selection-plan-objective-probes-hash (plan)
  (selection-plan-binding-hash plan "objective-probes-hash"))

(defun selection-plan-metric-hash (plan)
  (selection-plan-binding-hash plan "metric-hash"))

(defun selection-binding-valid-p (hash value)
  (and (selection-hash-string-p hash)
       (string= (atom-value hash) (term-hash value))))

(defun selection-plan-valid-p (plan)
  (handler-case
      (let ((objective (selection-plan-objective plan))
            (regression-term (selection-plan-regression-probes-term plan))
            (objective-probes-term (selection-plan-objective-probes-term plan))
            (metric (selection-plan-metric plan)))
        (and (tagged-term-p plan "selection-plan")
             (selection-symbol-name-p (required-field plan "abi") +selection-v1-abi+)
             (term-p objective)
             (plusp (length (selection-plan-regression-probes plan)))
             (every #'trial-probe-valid-p (selection-plan-regression-probes plan))
             (plusp (length (selection-plan-objective-probes plan)))
             (every #'trial-probe-valid-p (selection-plan-objective-probes plan))
             (selection-symbol-name-p metric +selection-v1-metric+)
             (selection-binding-valid-p (required-field plan "objective-hash") objective)
             (selection-binding-valid-p
              (required-field plan "regression-probes-hash") regression-term)
             (selection-binding-valid-p
              (required-field plan "objective-probes-hash") objective-probes-term)
             (selection-binding-valid-p (required-field plan "metric-hash") metric)))
    (cell-zero-error () nil)))

(defun ensure-selection-plan (plan)
  (unless (selection-plan-valid-p plan)
    (error 'protocol-error :datum plan :reason "invalid selection/v1 plan"))
  plan)

(defun selection-plan-hash (plan)
  (term-hash (ensure-selection-plan plan)))

(defun make-selection-fitness (plan score)
  (ensure-selection-plan plan)
  (let ((total (length (selection-plan-objective-probes plan))))
    (unless (and (integerp score) (<= 0 score total))
      (error 'protocol-error :datum score :reason "selection fitness score is out of range"))
    (make-tagged-term
     "fitness"
     (make-field "abi" (make-symbol-atom +selection-v1-abi+))
     (make-field "plan" (make-string-atom (selection-plan-hash plan)))
     (make-field "metric" (selection-plan-metric plan))
     (make-field "metric-hash" (make-string-atom (selection-plan-metric-hash plan)))
     (make-field "score" (make-integer-atom score))
     (make-field "total" (make-integer-atom total)))))

(defun selection-fitness-score (fitness)
  (integer-term-value/protocol (required-field fitness "score")))

(defun selection-fitness-total (fitness)
  (integer-term-value/protocol (required-field fitness "total")))

(defun selection-fitness-valid-p (fitness &optional plan)
  (handler-case
      (let ((metric (required-field fitness "metric")))
        (and (tagged-term-p fitness "fitness")
             (selection-symbol-name-p (required-field fitness "abi") +selection-v1-abi+)
             (selection-hash-string-p (required-field fitness "plan"))
             (selection-symbol-name-p metric +selection-v1-metric+)
             (selection-binding-valid-p (required-field fitness "metric-hash") metric)
             (let ((score (selection-fitness-score fitness))
                   (total (selection-fitness-total fitness)))
               (and (<= 0 score total)
                    (or (null plan)
                        (and (selection-plan-valid-p plan)
                             (string= (string-term-value (required-field fitness "plan"))
                                      (selection-plan-hash plan))
                             (term-equal metric (selection-plan-metric plan))
                             (string= (string-term-value
                                       (required-field fitness "metric-hash"))
                                      (selection-plan-metric-hash plan))
                             (= total
                                (length (selection-plan-objective-probes plan)))))))))
    (cell-zero-error () nil)))

(defun selection-fitness-improves-p (candidate baseline &optional plan)
  (and (selection-fitness-valid-p candidate plan)
       (selection-fitness-valid-p baseline plan)
       (string= (string-term-value (required-field candidate "plan"))
                (string-term-value (required-field baseline "plan")))
       (string= (string-term-value (required-field candidate "metric-hash"))
                (string-term-value (required-field baseline "metric-hash")))
       (= (selection-fitness-total candidate)
          (selection-fitness-total baseline))
       (> (selection-fitness-score candidate)
          (selection-fitness-score baseline))))
