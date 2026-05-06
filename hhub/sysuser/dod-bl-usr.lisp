;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— 系统用户业务逻辑
;;;; 分层：BL（业务逻辑层）
;;;; 文件：hhub/sysuser/dod-bl-usr.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：dod-users 实体的业务函数集合 —— 用户登录会话管理、单用户登录强制、
;;;;       CRUD（新建/查询/软删/恢复）以及密码重置。
;;;;
;;;; 主要导出：
;;;;   set-user-session-params       — 把 user/company 注入 Hunchentoot session 与 BusinessSession
;;;;   enforceusersession            — 限制单用户最大并发会话数（HHUBMAXUSERLOGINS）
;;;;   list-dod-users / get-users-for-company / select-user-by-id / select-user-by-phonenumber
;;;;   delete-dod-user / delete-dod-users / restore-deleted-dod-users
;;;;   update-user / reset-user-password / create-dod-user
;;;;
;;;; 关联：
;;;;   上游使用方：sysuser/dod-ui-sys.lisp（系统超管控制器）、
;;;;               sysuser/dod-ui-cad.lisp（CAD 控制器）、登录流程
;;;;   下游依赖：sysuser/dod-dal-usr.lisp（dod-users 实体）、
;;;;             core/utils（encrypt/hhub-random-password/createciphersalt/business-session）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)


