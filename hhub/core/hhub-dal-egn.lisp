;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— DAL 引擎类模板（DDD/六边形架构骨架）
;;;; 分层：DAL（数据访问层）+ 模板代码生成器源
;;;; 文件：hhub/core/hhub-dal-egn.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义新版"DDD / Hexagonal"风格领域类的脚手架。所有类名都用
;;;;       %entity-name% 占位符，槽位用 %0%..%37%。代码生成器（脚手架脚本）
;;;;       会把这些占位符替换成实际实体名（如 Customer / Order / Warehouse），
;;;;       由此一次生成 Adapter / DBService / Presenter / Service / HTMLView
;;;;       以及 RequestModel / ResponseModel / ViewModel / BusinessObject /
;;;;       def-view-class 等一整套类。
;;;;
;;;; 主要导出（占位符版本，仅供模板替换）：
;;;;   %entity-name%Adapter / %entity-name%DBService / %entity-name%Presenter
;;;;   %entity-name%Service / %entity-name%HTMLView
;;;;   %entity-name%-NotFound-View / -Unavailable-View / -Conflict-View
;;;;       — 对应 Belnap :F / :U / :C 真值的容错视图
;;;;   %entity-name%ViewModel / %entity-name%ResponseModel
;;;;   %entity-name%RequestModel / %entity-name%SearchRequestModel
;;;;   %entity-name%（BusinessObject）
;;;;   dod-%entity-name%（CLSQL view-class）
;;;;
;;;; 关联：
;;;;   下游使用方：脚手架生成的 nst-{dal,bl,ui}-<Entity>.lisp 文件
;;;;   备注：本文件原样编译时无害（占位符是合法 CL 符号），但在生产代码里
;;;;         不应被业务直接调用。
;;;; ============================================================================

(in-package :nstores)


(defclass %entity-name%Adapter (AdapterService)
  ())

(defclass %entity-name%DBService (DBAdapterService)
  ())

(defclass %entity-name%Presenter (PresenterService)
  ())

(defclass %entity-name%Service (BusinessService)
  ())
(defclass %entity-name%HTMLView (HTMLView)
  ())

;; ============================================================================
;; NEW: TCUF-AWARE VIEW CLASSES
;; ============================================================================

(defclass %entity-name%-NotFound-View (HTMLView)
  ()
  (:documentation "Renders when bo-knowledge truth = :F (not found)"))

(defclass %entity-name%-Unavailable-View (HTMLView)
  ()
  (:documentation "Renders when bo-knowledge truth = :U (service unavailable)"))

(defclass %entity-name%-Conflict-View (HTMLView)
  ()
  (:documentation "Renders when bo-knowledge truth = :C (data conflict)"))


(defclass %entity-name%ViewModel (ViewModel)
  ((%0%
    :initarg :%0%
    :accessor %0%)
   (%1%
    :initarg :%1%
    :accessor %1%)
   (%2%
    :initarg :%2%
    :accessor %2%)
   (%3%
    :initarg :%3%
    :accessor %3%)
   (%4%
    :initarg :%4%
    :accessor %4%)
   (%5%
    :initarg :%5%
    :accessor %5%)
   (%6%
    :initarg :%6%
    :accessor %6%)
   (%7%
    :initarg :%7%
    :accessor %7%)
   (%8%
    :initarg :%8%
    :accessor %8%)
   (%9%
    :initarg :%9%
    :accessor %9%)
   (%10%
    :initarg :%10%
    :accessor %10%)
   (%11%
    :initarg :%11%
    :accessor %11%)
   (%12%
    :initarg :%12%
    :accessor %12%)
   (%13%
    :initarg :%13%
    :accessor %13%)
   (%14%
    :initarg :%14%
    :accessor %14%)
   (%15%
    :initarg :%15%
    :accessor %15%)
   (%16%
    :initarg :%16%
    :accessor %16%)
   (%17%
    :initarg :%17%
    :accessor %17%)
   (%18%
    :initarg :%18%
    :accessor %18%)
   (%19%
    :initarg :%19%
    :accessor %19%)
   (%20%
    :initarg :%20%
    :accessor %20%)
   (%21%
    :initarg :%21%
    :accessor %21%)
   (%22%
    :initarg :%22%
    :accessor %22%)
   (%23%
    :initarg :%23%
    :accessor %23%)
   (%24%
    :initarg :%24%
    :accessor %24%)
   (%25%
    :initarg :%25%
    :accessor %25%)
   (%26%
    :initarg :%26%
    :accessor %26%)
   (%27%
    :initarg :%27%
    :accessor %27%)
   (%28%
    :initarg :%28%
    :accessor %28%)
   (%29%
    :initarg :%29%
    :accessor %29%)
   (%30%
    :initarg :%30%
    :accessor %30%)
   (%31%
    :initarg :%31%
    :accessor %31%)
   (%32%
    :initarg :%32%
    :accessor %32%)
   (%33%
    :initarg :%33%
    :accessor %33%)
   (%34%
    :initarg :%34%
    :accessor %34%)
   (%35%
    :initarg :%35%
    :accessor %35%)
   (%36%
    :initarg :%36%
    :accessor %36%)
   (%37%
    :initarg :%37%
    :accessor %37%)
   (bo-knowledge
    :initarg :bo-knowledge
    :accessor bo-knowledge
    :initform nil)
   (company
    :initarg :company
    :accessor company)))

