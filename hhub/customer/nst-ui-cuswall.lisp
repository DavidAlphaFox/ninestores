;; -*- mode: common lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：customer 客户
;;;; 分层：UI 控制器/视图层
;;;; 文件：hhub/customer/nst-ui-cuswall.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：客户钱包列表页面的控制器与 MVC 三件套（Model + Widgets）。
;;;;       展示当前登录客户在不同卖家处的钱包余额，并提供充值入口。
;;;;
;;;; 主要导出：
;;;;   dod-controller-cust-wallet-display       — 控制器入口（客户登录后查看钱包）
;;;;   create-model-for-custwalletdisplay       — 构造表格模型（表头 + 行数据）
;;;;   create-widgets-for-custwalletdisplay     — 构造视图 widget 列表
;;;;
;;;; 关联：
;;;;   上游使用方：客户 PWA 自助门店导航
;;;;   下游依赖：BL get-cust-wallets、core 的 with-mvc-ui-page / with-cust-session-check、
;;;;             cust-wallet-as-row 渲染函数
;;;; ============================================================================

(in-package :nstores)


(defun dod-controller-cust-wallet-display ()
  :documentation "客户钱包展示页控制器：要求客户已登录，进入后用 with-mvc-ui-page
   渲染标题为 \"Customer Wallets\" 的页面。
   参数：无（从 session 读取登录态）。
   返回：渲染后的 HTML 字符串。"
  (with-cust-session-check
    (with-mvc-ui-page "Customer Wallets" #'create-model-for-custwalletdisplay #'create-widgets-for-custwalletdisplay :role :customer)))


(defun create-model-for-custwalletdisplay ()
  "构造钱包展示模型。从 session 取出当前 company / customer，查询其全部钱包记录，
   返回一个 thunk；调用该 thunk 得到两个返回值：表头列表 与 钱包实例列表。"
  (let* ((company (hunchentoot:session-value :login-customer-company))
	 (customer (hunchentoot:session-value :login-customer))
	 (header (list "Vendor" "Phone" "Balance" "Recharge"))
	 (wallets (get-cust-wallets customer company)))
    (function (lambda ()
      (values header wallets)))))

(defun create-widgets-for-custwalletdisplay (modelfunc)
  "把 model thunk 中的表头 + 行数据交给 display-as-table 渲染为 HTML 表格，
   每行使用 'cust-wallet-as-row' 渲染。
   返回：单元素 widget 列表（widget 本身是无参 thunk，调用时输出 HTML）。"
  (multiple-value-bind (header wallets) (funcall modelfunc)
    (let ((widget1 (function (lambda ()
		     (cl-who:with-html-output (*standard-output* nil)
		       (cl-who:str (display-as-table header wallets 'cust-wallet-as-row)))))))
      (list widget1))))
