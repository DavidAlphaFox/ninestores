;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：sysuser —— 超级管理员维护租户内用户
;;;; 分层：UI（控制器 + CL-WHO 模板）
;;;; 文件：hhub/sysuser/dod-ui-usr.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：超管视角列出某租户的用户、添加/编辑用户对话框、提交动作；
;;;;       辅助登录会话访问函数（get-login-userid / get-login-username 等）。
;;;;
;;;; 主要导出：
;;;;   com-hhub-transaction-sadmin-create-users-page  — 列表 + Add 按钮页面
;;;;   modal.com-hhub-transaction-sadmin-create-users — Add/Edit 用户模态对话框
;;;;   user-card                                       — 列表行渲染
;;;;   dod-controller-add-user-action                  — POST /hhub/dasadduseraction 提交动作
;;;;   create-user-with-role                           — 编程式创建用户（带角色绑定）
;;;;   get-login-userid / get-login-username / get-login-user-name / hhub-session-validp
;;;;   verify-superadmin / superadmin-login
;;;;
;;;; 关联：
;;;;   上游：浏览器 /hhub/sadmin* 路径
;;;;   下游：sysuser/dod-bl-usr.lisp（用户 CRUD）、sysuser/dod-bl-sys.lisp（user-role）、
;;;;         core utils（check&encrypt/createciphersalt）
;;;; ============================================================================

(in-package :nstores)
(clsql:file-enable-sql-reader-syntax)