(defclass %entity-name%ResponseModel (ResponseModel)
  ((%0%
    :initarg :%0%
    :accessor %0%)
   (%1%
    :initarg :%1%
    :accessor %1%)
   (%2%
    :initarg :%2%
    :accessor %2%)
   (%3%
    :initarg :%3%
    :accessor %3%)
   (%4%
    :initarg :%4%
    :accessor %4%)
   (%5%
    :initarg :%5%
    :accessor %5%)
   (%6%
    :initarg :%6%
    :accessor %6%)
   (%7%
    :initarg :%7%
    :accessor %7%)
   (%8%
    :initarg :%8%
    :accessor %8%)
   (%9%
    :initarg :%9%
    :accessor %9%)
   (%10%
    :initarg :%10%
    :accessor %10%)
   (%11%
    :initarg :%11%
    :accessor %11%)
   (%12%
    :initarg :%12%
    :accessor %12%)
   (%13%
    :initarg :%13%
    :accessor %13%)
   (%14%
    :initarg :%14%
    :accessor %14%)
   (%15%
    :initarg :%15%
    :accessor %15%)
   (%16%
    :initarg :%16%
    :accessor %16%)
   (%17%
    :initarg :%17%
    :accessor %17%)
   (%18%
    :initarg :%18%
    :accessor %18%)
   (%19%
    :initarg :%19%
    :accessor %19%)
   (%20%
    :initarg :%20%
    :accessor %20%)
   (%21%
    :initarg :%21%
    :accessor %21%)
   (%22%
    :initarg :%22%
    :accessor %22%)
   (%23%
    :initarg :%23%
    :accessor %23%)
   (%24%
    :initarg :%24%
    :accessor %24%)
   (%25%
    :initarg :%25%
    :accessor %25%)
   (%26%
    :initarg :%26%
    :accessor %26%)
   (%27%
    :initarg :%27%
    :accessor %27%)
   (%28%
    :initarg :%28%
    :accessor %28%)
   (%29%
    :initarg :%29%
    :accessor %29%)
   (%30%
    :initarg :%30%
    :accessor %30%)
   (%31%
    :initarg :%31%
    :accessor %31%)
   (%32%
    :initarg :%32%
    :accessor %32%)
   (%33%
    :initarg :%33%
    :accessor %33%)
   (%34%
    :initarg :%34%
    :accessor %34%)
   (%35%
    :initarg :%35%
    :accessor %35%)
   (%36%
    :initarg :%36%
    :accessor %36%)
   (%37%
    :initarg :%37%
    :accessor %37%)
  (bo-knowledge :initarg :bo-knowledge :accessor bo-knowledge :initform nil)
   (company
    :initarg :company
    :accessor company)))
   

