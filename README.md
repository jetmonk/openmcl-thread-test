

Clozure Lisp has a long-standing thread bug on the Raspberry Pi
(maybe all ARM7? ARMx?) that causes threading to crash.

This might be caused by a locking failure.

This test shows that threads can steal a lock away from each
other.

Running (threadtest2) will eventually throw an error that a thread
detects that it no longer owns the lock it grabbed.

-----

I suspected this might be because ccl::%lock-recursive-lock-ptr doesn't
have an ARM DMB (Data Memory Barrier) instruction, that "ensures that
all memory accesses are completed before new memory access is
committed."   

The ARM documentation that explains the necessity of this instruction
has been moved since I found it, however.


However, this adding this to routines in ARM/arm-misc.lisp
doesn't seem to fix the problem.

----

The failure seems to occur as follows:

%lock-recursive-lock-object (l0-misc.lisp)  calls
   #-futex %lock-recursive-lock-ptr  (l0-misc.lisp) calls
      %get-spin-lock (l0-misc.lisp) calls
         %ptr-store-fixnum-conditional (ARM/arm-misc.lisp)
	     [where I tried to put in (dmb) instruction to force core sync]


---

Also tried: using 'taskset' linux command to force the lisp process to
run on one core, in the belief that different cores might not have a
sync'ed vision of current memory (lock) status.   This did not seem to
help, arguing against (dmb) instruction solution.

----

NO, taskset DOES help - I was using it wrong according to Robert M.
I still think the DMB instruction is missing somewhere.  In C code?
