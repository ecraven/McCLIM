(in-package :clim-clx-fb)

(defclass clx-fb-port (standard-handled-event-port-mixin
		       render-port-mixin
		       clim-xcommon:keysym-port-mixin
		       clim-clx::clx-basic-port)
  ())

(defun parse-clx-fb-server-path (path)
  (let ((server-path (clim-clx::parse-clx-server-path path)))
    (pop path)
    (cons :clx-fb (cdr server-path))))

(setf (get :clx-fb :port-type) 'clx-fb-port)
(setf (get :clx-fb :server-path-parser) 'parse-clx-fb-server-path)

(defmethod initialize-instance :after ((port clx-fb-port) &rest args)
  (declare (ignore args))
  (push (make-instance 'clx-fb-frame-manager :port port)
	(slot-value port 'frame-managers))
  (setf (slot-value port 'pointer)
	(make-instance 'clim-clx::clx-basic-pointer :port port))
  (initialize-clx port)
  (clim-extensions:port-all-font-families port))
  

(defparameter *event-mask* '(:exposure 
			     :key-press :key-release
			     :button-press :button-release
			     :owner-grab-button
			     :enter-window :leave-window
			     :structure-notify
			     :pointer-motion :button-motion))

(defmethod clim-clx::realize-mirror ((port clx-fb-port) (sheet mirrored-sheet-mixin))
   (clim-clx::%realize-mirror port sheet)
   (port-register-mirror (port sheet) sheet (make-instance 'clx-fb-mirror :xmirror (port-lookup-mirror port sheet)))
   (port-lookup-mirror port sheet))

(defmethod clim-clx::realize-mirror ((port clx-fb-port) (pixmap pixmap))
  )

(defmethod clim-clx::%realize-mirror ((port clx-fb-port) (sheet basic-sheet))
  (clim-clx::realize-mirror-aux port sheet
		      :event-mask *event-mask*
                      :border-width 0
                      :map (sheet-enabled-p sheet)))

(defmethod clim-clx::%realize-mirror ((port clx-fb-port) (sheet top-level-sheet-pane))
  (let ((q (compose-space sheet)))
    (let ((frame (pane-frame sheet))
          (window (clim-clx::realize-mirror-aux port sheet
				      :event-mask *event-mask*
                                      :map nil
                                      :width (clim-clx::round-coordinate (space-requirement-width q))
                                      :height (clim-clx::round-coordinate (space-requirement-height q)))))           
      (setf (xlib:wm-hints window) (xlib:make-wm-hints :input :on))
      (setf (xlib:wm-name window) (frame-pretty-name frame))
      (setf (xlib:wm-icon-name window) (frame-pretty-name frame))
      (xlib:set-wm-class
       window
       (string-downcase (frame-name frame))
       (string-capitalize (string-downcase (frame-name frame))))
      (setf (xlib:wm-protocols window) `(:wm_delete_window))
      (xlib:change-property window
                            :WM_CLIENT_LEADER (list (xlib:window-id window))
                            :WINDOW 32))))

(defmethod clim-clx::%realize-mirror ((port clx-fb-port) (sheet unmanaged-top-level-sheet-pane))
  (clim-clx::realize-mirror-aux port sheet
		      :event-mask *event-mask*
		      :override-redirect :on
		      :map nil))



(defmethod make-medium ((port clx-fb-port) sheet)
  (make-instance 'clx-fb-medium 
		 ;; :port port 
		 ;; :graft (find-graft :port port) 
		 :sheet sheet))


(defmethod make-graft ((port clx-fb-port) &key (orientation :default) (units :device))
  (let ((graft (make-instance 'clx-graft
		 :port port :mirror (clx-port-window port)
		 :orientation orientation :units units)))
    (setf (sheet-region graft) (make-bounding-rectangle 0 0 (xlib:screen-width (clx-port-screen port)) (xlib:screen-height (clx-port-screen port))))
    (push graft (port-grafts port))
    graft))

(defmethod graft ((port clx-fb-port))
  (first (port-grafts port)))

;; this is evil.
(defmethod allocate-space :after ((pane top-level-sheet-pane) width height)
  (when (sheet-direct-mirror pane)
    (with-slots (space-requirement) pane
      '(setf (xlib:wm-normal-hints (sheet-direct-mirror pane))
            (xlib:make-wm-size-hints 
             :width (round width)
             :height (round height)
             :max-width (min 65535 (round (space-requirement-max-width space-requirement)))
             :max-height (min 65535 (round (space-requirement-max-height space-requirement)))
             :min-width (round (space-requirement-min-width space-requirement))
             :min-height (round (space-requirement-min-height space-requirement)))))))

(defmethod port-force-output ((port clx-fb-port))
  (xlib:display-force-output (clx-port-display port)))

(defmethod get-next-event ((port clx-fb-port) &key wait-function (timeout nil))
  (declare (ignore wait-function))
  (let* ((clim-clx::*clx-port* port)
         (display (clx-port-display port)))
    (unless (xlib:event-listen display)
      (xlib:display-force-output (clx-port-display port)))
    (let ((event (xlib:process-event (clx-port-display port)
				     :timeout 0.1
				     :handler #'clim-clx::event-handler :discard-p t)))
       (maphash #'(lambda (key val)
		    (when (typep key 'clx-fb-mirrored-sheet-mixin)
		      (image-mirror-to-x (sheet-mirror key))))
		(slot-value port 'climi::sheet->mirror))
      (if event
	  event
	  :timeout))))

;;; Pixmap

(defmethod destroy-mirror ((port clx-fb-port) (pixmap mcclim-render::image-pixmap-mixin))
  (call-next-method))

(defmethod realize-mirror ((port clx-fb-port) (pixmap mcclim-render::image-pixmap-mixin))
  (setf (sheet-parent pixmap) (graft port))
  (let ((mirror (make-instance 'mcclim-render::rgb-image-mirror-mixin)))
    (port-register-mirror port pixmap mirror)
    (mcclim-render::%make-image mirror pixmap)))

(defmethod port-allocate-pixmap ((port clx-fb-port) sheet width height)
  (let ((pixmap (make-instance 'clx-fb-pixmap
			       :sheet sheet
			       :width width
			       :height height
			       :port port)))
    (when (sheet-grafted-p sheet)
      (realize-mirror port pixmap))
    pixmap))

(defmethod port-deallocate-pixmap ((port clx-fb-port) pixmap)
  (when (port-lookup-mirror port pixmap)
    (destroy-mirror port pixmap)))

