;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：package 平台基础 —— 顶层包定义
;;;; 分层：平台基础（必须最先编译）
;;;; 文件：hhub/package/packages.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义全局唯一的应用包 com.nstores.app，并以 :nstores 作为昵称。
;;;;       全工程其它 .lisp 文件首行均使用 (in-package :nstores)。
;;;;       仅显式导出三个全局状态符号（在线用户、数据库实例、HTTP 服务器实例）。
;;;;       其它符号一律 internal —— 这是有意为之的"单巨包"风格。
;;;;
;;;; 关联：
;;;;   上游使用方：所有业务/UI/DAL/test 文件
;;;;   下游依赖：cl 标准包
;;;; ============================================================================

(in-package :cl-user)
(defpackage :com.nstores.app
  (:use :cl)
  (:nicknames :nstores)
  (:export #:*logged-in-users*    ; 当前登录用户表（hash-table 或 alist，推测）
	   #:*dod-db-instance*    ; CLSQL 数据库连接句柄
	    #:*http-server*))     ; Hunchentoot HTTP 服务器实例