(defclass %entity-name%RequestModel (RequestModel)
  ((%0%
    :initarg :%0%
    :accessor %0%)
   (%1%
    :initarg :%1%
    :accessor %1%)
   (%2%
    :initarg :%2%
    :accessor %2%)
   (%3%
    :initarg :%3%
    :accessor %3%)
   (%4%
    :initarg :%4%
    :accessor %4%)
   (%5%
    :initarg :%5%
    :accessor %5%)
   (%6%
    :initarg :%6%
    :accessor %6%)
   (%7%
    :initarg :%7%
    :accessor %7%)
   (%8%
    :initarg :%8%
    :accessor %8%)
   (%9%
    :initarg :%9%
    :accessor %9%)
   (%10%
    :initarg :%10%
    :accessor %10%)
   (%11%
    :initarg :%11%
    :accessor %11%)
   (%12%
    :initarg :%12%
    :accessor %12%)
   (%13%
    :initarg :%13%
    :accessor %13%)
   (%14%
    :initarg :%14%
    :accessor %14%)
   (%15%
    :initarg :%15%
    :accessor %15%)
   (%16%
    :initarg :%16%
    :accessor %16%)
   (%17%
    :initarg :%17%
    :accessor %17%)
   (%18%
    :initarg :%18%
    :accessor %18%)
   (%19%
    :initarg :%19%
    :accessor %19%)
   (%20%
    :initarg :%20%
    :accessor %20%)
   (%21%
    :initarg :%21%
    :accessor %21%)
   (%22%
    :initarg :%22%
    :accessor %22%)
   (%23%
    :initarg :%23%
    :accessor %23%)
   (%24%
    :initarg :%24%
    :accessor %24%)
   (%25%
    :initarg :%25%
    :accessor %25%)
   (%26%
    :initarg :%26%
    :accessor %26%)
   (%27%
    :initarg :%27%
    :accessor %27%)
   (%28%
    :initarg :%28%
    :accessor %28%)
   (%29%
    :initarg :%29%
    :accessor %29%)
   (%30%
    :initarg :%30%
    :accessor %30%)
   (%31%
    :initarg :%31%
    :accessor %31%)
   (%32%
    :initarg :%32%
    :accessor %32%)
   (%33%
    :initarg :%33%
    :accessor %33%)
   (%34%
    :initarg :%34%
    :accessor %34%)
   (%35%
    :initarg :%35%
    :accessor %35%)
   (%36%
    :initarg :%36%
    :accessor %36%)
   (%37%
    :initarg :%37%
    :accessor %37%)
   (bo-knowledge :initarg :bo-knowledge :accessor bo-knowledge :initform nil)
   (company
    :initarg :company
    :accessor company)))


(defclass %entity-name%SearchRequestModel (%entity-name%RequestModel)
  ())

(defclass %entity-name% (BusinessObject)
  ((row-id)
   (%0%
    :initarg :%0%
    :accessor %0%)
   (%1%
    :initarg :%1%
    :accessor %1%)
   (%2%
    :initarg :%2%
    :accessor %2%)
   (%3%
    :initarg :%3%
    :accessor %3%)
   (%4%
    :initarg :%4%
    :accessor %4%)
   (%5%
    :initarg :%5%
    :accessor %5%)
   (%6%
    :initarg :%6%
    :accessor %6%)
   (%7%
    :initarg :%7%
    :accessor %7%)
   (%8%
    :initarg :%8%
    :accessor %8%)
   (%9%
    :initarg :%9%
    :accessor %9%)
   (%10%
    :initarg :%10%
    :accessor %10%)
   (%11%
    :initarg :%11%
    :accessor %11%)
   (%12%
    :initarg :%12%
    :accessor %12%)
   (%13%
    :initarg :%13%
    :accessor %13%)
   (%14%
    :initarg :%14%
    :accessor %14%)
   (%15%
    :initarg :%15%
    :accessor %15%)
   (%16%
    :initarg :%16%
    :accessor %16%)
   (%17%
    :initarg :%17%
    :accessor %17%)
   (%18%
    :initarg :%18%
    :accessor %18%)
   (%19%
    :initarg :%19%
    :accessor %19%)
   (%20%
    :initarg :%20%
    :accessor %20%)
   (%21%
    :initarg :%21%
    :accessor %21%)
   (%22%
    :initarg :%22%
    :accessor %22%)
   (%23%
    :initarg :%23%
    :accessor %23%)
   (%24%
    :initarg :%24%
    :accessor %24%)
   (%25%
    :initarg :%25%
    :accessor %25%)
   (%26%
    :initarg :%26%
    :accessor %26%)
   (%27%
    :initarg :%27%
    :accessor %27%)
   (%28%
    :initarg :%28%
    :accessor %28%)
   (%29%
    :initarg :%29%
    :accessor %29%)
   (%30%
    :initarg :%30%
    :accessor %30%)
   (%31%
    :initarg :%31%
    :accessor %31%)
   (%32%
    :initarg :%32%
    :accessor %32%)
   (%33%
    :initarg :%33%
    :accessor %33%)
   (%34%
    :initarg :%34%
    :accessor %34%)
   (%35%
    :initarg :%35%
    :accessor %35%)
   (%36%
    :initarg :%36%
    :accessor %36%)
   (%37%
    :initarg :%37%
    :accessor %37%)

   (company
    :initarg :company
    :accessor company)))