(defun set-user-session-params (company  user)
  "登录成功后把 (company, user) 注入 Hunchentoot 会话以及 HHUB BusinessSession。
   写入若干 :login-user-* 会话键供后续控制器读取，注册到 HHUBBUSINESSSERVER 的 'compadminsite' 上下文，
   并调用 enforceusersession 强制单用户最大并发数。
   返回：BusinessSession 的 sessionkey。
   副作用：修改 hunchentoot:*session*、写日志、可能踢掉旧会话。"
  ;; Add the vendor object and the tenant to the Business Session
  ;;set vendor company related params
  (let ((usessionobj (make-instance 'UserSessionObject)))
    (setf (slot-value usessionobj 'uwebsession) hunchentoot:*session*)
    (setf (hunchentoot:session-value :login-user ) user)
    (setf (slot-value usessionobj 'user) user)
    (setf (hunchentoot:session-value :login-username) (slot-value user 'username))
    (setf (hunchentoot:session-value :login-user-name) (slot-value user 'name))
    (setf (slot-value usessionobj 'user-name) (slot-value user 'name))
    (setf (hunchentoot:session-value :login-user-id) (slot-value user 'row-id))
    (setf (slot-value usessionobj 'user-id) (slot-value user 'row-id))
    (setf (hunchentoot:session-value :login-user-tenant-id) (slot-value company 'row-id ))
    (setf (slot-value usessionobj 'user-tenant-id) (slot-value company 'row-id))
    (setf (hunchentoot:session-value :login-user-company-name) (slot-value company 'name))
    (setf (slot-value usessionobj 'companyname) (slot-value company 'name))
    (setf (hunchentoot:session-value :login-user-company) company)
    (setf (hunchentoot:session-value :login-user-currency) (get-account-currency company))
    (setf (hunchentoot:session-value :login-user-role-name) (com-hhub-attribute-role-name))
    (setf (hunchentoot:session-value :login-attribute-cart) '())
    ;;(setf (hunchentoot:session-value :login-prd-cache )  (select-products-by-company company))
    ;;set vendor related params 
    (addloginusersettings)
    (let ((sessionkey (createBusinessSession (getBusinessContext *HHUBBUSINESSSERVER* "compadminsite") usessionobj)))
      (setf (hunchentoot:session-value :login-user-business-session-id) sessionkey)
      (logiamhere (format nil "web session is ~A" (slot-value usessionobj 'uwebsession)))
      (logiamhere (format nil "session key is ~A" sessionkey))
      (enforceusersession sessionkey "compadminsite" *HHUBMAXUSERLOGINS*)
      sessionkey)))

(defun enforceusersession (sessionkey contextname maxusersallowed)
  "强制单用户最大并发登录数。扫描 contextname 上下文里的全部 BusinessSession，
   找出与当前 user-id 相同但 sessionkey 不同的旧会话；若数量 >= maxusersallowed，
   踢掉第一条（remove-session + deleteBusinessSession）。
   参数：sessionkey — 当前刚建好的会话 key；contextname — 业务上下文名；
        maxusersallowed — 同一用户最多保留多少个并发 session。
   副作用：可能销毁旧会话，写日志。"
  (let* ((bcontext (getBusinessContext *HHUBBUSINESSSERVER* contextname))
	 (bsessions-ht (businesssessions-ht bcontext))
	 (busersession (gethash sessionkey bsessions-ht))
	 (user (slot-value busersession 'user))
	 (sessionlist '())
	 (keylist '()))
    (maphash (lambda (k v)
	       (let ((prevuserid (slot-value v 'user-id))
		     (prevwebsession (slot-value v 'uwebsession))
		     (loginuserid (slot-value user 'row-id))
		     (username (slot-value user 'name)))
		 (when (and
			(not (equal k sessionkey)) ;; There are 2 separate sessions from same user. 
			(= prevuserid loginuserid)) ;; Same user is login again.
		   (logiamhere (format nil "User is ~A. key is ~A. Websession is ~A" username k prevwebsession))
		   (setf sessionlist (append sessionlist (list v)))
		   (setf keylist (append keylist (list k)))))) bsessions-ht)
    ;; If there are exactly 1 item in the list that means that user has logged in previouly. 
    (when (>= (length sessionlist) maxusersallowed)
      (let* ((sessiontoremove (nth 0 sessionlist))
	     (websession (slot-value sessiontoremove 'uwebsession))
	     (firstkey (nth 0 keylist)))
	(hunchentoot:remove-session websession)
	(deleteBusinessSession bcontext firstkey)))
    (logiamhere (format nil "there are ~d items in session list " (length sessionlist)))))



(defun addloginusersettings ()
  ;; 占位钩子：登录后追加用户设置（当前为空实现，预留扩展）。
  )


(defun list-dod-users ()
  "列出当前登录租户下的全部用户（排除内置 superadmin），不缓存。
   过滤：deleted-state='N' AND tenant-id=(get-login-tenant-id) AND name != 'superadmin'。"
  (clsql:select 'dod-users  :where [and [= [:deleted-state] "N"]
		[= [:tenant-id] (get-login-tenant-id)]
		[<> [:name] "superadmin"]]    :caching nil :flatp t ))

(defun get-users-for-company (tenant-id)
  "按显式 tenant-id 列用户（排除 superadmin）。"
  (clsql:select 'dod-users  :where [and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[<> [:name] "superadmin"]]    :caching nil :flatp t ))


(defun select-user-by-id (user-id tenant-id)
  "按主键在指定租户中查用户。排除 superadmin、过滤软删。"
  (car (clsql:select 'dod-users  :where [and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:row-id] user-id]
		[<> [:name] "superadmin"]]    :caching nil :flatp t )))

(defun select-user-by-phonenumber (phone tenant-id)
  "按手机号在指定租户中查用户。排除 superadmin、过滤软删。"
  (car (clsql:select 'dod-users  :where [and [= [:deleted-state] "N"]
		[= [:tenant-id] tenant-id]
		[= [:phone-mobile] phone]
		[<> [:name] "superadmin"]]    :caching nil :flatp t )))



(defun delete-dod-user ( id )
  "软删单条用户：deleted-state 置为 'Y'。注意：未限定 tenant_id（系统级动作）。"
  (let ((doduser (car (clsql:select 'dod-users :where [= [:row-id] id] :flatp t :caching nil))))
    (setf (slot-value doduser 'deleted-state) "Y")
    (clsql:update-record-from-slot doduser 'deleted-state)))



(defun update-user (user-instance); This function has side effect of modifying the database record.
  "把用户实例 UPDATE 回 DOD_USERS。副作用：修改数据库记录。"
  (clsql:update-records-from-instance user-instance))

(defun delete-dod-users ( list )
  "批量软删用户。list — 主键 id 列表。"
  (mapcar (lambda (id)  (let ((doduser (car (clsql:select 'dod-users :where [= [:row-id] id] :flatp t :caching nil))))
			  (setf (slot-value doduser 'deleted-state) "Y")
			  (clsql:update-record-from-slot doduser  'deleted-state))) list ))


(defun restore-deleted-dod-users ( list )
  "批量恢复软删用户：deleted-state 改回 'N'。"
(mapcar (lambda (id)  (let ((doduser (car (clsql:select 'dod-users :where [= [:row-id] id] :flatp t :caching nil))))
    (setf (slot-value doduser 'deleted-state) "N")
    (clsql:update-record-from-slot doduser 'deleted-state))) list ))


(defun reset-user-password (user &optional password)
  :description "If a password is provided, then it is set otherwise returns a random password.
   中文：重置用户密码。给定 password 则使用之，否则生成 10 位随机密码；
         统一通过 createciphersalt + encrypt 完成加盐加密后写库。
   返回：未提供 password 时返回随机明文密码（供管理员转告用户）。
   副作用：UPDATE dod-users 的 password 与 salt。"
  (let* ((randompassword (hhub-random-password 10))
         (salt (createciphersalt))
         (encryptedpass (if password (encrypt password salt) (encrypt randompassword salt))))
    (setf (slot-value user 'password) encryptedpass)
    (setf (slot-value user 'salt) salt)
    (update-user user)
    (unless password randompassword)))


(defun create-dod-user(name uname passwd salt email-address phone tenant-id )
  "底层持久化：构造 dod-users 实例并写库。created-by/updated-by 都置为 tenant-id（注：而非真正的 user-id，疑似历史习惯）。
   副作用：INSERT 一条 DOD_USERS 记录。"
 (clsql:update-records-from-instance (make-instance 'dod-users
				    :name name
				    :username uname
				    :salt salt
				    :password passwd
				    :email email-address
				    :phone-mobile phone
				    :tenant-id tenant-id
				    :deleted-state "N"
				    :created-by tenant-id
				    :updated-by tenant-id)))
 


