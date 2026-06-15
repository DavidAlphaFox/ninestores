;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 简易单元测试集合（顶层脚本）
;;;; 分层：平台基础（开发期 REPL 脚本）
;;;; 文件：hhub/core/unit-tests.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：在 SLIME REPL 里手工跑的"端到端"小脚本：
;;;;       1) 在 demo 公司里创建测试 customer / vendor / product；
;;;;       2) 创建订单、订单明细、订单偏好；
;;;;       3) 演示软删除 + 恢复。
;;;;       注：本文件是"加载即执行"的顶层 form，会真正写入数据库 —— 仅在开发环境跑。
;;;;
;;;; 主要导出（多为顶层 defparameter 测试数据）：
;;;;   dod-company、Testcustomer1、Testvendor1、TestOrder1、Testproduct
;;;;   prepare-test-customer / test-create-customer / test-delete-customer
;;;;   prepare-test-orders / test-order-details
;;;;
;;;; 关联：
;;;;   下游依赖：customer / vendor / product / order 各模块的 BL 函数
;;;;   备注：正式测试在 hhub/test/ 下；本文件更接近"REPL 段子"。
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)
					;**********Get the company***********
(defparameter dod-company (select-company-by-name "demo"))


					;******Create the customer ******
(defparameter *birthdate* (make-date :year 2016 :month 5 :day 29))
(defparameter *customer-params* nil)
(setf *customer-params* (list (format nil "Test Customer ~a" (random 200)) "GA Bangalore 560066" (format nil "98456~a" (random 99999)) "test@test.com" *birthdate* "P@ssword" "salt" "Bangalore" "Karnataka" "560066"  dod-company))
;Create the customer now.
(apply #'create-customer *customer-params*)
;Get the customer which we have created in the above steps. 
(defparameter Testcustomer1 (select-customer-by-name (car *customer-params*) dod-company))

; **** Create the vendor *****
(defparameter *vendor-params* nil)
(setf *vendor-params* (list (format nil "Test Vendor ~a" (random 20)) "GA Bangalore 560066" (format nil "98456~a" (random 99999)) "testvendor@test.com" "P@ssword" "salt"  "Bangalore"  "Karnataka" "560066" dod-company))
;Create the vendor now.
(apply #'create-vendor *vendor-params*)
;Get the vendor which we have created in the above steps. 
(defparameter Testvendor1(select-vendor-by-name (car *vendor-params*) dod-company))

;******* Create new order ********
(defparameter OrderDate (make-date :year 2016 :month 5 :day 29))
(defparameter RequestDate (make-date :year 2016 :month 5 :day 29))
(defparameter ShipDate (make-date :year 2016 :month 5 :day 29))
(defparameter NandiniBlue (select-product-by-name "%Nandini Blue" dod-company))
(defparameter NandiniGreen (select-product-by-name "%Nandini-Green" dod-company))
(create-order OrderDate Testcustomer1 RequestDate ShipDate "GA Bangalore" nil nil "PRE" "Test CommentS" dod-company  )
(defparameter TestOrder1 (get-latest-order-for-customer Testcustomer1 ))
;;****** Create order details ********
(create-order-items TestOrder1 NandiniBlue 1 15.00 dod-company)
(create-order-items TestOrder1 NandiniGreen 1 20.00 dod-company)

(defparameter Customer1-orders (get-orders-for-customer  Testcustomer1))
;Create test data for Tenant 3

					;Delete a customer
(delete-customer Testcustomer1)
(restore-deleted-Customer Testcustomer1)
					;Get the number of customers;
(defparameter *num-customers* nil)
(defparameter *list-customers* nil)
(setf *list-customers*  (list-cust-profiles dod-company))
(defparameter num-customers (length (list-cust-profiles dod-company)))

(defparameter dod-company (select-company-by-name "Gopalan Atlantis"))
(defparameter Rajesh (Select-vendor-by-name "%Rajesh" dod-company))
(defparameter NandiniPurple (list (format nil "Nandini Sumrudhi (Purple packet)") Rajesh "500 ml" 18.50 "/resources/nandini-purple.png" dod-company))
(defparameter NandiniSTM (list (format nil "Nandini Special Toned Milk") Rajesh "500 ml" 18.50 "/resources/nandini-stm.png" dod-company))
(defparameter NandiniYellow (list (format nil "Nandini Double Toned Milk (Yellow packet)") Rajesh "500 ml" 46.00 "/resources/nandini-yellow.png" dod-company))
; (apply #'create-product NandiniPurple)


(defparameter *product-params* nil)
(setf *product-params* (list (format nil "Test Product ~a" (random 200)) TestVendor1 "1 Litre" 20.00 "/resources/test-product.png" nil dod-company))
;Create the customer now.
(apply #'create-product *product-params*)
;Get the customer which we have created in the above steps. 
(defparameter Testproduct (select-product-by-name (car *product-params*) dod-company ))

;*************************************************************************
;********************** create order preferences  ****************************

(create-opref Testcustomer1 NandiniBlue 1 dod-company)
(create-opref Testcustomer1 NandiniGreen 1 dod-company)

(defparameter opflist (get-opreflist-for-customer Testcustomer1))
(create-order-from-pref opflist orderdate requestdate shipdate "Gopalan Atlantis Bangalore" Testcustomer1  dod-company)


;*************************************************************************
;********************** create a new product ****************************

(defun prepare-test-customer ()
  "在 'Gopalan Atlantis' 公司下准备测试客户的闭包。
   返回值不重要 —— 副作用是定义出 test-create-customer / test-delete-customer 两个内层 defun。
   备注：内嵌 defun 不是惯用做法（每次调用 prepare 都会重定义全局函数），
         视为开发期手稿。"
  (let* ((dod-company (select-company-by-name "Gopalan Atlantis"))
					;******Create the customer ******
	 (customer-params (list (format nil "Test Customer ~a" (random 200)) "GA Bangalore 560066" (format nil "98456~a" (random 99999)) dod-company))
	 (Testcustomer1 nil))

    (defun test-create-customer ()
      (progn (apply #'create-customer customer-params)
	     (setf Testcustomer1 (select-customer-by-name (car customer-params) dod-company)))
      (defun test-delete-customer () (apply #'delete-customer (list TestCustomer1))))))



(defun prepare-test-orders (customer-id company-name)
  "为指定 customer 准备订单测试上下文（按公司名 + 客户主键查找）。
   副作用：内层 defun 定义 test-order-details；返回该函数的最终值。"
  (let* ((dod-company (select-company-by-name company-name))
	 (customer (select-customer-by-id customer-id dod-company))
	 (order (get-orders-for-customer customer)))
	 

    (defun test-order-details ()
     (let ((order-details (get-order-items order)))
       order-details))))
		



(defparameter Testvendor1(select-vendor-by-name "%Rajesh" dod-company))
(defparameter *product-params* nil)
(setf *product-params* (list "Nandini Ghee"  TestVendor1 "500 Grams" 200.00 nil dod-company))
;Create the customer now.
;(apply #'create-product *product-params*)
;Get the customer which we have created in the above steps. 
(defparameter Testproduct (select-product-by-name (car *product-params*) dod-company ))
(defparameter OrderDate (make-date :year 2016 :month 8 :day 17))
(defparameter RequestDate (make-date :year 2016 :month 8 :day 17))

 