(defun com-hhub-transaction-sadmin-create-users-page ()
  "URL：/hhub/sadmincreateuserspage（推测）。
   超管视角：从 query 参数 tenant-id 取目标租户，列出该租户全部用户表格，
   并提供 'Add User' 模态对话框。包在 with-hhub-transaction 内做 PEP 鉴权。"
 (with-opr-session-check 
   (let* ((tenant-id (hunchentoot:parameter "tenant-id"))
	  (users (get-users-for-company tenant-id))
	  (params nil))

     (setf params (acons "uri" (hunchentoot:request-uri*)  params))
     (setf params (acons "username" (get-login-username)  params))
     
     (with-hhub-transaction "com-hhub-transaction-sadmin-create-users-page" params
       (with-standard-admin-page "List HHUB Users"
	 (:h3 "Users")
	 (:a  :data-toggle "modal" :tooltip "Add User" :data-target (format nil "#adduser-modal")  :href "#"  (:i :class "fa-solid fa-user-plus"))
	 (hunchentoot:log-message* :info "I am here" )
	 (modal-dialog (format nil "adduser-modal") "Add/Edit Policy" (modal.com-hhub-transaction-sadmin-create-users tenant-id "NEW"))
	 
	 (cl-who:str (display-as-table (list "Name" "Phone number" "Email" "Action")  users 'user-card)))))))



(defun user-card (user-instance &rest arguments)
  "用户列表行渲染：4 列（Name / Phone / Email / Action 编辑按钮）；
   编辑按钮触发 #edituser-modal<row-id> 模态框（带 EDIT 模式参数）。"
  (declare (ignore arguments))
  (let ((name (slot-value user-instance 'name))
	(phone-mobile (slot-value user-instance 'phone-mobile))
	(email (slot-value user-instance 'email))
	(row-id (slot-value user-instance 'row-id)))
    (cl-who:with-html-output (*standard-output* nil)
      (:td :height "10px" 
	(:h6 :class "user-name"  (cl-who:str name)))
      (:td :height "10px" 
	(:h6 :class "user-phone-mobile"  (cl-who:str phone-mobile)))
      (:td :height "10px" 
       	 (:h6 :class "user-email"  (cl-who:str email) ))
      (:td :height "10px" 
       (:a  :data-toggle "modal" :data-target (format nil "#edituser-modal~A" row-id)  :href "#"  (:i :class "fa-solid fa-pencil"))
	(modal-dialog (format nil "edituser-modal~a" row-id) "Add/Edit Policy" (modal.com-hhub-transaction-sadmin-create-users nil "EDIT" user-instance))))))




(defun modal.com-hhub-transaction-sadmin-create-users (for-tenant-id mode  &optional (user nil))
  "Add/Edit User 模态对话框 fragment。
   mode: 'NEW' 显示 password / confirmpass 字段（且 usertenantid 取入参 for-tenant-id）；
         'EDIT' 隐藏密码字段，并预填用户既有字段（usertenantid 取自 user.tenant-id）。
   role-dropdown 自动从角色表取出选项，预选用户当前角色。
   表单 action='dasadduseraction' POST。"
  (let* ((fullname (if user (slot-value user 'name)))
	 (username (if user (slot-value user 'username)))
	 (email (if user (slot-value user 'email)))
	 (phone (if user (slot-value user 'phone-mobile)))
	 (row-id (if user (slot-value user 'row-id)))
	 (tenant-id (if user (slot-value user 'tenant-id)))
	 (userrole-instance (if user (select-user-role-by-userid row-id tenant-id)))
	 (userrolename (if userrole-instance (slot-value (get-user-roles.role userrole-instance) 'name))))

       (cl-who:with-html-output (*standard-output* nil)
	(:div :class "row" 
	      (:div :class "col-xs-12 col-sm-12 col-md-12 col-lg-12"
		    (:form :class "form-adduser" :role "form" :method "POST" :action "dasadduseraction" :data-toggle "validator"
			   (if user (cl-who:htm (:input :class "form-control" :type "hidden" :value row-id :name "id")))
			   (:img :class "profile-img" :src "/img/logo.png" :alt "")
			   (:h1 :class "text-center login-title"  "Add/Edit User")
			   (:div :class "form-group input-group"
				 (:input :class "form-control" :required T :name "fullname" :aria-describedby "fullnameprefix" :placeholder "Enter Full Name" :maxlength "60" :size "50" :type "text"  :value fullname)) 
			   
			   (:div :class "form-group input-group"
				 (:input :class "form-control" :name "username" :required T :aria-describedby "nameprefix" :placeholder "Enter username" :maxlength "30" :type "text"  :value username)) 
			   (:div :class "form-group"
				 (:label :for "email")
				 (:input :class "form-control" :name "email" :required T :placeholder "Enter User Email " :type "text" :value email ))
			   (:div :class "form-group"
				 (:label :for "userrole")
				 (role-dropdown "userrole" userrolename))
			   (:div :class "form-group input-group"
				 (:input :class "form-control" :name "phone" :maxlength "30"  :required T :value phone :placeholder "Phone"  :type "text"))
			   (if (equal mode "NEW") 
			       (cl-who:htm 
				(:div :class "form-group input-group"
				      (:input :class "form-control" :name "usertenantid" :type "hidden" :value for-tenant-id))
				
				(:div :class "form-group input-group"
				      (:input :class "form-control" :name "password" :id "password" :maxlength "30" :required T  :placeholder "Password"  :type "password"))
				(:div :class "form-group input-group"
				      (:input :class "form-control" :name "confirmpass" :maxlength "30" :required T :data-match "#password" :data-match-error "Passwords dont match !"  :placeholder "Confirm Password"  :type "password"))))
					;else
			   (if (equal mode "EDIT") (cl-who:htm (:div :class "form-group input-group"
							      (:input :class "form-control" :name "usertenantid" :type "hidden" :value tenant-id))))
			   
			   (:div :class "form-group input-group"
				 (:input :class "form-control" :name "userid" :type "hidden" :value row-id))
			   
			   (:div :class "form-group"
				 (:button :class "btn btn-lg btn-primary btn-block" :type "submit" "Submit"))))))))


(defun dod-controller-add-user-action ()
  "URL：/hhub/dasadduseraction（推测）。
   处理 Add/Edit 用户表单提交：
     - 若 user 已存在（按 userid+usertenantid 找到）则 UPDATE 并重绑角色；
     - 否则用 create-dod-user 新建用户，再用 create-user-role 绑定角色。
   所有非空校验通过才提交。完成后 302 跳转 /hhub/sadminhome。
   备注：unless 内的检查用了 (and ... (or null zerop)) 组合，行为是 *任一*
   字段非空时才执行写入（推测：原意可能为 unless 任一字段为空才阻止）。"
  (with-opr-session-check
      (let*  ((userid (hunchentoot:parameter "userid"))
	      (usertenantid (parse-integer (hunchentoot:parameter "usertenantid")))
	      (fullname (hunchentoot:parameter "fullname"))
	      (username (hunchentoot:parameter "username"))
	      (phone (hunchentoot:parameter "phone"))
	      (email (hunchentoot:parameter "email"))
	      (userrole-name (hunchentoot:parameter "userrole"))
	      (password (hunchentoot:parameter "password"))
	      (confirmpass (hunchentoot:parameter "confirmpass"))
	      (salt (createciphersalt))
	      (encryptedpass (if (and password confirmpass) (check&encrypt password confirmpass salt)))
      	      (user (select-user-by-id userid usertenantid))
	      (userrole-instance (select-user-role-by-userid userid usertenantid))
	      (roletobeupdated (select-role-by-name userrole-name))
	      (role-row-id (if roletobeupdated (slot-value roletobeupdated 'row-id))))

	(unless (and  
		 (or (null fullname) (zerop (length fullname)))
		 (or (null username) (zerop (length username)))
		 (or (null phone) (zerop (length phone)))
		 (or (null email) (zerop (length email))))		
	  (if user (progn 
		     (setf (slot-value user 'name) fullname)
		     (setf (slot-value user 'username) username)
		     (setf (slot-value user 'phone-mobile) phone)
		     (setf (slot-value user 'email) email)
		     (setf (slot-value userrole-instance 'role-id) role-row-id) 
		     (update-user user)
		     (update-user-role userrole-instance))
					;else
	      (progn 
		(create-dod-user fullname username encryptedpass salt  email phone  usertenantid)
		(let ((user-id  (slot-value (select-user-by-phonenumber phone usertenantid) 'row-id))
		      (role-id (slot-value roletobeupdated 'row-id))) 
		(create-user-role user-id role-id usertenantid)))))
	(hunchentoot:redirect  "/hhub/sadminhome"))))



(defun create-user-with-role (fullname username email phone password userrole-name usertenantid)
  "编程式接口：创建一个用户并绑定指定角色。
   生成 56 字节随机盐 + check&encrypt 加密密码，调用 create-dod-user 与 create-user-role。
   仅当所有非空校验都通过时才执行（行为同 dod-controller-add-user-action）。"
  (let*  ((confirmpass password)
	  (salt-octet (secure-random:bytes 56 secure-random:*generator*))
	  (salt (flexi-streams:octets-to-string  salt-octet))
	  (encryptedpass (check&encrypt password confirmpass salt))
	  (roletobeupdated (select-role-by-name userrole-name)))
    (unless (and  
	     (or (null fullname) (zerop (length fullname)))
	     (or (null username) (zerop (length username)))
	     (or (null phone) (zerop (length phone)))
	     (or (null email) (zerop (length email))))		
      
      (progn 
	(create-dod-user fullname username encryptedpass salt  email phone  usertenantid)
	(let ((user-id  (slot-value (select-user-by-phonenumber phone usertenantid) 'row-id))
	      (role-id (slot-value roletobeupdated 'row-id))) 
	  (create-user-role user-id role-id usertenantid))))))



(defun get-login-userid ()
  "读 :login-user-id session 值（当前登录用户的 row-id）。"
     (hunchentoot:session-value :login-user-id))

(defun hhub-session-validp ()
  "判定 hunchentoot:*session* 是否存在。返回 T/NIL。"
  (if hunchentoot:*session* T NIL))

(defun get-login-username ()
  "读 :login-username session 值（登录账号字符串）。"
  (hunchentoot:session-value :login-username))

(defun get-login-user-name ()
  "读 :login-user-name session 值（用户姓名）。"
  (hunchentoot:session-value :login-user-name))


(defun verify-superadmin ();;"Verifies whether username is superadmin"
  "判定当前登录是否为超级管理员（username = 'superadmin'）。"
  (if (equal (get-login-username) "superadmin") T NIL ))

(defun superadmin-login ()
  "若当前是超管，向 session 写入 :login-company 'super' 标志。"
  (if (verify-superadmin )
      (setf ( hunchentoot:session-value :login-company) "super")))

