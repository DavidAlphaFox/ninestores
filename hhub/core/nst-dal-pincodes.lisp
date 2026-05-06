;; -*- mode: common-lisp; coding: utf-8 -*-
;;;; ============================================================================
;;;; 模块：core 平台基础 —— 印度 Pincode 实体
;;;; 分层：DAL（数据访问层）
;;;; 文件：hhub/core/nst-dal-pincodes.lisp
;;;; ----------------------------------------------------------------------------
;;;; 职责：定义 dod-india-pincodes CLSQL view-class，对应 DOD_INDIA_PINCODES 表，
;;;;       承载印度全国邮政编码的元数据（officename、district、state、circle、经纬度）。
;;;;
;;;; 主要导出：
;;;;   dod-india-pincodes    — view-class
;;;;
;;;; 关联：
;;;;   上游使用方：core/nst-bl-pincodes.lisp（构建 *NST-ALL-INDIA-PINCODES* 缓存）
;;;;   下游依赖：installation 的种子 SQL 数据
;;;; ============================================================================
(in-package :nstores)

;; ----------------------------------------------------------------------------
;; 实体：dod-india-pincodes
;; 表：DOD_INDIA_PINCODES
;; 含义：印度邮政编码主数据；地址校验、shipping-zone 路由、地区定位的基础。
;; 关键字段：
;;   row-id          主键
;;   pincode         6 位邮政编码
;;   office-name     邮局名
;;   office-type     邮局类型（如 BO/SO/HO）
;;   delivery        是否提供投递服务
;;   district        区
;;   state-name      省/邦
;;   division-name   邮区
;;   region-name     大区
;;   circle-name     邮政圈
;;   latitude/longitude  地理坐标（来自 decimal(8,6)/(9,6)）
;; 备注：本表仅启动时全量装入内存，运行期不再触发查询。
;; ----------------------------------------------------------------------------
(clsql:def-view-class dod-india-pincodes ()
  ((row-id
    :db-kind :key
    :db-constraints :not-null
    :column "row_id"
    :type integer
    :initarg :row-id)
   
   (pincode
    :column "pincode"
    :type integer
    :initarg :pincode)
   
   (office-name
    :column "officename"
    :type (string 100)
    :initarg :office-name)
   
   (office-type
    :column "officetype"
    :type (string 10)
    :initarg :office-type)
   
   (delivery
    :column "delivery"
    :type (string 50)
    :initarg :delivery)
   
   (district
    :column "district"
    :type (string 100)
    :initarg :district)
   
   (state-name
    :column "statename"
    :type (string 100)
    :initarg :state-name)
   
   (division-name
    :column "divisionname"
    :type (string 100)
    :initarg :division-name)
   
   (region-name
    :column "regionname"
    :type (string 100)
    :initarg :region-name)
   
   (circle-name
    :column "circlename"
    :type (string 100)
    :initarg :circle-name)
   
   (latitude
    :column "latitude"
    :type double-float ; Maps from decimal(8,6)
    :initarg :latitude)
   
   (longitude
    :column "longitude"
    :type double-float ; Maps from decimal(9,6)
    :initarg :longitude))
  (:base-table "DOD_INDIA_PINCODES"))
