
;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 自研 Actor 模型
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/nst-bl-act.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：CLOS + bordeaux-threads 实现的极简 Actor —— 每个 actor 独占一个线程，
;;;;       从消息队列里取出 lambda 函数执行；支持 stateful 状态累积、
;;;;       :running/:waiting/:stopped/:terminated 生命周期、批处理模式 (bulk)。
;;;;       系统启动时常驻 *NSTSENDORDEREMAILACTOR*、*NSTAWSS3FILEUPLOADACTOR*。
;;;;
;;;; 主要导出：
;;;;   nst-actor                     — 类定义
;;;;   send-message                  — 投递消息（必须是 function）
;;;;   process-messages              — 内部消费循环
;;;;   start-actor / stop-actor / destroy-actor
;;;;   counter-behavior / *counter* / test-counter-actor — 自测样例
;;;;
;;;; 关联：
;;;;   上游使用方：dod-ini-sys.lisp 的 (start-das) 启动两个常驻 actor；
;;;;               订单/文件上传等异步路径
;;;;   下游依赖：bordeaux-threads (bt:*)、cl-uuid
;;;; ============================================================================
(in-package :nstores)

(defclass nst-actor ()
  ((id :reader id
       :initform (format nil "~A" (uuid:make-v1-uuid)))
   (name
    :initarg :name
    :reader actor-name)
   (behavior
    :initarg :behavior
    :reader actor-behavior)
   (state
    :initarg :initial-state
    :accessor actor-state)
   (actor-state-clean-callback
    :initarg :state-clean-callback
    :accessor actor-state-clean-callback)
   (stateful
    :initarg :stateful
    :reader actor-stateful)
   (queue
    :initform '()
    :accessor actor-queue)
   (lock
    :initform (bt:make-lock)
    :reader actor-lock)
   (condition
    :initform (bt:make-condition-variable)
    :reader actor-condition)
   (thread-state
    :initform :created 
    :accessor actor-thread-state)
   (thread
    :accessor actor-thread)
   (role
    :initarg :role
    :reader actor-role)
   (created-at
    :initform (get-universal-time)
    :reader actor-created-at)
   (last-active-at
    :initform (get-universal-time)
    :accessor actor-last-active-at)
   (priority
    :initarg :priority
    :accessor actor-priority)
   (message-count
    :initform 0
    :accessor actor-message-count)
   (max-queue-size
    :initarg :max-queue-size
    :initform 100
    :accessor actor-max-queue-size))
  (:documentation "Class representing an actor with message queue and behavior."))

(defgeneric send-message (actor message &optional bulk-processing-mode-p))
(defgeneric process-messages (actor))
(defgeneric get-state (actor))
(defgeneric stop-actor (actor))
(defgeneric start-actor (actor))
(defgeneric destroy-actor (actor))


(defmethod initialize-instance :after ((self nst-actor) &key)
  "Start the actor thread after initialization.
   中文：实例化时立即起一个名为 (actor-name) 的线程跑 process-messages，
         但 thread-state 仍为 :created（直到 start-actor 才转为 :running）。"
  (with-slots (thread-state thread name) self 
    (setf thread (bt:make-thread
		  (lambda () (process-messages self))
                  :name name))
    (setf thread-state :created)))


;; ------------------------------------------
;; 🔹 Process Messages Function
;; ------------------------------------------
(defmethod process-messages ((self nst-actor))
  "Processes messages continuously, waiting if the queue is empty.
   中文：actor 主循环。
     :terminated  → 直接 return 退出线程
     :stopped     → condition-wait（外部 start-actor 会唤醒）
     队列为空     → 设为 :waiting 然后 condition-wait
     :running     → pop 一个消息（必须是 function）执行
   stateful=T 时把 (behavior state message) 的返回值赋回 state。"
  (with-slots (state lock last-active-at stateful  thread-state condition queue behavior) self
    (loop
    (bt:with-lock-held (lock)
      (cond
        ((eq thread-state :terminated)
         (return))  ;; Stop processing and exit when actor is terminated

	((eq thread-state  :stopped) ;; if Actor is stopped, then just wait and set thread state to stopped
	 (bt:condition-wait condition lock))

	
        ((null queue)  ;; Wait if queue is empty
         (setf thread-state :waiting)
         (bt:condition-wait condition lock))
	        
        ((eq thread-state :running)  ;; Process messages
         (let ((message (pop queue)))
	   (unless (functionp message) ;; message is always a function. either a named/lambda.  
	     (error "Message passed to an Actor should be of type 'function."))
	   
	   (when (functionp message) ;; message is always a function. either a named/lambda.  
	     (setf last-active-at (get-universal-time)) ;; Actor was last active at time. 
	     (if stateful
		 (setf state (funcall behavior state message))
		 ;; else
		 (funcall behavior message))))))))))



;; ------------------------------------------
;; 🔹 Start, Stop, and Destroy Actor
;; ------------------------------------------
(defmethod start-actor ((actor nst-actor))
  "Starts the actor if it is not already running.
   中文：把 thread-state 切到 :running 并 condition-notify 唤醒等待的线程。"
  (with-slots (lock thread-state condition) actor
    (bt:with-lock-held (lock)
      (setf thread-state :running))
    (bt:condition-notify condition)))  ;; Wake up thread if waiting

