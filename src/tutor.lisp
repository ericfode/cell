;;;; src/tutor.lisp

(in-package #:cell-zero)

(defparameter +tutor-v1-abi+ "tutor/v1")
(defparameter +candidate-v1-abi+ "candidate/v1")

(defun tutor-v1-abi ()
  +tutor-v1-abi+)

(defun tutor-term-list (value description)
  (handler-case
      (term-list-elements value)
    (cell-zero-error ()
      (error 'protocol-error :datum value :reason description))))

(defun tutor-claims-valid-p (claims)
  (handler-case
      (and (tagged-term-p claims "claims")
           (progn (tutor-term-list (required-field claims "automatic")
                                   "automatic claims are not a list")
                  t)
           (progn (tutor-term-list (required-field claims "semantic")
                                   "semantic claims are not a list")
                  t))
    (cell-zero-error () nil)))

(defun make-tutor-lesson (kind content)
  (unless (term-p content)
    (error 'protocol-error :datum content :reason "tutor lesson content is not a term"))
  (make-tagged-term
   "tutor-lesson"
   (make-field "kind" (make-symbol-atom kind))
   (make-field "content" content)))

(defun tutor-lesson-kind (lesson)
  (symbol-term-value (required-field lesson "kind")))

(defun tutor-lesson-content (lesson)
  (required-field lesson "content"))

(defun tutor-lesson-valid-p (lesson)
  (handler-case
      (and (tagged-term-p lesson "tutor-lesson")
           (progn (tutor-lesson-kind lesson) t)
           (term-p (tutor-lesson-content lesson)))
    (cell-zero-error () nil)))

(defun make-candidate-artifact (genome state claims &key (lessons nil))
  "Construct an explicit candidate/v1 artifact around a genome/v1 source bundle."
  (unless (source-genome-valid-p genome)
    (error 'protocol-error :datum genome :reason "candidate genome is not genome/v1"))
  (unless (term-p state)
    (error 'protocol-error :datum state :reason "candidate initial state is not a term"))
  (unless (tutor-claims-valid-p claims)
    (error 'protocol-error :datum claims :reason "candidate claims are malformed"))
  (unless (and (listp lessons) (every #'tutor-lesson-valid-p lessons))
    (error 'protocol-error :datum lessons :reason "candidate lessons are malformed"))
  (make-tagged-term
   "candidate-artifact"
   (make-field "abi" (make-symbol-atom +candidate-v1-abi+))
   (make-field "genome" genome)
   (make-field "state" state)
   (make-field "claims" claims)
   (make-field "lessons" (term-list-from-elements lessons))))

(defun candidate-artifact-genome (artifact)
  (required-field artifact "genome"))

(defun candidate-artifact-state (artifact)
  (required-field artifact "state"))

(defun candidate-artifact-claims (artifact)
  (required-field artifact "claims"))

(defun candidate-artifact-lessons (artifact)
  (term-list-elements (required-field artifact "lessons")))

(defun candidate-artifact-valid-p (artifact)
  (handler-case
      (and (tagged-term-p artifact "candidate-artifact")
           (model-symbol-name-p (required-field artifact "abi") +candidate-v1-abi+)
           (source-genome-valid-p (candidate-artifact-genome artifact))
           (term-p (candidate-artifact-state artifact))
           (tutor-claims-valid-p (candidate-artifact-claims artifact))
           (every #'tutor-lesson-valid-p (candidate-artifact-lessons artifact)))
    (cell-zero-error () nil)))

(defun candidate-artifact-world (artifact)
  (unless (candidate-artifact-valid-p artifact)
    (error 'protocol-error :datum artifact :reason "invalid candidate/v1 artifact"))
  (make-tagged-term
   "world"
   (make-field "genome" (candidate-artifact-genome artifact))
   (make-field "state" (candidate-artifact-state artifact))))

(defun make-tutor-request (objective parent &key (context (empty-term)))
  "Construct an explicit tutor/v1 evolution request.
PARENT is the complete parent world so a host can inspect its source bundle."
  (unless (term-p objective)
    (error 'protocol-error :datum objective :reason "tutor objective is not a term"))
  (unless (term-p parent)
    (error 'protocol-error :datum parent :reason "tutor parent is not a term"))
  (unless (term-p context)
    (error 'protocol-error :datum context :reason "tutor context is not a term"))
  (make-tagged-term
   "tutor-request"
   (make-field "abi" (make-symbol-atom +tutor-v1-abi+))
   (make-field "kind" (make-symbol-atom "evolve"))
   (make-field "objective" objective)
   (make-field "parent" parent)
   (make-field "context" context)))

(defun tutor-request-objective (request)
  (required-field request "objective"))

(defun tutor-request-parent (request)
  (required-field request "parent"))

(defun tutor-request-context (request)
  (required-field request "context"))

(defun tutor-request-valid-p (request)
  (handler-case
      (and (tagged-term-p request "tutor-request")
           (model-symbol-name-p (required-field request "abi") +tutor-v1-abi+)
           (model-symbol-name-p (required-field request "kind") "evolve")
           (term-p (tutor-request-objective request))
           (world-valid-p (tutor-request-parent request) :load-p nil)
           (term-p (tutor-request-context request)))
    (cell-zero-error () nil)))

(defun ensure-tutor-request (request)
  (unless (tutor-request-valid-p request)
    (error 'protocol-error :datum request :reason "invalid tutor/v1 request"))
  request)

(defun tutor-request-hash (request)
  (term-hash (ensure-tutor-request request)))

(defun tutor-candidate-term (candidate)
  (cond
    ((null candidate) (empty-term))
    ((candidate-artifact-valid-p candidate) candidate)
    (t
     (error 'protocol-error :datum candidate
            :reason "tutor candidate is not a candidate/v1 artifact"))))

(defun make-tutor-result (request &key (lessons nil) candidate)
  (ensure-tutor-request request)
  (unless (and (listp lessons) (every #'tutor-lesson-valid-p lessons))
    (error 'protocol-error :datum lessons :reason "invalid tutor lessons"))
  (make-tagged-term
   "tutor-result"
   (make-field "abi" (make-symbol-atom +tutor-v1-abi+))
   (make-field "request-hash" (make-string-atom (tutor-request-hash request)))
   (make-field "lessons" (term-list-from-elements lessons))
   (make-field "candidate" (tutor-candidate-term candidate))))

(defun tutor-result-lessons (result)
  (term-list-elements (required-field result "lessons")))

(defun tutor-result-candidate (result)
  (let ((candidate (required-field result "candidate")))
    (unless (term-equal candidate (empty-term)) candidate)))

(defun tutor-result-valid-p (result &optional request)
  (handler-case
      (let ((candidate (tutor-result-candidate result)))
        (and (tagged-term-p result "tutor-result")
             (model-symbol-name-p (required-field result "abi") +tutor-v1-abi+)
             (model-hash-string-p (required-field result "request-hash"))
             (every #'tutor-lesson-valid-p (tutor-result-lessons result))
             (or (null candidate) (candidate-artifact-valid-p candidate))
             (or (null request)
                 (and (tutor-request-valid-p request)
                      (string= (string-term-value
                                (required-field result "request-hash"))
                               (tutor-request-hash request))))))
    (cell-zero-error () nil)))

(defun make-tutor-failure (request kind message)
  (ensure-tutor-request request)
  (unless (stringp message)
    (error 'protocol-error :datum message :reason "tutor failure message is not a string"))
  (make-tagged-term
   "tutor-failure"
   (make-field "abi" (make-symbol-atom +tutor-v1-abi+))
   (make-field "request-hash" (make-string-atom (tutor-request-hash request)))
   (make-field "kind" (make-symbol-atom kind))
   (make-field "message" (make-string-atom message))))

(defun tutor-failure-valid-p (failure &optional request)
  (handler-case
      (and (tagged-term-p failure "tutor-failure")
           (model-symbol-name-p (required-field failure "abi") +tutor-v1-abi+)
           (model-hash-string-p (required-field failure "request-hash"))
           (progn (symbol-term-value (required-field failure "kind")) t)
           (progn (string-term-value (required-field failure "message")) t)
           (or (null request)
               (and (tutor-request-valid-p request)
                    (string= (string-term-value
                              (required-field failure "request-hash"))
                             (tutor-request-hash request)))))
    (cell-zero-error () nil)))

(defun tutor-handler-response-valid-p (status response request)
  (cond
    ((string= status "ok") (tutor-result-valid-p response request))
    ((string= status "error") (tutor-failure-valid-p response request))
    (t nil)))

(defun make-tutor-exchange (request status response usage)
  (ensure-tutor-request request)
  (let ((status (canonical-symbol-name status)))
    (unless (tutor-handler-response-valid-p status response request)
      (error 'protocol-error :datum response
             :reason "tutor handler status and response disagree"))
    (unless (model-resource-usage-valid-p usage)
      (error 'protocol-error :datum usage
             :reason "invalid tutor handler resource usage"))
    (make-tagged-term
     "tutor-exchange"
     (make-field "request" request)
     (make-field "request-hash" (make-string-atom (tutor-request-hash request)))
     (make-field "status" (make-symbol-atom status))
     (make-field "response" response)
     (make-field "response-hash" (make-string-atom (term-hash response)))
     (make-field "usage" usage))))

(defun tutor-exchange-valid-p (exchange)
  (handler-case
      (let* ((request (required-field exchange "request"))
             (status (symbol-term-value (required-field exchange "status")))
             (response (required-field exchange "response")))
        (and (tagged-term-p exchange "tutor-exchange")
             (tutor-request-valid-p request)
             (string= (string-term-value (required-field exchange "request-hash"))
                      (tutor-request-hash request))
             (tutor-handler-response-valid-p status response request)
             (string= (string-term-value (required-field exchange "response-hash"))
                      (term-hash response))
             (model-resource-usage-valid-p (required-field exchange "usage"))))
    (cell-zero-error () nil)))

(defun make-tutor-transcript (&optional (exchanges nil))
  (unless (and (listp exchanges) (every #'tutor-exchange-valid-p exchanges))
    (error 'protocol-error :datum exchanges :reason "invalid tutor transcript exchanges"))
  (make-tagged-term
   "tutor-transcript"
   (make-field "abi" (make-symbol-atom +tutor-v1-abi+))
   (make-field "exchanges" (term-list-from-elements exchanges))))

(defun tutor-transcript-exchanges (transcript)
  (term-list-elements (required-field transcript "exchanges")))

(defun tutor-transcript-valid-p (transcript)
  (handler-case
      (and (tagged-term-p transcript "tutor-transcript")
           (model-symbol-name-p (required-field transcript "abi") +tutor-v1-abi+)
           (every #'tutor-exchange-valid-p
                  (tutor-transcript-exchanges transcript)))
    (cell-zero-error () nil)))

(defun make-recording-tutor-handler (handler)
  "Wrap a hosted tutor and return it with a replayable transcript reader."
  (unless (functionp handler)
    (error 'protocol-error :datum handler :reason "tutor handler is not a function"))
  (let ((exchanges nil))
    (values
     (lambda (subzero request budget effect)
       (ensure-tutor-request request)
       (multiple-value-bind (status response usage)
           (funcall handler subzero request budget effect)
         (let ((status (canonical-symbol-name status)))
           (unless (tutor-handler-response-valid-p status response request)
             (error 'protocol-error :datum response
                    :reason "tutor handler returned an invalid response"))
           (unless (model-resource-usage-valid-p usage)
             (error 'protocol-error :datum usage
                    :reason "tutor handler returned invalid resource usage"))
           (push (make-tutor-exchange request status response usage) exchanges)
           (values status response usage))))
     (lambda ()
       (make-tutor-transcript (nreverse (copy-list exchanges)))))))

(defun make-tutor-fixture-handler (transcript)
  "Return a standalone deterministic tutor and a consumed-p inspector."
  (unless (tutor-transcript-valid-p transcript)
    (error 'protocol-error :datum transcript :reason "invalid tutor transcript"))
  (let ((remaining (tutor-transcript-exchanges transcript)))
    (values
     (lambda (subzero request budget effect)
       (declare (ignore subzero budget effect))
       (unless remaining
         (error 'protocol-error :datum request :reason "tutor fixture transcript exhausted"))
       (let* ((exchange (pop remaining))
              (expected (required-field exchange "request")))
         (unless (term-equal request expected)
           (error 'protocol-error :datum request :reason "tutor fixture request mismatch"))
         (values
          (symbol-term-value (required-field exchange "status"))
          (required-field exchange "response")
          (required-field exchange "usage"))))
     (lambda () (null remaining)))))
