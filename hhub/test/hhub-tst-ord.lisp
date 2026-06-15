;;; hhub-tst-ord.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：test —— 订单 / 运费 / 异步事件 综合测试
;;;; 分层：测试套件（集成测试 + cl-async 实验）
;;;; 文件：hhub/test/hhub-tst-ord.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：聚合三类测试 ——
;;;;   1) 订单创建端到端（hhub-test-order） + 运费计算
;;;;   2) cl-async 事件循环 / 通知器 / idler / promise 的探索性 PoC
;;;;   3) 复数因子驱动的"下一个函数"调度器实验（mapcomplexfunc / nextfunc）
;;;;
;;;; 主要导出：
;;;;   hhub-test-order                       — 走 orderAdapter 端到端创建一张演示订单
;;;;   hhub-test-shipping-rate-check         — 调用 order-shipping-rate-check（指定收发邮编）
;;;;   hhub-test-shipping-rate-check-zonewise — 按区域计费的运费检查
;;;;   hhub-test-async-event-loop            — cl-async 最小事件循环示例
;;;;   hhub-background-task-with-events      — 后台线程 + 多事件键
;;;;   process-event / event-worker          — 触发事件 / 事件工作体（发邮件）
;;;;   hhub-background-task-with-notifier    — 通知器（finished 时回调）
;;;;   hhub-background-task-with-async-delay — 延时任务
;;;;   hhub-background-task-with-idlers      — idler（事件循环空闲触发）
;;;;   promise-task                          — bb:with-promise 示例
;;;;   func1..func4 / mapcomplexfunc / nextfunc — 复数因子调度器 PoC
;;;;
;;;; 关联：
;;;;   下游依赖：order/dod-bl-ord.lisp / order/nst-ui-Order.lisp（orderAdapter）、
;;;;             shipping/dod-bl-osh.lisp（运费）、cl-async (as:*)、blackbird (bb:*)、
;;;;             sb-thread:make-thread、hhubsendmail
;;;; ============================================================================

(in-package :nstores)