(clsql:def-view-class dod-%entity-name% ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :type integer
    :initarg row-id)
   (%0%
    :initarg :%0%
    :type (string 20)
    :accessor %0%)
   (%1%
    :type (string 20)
    :initarg :%1%
    :accessor %1%)
   (%2%
    :type (string 20)
    :initarg :%2%
    :accessor %2%)
   (%3%
    :type (string 20)
    :initarg :%3%
    :accessor %3%)
   (%4%
    :type (string 20)
    :initarg :%4%
    :accessor %4%)
   (%5%
    :type (string 20)
    :initarg :%5%
    :accessor %5%)
   (%6%
    :type (string 20)
    :initarg :%6%
    :accessor %6%)
   (%7%
    :type (string 20)
    :initarg :%7%
    :accessor %7%)
   (%8%
    :type (string 20)
    :initarg :%8%
    :accessor %8%)
   (%9%
    :type (string 20)
    :initarg :%9%
    :accessor %9%)
   (%10%
    :type (string 20)
    :initarg :%10%
    :accessor %10%)
   (%11%
    :type (string 20)
    :initarg :%11%
    :accessor %11%)
   (%12%
    :type (string 20)
    :initarg :%12%
    :accessor %12%)
   (%13%
    :type (string 20)
    :initarg :%13%
    :accessor %13%)
   (%14%
    :type (string 20)
    :initarg :%14%
    :accessor %14%)
   (%15%
    :type (string 20)
    :initarg :%15%
    :accessor %15%)
   (%16%
    :type (string 20)
    :initarg :%16%
    :accessor %16%)
   (%17%
    :type (string 20)
    :initarg :%17%
    :accessor %17%)
   (%18%
    :type (string 20)
    :initarg :%18%
    :accessor %18%)
   (%19%
    :type (string 20)
    :initarg :%19%
    :accessor %19%)
   (%20%
    :type (string 20)
    :initarg :%20%
    :accessor %20%)
   (%21%
    :type (string 20)
    :initarg :%21%
    :accessor %21%)
   (%22%
    :type (string 20)
    :initarg :%22%
    :accessor %22%)
   (%23%
    :type (string 20)
    :initarg :%23%
    :accessor %23%)
   (%24%
    :type (string 20)
    :initarg :%24%
    :accessor %24%)
   (%25%
    :type (string 20)
    :initarg :%25%
    :accessor %25%)
   (%26%
    :type (string 20)
    :initarg :%26%
    :accessor %26%)
   (%27%
    :type (string 20)
    :initarg :%27%
    :accessor %27%)
   (%28%
    :type (string 20)
    :initarg :%28%
    :accessor %28%)
   (%29%
    :type (string 20)
    :initarg :%29%
    :accessor %29%)
   (%30%
    :type (string 20)
    :initarg :%30%
    :accessor %30%)
   (%31%
    :type (string 20)
    :initarg :%31%
    :accessor %31%)
   (%32%
    :type (string 20)
    :initarg :%32%
    :accessor %32%)
   (%33%
    :type (string 20)
    :initarg :%33%
    :accessor %33%)
   (%34%
    :type (string 20)
    :initarg :%34%
    :accessor %34%)
   (%35%
    :type (string 20)
    :initarg :%35%
    :accessor %35%)
   (%36%
    :type (string 20)
    :initarg :%36%
    :accessor %36%)
   (%37%
    :type (string 20)
    :initarg :%37%
    :accessor %37%)

   (deleted-state
    :type (string 1)
    :void-value "N"
    :initarg :deleted-state) 
  (tenant-id
    :type integer
    :initarg :tenant-id)
   (COMPANY
    :ACCESSOR get-company
    :DB-KIND :JOIN
    :DB-INFO (:JOIN-CLASS dod-company
	                  :HOME-KEY tenant-id
                          :FOREIGN-KEY row-id
                          :SET NIL)))
  (:BASE-TABLE dod_%entity-name%))
