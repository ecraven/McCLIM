;;; -*- Mode: LISP; Syntax: COMMON-LISP; Package: CL-USER; Base: 10 -*-
(in-package :cl-user)

(defpackage #:clim-listener
  (:use #:clim #:clim-lisp #:clim-extensions)
  (:export #:run-listener #:dev-commands))

(in-package #:clim-listener)

(eval-when (:load-toplevel)
  (defparameter *icon-path* 
    (merge-pathnames
     #P"icons/"
     (load-time-value (or #.*compile-file-pathname* *load-pathname*)))))
