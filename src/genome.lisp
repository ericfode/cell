;;;; src/genome.lisp

(in-package #:cell-zero)

(defparameter +genome-v1-abi+ "genome/v1")
(defparameter *source-genome-lisp-program*
  (or (uiop:getenv "CELL_ZERO_LISP") "sbcl"))

(define-condition source-genome-error (cell-zero-error)
  ((reason :initarg :reason :reader source-genome-error-reason)
   (datum :initarg :datum :initform nil :reader source-genome-error-datum))
  (:report (lambda (condition stream)
             (format stream "Source genome error: ~A"
                     (source-genome-error-reason condition)))))

(defun genome-v1-abi ()
  +genome-v1-abi+)

(defun source-genome-tagged-p (term tag)
  (and (cell-p term)
       (let ((term-tag (term-tag term)))
         (and (atom-p term-tag)
              (eq (atom-kind term-tag) :symbol)
              (string= (atom-value term-tag) tag)))))

(defun source-genome-required-field (term name)
  (let* ((absent (make-symbol-atom "source-genome-field-absent"))
         (value (term-field term name absent)))
    (when (term-equal value absent)
      (error 'source-genome-error :datum term
             :reason (format nil "missing field ~A" name)))
    value))

(defun source-genome-symbol-name-p (term name)
  (and (atom-p term)
       (eq (atom-kind term) :symbol)
       (string= (atom-value term) name)))

(defun source-genome-string-value (term description)
  (unless (and (atom-p term) (eq (atom-kind term) :string))
    (error 'source-genome-error :datum term :reason description))
  (atom-value term))

(defun genome-source-text-hash (text)
  (sha256-hex (string-utf8-octets text)))

(defun safe-genome-source-path-p (path)
  (and (stringp path)
       (plusp (length path))
       (not (char= (char path 0) #\/))
       (not (find #\\ path))
       (uiop:string-suffix-p path ".lisp")
       (every (lambda (character)
                (or (alphanumericp character)
                    (find character "-_./")))
              path)
       (let ((components (uiop:split-string path :separator '(#\/))))
         (and (every (lambda (component) (plusp (length component))) components)
              (notany (lambda (component)
                        (member component '("." "..") :test #'string=))
                      components)))))

(defun make-genome-source (path text)
  (unless (safe-genome-source-path-p path)
    (error 'source-genome-error :datum path
           :reason "genome source path is not a safe relative Lisp pathname"))
  (unless (stringp text)
    (error 'source-genome-error :datum text
           :reason "genome source text is not a string"))
  (make-tagged-term
   "source"
   (make-field "path" (make-string-atom path))
   (make-field "sha256" (make-string-atom (genome-source-text-hash text)))
   (make-field "text" (make-string-atom text))))

(defun genome-source-path (source)
  (source-genome-string-value
   (source-genome-required-field source "path")
   "genome source path is not a string"))

(defun genome-source-text (source)
  (source-genome-string-value
   (source-genome-required-field source "text")
   "genome source text is not a string"))

(defun genome-source-hash (source)
  (source-genome-string-value
   (source-genome-required-field source "sha256")
   "genome source hash is not a string"))

(defun genome-source-valid-p (source)
  (handler-case
      (let ((path (genome-source-path source))
            (text (genome-source-text source))
            (hash (genome-source-hash source)))
        (and (source-genome-tagged-p source "source")
             (safe-genome-source-path-p path)
             (= 64 (length hash))
             (string= hash (genome-source-text-hash text))))
    (error () nil)))

(defun make-genome-entry-point (package function)
  (unless (and (stringp package) (plusp (length package)))
    (error 'source-genome-error :datum package
           :reason "genome entry-point package is not a nonempty string"))
  (unless (and (stringp function) (plusp (length function)))
    (error 'source-genome-error :datum function
           :reason "genome entry-point function is not a nonempty string"))
  (make-tagged-term
   "entry-point"
   (make-field "package" (make-string-atom package))
   (make-field "function" (make-string-atom function))))

(defun source-genome-sources (genome)
  (term-list-elements (source-genome-required-field genome "sources")))

(defun source-genome-entry-points (genome)
  (source-genome-required-field genome "entry-points"))

(defun source-genome-react-entry-point (genome)
  (source-genome-required-field (source-genome-entry-points genome) "react"))

(defun source-genome-admit-entry-point (genome)
  (source-genome-required-field (source-genome-entry-points genome) "admit"))

(defun source-genome-entry-point-valid-p (entry-point)
  (handler-case
      (and (source-genome-tagged-p entry-point "entry-point")
           (plusp (length
                   (source-genome-string-value
                    (source-genome-required-field entry-point "package")
                    "entry-point package is not a string")))
           (plusp (length
                   (source-genome-string-value
                    (source-genome-required-field entry-point "function")
                    "entry-point function is not a string"))))
    (error () nil)))

(defun make-source-genome (sources react-entry-point admit-entry-point data)
  "Construct a canonical genome/v1 Common Lisp source bundle."
  (unless (and (listp sources) sources (every #'genome-source-valid-p sources))
    (error 'source-genome-error :datum sources
           :reason "source genome requires valid source files"))
  (unless (= (length sources)
             (length (remove-duplicates sources :key #'genome-source-path
                                                :test #'string=)))
    (error 'source-genome-error :datum sources
           :reason "source genome contains duplicate paths"))
  (unless (source-genome-entry-point-valid-p react-entry-point)
    (error 'source-genome-error :datum react-entry-point
           :reason "invalid react entry point"))
  (unless (source-genome-entry-point-valid-p admit-entry-point)
    (error 'source-genome-error :datum admit-entry-point
           :reason "invalid admit entry point"))
  (unless (term-p data)
    (error 'source-genome-error :datum data :reason "genome data is not a term"))
  (make-tagged-term
   "genome"
   (make-field "abi" (make-symbol-atom +genome-v1-abi+))
   (make-field "language" (make-symbol-atom "common-lisp"))
   (make-field "sources" (term-list-from-elements sources))
   (make-field
    "entry-points"
    (make-tagged-term
     "entry-points"
     (make-field "react" react-entry-point)
     (make-field "admit" admit-entry-point)))
   (make-field "data" data)))

(defun source-genome-valid-p (genome)
  "Return true when GENOME is a structurally valid, content-bound genome/v1 bundle."
  (handler-case
      (let ((sources (source-genome-sources genome)))
        (and (source-genome-tagged-p genome "genome")
             (source-genome-symbol-name-p
              (source-genome-required-field genome "abi") +genome-v1-abi+)
             (source-genome-symbol-name-p
              (source-genome-required-field genome "language") "common-lisp")
             sources
             (every #'genome-source-valid-p sources)
             (= (length sources)
                (length (remove-duplicates sources :key #'genome-source-path
                                                   :test #'string=)))
             (source-genome-tagged-p
              (source-genome-entry-points genome) "entry-points")
             (source-genome-entry-point-valid-p
              (source-genome-react-entry-point genome))
             (source-genome-entry-point-valid-p
              (source-genome-admit-entry-point genome))
             (term-p (source-genome-required-field genome "data"))))
    (error () nil)))

(defun source-genome-temporary-directory (genome)
  (uiop:call-with-temporary-file
   (lambda (pathname)
     (delete-file pathname)
     (let ((directory (uiop:ensure-directory-pathname pathname)))
       (ensure-directories-exist (merge-pathnames "placeholder" directory))
       directory))
   :want-stream-p nil
   :prefix (format nil "cell-zero-genome-~A-"
                   (subseq (term-hash genome) 0 12))
   :type nil
   :keep (constantly t)))

(defun write-utf8-file (pathname text)
  (ensure-directories-exist pathname)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-string text stream))
  pathname)

(defun materialize-source-genome (genome directory)
  (dolist (source (source-genome-sources genome))
    (write-utf8-file (merge-pathnames (genome-source-path source) directory)
                     (genome-source-text source)))
  directory)

(defun source-genome-invocation (genome operation arguments)
  (make-tagged-term
   "genome-invocation"
   (make-field "operation" (make-symbol-atom operation))
   (make-field
    "sources"
    (term-list-from-elements
     (mapcar (lambda (source)
               (make-string-atom (genome-source-path source)))
             (source-genome-sources genome))))
   (make-field "entry-points" (source-genome-entry-points genome))
   (make-field "arguments" (term-list-from-elements arguments))))

(defun write-canonical-term-file (pathname term)
  (with-open-file (stream pathname
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create
                          :external-format :utf-8)
    (write-term term stream)
    (terpri stream))
  pathname)

(defun read-canonical-term-file (pathname)
  (with-open-file (stream pathname :direction :input :external-format :utf-8)
    (read-term stream)))

(defun bounded-diagnostic (text)
  (let ((text (or text "")))
    (if (> (length text) 4000)
        (subseq text 0 4000)
        text)))

(defun source-genome-runner-form (asdf-file directory invocation response)
  (format nil "(cell-zero.genome-runner:main ~S ~S ~S ~S)"
          (namestring asdf-file)
          (namestring directory)
          (namestring invocation)
          (namestring response)))

(defun read-source-genome-runner-response (response stdout stderr status)
  (unless (probe-file response)
    (error 'source-genome-error
           :datum status
           :reason (format nil "isolated runner exited with status ~A: ~A~@[ / ~A~]"
                           status (bounded-diagnostic stderr)
                           (let ((output (bounded-diagnostic stdout)))
                             (and (plusp (length output)) output)))))
  (let ((result (read-canonical-term-file response)))
    (cond
      ((source-genome-tagged-p result "genome-runner-result")
       (source-genome-required-field result "value"))
      ((source-genome-tagged-p result "genome-runner-failure")
       (error 'source-genome-error
              :datum result
              :reason (source-genome-string-value
                       (source-genome-required-field result "detail")
                       "runner failure detail is malformed")))
      (t
       (error 'source-genome-error :datum result
              :reason "isolated runner returned a malformed response")))))

(defun run-source-genome-invocation (genome operation arguments)
  (unless (source-genome-valid-p genome)
    (error 'source-genome-error :datum genome
           :reason "invalid genome/v1 source bundle"))
  (let* ((directory (source-genome-temporary-directory genome))
         (invocation (merge-pathnames "invocation.sexp" directory))
         (response (merge-pathnames "response.sexp" directory))
         (asdf-file (asdf:system-source-file (asdf:find-system "cell-zero")))
         (runner (asdf:system-relative-pathname
                  (asdf:find-system "cell-zero") "scripts/genome-runner.lisp")))
    (unwind-protect
         (progn
           (materialize-source-genome genome directory)
           (write-canonical-term-file
            invocation (source-genome-invocation genome operation arguments))
           (multiple-value-bind (stdout stderr status)
               (uiop:run-program
                (list *source-genome-lisp-program*
                      "--noinform" "--disable-debugger" "--non-interactive"
                      "--load" (namestring runner)
                      "--eval" (source-genome-runner-form
                                asdf-file directory invocation response))
                :directory directory
                :output :string
                :error-output :string
                :ignore-error-status t)
             (read-source-genome-runner-response
              response stdout stderr status)))
      (uiop:delete-directory-tree directory :validate t
                                            :if-does-not-exist :ignore))))

(defun source-genome-loads-p (genome)
  (handler-case
      (progn
        (run-source-genome-invocation genome "load" nil)
        t)
    (error () nil)))

(defun invoke-source-genome-react (genome state event world)
  (let ((result
          (run-source-genome-invocation
           genome "react"
           (list state event
                 (source-genome-required-field genome "data") world))))
    (values result
            (make-evaluation-usage :steps 1 :max-depth 0
                                   :output-size (term-size result)))))

(defun invoke-source-genome-admit (genome candidate evidence)
  (let ((result
          (run-source-genome-invocation
           genome "admit"
           (list candidate evidence
                 (source-genome-required-field genome "data")))))
    (values result
            (make-evaluation-usage :steps 1 :max-depth 0
                                   :output-size (term-size result)))))

(defun materialized-entry-point-function (entry-point)
  (let* ((package-name
           (source-genome-string-value
            (source-genome-required-field entry-point "package")
            "entry-point package is malformed"))
         (function-name
           (source-genome-string-value
            (source-genome-required-field entry-point "function")
            "entry-point function is malformed"))
         (package (or (find-package package-name)
                      (error 'source-genome-error :datum package-name
                             :reason "entry-point package was not defined"))))
    (multiple-value-bind (symbol status) (find-symbol function-name package)
      (unless (and symbol status (fboundp symbol))
        (error 'source-genome-error :datum entry-point
               :reason "entry-point function was not defined"))
      (symbol-function symbol))))

(defun load-materialized-genome-sources (directory sources)
  (dolist (source sources)
    (let ((pathname (merge-pathnames
                     (source-genome-string-value
                      source "materialized source path is malformed")
                     directory)))
      (multiple-value-bind (output warnings-p failure-p)
          (compile-file pathname)
        (declare (ignore warnings-p))
        (when failure-p
          (error 'source-genome-error :datum pathname
                 :reason "source compilation failed"))
        (load output)))))

(defun execute-materialized-genome-invocation (directory invocation)
  "Execute one invocation inside the disposable runner process."
  (unless (source-genome-tagged-p invocation "genome-invocation")
    (error 'source-genome-error :datum invocation
           :reason "malformed materialized invocation"))
  (let* ((operation
           (atom-value (source-genome-required-field invocation "operation")))
         (sources
           (term-list-elements
            (source-genome-required-field invocation "sources")))
         (entry-points
           (source-genome-required-field invocation "entry-points"))
         (arguments
           (term-list-elements
            (source-genome-required-field invocation "arguments"))))
    (load-materialized-genome-sources directory sources)
    (cond
      ((string= operation "load")
       (materialized-entry-point-function
        (source-genome-required-field entry-points "react"))
       (materialized-entry-point-function
        (source-genome-required-field entry-points "admit"))
       (true-term))
      ((member operation '("react" "admit") :test #'string=)
       (let* ((entry-point
                (source-genome-required-field entry-points operation))
              (value (apply (materialized-entry-point-function entry-point)
                            arguments)))
         (unless (term-p value)
           (error 'source-genome-error :datum value
                  :reason "genome entry point did not return a canonical term"))
         value))
      (t
       (error 'source-genome-error :datum operation
              :reason "unknown genome operation")))))
