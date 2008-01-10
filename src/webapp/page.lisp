(in-package #:tpd2.webapp)

(defconstant +webapp-session-id-param+ (force-byte-vector "*webapp-session*"))

(defconstant +web-safe-chars+ 
  (force-byte-vector 
   (append (loop for c from (char-code #\A) to (char-code #\Z) collect c)
	   (loop for c from (char-code #\a) to (char-code #\z) collect c)
	   (loop for c from (char-code #\0) to (char-code #\9) collect c)
	   (mapcar 'char-code '(#\- #\_)))))

(defun generate-args-for-defpage-from-params (params-var defaulting-lambda-list)
  (let ((arg-names (mapcar 'force-first defaulting-lambda-list))
	(arg-values (mapcar (lambda(x)(second (force-list x))) defaulting-lambda-list)))
    (loop for name in arg-names
	  for value in arg-values
	  collect (intern (force-string name) :keyword)
	  if (eq name 'all-http-params)
	  collect params-var
	  else
	  collect `(or (cdr-assoc ,params-var ,(force-byte-vector name) 
				  :test 'byte-vector=-fold-ascii-case)
		       ,value))))

(defmacro with-webapp-session ((params) &body body)
  (check-symbols params)
  `(let ((*webapp-session*
	  (awhen (cdr-assoc ,params +webapp-session-id-param+ :test 'byte-vector=-fold-ascii-case)
	    (find-session it))))
     ,@body))


(defmacro apply-page-call (function &rest args)
  (let* ((defaulting-lambda-list (car (last args)))
	 (normal-args (butlast args)))
    `(with-webapp-session (all-http-params)
       (funcall ,function ,@normal-args ,@(generate-args-for-defpage-from-params 'all-http-params defaulting-lambda-list)))))

(defmacro defpage (path defaulting-lambda-list &body body)
  (let ((normal-func-name (intern (strcat 'page- path))))
    `(progn
       (defun ,normal-func-name (&key ,@defaulting-lambda-list)
	 ,@body)
       (dispatcher-register-path *default-dispatcher* ,path
				 (lambda(dispatcher con done path all-http-params)
				   (declare (ignore dispatcher path))
				   (respond-http con done :body (apply-page-call ',normal-func-name ,defaulting-lambda-list))))
	 ',normal-func-name)))

(defmacro page-link (page &rest args)
  `(sendbuf-to-byte-vector
    (with-sendbuf (sendbuf)
      ,page
      "?"
      +webapp-session-id-param+
      "="
      (awhen *webapp-session*
	(session-id it))
      ,@(loop for (param val) on args by #'cddr
	      collect "&"
	      collect (symbol-name param)
	      collect "="
	      collect `(percent-hexpair-encode ,val)))))

(defun random-web-safe-char ()
  (declare (optimize speed))
  (aref +web-safe-chars+ (random (length +web-safe-chars+))))
(declaim (inline random-web-safe-char))

(defun random-web-sparse-key (length)
  (let ((bv (make-byte-vector length)))
    (loop for i from 0 below length
	  do (setf (aref bv i) (random-web-safe-char)))
    bv))
