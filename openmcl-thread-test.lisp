
;; (THREADTEST2 ..) launches some threads that don't generate garbage.
;;  it demonstrates that locks don't get held (are grabbed by another thread)
;;
;; tested on raspberri pi armcl dev version:
;;        * "Version 1.12-dev (v1.12-dev.4-3-gdd5622e9) LinuxARM32"
 
;; with
;; (threadtest2 :exercise-locking nil)
;; and nothing happens, and threads run fine.
 
;; with
;; (threadtest2 :exercise-locking t)
;; the error
;;
;;ERR2 - current proc #<PROCESS Threadtest 4(63) [Active] #x14F93B76> doesn't own lock #<RECURSIVE-LOCK "glock" [ptr @ #x76105480] #x14F8FB26>, which is owned by #<PROCESS Threadtest 1(60) [Sleep] #x14F8F496>
;;
;; is generated, indicated that a thread detected that a lock it owned was stolen
;; by another thread
 
 
(defparameter *the-glock* nil) ;; allow us to look at lock while running
(defparameter *thread-count* nil) ;; global vars so we know it isn't frozen
(defparameter *loop-count* nil)
(defun threadtest2 (&key
		     (thread-count 7)
		     (loop-count 1000)
		     ;; test locking in the threads
		     (exercise-locking t)
		     (count 1000))
  (let ((done-flags (make-array thread-count :initial-element nil))
	(lock (ccl:make-lock "done-flags-lock"))
	(glock (when exercise-locking
		 (ccl:make-lock "glock"))))
    (setf *the-glock* glock)
    (dotimes (i thread-count)
      (setf *thread-count* i)
      (process-run-function
       (format nil "Threadtest ~d" i)
       (lambda (i)
	 (unwind-protect
	      (dotimes (j loop-count)
		(setf *loop-count* j)
		(threadfunc count glock)
		))
	 (ccl:with-lock-grabbed (lock) (setf (elt done-flags i) t)))
       i))
    (loop do
         (unless
	     (ccl:with-lock-grabbed (lock)
	       (position nil done-flags))
	   (return)))))
 
;; see https://lists.clozure.com/pipermail/openmcl-devel/2011-July/008664.html
(defun recursive-lock-owner (lock)
  (let* ((tcr (ccl::%get-object (ccl::recursive-lock-ptr lock)
				target::lockptr.owner)))
    (unless (eql 0 tcr) (ccl::tcr->process tcr))))
 
 
;; a duplicate of ccl's with-lock-grabbed macro, with extra
;; code to check that the lock owner hasn't changed while lock is held
(defmacro with-lock ((the-lock) &body body)
  `(let ((lacq (make-lock-acquisition))
	 (lock ,the-lock))
     (progn (ccl::%lock-recursive-lock-object
	     lock lacq)
	    ;; do a pre-check that owner is OK
	    (let ((owner (recursive-lock-owner lock)))
	      (unless (eq owner *current-process*)
		(error "ERR1 - current proc ~A doesn't own lock ~A, which is owned by ~A"
		       *current-process* lock owner)))
	    (progn ,@body)
	    ;; do a post-check that owner is OK
	    (let ((owner (recursive-lock-owner lock)))
	      (unless (eq owner *current-process*)
		(error "ERR2 - current proc ~A doesn't own lock ~A, which is owned by ~A"
		       *current-process* lock owner)))
	    (when (ccl::lock-acquisition.status lacq)
	       (release-lock lock)))))
 
 
 
 
;; locking in threads -- just sleep, with no garbage generation
(defun threadfunc (count lock)
  (loop for i below count
     collect (cond (lock ;; using normal locking
		    (with-lock (lock)
		      (sleep 0.000001)))
		    (t ;; no locks
		     (sleep 0.000001)))))



;; lock this CCL to one core - need to install schedutils
(defun lock-to-one-core (&key (mask 1)) ;; mask=1 means "just core 0"
  (let ((pid (ccl::getpid)))
    (ccl:run-program "sudo" ;; must have sudo without password as for PI user
		     (list "taskset"
			   "-p"  (format nil "~D" mask) (format nil "~D" pid)))))
			   
  
