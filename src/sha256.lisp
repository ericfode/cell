;;;; src/sha256.lisp

(in-package #:cell-zero)

(declaim (inline u32 rotr32 choose32 majority32 big-sigma-0 big-sigma-1
                 small-sigma-0 small-sigma-1))

(defun u32 (integer)
  (logand integer #xffffffff))

(defun rotr32 (integer count)
  (u32 (logior (ash integer (- count))
               (ash integer (- 32 count)))))

(defun choose32 (x y z)
  (logxor (logand x y) (logand (lognot x) z)))

(defun majority32 (x y z)
  (logxor (logand x y) (logand x z) (logand y z)))

(defun big-sigma-0 (x)
  (logxor (rotr32 x 2) (rotr32 x 13) (rotr32 x 22)))

(defun big-sigma-1 (x)
  (logxor (rotr32 x 6) (rotr32 x 11) (rotr32 x 25)))

(defun small-sigma-0 (x)
  (logxor (rotr32 x 7) (rotr32 x 18) (ash x -3)))

(defun small-sigma-1 (x)
  (logxor (rotr32 x 17) (rotr32 x 19) (ash x -10)))

(defparameter +sha256-round-constants+
  #(#x428a2f98 #x71374491 #xb5c0fbcf #xe9b5dba5
    #x3956c25b #x59f111f1 #x923f82a4 #xab1c5ed5
    #xd807aa98 #x12835b01 #x243185be #x550c7dc3
    #x72be5d74 #x80deb1fe #x9bdc06a7 #xc19bf174
    #xe49b69c1 #xefbe4786 #x0fc19dc6 #x240ca1cc
    #x2de92c6f #x4a7484aa #x5cb0a9dc #x76f988da
    #x983e5152 #xa831c66d #xb00327c8 #xbf597fc7
    #xc6e00bf3 #xd5a79147 #x06ca6351 #x14292967
    #x27b70a85 #x2e1b2138 #x4d2c6dfc #x53380d13
    #x650a7354 #x766a0abb #x81c2c92e #x92722c85
    #xa2bfe8a1 #xa81a664b #xc24b8b70 #xc76c51a3
    #xd192e819 #xd6990624 #xf40e3585 #x106aa070
    #x19a4c116 #x1e376c08 #x2748774c #x34b0bcb5
    #x391c0cb3 #x4ed8aa4a #x5b9cca4f #x682e6ff3
    #x748f82ee #x78a5636f #x84c87814 #x8cc70208
    #x90befffa #xa4506ceb #xbef9a3f7 #xc67178f2))

(defun sha256-padding (octets)
  (let* ((length (length octets))
         (bit-length (* length 8))
         (padding-length (mod (- 56 (1+ length)) 64))
         (result (make-array (+ length 1 padding-length 8)
                             :element-type '(unsigned-byte 8)
                             :initial-element 0)))
    (replace result octets)
    (setf (aref result length) #x80)
    (dotimes (index 8 result)
      (setf (aref result (+ length 1 padding-length index))
            (ldb (byte 8 (* 8 (- 7 index))) bit-length)))))

(defun sha256-octets (octets)
  "Return the SHA-256 digest of OCTETS as a fresh 32-octet vector."
  (let ((message (sha256-padding octets))
        (hash (vector #x6a09e667 #xbb67ae85 #x3c6ef372 #xa54ff53a
                      #x510e527f #x9b05688c #x1f83d9ab #x5be0cd19))
        (schedule (make-array 64 :element-type '(unsigned-byte 32))))
    (loop for offset from 0 below (length message) by 64 do
      (dotimes (index 16)
        (let ((base (+ offset (* index 4))))
          (setf (aref schedule index)
                (u32 (logior (ash (aref message base) 24)
                             (ash (aref message (+ base 1)) 16)
                             (ash (aref message (+ base 2)) 8)
                             (aref message (+ base 3)))))))
      (loop for index from 16 below 64 do
        (setf (aref schedule index)
              (u32 (+ (small-sigma-1 (aref schedule (- index 2)))
                      (aref schedule (- index 7))
                      (small-sigma-0 (aref schedule (- index 15)))
                      (aref schedule (- index 16))))))
      (let ((a (aref hash 0)) (b (aref hash 1))
            (c (aref hash 2)) (d (aref hash 3))
            (e (aref hash 4)) (f (aref hash 5))
            (g (aref hash 6)) (h (aref hash 7)))
        (dotimes (index 64)
          (let* ((temporary-1
                   (u32 (+ h (big-sigma-1 e) (choose32 e f g)
                           (aref +sha256-round-constants+ index)
                           (aref schedule index))))
                 (temporary-2
                   (u32 (+ (big-sigma-0 a) (majority32 a b c)))))
            (setf h g
                  g f
                  f e
                  e (u32 (+ d temporary-1))
                  d c
                  c b
                  b a
                  a (u32 (+ temporary-1 temporary-2)))))
        (setf (aref hash 0) (u32 (+ (aref hash 0) a))
              (aref hash 1) (u32 (+ (aref hash 1) b))
              (aref hash 2) (u32 (+ (aref hash 2) c))
              (aref hash 3) (u32 (+ (aref hash 3) d))
              (aref hash 4) (u32 (+ (aref hash 4) e))
              (aref hash 5) (u32 (+ (aref hash 5) f))
              (aref hash 6) (u32 (+ (aref hash 6) g))
              (aref hash 7) (u32 (+ (aref hash 7) h)))))
    (let ((digest (make-array 32 :element-type '(unsigned-byte 8))))
      (dotimes (word-index 8 digest)
        (dotimes (byte-index 4)
          (setf (aref digest (+ (* word-index 4) byte-index))
                (ldb (byte 8 (* 8 (- 3 byte-index)))
                     (aref hash word-index))))))))

(defun octets-hex (octets)
  (with-output-to-string (stream)
    (loop for octet across octets
          do (format stream "~2,'0x" octet))))

(defun hex-octets (hex)
  (unless (and (evenp (length hex))
               (every (lambda (character) (digit-char-p character 16)) hex))
    (error "Invalid hexadecimal string: ~S" hex))
  (let ((octets (make-array (/ (length hex) 2)
                            :element-type '(unsigned-byte 8))))
    (dotimes (index (length octets) octets)
      (setf (aref octets index)
            (parse-integer hex :start (* index 2) :end (+ (* index 2) 2)
                                :radix 16)))))

(defun sha256-hex (octets)
  (octets-hex (sha256-octets octets)))
