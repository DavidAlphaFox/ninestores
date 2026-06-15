;;; nst-bl-otp.lisp
;;;
;;; Copyright (c) 2026 Nine Stores. All rights reserved.
;;;
;;; Distributed under the MIT License. See LICENSE file in the project root.

; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— OTP 一次性密码存储
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/core/nst-bl-otp.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：提供进程内的 OTP（手机短信验证码）存储 —— 闭包式 KV，
;;;;       带 TTL 自动清理后台线程 + 周期性日志落盘线程；OTP 写入日志时做掩码。
;;;;
;;;; 主要导出：
;;;;   make-otp-store                — 创建闭包；返回 (lambda (action &key ...))
;;;;   *otp-cleanup-interval*        — TTL 清理周期（秒）
;;;;   *otp-default-ttl*             — OTP 默认有效时间（秒）
;;;;   *log-dump-interval*           — 日志落盘周期（秒）
;;;;   today-log-file-path           — 当日日志文件路径生成
;;;;   mask-otp                      — OTP 字符串掩码（仅留末两位）
;;;;
;;;; 关联：
;;;;   上游使用方：登录页 OTP 校验、短信验证码下发；闭包通常存于 *otp-store*
;;;;   下游依赖：bordeaux-threads（bt:make-thread / bt:make-lock）
;;;; ============================================================================
(in-package :nstores)

(defparameter *otp-cleanup-interval* 60)     ; seconds between TTL cleanup. should be less than TTL.
(defparameter *otp-default-ttl* 120)         ; 2 minutes
(defparameter *log-dump-interval* 3600)       ; every 1 hour

(defun today-log-file-path (&optional (base "~hunchentoot/hhublogs"))
  "返回当天的 OTP 日志文件路径，按 base/otp-log-YYYY-MM-DD.txt 格式。"
  (multiple-value-bind (sec min hour day month year)
      (decode-universal-time (get-universal-time))
    (declare (ignore sec min hour))
    (format nil "~A/otp-log-~4,'0D-~2,'0D-~2,'0D.txt" base year month day)))

(defun mask-otp (otp)
  "把 OTP 字符串前 N-2 位替换成 '*'，仅保留末 2 位（写日志时用，避免明文外泄）。"
  (if (and (stringp otp) (> (length otp) 2))
      (concatenate 'string (make-string (- (length otp) 2) :initial-element #\*) (subseq otp (- (length otp) 2)))
      otp))

(defun make-otp-store ()
  "创建一个 OTP 闭包存储；启动两个守护线程：
     - otp-cleanup-thread：每 *otp-cleanup-interval* 秒清理过期项
     - otp-log-dump-thread：每 *log-dump-interval* 秒把内存日志冲到磁盘
   返回值：(lambda (action &key session-id persona purpose phone otp context ip ttl log-dir))。
   action 关键字：
     :set         写入新 OTP（按 session-id 索引）
     :get         读取整个项 plist
     :get-otp / :get-context / :get-persona / :get-purpose / :get-phone
     :delete      按 session-id 移除单条
     :clear       清空全部 OTP 并丢弃日志
     :log-dump    立即落盘日志
   备注：所有读写都在 bt:with-lock-held 内，保证多线程安全。"
  (let ((otp-table (make-hash-table :test 'equal))
        (log-entries '())
        (lock (bt:make-lock)))

    ;; Background cleanup thread
    (bt:make-thread
     (lambda ()
       (loop
         (sleep *otp-cleanup-interval*)
         (bt:with-lock-held (lock)
           (maphash
            (lambda (key value)
              (let ((timestamp (getf value :timestamp))
                    (ttl (getf value :ttl)))
                (when (> (- (get-universal-time) timestamp) ttl)
                  (remhash key otp-table))))
            otp-table))))
     :name "otp-cleanup-thread")

    ;; Background log dumper thread
    (bt:make-thread
     (lambda ()
       (loop
         (sleep *log-dump-interval*)
         (bt:with-lock-held (lock)
           (let ((log-file (today-log-file-path)))
             (with-open-file (out log-file :direction :output
                                           :if-exists :append
                                           :if-does-not-exist :create)
               (when (> (length log-entries) 0)
		 (dolist (entry (reverse log-entries))
                   (format out "~A~%" entry))))
             (setf log-entries '())))))
     :name "otp-log-dump-thread")

    ;; Store interface function
    (lambda (action &key session-id persona purpose phone otp context ip ttl log-dir)
      (let ((key (format nil "~A" session-id)))
        (bt:with-lock-held (lock)
          (ecase action
            (:set
             (setf (gethash key otp-table)
                   (list :otp otp
			 :phone phone
			 :persona persona
			 :purpose purpose
			 :context context
                         :timestamp (get-universal-time)
                         :ttl (or ttl *otp-default-ttl*)))

             ;; Push masked log
             (push (list :time (mysql-now)
                         :phone phone
                         :otp (mask-otp (format nil "~A" otp))
			 :ip ip
                         :persona persona
                         :purpose purpose)
                   log-entries))

            (:get
             (gethash key otp-table))
            (:get-otp
             (getf (gethash key otp-table) :otp))
            (:get-context
             (getf (gethash key otp-table) :context))
	    (:get-persona
	     (getf (gethash key otp-table) :persona))
	    (:get-purpose
	     (getf (gethash key otp-table) :purpose))
	    (:get-phone
	     (getf (gethash key otp-table) :phone))
	    (:delete
             (remhash key otp-table))
            (:clear
             (clrhash otp-table)
             (setf log-entries '()))
            (:log-dump
             (let ((log-file (today-log-file-path (or log-dir "~hunchentoot/hhublogs"))))
               (with-open-file (out log-file :direction :output
                                             :if-exists :append
                                             :if-does-not-exist :create)
                 (dolist (entry (reverse log-entries))
                   (format out "~A~%" entry)))
               (setf log-entries '())))))))))
