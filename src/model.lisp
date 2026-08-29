;;;; src/model.lisp

(in-package #:cell-zero)

(defparameter +model-v1-abi+ "model/v1")

(defun model-v1-abi ()
  +model-v1-abi+)

(defun model-nonnegative-integer-term-p (term)
  (and (atom-p term)
       (eq (atom-kind term) :integer)
       (<= 0 (atom-value term))))

(defun model-positive-integer-term-p (term)
  (and (model-nonnegative-integer-term-p term)
       (plusp (atom-value term))))

(defun model-string-term-p (term)
  (and (atom-p term) (eq (atom-kind term) :string)))

(defun model-symbol-name-p (term name)
  (and (atom-p term)
       (eq (atom-kind term) :symbol)
       (string= (atom-value term) name)))

(defun model-hash-string-p (term)
  (and (model-string-term-p term)
       (= 64 (length (atom-value term)))
       (every (lambda (character)
                (or (digit-char-p character)
                    (find character "ABCDEF")))
              (atom-value term))))

(defun make-model-text-part (value)
  (unless (stringp value)
    (error 'protocol-error :datum value :reason "model text part is not a string"))
  (make-tagged-term
   "text"
   (make-field "value" (make-string-atom value))))

(defun make-model-term-part (value)
  (unless (term-p value)
    (error 'protocol-error :datum value :reason "model term part is not a term"))
  (make-tagged-term
   "term"
   (make-field "value" value)))

(defun model-part-kind (part)
  (let ((tag (term-tag part)))
    (unless (and tag (atom-p tag) (eq (atom-kind tag) :symbol))
      (error 'protocol-error :datum part :reason "model prompt part has no symbol tag"))
    (atom-value tag)))

(defun model-part-value (part)
  (required-field part "value"))

(defun model-part-valid-p (part)
  (handler-case
      (let ((kind (model-part-kind part))
            (value (model-part-value part)))
        (cond
          ((string= kind "text") (model-string-term-p value))
          ((string= kind "term") (term-p value))
          (t nil)))
    (cell-zero-error () nil)))

(defun model-parts-list (parts)
  (if (term-p parts)
      (term-list-elements parts)
      parts))

(defun make-model-request (parts &key (max-output-bytes 262144))
  "Construct the frozen model/v1 text-completion request.
PARTS is a nonempty list of text and term prompt parts."
  (let ((parts (model-parts-list parts)))
    (unless (and (listp parts) parts (every #'model-part-valid-p parts))
      (error 'protocol-error :datum parts :reason "invalid model/v1 prompt parts"))
    (unless (and (integerp max-output-bytes) (plusp max-output-bytes))
      (error 'protocol-error :datum max-output-bytes
             :reason "max-output-bytes must be positive"))
    (make-tagged-term
     "model-request"
     (make-field "abi" (make-symbol-atom +model-v1-abi+))
     (make-field "kind" (make-symbol-atom "complete"))
     (make-field "prompt" (term-list-from-elements parts))
     (make-field
      "limits"
      (make-tagged-term
       "model-limits"
       (make-field "max-output-bytes"
                   (make-integer-atom max-output-bytes)))))))

(defun model-request-parts (request)
  (term-list-elements (required-field request "prompt")))

(defun model-request-max-output-bytes (request)
  (integer-term-value/protocol
   (required-field (required-field request "limits") "max-output-bytes")))

(defun model-request-valid-p (request)
  (handler-case
      (and (tagged-term-p request "model-request")
           (model-symbol-name-p (required-field request "abi") +model-v1-abi+)
           (model-symbol-name-p (required-field request "kind") "complete")
           (let ((parts (model-request-parts request)))
             (and parts (every #'model-part-valid-p parts)))
           (let ((limits (required-field request "limits")))
             (and (tagged-term-p limits "model-limits")
                  (model-positive-integer-term-p
                   (required-field limits "max-output-bytes")))))
    (cell-zero-error () nil)))

(defun ensure-model-request (request)
  (unless (model-request-valid-p request)
    (error 'protocol-error :datum request :reason "invalid model/v1 request"))
  request)

(defun model-request-hash (request)
  (term-hash (ensure-model-request request)))

(defun render-model-prompt (request)
  "Render REQUEST deterministically for a text-completion provider."
  (ensure-model-request request)
  (with-output-to-string (stream)
    (dolist (part (model-request-parts request))
      (let ((kind (model-part-kind part))
            (value (model-part-value part)))
        (cond
          ((string= kind "text")
           (write-string (string-term-value value) stream))
          ((string= kind "term")
           (write-term value stream)))))))

(defun model-token-term (value)
  (if (null value)
      (make-symbol-atom "unknown")
      (progn
        (unless (and (integerp value) (<= 0 value))
          (error 'protocol-error :datum value
                 :reason "model token usage must be nonnegative or unknown"))
        (make-integer-atom value))))

(defun make-model-usage (&key input-tokens output-tokens)
  (make-tagged-term
   "model-usage"
   (make-field "input-tokens" (model-token-term input-tokens))
   (make-field "output-tokens" (model-token-term output-tokens))))

(defun model-token-value (term)
  (cond
    ((model-symbol-name-p term "unknown") nil)
    ((model-nonnegative-integer-term-p term) (atom-value term))
    (t
     (error 'protocol-error :datum term
            :reason "invalid model token usage value"))))

(defun model-usage-input-tokens (usage)
  (model-token-value (required-field usage "input-tokens")))

(defun model-usage-output-tokens (usage)
  (model-token-value (required-field usage "output-tokens")))

(defun model-usage-valid-p (usage)
  (handler-case
      (and (tagged-term-p usage "model-usage")
           (progn (model-usage-input-tokens usage) t)
           (progn (model-usage-output-tokens usage) t))
    (cell-zero-error () nil)))

(defun model-text-within-request-limit-p (request text)
  (<= (length (string-utf8-octets text))
      (model-request-max-output-bytes request)))

(defun make-model-result (request text
                          &key (finish-reason "complete")
                               (usage (make-model-usage)))
  (ensure-model-request request)
  (unless (stringp text)
    (error 'protocol-error :datum text :reason "model result text is not a string"))
  (unless (model-text-within-request-limit-p request text)
    (error 'protocol-error :datum text :reason "model result exceeds request byte limit"))
  (unless (member (canonical-symbol-name finish-reason)
                  '("complete" "length" "unknown") :test #'string=)
    (error 'protocol-error :datum finish-reason
           :reason "invalid model finish reason"))
  (unless (model-usage-valid-p usage)
    (error 'protocol-error :datum usage :reason "invalid model usage"))
  (make-tagged-term
   "model-result"
   (make-field "abi" (make-symbol-atom +model-v1-abi+))
   (make-field "request-hash" (make-string-atom (model-request-hash request)))
   (make-field "text" (make-string-atom text))
   (make-field "finish-reason" (make-symbol-atom finish-reason))
   (make-field "usage" usage)))

(defun model-result-text (result)
  (string-term-value (required-field result "text")))

(defun model-result-finish-reason (result)
  (symbol-term-value (required-field result "finish-reason")))

(defun model-result-usage (result)
  (required-field result "usage"))

(defun model-result-valid-p (result &optional request)
  (handler-case
      (and (tagged-term-p result "model-result")
           (model-symbol-name-p (required-field result "abi") +model-v1-abi+)
           (model-hash-string-p (required-field result "request-hash"))
           (model-string-term-p (required-field result "text"))
           (member (model-result-finish-reason result)
                   '("complete" "length" "unknown") :test #'string=)
           (model-usage-valid-p (model-result-usage result))
           (or (null request)
               (and (model-request-valid-p request)
                    (string= (string-term-value
                              (required-field result "request-hash"))
                             (model-request-hash request))
                    (model-text-within-request-limit-p
                     request (model-result-text result)))))
    (cell-zero-error () nil)))

(defun ensure-model-result (result &optional request)
  (unless (model-result-valid-p result request)
    (error 'protocol-error :datum result :reason "invalid model/v1 result"))
  result)

(defun make-model-failure (request kind message)
  (ensure-model-request request)
  (unless (stringp message)
    (error 'protocol-error :datum message :reason "model failure message is not a string"))
  (make-tagged-term
   "model-failure"
   (make-field "abi" (make-symbol-atom +model-v1-abi+))
   (make-field "request-hash" (make-string-atom (model-request-hash request)))
   (make-field "kind" (make-symbol-atom kind))
   (make-field "message" (make-string-atom message))))

(defun model-failure-kind (failure)
  (symbol-term-value (required-field failure "kind")))

(defun model-failure-message (failure)
  (string-term-value (required-field failure "message")))

(defun model-failure-valid-p (failure &optional request)
  (handler-case
      (and (tagged-term-p failure "model-failure")
           (model-symbol-name-p (required-field failure "abi") +model-v1-abi+)
           (model-hash-string-p (required-field failure "request-hash"))
           (let ((kind (required-field failure "kind")))
             (and (atom-p kind) (eq (atom-kind kind) :symbol)))
           (model-string-term-p (required-field failure "message"))
           (or (null request)
               (and (model-request-valid-p request)
                    (string= (string-term-value
                              (required-field failure "request-hash"))
                             (model-request-hash request)))))
    (cell-zero-error () nil)))

(defun make-model-credential (ref)
  "Construct a host-only nonsecret credential selector.
Credential material never belongs in model requests or transcripts."
  (unless (and (stringp ref) (plusp (length ref)) (<= (length ref) 256))
    (error 'protocol-error :datum ref
           :reason "model credential ref must be a nonempty bounded string"))
  (make-tagged-term
   "model-credential"
   (make-field "abi" (make-symbol-atom +model-v1-abi+))
   (make-field "ref" (make-string-atom ref))))

(defun model-credential-ref (credential)
  (string-term-value (required-field credential "ref")))

(defun model-credential-valid-p (credential)
  (handler-case
      (and (tagged-term-p credential "model-credential")
           (model-symbol-name-p (required-field credential "abi") +model-v1-abi+)
           (let ((ref (model-credential-ref credential)))
             (and (plusp (length ref)) (<= (length ref) 256))))
    (cell-zero-error () nil)))

(defun model-resource-usage-valid-p (usage)
  (handler-case
      (and (tagged-term-p usage "resource-usage")
           (model-nonnegative-integer-term-p (required-field usage "effects"))
           (model-nonnegative-integer-term-p (required-field usage "eval-steps"))
           (model-nonnegative-integer-term-p (required-field usage "events")))
    (cell-zero-error () nil)))

(defun model-handler-response-valid-p (status response request)
  (cond
    ((string= status "ok") (model-result-valid-p response request))
    ((string= status "error") (model-failure-valid-p response request))
    (t nil)))

(defun make-model-exchange (request status response usage)
  (ensure-model-request request)
  (let ((status (canonical-symbol-name status)))
    (unless (model-handler-response-valid-p status response request)
      (error 'protocol-error :datum response
             :reason "model handler status and response disagree"))
    (unless (model-resource-usage-valid-p usage)
      (error 'protocol-error :datum usage
             :reason "invalid model handler resource usage"))
    (make-tagged-term
     "model-exchange"
     (make-field "request" request)
     (make-field "request-hash" (make-string-atom (model-request-hash request)))
     (make-field "status" (make-symbol-atom status))
     (make-field "response" response)
     (make-field "response-hash" (make-string-atom (term-hash response)))
     (make-field "usage" usage))))

(defun model-exchange-valid-p (exchange)
  (handler-case
      (let* ((request (required-field exchange "request"))
             (status (symbol-term-value (required-field exchange "status")))
             (response (required-field exchange "response")))
        (and (tagged-term-p exchange "model-exchange")
             (model-request-valid-p request)
             (string= (string-term-value (required-field exchange "request-hash"))
                      (model-request-hash request))
             (model-handler-response-valid-p status response request)
             (string= (string-term-value (required-field exchange "response-hash"))
                      (term-hash response))
             (model-resource-usage-valid-p (required-field exchange "usage"))))
    (cell-zero-error () nil)))

(defun make-model-transcript (&optional (exchanges nil))
  (unless (and (listp exchanges) (every #'model-exchange-valid-p exchanges))
    (error 'protocol-error :datum exchanges :reason "invalid model transcript exchanges"))
  (make-tagged-term
   "model-transcript"
   (make-field "abi" (make-symbol-atom +model-v1-abi+))
   (make-field "exchanges" (term-list-from-elements exchanges))))

(defun model-transcript-exchanges (transcript)
  (term-list-elements (required-field transcript "exchanges")))

(defun model-transcript-valid-p (transcript)
  (handler-case
      (and (tagged-term-p transcript "model-transcript")
           (model-symbol-name-p (required-field transcript "abi") +model-v1-abi+)
           (every #'model-exchange-valid-p
                  (model-transcript-exchanges transcript)))
    (cell-zero-error () nil)))

(defun make-recording-model-handler (handler)
  "Wrap HANDLER and return the wrapper plus a zero-argument transcript reader."
  (unless (functionp handler)
    (error 'protocol-error :datum handler :reason "model handler is not a function"))
  (let ((exchanges nil))
    (values
     (lambda (subzero request budget effect)
       (ensure-model-request request)
       (multiple-value-bind (status response usage)
           (funcall handler subzero request budget effect)
         (let ((status (canonical-symbol-name status)))
           (unless (model-handler-response-valid-p status response request)
             (error 'protocol-error :datum response
                    :reason "model handler returned an invalid response"))
           (unless (model-resource-usage-valid-p usage)
             (error 'protocol-error :datum usage
                    :reason "model handler returned invalid resource usage"))
           (push (make-model-exchange request status response usage) exchanges)
           (values status response usage))))
     (lambda ()
       (make-model-transcript (nreverse (copy-list exchanges)))))))

(defun make-model-fixture-handler (transcript)
  "Return a deterministic handler and a zero-argument consumed-p inspector."
  (unless (model-transcript-valid-p transcript)
    (error 'protocol-error :datum transcript :reason "invalid model transcript"))
  (let ((remaining (model-transcript-exchanges transcript)))
    (values
     (lambda (subzero request budget effect)
       (declare (ignore subzero budget effect))
       (unless remaining
         (error 'protocol-error :datum request :reason "model fixture transcript exhausted"))
       (let* ((exchange (pop remaining))
              (expected (required-field exchange "request")))
         (unless (term-equal request expected)
           (error 'protocol-error :datum request :reason "model fixture request mismatch"))
         (values
          (symbol-term-value (required-field exchange "status"))
          (required-field exchange "response")
          (required-field exchange "usage"))))
     (lambda () (null remaining)))))
