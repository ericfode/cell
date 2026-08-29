;;;; src/term.lisp

(in-package #:cell-zero)

(define-condition cell-zero-error (error) ())

(define-condition malformed-term (cell-zero-error)
  ((datum :initarg :datum :reader malformed-term-datum)
   (reason :initarg :reason :reader malformed-term-reason))
  (:report (lambda (condition stream)
             (format stream "Malformed term ~S: ~A"
                     (malformed-term-datum condition)
                     (malformed-term-reason condition)))))

(define-condition store-error (cell-zero-error)
  ((reason :initarg :reason :reader store-error-reason))
  (:report (lambda (condition stream)
             (write-string (store-error-reason condition) stream))))

(defclass term ()
  ((hash :initarg :hash :reader %term-hash)
   (node-octets :initarg :node-octets :reader %term-node-octets)))

(defclass atom (term)
  ((kind :initarg :kind :reader atom-kind)
   (value :initarg :value :reader %atom-value)))

(defclass cell (term)
  ((left :initarg :left :reader cell-left)
   (right :initarg :right :reader cell-right)))

(defun term-hash (term)
  "Return a defensive copy of TERM's canonical SHA-256 identifier."
  (copy-seq (%term-hash term)))

(defun term-node-octets (term)
  (copy-seq (%term-node-octets term)))

(defun atom-value (atom)
  "Return ATOM's value without exposing mutable canonical storage."
  (let ((value (%atom-value atom)))
    (if (or (stringp value)
            (typep value '(vector (unsigned-byte 8))))
        (copy-seq value)
        value)))

(defun term-p (object)
  (typep object 'term))

(defun atom-p (object)
  (typep object 'atom))

(defun cell-p (object)
  (typep object 'cell))

(defun octet-vector (&rest octets)
  (make-array (length octets)
              :element-type '(unsigned-byte 8)
              :initial-contents octets))

(defun concatenate-octets (&rest vectors)
  (let* ((length (reduce #'+ vectors :key #'length :initial-value 0))
         (result (make-array length :element-type '(unsigned-byte 8)))
         (position 0))
    (dolist (vector vectors result)
      (replace result vector :start1 position)
      (incf position (length vector)))))

(defun uint64-octets (integer)
  (unless (and (integerp integer) (<= 0 integer) (< integer (ash 1 64)))
    (error 'malformed-term :datum integer :reason "not an unsigned 64-bit integer"))
  (let ((result (make-array 8 :element-type '(unsigned-byte 8))))
    (dotimes (index 8 result)
      (setf (aref result index)
            (ldb (byte 8 (* 8 (- 7 index))) integer)))))

(defun octets-uint64 (octets start)
  (let ((value 0))
    (dotimes (index 8 value)
      (setf value (+ (ash value 8) (aref octets (+ start index)))))))

(defun string-utf8-octets (string)
  (let ((octets (make-array 16 :element-type '(unsigned-byte 8)
                               :adjustable t :fill-pointer 0)))
    (labels ((emit (octet) (vector-push-extend octet octets)))
      (loop for character across string
            for code = (char-code character)
            do (cond
                 ((<= code #x7f)
                  (emit code))
                 ((<= code #x7ff)
                  (emit (logior #xc0 (ash code -6)))
                  (emit (logior #x80 (logand code #x3f))))
                 ((<= code #xffff)
                  (when (<= #xd800 code #xdfff)
                    (error 'malformed-term :datum string
                           :reason "contains a surrogate code point"))
                  (emit (logior #xe0 (ash code -12)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f))))
                 ((<= code #x10ffff)
                  (emit (logior #xf0 (ash code -18)))
                  (emit (logior #x80 (logand (ash code -12) #x3f)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f))))
                 (t
                  (error 'malformed-term :datum string
                         :reason "contains a code point outside Unicode"))))
      (copy-seq octets))))

(defun utf8-octets-string (octets)
  (with-output-to-string (stream)
    (labels ((continuation (index)
               (when (>= index (length octets))
                 (error 'store-error :reason "truncated UTF-8 payload"))
               (let ((octet (aref octets index)))
                 (unless (= (logand octet #xc0) #x80)
                   (error 'store-error :reason "invalid UTF-8 continuation byte"))
                 (logand octet #x3f)))
             (emit-code (code minimum)
               (when (or (< code minimum)
                         (> code #x10ffff)
                         (<= #xd800 code #xdfff))
                 (error 'store-error :reason "non-canonical UTF-8 payload"))
               (write-char (code-char code) stream)))
      (loop with index = 0
            while (< index (length octets))
            for first = (aref octets index)
            do (cond
                 ((<= first #x7f)
                  (write-char (code-char first) stream)
                  (incf index))
                 ((= (logand first #xe0) #xc0)
                  (emit-code (logior (ash (logand first #x1f) 6)
                                     (continuation (1+ index)))
                             #x80)
                  (incf index 2))
                 ((= (logand first #xf0) #xe0)
                  (emit-code (logior (ash (logand first #x0f) 12)
                                     (ash (continuation (1+ index)) 6)
                                     (continuation (+ index 2)))
                             #x800)
                  (incf index 3))
                 ((= (logand first #xf8) #xf0)
                  (emit-code (logior (ash (logand first #x07) 18)
                                     (ash (continuation (1+ index)) 12)
                                     (ash (continuation (+ index 2)) 6)
                                     (continuation (+ index 3)))
                             #x10000)
                  (incf index 4))
                 (t
                  (error 'store-error :reason "invalid UTF-8 lead byte")))))))

(defparameter +node-magic+ (octet-vector #x43 #x5a #x01))
(defconstant +symbol-node-tag+ #x01)
(defconstant +string-node-tag+ #x02)
(defconstant +integer-node-tag+ #x03)
(defconstant +bytes-node-tag+ #x04)
(defconstant +cell-node-tag+ #x10)

(defun canonical-symbol-name (designator)
  "Normalize only ASCII A-Z. Non-ASCII code points are preserved verbatim."
  (let ((name (etypecase designator
                (symbol (symbol-name designator))
                (string designator))))
    (map 'string
         (lambda (character)
           (if (char<= #\A character #\Z)
               (code-char (+ (char-code character) 32))
               character))
         name)))

(defun canonical-integer-string (integer)
  (format nil "~D" integer))

(defun atom-payload-octets (kind value)
  (ecase kind
    (:symbol (string-utf8-octets value))
    (:string (string-utf8-octets value))
    (:integer (string-utf8-octets (canonical-integer-string value)))
    (:bytes (copy-seq value))))

(defun atom-kind-tag (kind)
  (ecase kind
    (:symbol +symbol-node-tag+)
    (:string +string-node-tag+)
    (:integer +integer-node-tag+)
    (:bytes +bytes-node-tag+)))

(defun normalize-atom-value (kind value)
  (ecase kind
    (:symbol (canonical-symbol-name value))
    (:string
     (unless (stringp value)
       (error 'malformed-term :datum value :reason "string atom value is not a string"))
     (copy-seq value))
    (:integer
     (unless (integerp value)
       (error 'malformed-term :datum value :reason "integer atom value is not an integer"))
     value)
    (:bytes
     (unless (typep value '(vector (unsigned-byte 8)))
       (error 'malformed-term :datum value :reason "bytes atom value is not an octet vector"))
     (copy-seq value))))

(defun make-atom (kind value)
  (let* ((normalized (normalize-atom-value kind value))
         (payload (atom-payload-octets kind normalized))
         (node (concatenate-octets +node-magic+
                                   (octet-vector (atom-kind-tag kind))
                                   (uint64-octets (length payload))
                                   payload)))
    (make-instance 'atom
                   :kind kind
                   :value normalized
                   :node-octets node
                   :hash (sha256-hex node))))

(defun make-symbol-atom (symbol)
  (make-atom :symbol symbol))

(defun make-string-atom (string)
  (make-atom :string string))

(defun make-integer-atom (integer)
  (make-atom :integer integer))

(defun make-bytes-atom (octets)
  (make-atom :bytes octets))

(defun make-cell (left right)
  (unless (and (term-p left) (term-p right))
    (error 'malformed-term :datum (list left right)
           :reason "cell children must both be terms"))
  (let ((node (concatenate-octets +node-magic+
                                  (octet-vector +cell-node-tag+)
                                  (hex-octets (term-hash left))
                                  (hex-octets (term-hash right)))))
    (make-instance 'cell
                   :left left
                   :right right
                   :node-octets node
                   :hash (sha256-hex node))))

(defun empty-term ()
  (make-symbol-atom "nil"))

(defun true-term ()
  (make-symbol-atom "true"))

(defun false-term ()
  (make-symbol-atom "false"))

(defun term-list-from-elements (terms)
  (reduce #'make-cell terms :from-end t :initial-value (empty-term)))

(defun term-list (&rest terms)
  (term-list-from-elements terms))

(defun proper-list-tail-p (term)
  (and (atom-p term)
       (eq (atom-kind term) :symbol)
       (string= (atom-value term) "nil")))

(defun term-list-elements (term)
  (loop with cursor = term
        while (cell-p cursor)
        collect (cell-left cursor)
        do (setf cursor (cell-right cursor))
        finally
           (unless (proper-list-tail-p cursor)
             (error 'malformed-term :datum term :reason "not a proper term list"))))

(defun byte-vector-projection-p (object)
  (and (vectorp object)
       (not (stringp object))
       (every (lambda (element)
                (and (integerp element) (<= 0 element 255)))
              object)))

(defun sexp->term (sexp &key (max-depth 10000) (max-nodes 1000000))
  "Convert a bounded, acyclic standard S-expression projection to a term."
  (let ((active (make-hash-table :test #'eq))
        (nodes 0))
    (labels ((convert (object depth)
               (incf nodes)
               (when (> nodes max-nodes)
                 (error 'malformed-term :datum sexp :reason "projection exceeds node limit"))
               (when (> depth max-depth)
                 (error 'malformed-term :datum sexp :reason "projection exceeds depth limit"))
               (cond
                 ((term-p object) object)
                 ((null object) (empty-term))
                 ((symbolp object) (make-symbol-atom object))
                 ((stringp object) (make-string-atom object))
                 ((integerp object) (make-integer-atom object))
                 ((byte-vector-projection-p object)
                  (make-bytes-atom
                   (make-array (length object)
                               :element-type '(unsigned-byte 8)
                               :initial-contents object)))
                 ((consp object)
                  (when (gethash object active)
                    (error 'malformed-term :datum sexp :reason "cyclic projection"))
                  (setf (gethash object active) t)
                  (unwind-protect
                       (make-cell (convert (car object) (1+ depth))
                                  (convert (cdr object) (1+ depth)))
                    (remhash object active)))
                 (t
                  (error 'malformed-term :datum object
                         :reason "unsupported S-expression projection")))))
      (convert sexp 0))))

(defun term->sexp (term)
  (cond
    ((atom-p term)
     (ecase (atom-kind term)
       (:symbol
        (if (string= (atom-value term) "nil")
            nil
            (intern (atom-value term) :keyword)))
       (:string (atom-value term))
       (:integer (atom-value term))
       (:bytes (atom-value term))))
    ((cell-p term)
     (cons (term->sexp (cell-left term))
           (term->sexp (cell-right term))))
    (t (error 'malformed-term :datum term :reason "not a term"))))

(defun read-term (stream-or-string)
  "Read one bounded standard S-expression using an isolated standard readtable."
  (let ((*read-eval* nil)
         (*read-suppress* nil)
        (*readtable* (copy-readtable nil))
        (*package* (find-package :keyword))
        (*read-base* 10)
        (eof (gensym "EOF")))
    (etypecase stream-or-string
      (stream
       (let ((object (read stream-or-string nil eof)))
         (when (eq object eof)
           (error 'malformed-term :datum nil :reason "empty textual projection"))
         (sexp->term object)))
      (string
       (multiple-value-bind (object position)
           (read-from-string stream-or-string nil eof)
         (when (eq object eof)
           (error 'malformed-term :datum stream-or-string
                  :reason "empty textual projection"))
         (multiple-value-bind (trailing ignored-position)
             (read-from-string stream-or-string nil eof :start position)
           (declare (ignore ignored-position))
           (unless (eq trailing eof)
             (error 'malformed-term :datum stream-or-string
                    :reason "textual projection contains trailing forms")))
         (sexp->term object))))))

(defun write-escaped-symbol-name (name stream)
  (write-char #\| stream)
  (loop for character across name
        do (when (find character "|\\")
             (write-char #\\ stream))
           (write-char character stream))
  (write-char #\| stream))

(defun write-escaped-string (string stream)
  (write-char #\" stream)
  (loop for character across string
        do (when (find character "\"\\")
             (write-char #\\ stream))
           (write-char character stream))
  (write-char #\" stream))

(defun write-term (term &optional (stream *standard-output*))
  "Write the canonical readable S-expression projection of TERM."
  (labels ((write-one (value)
             (cond
               ((atom-p value)
                (ecase (atom-kind value)
                  (:symbol (write-escaped-symbol-name (atom-value value) stream))
                  (:string (write-escaped-string (atom-value value) stream))
                  (:integer (write-string (canonical-integer-string (atom-value value)) stream))
                  (:bytes
                   (format stream "#(~{~D~^ ~})" (coerce (atom-value value) 'list)))))
               ((cell-p value)
                (write-char #\( stream)
                (write-one (cell-left value))
                (loop with cursor = (cell-right value)
                      while (cell-p cursor)
                      do (write-char #\Space stream)
                         (write-one (cell-left cursor))
                         (setf cursor (cell-right cursor))
                      finally
                         (unless (proper-list-tail-p cursor)
                           (write-string " . " stream)
                           (write-one cursor)))
                (write-char #\) stream))
               (t (error 'malformed-term :datum value :reason "not a term")))))
    (write-one term)
    term))

(defun term-equal (left right)
  (and (term-p left) (term-p right)
       (string= (term-hash left) (term-hash right))))

(defun term-size (term)
  "Return the number of distinct canonical nodes reachable from TERM."
  (unless (term-p term)
    (error 'malformed-term :datum term :reason "not a term"))
  (let ((stack (list term))
        (seen (make-hash-table :test #'equal))
        (count 0))
    (loop while stack
          for value = (pop stack)
          for hash = (term-hash value)
          unless (gethash hash seen)
            do (setf (gethash hash seen) t)
               (incf count)
               (when (cell-p value)
                 (push (cell-left value) stack)
                 (push (cell-right value) stack)))
    count))

(defun symbol-atom-name= (term name)
  (and (atom-p term)
       (eq (atom-kind term) :symbol)
       (string= (atom-value term) (canonical-symbol-name name))))

(defun term-tag (term)
  (when (cell-p term)
    (cell-left term)))

(defun term-fields (term)
  (let ((fields (rest (term-list-elements term)))
        (seen (make-hash-table :test #'equal)))
    (dolist (field fields fields)
      (let ((name (field-name field)))
        (when (gethash name seen)
          (error 'malformed-term :datum term
                 :reason (format nil "duplicate field ~A" name)))
        (setf (gethash name seen) t)))))

(defun field-name (field)
  (let ((elements (term-list-elements field)))
    (unless (and (= (length elements) 2)
                 (atom-p (first elements))
                 (eq (atom-kind (first elements)) :symbol))
      (error 'malformed-term :datum field :reason "field must be (name value)"))
    (atom-value (first elements))))

(defun field-value (field)
  (second (term-list-elements field)))

(defun term-field (term name &optional (default (empty-term)))
  (let ((wanted (canonical-symbol-name name)))
    (dolist (field (term-fields term) default)
      (when (string= (field-name field) wanted)
        (return (field-value field))))))

(defun put-term-field (term name value)
  (unless (term-p value)
    (error 'malformed-term :datum value :reason "field value must be a term"))
  (let* ((elements (term-list-elements term))
         (tag (first elements))
         (wanted (canonical-symbol-name name))
         (replacement (term-list (make-symbol-atom wanted) value))
         (found nil)
         (fields
           (mapcar (lambda (field)
                     (if (string= (field-name field) wanted)
                         (progn (setf found t) replacement)
                         field))
                   (rest elements))))
    (unless found
      (setf fields (append fields (list replacement))))
    (apply #'term-list tag fields)))

(defun append-term-field (term name value)
  (let* ((current (term-field term name))
         (elements (term-list-elements current)))
    (put-term-field term name (apply #'term-list (append elements (list value))))))

(defun term-truth-p (term)
  (not (or (symbol-atom-name= term "nil")
           (symbol-atom-name= term "false"))))

(defclass term-store ()
  ((directory :initarg :directory :reader store-directory)
   (cache :initform (make-hash-table :test #'equal) :reader store-cache)
   (lock :initform #+sb-thread (sb-thread:make-mutex :name "cell-zero-store")
                   #-sb-thread nil
         :reader store-lock)))

(defmacro with-store-lock ((store) &body body)
  #+sb-thread `(sb-thread:with-mutex ((store-lock ,store)) ,@body)
  #-sb-thread `(progn ,@body))

(defun make-term-store (&key directory)
  (let ((normalized
          (when directory
            (uiop:ensure-directory-pathname (pathname directory)))))
    (when normalized
      (ensure-directories-exist (merge-pathnames "objects/00/placeholder" normalized))
      (ensure-directories-exist (merge-pathnames "refs/placeholder" normalized)))
    (make-instance 'term-store :directory normalized)))

(defun canonical-hash-p (hash)
  (and (stringp hash)
       (= (length hash) 64)
       (every (lambda (character)
                (or (digit-char-p character 10)
                    (find character "ABCDEF")))
              hash)))

(defun ensure-canonical-hash (hash)
  (unless (canonical-hash-p hash)
    (error 'store-error :reason (format nil "invalid canonical SHA-256 root ~S" hash)))
  hash)

(defun object-pathname (store hash)
  (ensure-canonical-hash hash)
  (let ((directory (store-directory store)))
    (when directory
      (merge-pathnames (format nil "objects/~A/~A" (subseq hash 0 2) (subseq hash 2))
                       directory))))

(defun store-exists-p-unlocked (store hash)
  (let ((hash (copy-seq (ensure-canonical-hash hash))))
    (or (gethash hash (store-cache store))
        (let ((path (object-pathname store hash)))
          (and path (probe-file path))))))

(defun store-exists-p (store hash)
  (with-store-lock (store)
    (store-exists-p-unlocked store hash)))

(defun read-file-octets (pathname)
  (with-open-file (stream pathname :direction :input
                                  :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length stream)
                              :element-type '(unsigned-byte 8))))
      (unless (= (read-sequence octets stream) (length octets))
        (error 'store-error :reason (format nil "short read from ~A" pathname)))
      octets)))

(defun temporary-object-pathname (pathname)
  (make-pathname
   :name (format nil ".~A-~36R-~36R-tmp"
                 (pathname-name pathname)
                 (get-internal-real-time)
                 (random (ash 1 60)))
   :type :unspecific
   :defaults pathname))

(defun write-file-octets-atomically (pathname octets)
  (ensure-directories-exist pathname)
  (loop repeat 100
        for temporary = (temporary-object-pathname pathname)
        do (handler-case
               (progn
                 (unwind-protect
                      (progn
                        (with-open-file (stream temporary
                                                :direction :output
                                                :if-does-not-exist :create
                                                :if-exists :error
                                                :element-type '(unsigned-byte 8))
                          (write-sequence octets stream)
                          (finish-output stream))
                        (uiop:rename-file-overwriting-target temporary pathname)
                        (return-from write-file-octets-atomically pathname))
                   (when (probe-file temporary)
                     (ignore-errors (delete-file temporary)))))
             (file-error () nil))
        finally
           (error 'store-error :reason
                  (format nil "could not create an atomic object file for ~A" pathname))))

(defun canonical-term-snapshot (term &optional store)
  "Validate TERM's semantic slots against its canonical encoding."
  (let ((memo (make-hash-table :test #'eq)))
    (labels ((snapshot (value)
               (or (gethash value memo)
                   (handler-case
                       (let* ((hash (%term-hash value))
                              (copy
                                (cond
                                  ((atom-p value)
                                   (make-atom (atom-kind value) (%atom-value value)))
                                  ((cell-p value)
                                   (make-cell (snapshot (cell-left value))
                                              (snapshot (cell-right value))))
                                  (t
                                   (error 'store-error :reason
                                          "store accepts only terms"))))
                              (existing (and store
                                             (gethash hash (store-cache store))))
                              (canonical
                                (if (and existing
                                         (equalp (%term-node-octets copy)
                                                 (%term-node-octets existing)))
                                    existing
                                    copy)))
                         (unless (and (string= hash (%term-hash copy))
                                      (equalp (%term-node-octets value)
                                              (%term-node-octets copy)))
                           (error 'store-error :reason
                                  "term slots do not match their canonical encoding"))
                         (setf (gethash value memo) canonical))
                     (store-error (condition) (error condition))
                     (error (condition)
                       (error 'store-error :reason
                              (format nil "malformed term object: ~A" condition)))))))
      (snapshot term))))

(defun store-canonical-term-unlocked (store term visited)
  (let* ((hash (%term-hash term))
         (node (%term-node-octets term))
         (existing (gethash hash (store-cache store))))
    (when existing
      (unless (equalp (%term-node-octets existing) node)
        (error 'store-error :reason (format nil "hash collision at ~A" hash)))
      (return-from store-canonical-term-unlocked (copy-seq hash)))
    (unless (gethash term visited)
      (setf (gethash term visited) t)
      (when (cell-p term)
        (store-canonical-term-unlocked store (cell-left term) visited)
        (store-canonical-term-unlocked store (cell-right term) visited))
      (let ((pathname (object-pathname store hash)))
        (when pathname
          (if (probe-file pathname)
              (let ((octets (read-file-octets pathname)))
                (unless (and (string= hash (sha256-hex octets))
                             (equalp octets node))
                  (error 'store-error :reason
                         (format nil "stored object ~A failed integrity verification" hash))))
              (write-file-octets-atomically pathname node))))
      (setf (gethash (copy-seq hash) (store-cache store)) term))
    (copy-seq hash)))

(defun store-put-unlocked (store term)
  (unless (term-p term)
    (error 'malformed-term :datum term :reason "store accepts only terms"))
  (let ((snapshot (canonical-term-snapshot term store)))
    (store-canonical-term-unlocked store snapshot (make-hash-table :test #'eq))))

(defun store-put (store term)
  (with-store-lock (store)
    (store-put-unlocked store term)))

(defun decode-atom-node (octets tag)
  (unless (>= (length octets) 12)
    (error 'store-error :reason "truncated atom node"))
  (let* ((payload-length (octets-uint64 octets 4))
         (expected (+ 12 payload-length)))
    (unless (= (length octets) expected)
      (error 'store-error :reason "atom node length mismatch"))
    (let ((payload (subseq octets 12)))
      (cond
        ((= tag +symbol-node-tag+)
         (make-atom :symbol (utf8-octets-string payload)))
        ((= tag +string-node-tag+)
         (make-atom :string (utf8-octets-string payload)))
        ((= tag +integer-node-tag+)
         (let* ((string (utf8-octets-string payload))
                (integer (parse-integer string :junk-allowed nil)))
           (unless (string= string (canonical-integer-string integer))
             (error 'store-error :reason "non-canonical integer atom"))
           (make-atom :integer integer)))
        ((= tag +bytes-node-tag+)
         (make-atom :bytes payload))
        (t
         (error 'store-error :reason (format nil "unknown atom node tag ~D" tag)))))))

(defun decode-node-unlocked (store octets)
  (unless (and (>= (length octets) 4)
               (equalp (subseq octets 0 3) +node-magic+))
    (error 'store-error :reason "invalid Cell-zero node magic"))
  (let ((tag (aref octets 3)))
    (if (= tag +cell-node-tag+)
        (progn
          (unless (= (length octets) 68)
            (error 'store-error :reason "cell node length mismatch"))
          (make-cell (store-get-unlocked store (octets-hex (subseq octets 4 36)))
                     (store-get-unlocked store (octets-hex (subseq octets 36 68)))))
        (decode-atom-node octets tag))))

(defun store-get-unlocked (store hash)
  (let ((hash (copy-seq (ensure-canonical-hash hash))))
    (or (gethash hash (store-cache store))
        (let ((pathname (object-pathname store hash)))
          (unless (and pathname (probe-file pathname))
            (error 'store-error :reason (format nil "missing object ~A" hash)))
          (let ((octets (read-file-octets pathname)))
            (unless (string= hash (sha256-hex octets))
              (error 'store-error :reason
                     (format nil "object ~A does not match its content hash" hash)))
            (let ((term (decode-node-unlocked store octets)))
              (unless (string= hash (%term-hash term))
                (error 'store-error :reason
                       (format nil "decoded object ~A has a different canonical hash" hash)))
              (setf (gethash (copy-seq hash) (store-cache store)) term)))))))

(defun store-get (store hash)
  (with-store-lock (store)
    (store-get-unlocked store hash)))