(defmethod stop-actor ((actor nst-actor))
  "Stops the actor without destroying the thread.
   中文：仅暂停消费（thread-state=:stopped），线程仍在；可用 start-actor 恢复。"
  (with-slots (thread-state condition lock) actor
  (bt:with-lock-held (lock)
    (setf thread-state :stopped)
    (bt:condition-notify condition))))  ;; Wake up thread to terminate

(defmethod destroy-actor ((actor nst-actor))
  "Stops the actor and cleans up resources.
   中文：先 stop-actor，再 bt:destroy-thread；清空 queue/state，
         若有 state-clean-callback 则调用一次（用来释放 socket、文件等外部资源）。"
  (stop-actor actor)
  (with-slots (lock thread thread-state state queue actor-state-clean-callback) actor
    (bt:with-lock-held (lock)
      (when thread
	(bt:destroy-thread thread)
	(setf thread nil)
	(setf thread-state :terminated)
	(setf queue '())
	(setf state nil)
	(when (functionp actor-state-clean-callback)
	  (actor-state-clean-callback actor)
	  (setf actor-state-clean-callback nil))))))


;; ------------------------------------------
;; 🔹 Send Message Function
;; ------------------------------------------
(defmethod send-message ((actor nst-actor) message &optional (bulk-processing-mode-p nil))
  "Sends a message to the actor's queue and notifies it.
   中文：把 message（必须是 function）push 到 queue 并唤醒线程。
   bulk-processing-mode-p=T 时不会自动把 actor 切到 :running，
   适用于先批量灌消息、再统一 start-actor 触发的场景。"
  ;; Automatically start the actor if it is in stopped state
  (with-slots (lock thread-state condition queue message-count) actor
  (bt:with-lock-held ((actor-lock actor))
    (unless bulk-processing-mode-p ;; process the message as soon as it comes unless otherwise specified.
      (setf thread-state :running)) 
    (push message queue)
    (incf message-count)
    (bt:condition-notify condition))))  ;; Wake up waiting thread


;======================================================== TESTING OF ACTOR ===============================

(defun test-counter-actor ()
  "Test the lifecycle and behavior of the counter actor using standard assert.
   中文：自测脚本 —— 创建 stateful counter actor，依次走
         created → running/waiting → 增减消息 → stopped → restart → destroyed
         全生命周期，每步用 assert 校验状态。"

  (format t "Starting test for counter actor...~%")

  ;; Create Actor
  (let ((counter (make-instance 'nst-actor
				:name "Counter Actor Testing"
				:behavior #'counter-behavior
				:initial-state 0
				:stateful t)))

 
    ;; Ensure initial state
    (assert (eq (actor-thread-state counter) :created) (counter)
            "Actor should start in 'created' state.")

    ;; Start the actor
    (start-actor counter)
    (sleep 0.1) ;; Allow thread to start
    (assert (or (eq (actor-thread-state counter) :waiting)
                (eq (actor-thread-state counter) :running))
            (counter)
            "Actor should be in 'waiting' or 'running' state after start.")

    ;; Send messages and check state updates
    (send-message counter (lambda () :increment))
    (sleep 0.1) ;; Allow message processing
    
    (assert (= (actor-state counter) 1) (counter)
            "Counter state should be 1 after :increment.")

    (send-message counter (lambda () :increment))
    (sleep 0.1)
    (assert (= (actor-state counter) 2) (counter)
            "Counter state should be 2 after another :increment.")

    (send-message counter (lambda () :decrement))
    (sleep 0.1)
    (assert (= (actor-state counter) 1) (counter)
            "Counter state should be 1 after :decrement.")

    ;; Stop the actor
    (stop-actor counter)
    (sleep 0.1)
    (assert (eq (actor-thread-state counter) :stopped) (counter)
            "Actor should be in 'stopped' state after stop.")

    ;; Ensure messages are not processed when stopped and bulk-processing-mode-p is true.
    (send-message counter (lambda () :increment) t)
    (sleep 0.1)
    (assert (= (actor-state counter) 1) (counter)
            "Counter state should remain 1 when actor is stopped.")

    ;; Restarting actor and processing messages again
    (start-actor counter)
    (sleep 0.1)
    (assert (or (eq (actor-thread-state counter) :waiting)
                (eq (actor-thread-state counter) :running))
            (counter)
            "Actor should be 'waiting' or 'running' after restarting.")

    (send-message counter (lambda () :increment))
    (sleep 0.1)
    (assert (= (actor-state counter) 3) (counter)
            "Counter state should be 3 after restarting and incrementing.")

 
    ;; Destroy the actor
    (destroy-actor counter)
    (sleep 0.1)
    (assert (eq (actor-thread-state counter) :terminated) (counter)
            "Actor should be in 'destroyed' state after destroy.")

    (format t "All tests passed successfully!~%")))

;; Run Test
;;(test-counter-actor)

;=======================================================================================================


(defun counter-behavior (state message)
  "演示用 stateful 行为：消息 lambda 返回 :increment / :decrement，更新 state。
   未知消息打印告警并保留原 state。"
  (multiple-value-bind (msg) (funcall message)
    (cond
      ((eq msg :increment) (+ state 1))
      ((eq msg :decrement) (- state 1))
      (t (format t "Unknown message: ~A~%" msg) state))))

;; Create a stateful counter actor
(defparameter *counter* (make-instance 'nst-actor
				       :name "Counter Actor"
                                       :behavior #'counter-behavior
                                       :initial-state 0
                                       :stateful t))

;; (setf *counter* nil) to delete the actor.