(defun hhub-test-order ()
  ;; 集成测试：会真实写订单。固定 vendor=1, company=2, customer=1, 商品=1/2（Nandini Blue/Green）。
  ;; 关键计算：order-amt = 两件商品 current-price 之和；total-discount 同理；
  ;; shipping-cost 由 calculate-shipping-cost-for-order 按 vendor 的 shipping-method 计算。
  (let* ((company (select-company-by-id 2))
	 (vendor (select-vendor-by-id 1))
	 (customer (select-customer-by-id 1 company))
	 (order-date (current-date-object))
	 (request-date (current-date-object))
	 (shipped-date nil)
	 (expected-delivery-date (clsql::date+ (clsql::get-date) (clsql::make-duration :day 2)))
	 (NandiniBlue (select-product-by-id 1 company))
	 (NandiniGreen (select-product-by-id 2 company))
	 (shopcart-products (list NandiniBlue NandiniGreen))
	 (oitem1 (create-odtinst-shopcart nil NandiniBlue 1 (slot-value NandiniBlue 'current-price) (slot-value NandiniBlue 'current-discount) company))
	 (oitem2 (create-odtinst-shopcart nil NandiniGreen 1 (slot-value NandiniGreen 'current-price) (slot-value NandiniGreen 'current-discount) company))
	 (oitem1price (slot-value NandiniBlue 'current-price))
	 (oitem2price (slot-value NandiniGreen 'current-price))
	 (oitem1discount (slot-value NandiniBlue 'current-discount))
	 (oitem2discount (slot-value NandiniGreen 'current-discount))
	 (order-items (list oitem1 oitem2))
	 (shipaddr "A-456, Brigade Metropolis, Mahadevapura, Bangalore 560066")
	 (shipzipcode "560066")
	 (shipcity "Mahadevapura, Bangalore")
	 (shipstate "Karnataka")
	 (billaddr shipaddr)
	 (billzipcode shipzipcode)
	 (billcity shipcity)
	 (billstate shipstate)
	 (billsameasship "Y")
	 (storepickupenabled "N")
	 (gstnumber "")
	 (gstorgname "")
	 (order-amt (+ oitem1price oitem2price))
	 (total-discount (+ oitem1discount oitem2discount))
	 (total-tax 0.00)
	 (payment-mode "PRE")
	 (comments "This order is created")
	 (order-type "SALE")
	 (order-source "WEB")
	 (customer-name (slot-value customer 'name))
	 (vshipping-method (get-shipping-method-for-vendor vendor company))
	 (shiplst (calculate-shipping-cost-for-order vshipping-method shipzipcode order-amt order-items shopcart-products vendor company))
	 (shipping-cost (nth 0 shiplst))
	 ;;(shipping-info (nth 1 shiplst))
	 ;;(utrnum "829349823423")
	 (requestmodel (make-instance 'orderRequestModel
				      :ord-date order-date
				      :req-date request-date
				      :shipped-date shipped-date
				      :expected-delivery-date expected-delivery-date
				      :ordnum ""
				      :shipaddr shipaddr
				      :shipzipcode shipzipcode
				      :shipcity shipcity
				      :shipstate shipstate
				      :billaddr billaddr
				      :billzipcode billzipcode
				      :billcity billcity
				      :billstate billstate
				      :billsameasship billsameasship
				      :storepickupenabled storepickupenabled
				      :gstnumber gstnumber
				      :gstorgname gstorgname
				      :order-fulfilled "N"
				      :order-amt order-amt
				      :shipping-cost shipping-cost
				      :total-discount total-discount
				      :total-tax total-tax
				      :payment-mode payment-mode
				      :comments comments
				      :context-id (format nil "~A" (uuid:make-v1-uuid))
				      :status "PEN"
				      :order-type order-type
				      :order-source order-source
				      :is-converted-to-invoice "N"
				      :is-cancelled "N"
				      :cancel-reason "NOT APPLICABLE"
				      :deleted-state "N"
				      :external-url (format nil "https://~A/" *siteurl*)
				      :custname customer-name
				      :customer customer
				      :company company)))
    (with-entity-create 'orderAdapter requestmodel
      entity)))

(defun hhub-test-shipping-rate-check ()
  ;; 返回一个闭包；调用闭包时计算 商品(NandiniBlue x2 + NandiniGreen x2) 从邮编 560010 到 560096 的运费。
  (let ((ratecheckfunction
	  (lambda ()
	    (let* ((company (select-company-by-id 2))
		   (NandiniBlue (select-product-by-id 1 company))
		   (NandiniGreen (select-product-by-id 2 company))
		   (prodlist (list NandiniBlue NandiniGreen))
		   (oitem1 (create-odtinst-shopcart nil NandiniBlue 2 (slot-value NandiniBlue 'current-price) 0  company))
		   (oitem2 (create-odtinst-shopcart nil NandiniGreen 2 (slot-value NandiniGreen 'current-price) 0 company))
		   (odts (list oitem1 oitem2)))
	      (order-shipping-rate-check odts prodlist "560010" "560096")))))
    ratecheckfunction))


(defun hhub-test-shipping-rate-check-zonewise ()
  ;; 按区域定价：以收件邮编 400092 调用 order-shipping-rate-check-zonewise。
  (let* ((company (select-company-by-id 2))
	 (NandiniBlue (select-product-by-id 1 company))
	 (NandiniGreen (select-product-by-id 2 company))
	 (prodlist (list NandiniBlue NandiniGreen)))
    (order-shipping-rate-check-zonewise prodlist "400092")))


(defun hhub-test-async-event-loop ()
  ;; cl-async PoC：在事件循环里 3 秒后打印一行；演示 as:start-event-loop + as:delay。
  (format t "I am running before everybody else")
  
  (as:start-event-loop 
   (lambda ()
     (as:delay
      (lambda () (format t "I am running after 3 seconds")) :time 3)))
      
  (format t "I am completing"))


(defun worker-2 (context p)
  ;; 简单 worker：忽略 context 参数，仅打印 p。用于 actor / 任务调度示例。
  (declare (ignore context))

    (print p))

;; 三个 hash-table 用于存放后台任务体的句柄，键名见 process-* 函数：
(defvar *notifier-ht* (make-hash-table :test 'equal)) ;; "notifierkey<n>" → as:make-notifier 句柄
(defvar *events-ht* (make-hash-table :test 'equal))   ;; "eventkey<n>"    → as:make-event 句柄
(defvar *idlers-ht* (make-hash-table :test 'equal))   ;; "idlerkey<n>"    → as:idle 句柄

(defun hhub-background-task-with-events ()
  ;; 在独立线程里跑 cl-async 事件循环，并预注册 3 个事件键 eventkey1/2/3。
  ;; 后续用 process-event 触发它们，事件回调统一是 event-worker（发邮件 + sleep 10）。
  (let ((asynceventloopthread (sb-thread:make-thread
			       (lambda ()
				 (as:with-event-loop (:catch-app-errors t)
				   (setf (gethash "eventkey1" *events-ht*) (as:make-event #'event-worker))
				   (setf (gethash "eventkey2" *events-ht*) (as:make-event #'event-worker))
				   (setf (gethash "eventkey3" *events-ht*) (as:make-event #'event-worker))
				   )) :name "Async event loop thread having events")))

    (format *stdoutstream* "I have created an async event loop thread ~A ~C~C" asynceventloopthread #\return #\linefeed)
    asynceventloopthread))

(defun process-event (num)
  "中文：触发 *events-ht* 中编号为 num 的事件，2 秒后激活。"
  (let ((ekey (format nil "eventkey~d" num)))
    (as:add-event (gethash ekey *events-ht*)  :timeout 2 :activate t)))


(defun event-worker ()
  ;; 事件回调：发邮件后 sleep 10 秒模拟耗时任务。会真实触发邮件发送（hhubsendmail）。
  (format *stdoutstream* "Inside event and sending mail now  ~C~C"   #\return #\linefeed)
  (hhubsendmail "uflgxh+a335lpgfhjudo@sharklasers.com" (format nil "Test subject ~A " (gensym)) "Test 123") 
  (sleep 10)
  (format *stdoutstream* "Inside event and send mail done  ~C~C"   #\return #\linefeed))


(defun hhub-background-task-with-notifier ()
  ;; 与 events 版本类似，但用 as:make-notifier；预注册 6 个 notifier 键。
  ;; 后续 process-notifier-task 会先在独立线程里 sleep 1×20 次，然后 trigger-notifier。
  (let ((backgroundtask (sb-thread:make-thread
			   (lambda ()
			     (as:with-event-loop (:catch-app-errors t)
			       (let* ((result nil))
				 (setf (gethash "notifierkey1" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (setf (gethash "notifierkey2" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (setf (gethash "notifierkey3" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (setf (gethash "notifierkey4" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (setf (gethash "notifierkey5" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (setf (gethash "notifierkey6" *notifier-ht*) (as:make-notifier (lambda () (format t "Job finished! ~a~%" result))))
				 (format *stdoutstream* "I am in the async event loop. Exiting loop")))) :name "Event Loop Thread")))
    backgroundtask))

(defun process-notifier-task (num)
  "中文：启动一个后台任务（background-task），完成后会触发 *notifier-ht* 中第 num 个 notifier。"
  (let ((nkey (format nil "notifierkey~d" num)))
    (background-task num (gethash nkey *notifier-ht*))
  (format *stdoutstream* "Background task for notifier -  ~A will be triggered now" nkey)))

(defun background-task (num notifier)
  "中文：在新线程里 sleep×20 模拟工作，结束时调用 as:trigger-notifier 通知事件循环。"
  (sb-thread:make-thread
     (lambda ()
  	  (loop for i from 1 to  20 do 
	    (sleep 1)
	    (format *stdoutstream* "For thread number ~d I am running ~d iteration  ~C~C" num i  #\return #\linefeed))
       (as:trigger-notifier notifier)
       ) :name (format nil "Background Task/ Thread -~d" num)))

(defun hhub-background-task-with-async-delay ()
  ;; 仅事件循环 + 一次 3 秒 delay 的最小示例；不创建额外线程。
  (as:with-event-loop (:catch-app-errors t)
    (let* ((result nil))
      (as:delay
       (lambda ()
	 (setf result 10)
	 (format T "Timer Fired. Exiting. Result is ~A ~%" result)) :time 3))))
 


(defun hhub-background-task-with-idlers ()
  ;; idler 版：当事件循环空闲时反复触发 event-worker。
  (let ((asynceventloopthread (sb-thread:make-thread
			       (lambda ()
				 (as:with-event-loop (:catch-app-errors t)
				   (setf (gethash "idlerkey1" *idlers-ht*) (as:idle #'event-worker))
				   )) :name "Async event loop thread having idlers")))

    (format *stdoutstream* "I have created an async event loop thread ~A ~C~C" asynceventloopthread #\return #\linefeed)
    asynceventloopthread))
  

(defun idler-worker ()
  ;; idler 回调：与 event-worker 类似——发邮件 + sleep 10。
  (hhubsendmail "uflgxh+a335lpgfhjudo@sharklasers.com" (format nil "Test subject ~A " (gensym)) "Test 123")
  (sleep 10)
  (format *stdoutstream* "Idler has done its job of sending email ~C~C" #\return #\linefeed))



;;;;;;;;;;;;;;;;;;;;;;; CL-ASYNC PROMISES ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun promise-task ()
  ;; blackbird 库 promise 最小示例。返回一个 promise，resolve 时执行打印闭包。
  (bb:with-promise (resolve reject)
    (handler-case
	(resolve (lambda () (format *stdoutstream* "I am resolving")))
      (t (e) (reject e)))))
      


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;NST EVENT LOOP ARCHITECTURE;;;;;;;;;;;;;;;;;;;;;;;;;

;;; will work on it someday.


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;




;; 复数因子调度器 PoC：4 个示例函数，分别绑定到象限 (1+i)/(-1+i)/(-1-i)/(1-i)。
(defun func1 ()
  "Hello1")

(defun func2 ()
  "world1")

(defun func3 ()
  "Hello2")

(defun func4 ()
  "World2")

(defun mapcomplexfunc ()
  "中文：构造一个 alist：复数 ↔ 函数符号名，覆盖四个象限。"
  (let ((funclist nil))
    (setf funclist (acons (complex 1 1) "func1" funclist))
    (setf funclist (acons (complex -1 1 ) "func2"  funclist))
    (setf funclist (acons (complex -1 -1) "func3"  funclist))
    (setf funclist (acons (complex 1 -1) "func4"  funclist))
    funclist))

;; nextfunc：闭包，每次调用按 complex-factor 旋转上次的键，从 alist 取下一个函数并 funcall。
(defvar nextfunc
  (let* ((funclist (mapcomplexfunc))
	 (complexfactor (complex 0 0.5))
	 (lasttimefunckey (complex 1 1)))

    (lambda ()
     (let ((func (cdr (assoc lasttimefunckey funclist :test '=))))
       (setf lasttimefunckey (* complexfactor lasttimefunckey))
       (funcall (intern (string-upcase func) :nstores))
       ))))

;; 简易闭包计数器：每次 (funcall *counter*) 自增 1。
(defvar *counter* (let ((count 0))
                    (lambda () (incf count))))

    

  


