;;; MIME support functions
;;; Copyright (C) 1997 Kyle E. Jones
;;;
;;; This program is free software; you can redistribute it and/or modify
;;; it under the terms of the GNU General Public License as published by
;;; the Free Software Foundation; either version 1, or (at your option)
;;; any later version.
;;;
;;; This program is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU General Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License
;;; along with this program; if not, write to the Free Software
;;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

(provide 'vm-mime)

(defun vm-mime-error (&rest args)
  (signal 'vm-mime-error (list (apply 'format args)))
  (error "can't return from vm-mime-error"))

(if (fboundp 'define-error)
    (define-error 'vm-mime-error "MIME error")
  (put 'vm-mime-error 'error-conditions '(vm-mime-error error))
  (put 'vm-mime-error 'error-message "MIME error"))

(defun vm-mm-layout-type (e) (aref e 0))
(defun vm-mm-layout-qtype (e) (aref e 1))
(defun vm-mm-layout-encoding (e) (aref e 2))
(defun vm-mm-layout-id (e) (aref e 3))
(defun vm-mm-layout-description (e) (aref e 4))
(defun vm-mm-layout-disposition (e) (aref e 5))
(defun vm-mm-layout-qdisposition (e) (aref e 6))
(defun vm-mm-layout-header-start (e) (aref e 7))
(defun vm-mm-layout-body-start (e) (aref e 8))
(defun vm-mm-layout-body-end (e) (aref e 9))
(defun vm-mm-layout-parts (e) (aref e 10))
(defun vm-mm-layout-cache (e) (aref e 11))
;; if display of MIME part fails, error string will be here.
(defun vm-mm-layout-display-error (e) (aref e 12))

(defun vm-set-mm-layout-type (e type) (aset e 0 type))
(defun vm-set-mm-layout-cache (e c) (aset e 11 c))
(defun vm-set-mm-layout-display-error (e c) (aset e 12 c))

(defun vm-mm-layout (m)
  (or (vm-mime-layout-of m)
      (progn (vm-set-mime-layout-of
	      m
	      (condition-case data
		  (vm-mime-parse-entity m)
		(vm-mime-error (message "%s" (car (cdr data))))))
	     (vm-mime-layout-of m))))

(defun vm-mm-encoded-header (m)
  (or (vm-mime-encoded-header-flag-of m)
      (progn (setq m (vm-real-message-of m))
	     (vm-set-mime-encoded-header-flag-of
	      m
	      (save-excursion
		(set-buffer (vm-buffer-of m))
		(save-excursion
		  (save-restriction
		    (widen)
		    (goto-char (vm-headers-of m))
		    (or (re-search-forward vm-mime-encoded-word-regexp
					   (vm-text-of m) t)
			'none)))))
	     (vm-mime-encoded-header-flag-of m))))

(defun vm-mime-Q-decode-region (start end)
  (let ((buffer-read-only nil))
    (subst-char-in-region start end ?_ (string-to-char " ") t)
    (vm-mime-qp-decode-region start end)))

(fset 'vm-mime-B-decode-region 'vm-mime-base64-decode-region)

(defun vm-mime-Q-encode-region (start end)
  (let ((buffer-read-only nil))
    (subst-char-in-region start end (string-to-char " ") ?_ t)
    (vm-mime-qp-encode-region start end t)))

(defun vm-mime-B-encode-region (start end)
  (vm-mime-base64-encode-region start end nil t))

(defun vm-mime-crlf-to-lf-region (start end)
  (let ((buffer-read-only nil))
    (save-excursion
      (save-restriction
	(narrow-to-region start end)
	(goto-char start)
	(while (search-forward "\r\n" nil t)
	  (delete-char -2)
	  (insert "\n"))))))
      
(defun vm-mime-lf-to-crlf-region (start end)
  (let ((buffer-read-only nil))
    (save-excursion
      (save-restriction
	(narrow-to-region start end)
	(goto-char start)
	(while (search-forward "\n" nil t)
	  (delete-char -1)
	  (insert "\r\n"))))))
      
(defun vm-mime-charset-decode-region (charset start end)
  (or (markerp end) (setq end (vm-marker end)))
  (cond (vm-xemacs-mule-p
	 (if (eq (device-type) 'x)
	     (let ((buffer-read-only nil)
		   (cell (cdr (vm-string-assoc
			       charset
			       vm-mime-mule-charset-to-coding-alist)))
		   (oend (marker-position end))
		   (opoint (point)))
	       (if cell
		   (progn
		     (set-marker end (+ start
					(or (decode-coding-region
					     start end (car cell))
					    (- oend start))))
		     (put-text-property start end 'vm-string t)
		     (put-text-property start end 'vm-charset charset)
		     (put-text-property start end 'vm-coding (car cell))))
	       ;; In XEmacs 20.0 beta93 decode-coding-region moves point.
	       (goto-char opoint))))
	((not (vm-multiple-fonts-possible-p)) nil)
	((vm-string-member charset vm-mime-default-face-charsets) nil)
	(t
	 (let ((font (cdr (vm-string-assoc
			   charset
			   vm-mime-charset-font-alist)))
	       (face (make-face (make-symbol "temp-face")))
	       (e (vm-make-extent start end)))
	   (put-text-property start end 'vm-string t)
	   (put-text-property start end 'vm-charset charset)
	   (if font
	       (condition-case data
		   (progn (set-face-font face font)
			  (vm-set-extent-property e 'face face))
		 (error nil)))))))

(defun vm-mime-transfer-decode-region (layout start end)
  (let ((case-fold-search t) (crlf nil))
    (cond ((string-match "^base64$" (vm-mm-layout-encoding layout))
	   (cond ((vm-mime-types-match "text"
				       (car (vm-mm-layout-type layout)))
		  (setq crlf t))
		 ((vm-mime-types-match "message"
				       (car (vm-mm-layout-type layout)))
		  (setq crlf t)))
	   (vm-mime-base64-decode-region start end crlf))
	  ((string-match "^quoted-printable$"
			 (vm-mm-layout-encoding layout))
	   (vm-mime-qp-decode-region start end)))))

(defun vm-mime-base64-decode-region (start end &optional crlf)
  (message "Decoding base64...")
  (let ((work-buffer nil)
	(done nil)
	(counter 0)
	(bits 0)
	(lim 0) inputpos
	(non-data-chars (concat "^=" vm-mime-base64-alphabet)))
    (unwind-protect
	(save-excursion
	  (setq work-buffer (generate-new-buffer " *vm-work*"))
	  (buffer-disable-undo work-buffer)
	  (if vm-mime-base64-decoder-program
	      (let* ((binary-process-output t) ; any text already has CRLFs
		     (status (apply 'vm-run-command-on-region
				   start end work-buffer
				   vm-mime-base64-decoder-program
				   vm-mime-base64-decoder-switches)))
		(if (not (eq status t))
		    (vm-mime-error "%s" (cdr status))))
	    (goto-char start)
	    (skip-chars-forward non-data-chars end)
	    (while (not done)
	      (setq inputpos (point))
	      (cond
	       ((> (skip-chars-forward vm-mime-base64-alphabet end) 0)
		(setq lim (point))
		(while (< inputpos lim)
		  (setq bits (+ bits 
				(aref vm-mime-base64-alphabet-decoding-vector
				      (char-after inputpos))))
		  (vm-increment counter)
		  (vm-increment inputpos)
		  (cond ((= counter 4)
			 (vm-insert-char (lsh bits -16) 1 nil work-buffer)
			 (vm-insert-char (logand (lsh bits -8) 255) 1 nil
					 work-buffer)
			 (vm-insert-char (logand bits 255) 1 nil work-buffer)
			 (setq bits 0 counter 0))
			(t (setq bits (lsh bits 6)))))))
	      (cond
	       ((= (point) end)
		(if (not (zerop counter))
		    (vm-mime-error "at least %d bits missing at end of base64 encoding"
				   (* (- 4 counter) 6)))
		(setq done t))
	       ((= (char-after (point)) 61) ; 61 is ASCII equals
		(setq done t)
		(cond ((= counter 1)
		       (vm-mime-error "at least 2 bits missing at end of base64 encoding"))
		      ((= counter 2)
		       (vm-insert-char (lsh bits -10) 1 nil work-buffer))
		      ((= counter 3)
		       (vm-insert-char (lsh bits -16) 1 nil work-buffer)
		       (vm-insert-char (logand (lsh bits -8) 255)
				       1 nil work-buffer))
		      ((= counter 0) t)))
	       (t (skip-chars-forward non-data-chars end)))))
	  (and crlf
	       (save-excursion
		 (set-buffer work-buffer)
		 (vm-mime-crlf-to-lf-region (point-min) (point-max))))
	  (or (markerp end) (setq end (vm-marker end)))
	  (goto-char start)
	  (insert-buffer-substring work-buffer)
	  (delete-region (point) end))
      (and work-buffer (kill-buffer work-buffer))))
  (message "Decoding base64... done"))

(defun vm-mime-base64-encode-region (start end &optional crlf B-encoding)
  (and (> (- end start) 200)
       (message "Encoding base64..."))
  (let ((work-buffer nil)
	(counter 0)
	(cols 0)
	(bits 0)
	(alphabet vm-mime-base64-alphabet)
	inputpos)
    (unwind-protect
	(save-excursion
	  (setq work-buffer (generate-new-buffer " *vm-work*"))
	  (buffer-disable-undo work-buffer)
	  (if crlf
	      (progn
		(or (markerp end) (setq end (vm-marker end)))
		(vm-mime-lf-to-crlf-region start end)))
	  (if vm-mime-base64-encoder-program
	      (let ((status (apply 'vm-run-command-on-region
				   start end work-buffer
				   vm-mime-base64-encoder-program
				   vm-mime-base64-encoder-switches)))
		(if (not (eq status t))
		    (vm-mime-error "%s" (cdr status)))
		(if B-encoding
		    (progn
		      ;; if we're B encoding, strip out the line breaks
		      (goto-char (point-min))
		      (while (search-forward "\n" nil t)
			(delete-char -1)))))
	    (setq inputpos start)
	    (while (< inputpos end)
	      (setq bits (+ bits (char-after inputpos)))
	      (vm-increment counter)
	      (cond ((= counter 3)
		     (vm-insert-char (aref alphabet (lsh bits -18)) 1 nil
				     work-buffer)
		     (vm-insert-char (aref alphabet (logand (lsh bits -12) 63))
				     1 nil work-buffer)
		     (vm-insert-char (aref alphabet (logand (lsh bits -6) 63))
				     1 nil work-buffer)
		     (vm-insert-char (aref alphabet (logand bits 63)) 1 nil
				     work-buffer)
		     (setq cols (+ cols 4))
		     (cond ((= cols 72)
			    (setq cols 0)
			    (if (not B-encoding)
				(vm-insert-char ?\n 1 nil work-buffer))))
		     (setq bits 0 counter 0))
		    (t (setq bits (lsh bits 8))))
	      (vm-increment inputpos))
	    ;; write out any remaining bits with appropriate padding
	    (if (= counter 0)
		nil
	      (setq bits (lsh bits (- 16 (* 8 counter))))
	      (vm-insert-char (aref alphabet (lsh bits -18)) 1 nil
			      work-buffer)
	      (vm-insert-char (aref alphabet (logand (lsh bits -12) 63))
			      1 nil work-buffer)
	      (if (= counter 1)
		  (vm-insert-char ?= 2 nil work-buffer)
		(vm-insert-char (aref alphabet (logand (lsh bits -6) 63))
				1 nil work-buffer)
		(vm-insert-char ?= 1 nil work-buffer)))
	    (if (> cols 0)
		(vm-insert-char ?\n 1 nil work-buffer)))
	  (or (markerp end) (setq end (vm-marker end)))
	  (goto-char start)
	  (insert-buffer-substring work-buffer)
	  (delete-region (point) end)
	  (and (> (- end start) 200)
	       (message "Encoding base64... done"))
	  (- end start))
      (and work-buffer (kill-buffer work-buffer)))))

(defun vm-mime-qp-decode-region (start end)
  (and (> (- end start) 200)
       (message "Decoding quoted-printable..."))
  (let ((work-buffer nil)
	(buf (current-buffer))
	(case-fold-search nil)
	(hex-digit-alist '((?0 .  0)  (?1 .  1)  (?2 .  2)  (?3 .  3)
			   (?4 .  4)  (?5 .  5)  (?6 .  6)  (?7 .  7)
			   (?8 .  8)  (?9 .  9)  (?A . 10)  (?B . 11)
			   (?C . 12)  (?D . 13)  (?E . 14)  (?F . 15)))
	inputpos stop-point copy-point)
    (unwind-protect
	(save-excursion
	  (setq work-buffer (generate-new-buffer " *vm-work*"))
	  (buffer-disable-undo work-buffer)
	  (goto-char start)
	  (setq inputpos start)
	  (while (< inputpos end)
	    (skip-chars-forward "^=\n" end)
	    (setq stop-point (point))
	    (cond ((looking-at "\n")
		   ;; spaces or tabs before a hard line break must be ignored
		   (skip-chars-backward " \t")
		   (setq copy-point (point))
		   (goto-char stop-point))
		  (t (setq copy-point stop-point)))
	    (save-excursion
	      (set-buffer work-buffer)
	      (insert-buffer-substring buf inputpos copy-point))
	    (cond ((= (point) end) t)
		  ((looking-at "\n")
		   (vm-insert-char ?\n 1 nil work-buffer)
		   (forward-char))
		  (t ;; looking at =
		   (forward-char)
		   (cond ((looking-at "[0-9A-F][0-9A-F]")
			  (vm-insert-char (+ (* (cdr (assq (char-after (point))
							   hex-digit-alist))
						16)
					     (cdr (assq (char-after
							 (1+ (point)))
							hex-digit-alist)))
					  1 nil work-buffer)
			  (forward-char 2))
			 ((looking-at "\n") ; soft line break
			  (forward-char))
			 ((looking-at "\r")
			  ;; assume the user's goatloving
			  ;; delivery software didn't convert
			  ;; from Internet's CRLF newline
			  ;; convention to the local LF
			  ;; convention.
			  (forward-char))
			 ((looking-at "[ \t]")
			  ;; garbage added in transit
			  (skip-chars-forward " \t" end))
			 (t (vm-mime-error "something other than line break or hex digits after = in quoted-printable encoding")))))
	    (setq inputpos (point)))
	  (or (markerp end) (setq end (vm-marker end)))
	  (goto-char start)
	  (insert-buffer-substring work-buffer)
	  (delete-region (point) end))
      (and work-buffer (kill-buffer work-buffer))))
  (and (> (- end start) 200)
       (message "Decoding quoted-printable... done")))

(defun vm-mime-qp-encode-region (start end &optional Q-encoding quote-from)
  (and (> (- end start) 200)
       (message "Encoding quoted-printable..."))
  (let ((work-buffer nil)
	(buf (current-buffer))
	(cols 0)
	(hex-digit-alist '((?0 .  0)  (?1 .  1)  (?2 .  2)  (?3 .  3)
			   (?4 .  4)  (?5 .  5)  (?6 .  6)  (?7 .  7)
			   (?8 .  8)  (?9 .  9)  (?A . 10)  (?B . 11)
			   (?C . 12)  (?D . 13)  (?E . 14)  (?F . 15)))
	char inputpos)
    (unwind-protect
	(save-excursion
	  (setq work-buffer (generate-new-buffer " *vm-work*"))
	  (buffer-disable-undo work-buffer)
	  (setq inputpos start)
	  (while (< inputpos end)
	    (setq char (char-after inputpos))
	    (cond ((= char ?\n)
		   (vm-insert-char char 1 nil work-buffer)
		   (setq cols 0))
		  ((and (= char 32)
			(not (= (1+ inputpos) end))
			(not (= ?\n (char-after (1+ inputpos)))))
		   (vm-insert-char char 1 nil work-buffer)
		   (vm-increment cols))
		  ((or (< char 33) (> char 126) (= char 61)
		       (and quote-from (= cols 0) (let ((case-fold-search nil))
						    (looking-at "From ")))
		       (and (= cols 0) (= char ?.)
			    (looking-at "\\.\\(\n\\|\\'\\)")))
		   (vm-insert-char ?= 1 nil work-buffer)
		   (vm-insert-char (car (rassq (lsh char -4) hex-digit-alist))
				   1 nil work-buffer)
		   (vm-insert-char (car (rassq (logand char 15)
					       hex-digit-alist))
				   1 nil work-buffer)
		   (setq cols (+ cols 3)))
		  (t (vm-insert-char char 1 nil work-buffer)
		     (vm-increment cols)))
	    (cond ((> cols 70)
		   (setq cols 0)
		   (if Q-encoding
		       nil
		     (vm-insert-char ?= 1 nil work-buffer)
		     (vm-insert-char ?\n 1 nil work-buffer))))
	    (vm-increment inputpos))
	  (or (markerp end) (setq end (vm-marker end)))
	  (goto-char start)
	  (insert-buffer-substring work-buffer)
	  (delete-region (point) end)
	  (and (> (- end start) 200)
	       (message "Encoding quoted-printable... done"))
	  (- end start))
      (and work-buffer (kill-buffer work-buffer)))))

(defun vm-decode-mime-message-headers (m)
  (let ((case-fold-search t)
	(buffer-read-only nil)
	charset encoding match-start match-end start end)
    (save-excursion
      (goto-char (vm-headers-of m))
      (while (re-search-forward vm-mime-encoded-word-regexp (vm-text-of m) t)
	(setq match-start (match-beginning 0)
	      match-end (match-end 0)
	      charset (buffer-substring (match-beginning 1) (match-end 1))
	      encoding (buffer-substring (match-beginning 2) (match-end 2))
	      start (match-beginning 3)
	      end (vm-marker (match-end 3)))
	;; don't change anything if we can't display the
	;; character set properly.
	(if (not (vm-mime-charset-internally-displayable-p charset))
	    nil
	  (delete-region end match-end)
	  (condition-case data
	      (cond ((string-match "B" encoding)
		     (vm-mime-B-decode-region start end))
		    ((string-match "Q" encoding)
		     (vm-mime-Q-decode-region start end))
		    (t (vm-mime-error "unknown encoded word encoding, %s"
				      encoding)))
	    (vm-mime-error (apply 'message (cdr data))
			   (goto-char start)
			   (insert "**invalid encoded word**")
			   (delete-region (point) end)))
	  (vm-mime-charset-decode-region charset start end)
	  (delete-region match-start start))))))

(defun vm-decode-mime-encoded-words ()
  (let ((case-fold-search t)
	(buffer-read-only nil)
	charset encoding match-start match-end start end)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward vm-mime-encoded-word-regexp nil t)
	(setq match-start (match-beginning 0)
	      match-end (match-end 0)
	      charset (buffer-substring (match-beginning 1) (match-end 1))
	      encoding (buffer-substring (match-beginning 2) (match-end 2))
	      start (match-beginning 3)
	      end (vm-marker (match-end 3)))
	;; don't change anything if we can't display the
	;; character set properly.
	(if (not (vm-mime-charset-internally-displayable-p charset))
	    nil
	  (delete-region end match-end)
	  (condition-case data
	      (cond ((string-match "B" encoding)
		     (vm-mime-B-decode-region start end))
		    ((string-match "Q" encoding)
		     (vm-mime-Q-decode-region start end))
		    (t (vm-mime-error "unknown encoded word encoding, %s"
				      encoding)))
	    (vm-mime-error (apply 'message (cdr data))
			   (goto-char start)
			   (insert "**invalid encoded word**")
			   (delete-region (point) end)))
	  (vm-mime-charset-decode-region charset start end)
	  (delete-region match-start start))))))

(defun vm-decode-mime-encoded-words-in-string (string)
  (if (and vm-display-using-mime
	   (string-match vm-mime-encoded-word-regexp string))
      (vm-with-string-as-temp-buffer string 'vm-decode-mime-encoded-words)
    string ))

(defun vm-reencode-mime-encoded-words ()
  (let ((charset nil)
	start coding pos q-encoding
	old-size
	(case-fold-search t)
	(done nil))
    (save-excursion
      (setq start (point-min))
      (while (not done)
	(setq charset (get-text-property start 'vm-charset))
	(setq pos (next-single-property-change start 'vm-charset))
	(or pos (setq pos (point-max) done t))
	(if charset
	    (progn
	      (if (setq coding (get-text-property start 'vm-coding))
		  (progn
		    (setq old-size (buffer-size))
		    (encode-coding-region start pos coding)
		    (setq pos (+ pos (- (buffer-size) old-size)))))
	      (setq pos
		    (+ start 
		       (if (setq q-encoding
				 (string-match "^iso-8859-\\|^us-ascii"
					       charset))
			   (vm-mime-Q-encode-region start pos)
			 (vm-mime-B-encode-region start pos))))
	      (goto-char pos)
	      (insert "?=")
	      (setq pos (point))
	      (goto-char start)
	      (insert "=?" charset "?" (if q-encoding "Q" "B") "?")))
	(setq start pos)))))

(defun vm-reencode-mime-encoded-words-in-string (string)
  (if (and vm-display-using-mime
	   (text-property-any 0 (length string) 'vm-string t string))
      (vm-with-string-as-temp-buffer string 'vm-reencode-mime-encoded-words)
    string ))

(fset 'vm-mime-parse-content-header 'vm-parse-structured-header)

(defun vm-mime-get-header-contents (header-name-regexp)
  (let ((contents nil)
	regexp)
    (setq regexp (concat "^\\(" header-name-regexp "\\)\\|\\(^$\\)"))
    (save-excursion
      (let ((case-fold-search t))
	(if (and (re-search-forward regexp nil t)
		 (match-beginning 1)
		 (progn (goto-char (match-beginning 0))
			(vm-match-header)))
	    (vm-matched-header-contents)
	  nil )))))

(defun vm-mime-parse-entity (&optional m default-type default-encoding)
  (let ((case-fold-search t) version type qtype encoding id description
	disposition qdisposition boundary boundary-regexp start
	multipart-list c-t c-t-e done p returnval)
    (catch 'return-value
      (save-excursion
	(if m
	    (progn
	      (setq m (vm-real-message-of m))
	      (set-buffer (vm-buffer-of m))))
	(save-excursion
	  (save-restriction
	    (if m
		(progn
		  (setq version (vm-get-header-contents m "MIME-Version:")
			version (car (vm-mime-parse-content-header version))
			type (vm-get-header-contents m "Content-Type:")
			qtype (vm-mime-parse-content-header type ?\; t)
			type (vm-mime-parse-content-header type ?\;)
			encoding (or (vm-get-header-contents
				      m "Content-Transfer-Encoding:")
				     "7bit")
			encoding (car (vm-mime-parse-content-header encoding))
			id (vm-get-header-contents m "Content-ID:")
			id (car (vm-mime-parse-content-header id))
			description (vm-get-header-contents
				     m "Content-Description:")
			description (and description
					 (if (string-match "^[ \t\n]$"
							   description)
					     nil
					   description))
			disposition (vm-get-header-contents
				     m "Content-Disposition:")
			qdisposition (and disposition
					  (vm-mime-parse-content-header
					   disposition ?\; t))
			disposition (and disposition
					 (vm-mime-parse-content-header
					  disposition ?\;)))
		  (widen)
		  (narrow-to-region (vm-headers-of m) (vm-text-end-of m)))
	      (goto-char (point-min))
	      (setq type (vm-mime-get-header-contents "Content-Type:")
		    qtype (or (vm-mime-parse-content-header type ?\; t)
			      default-type)
		    type (or (vm-mime-parse-content-header type ?\;)
			     default-type)
		    encoding (or (vm-mime-get-header-contents
				  "Content-Transfer-Encoding:")
				 default-encoding)
		    encoding (car (vm-mime-parse-content-header encoding))
		    id (vm-mime-get-header-contents "Content-ID:")
		    id (car (vm-mime-parse-content-header id))
		    description (vm-mime-get-header-contents
				 "Content-Description:")
		    description (and description (if (string-match "^[ \t\n]+$"
								   description)
						     nil
						   description))
		    disposition (vm-mime-get-header-contents
				 "Content-Disposition:")
		    qdisposition (and disposition
				      (vm-mime-parse-content-header
				       disposition ?\; t))
		    disposition (and disposition
				     (vm-mime-parse-content-header
				      disposition ?\;))))
	    (cond ((null m) t)
		  ((null version)
		   (throw 'return-value 'none))
		  ((or vm-mime-ignore-mime-version (string= version "1.0")) t)
		  (t (vm-mime-error "Unsupported MIME version: %s" version)))
	    (cond ((and m (null type))
		   (throw 'return-value
			  (vector '("text/plain" "charset=us-ascii")
				  '("text/plain" "charset=us-ascii")
				  encoding id description
				  disposition qdisposition
				  (vm-headers-of m)
				  (vm-text-of m)
				  (vm-text-end-of m)
				  nil nil nil )))
		  ((null type)
		   (goto-char (point-min))
		   (or (re-search-forward "^\n\\|\n\\'" nil t)
		       (vm-mime-error "MIME part missing header/body separator line"))
		   (vector default-type default-type
			   encoding id description
			   disposition qdisposition
			   (vm-marker (point-min))
			   (vm-marker (point))
			   (vm-marker (point-max))
			   nil nil nil ))
		  ((null (string-match "[^/ ]+/[^/ ]+" (car type)))
		   (vm-mime-error "Malformed MIME content type: %s" (car type)))
		  ((and (string-match "^multipart/\\|^message/" (car type))
			(null (string-match "^\\(7bit\\|8bit\\|binary\\)$"
					    encoding)))
		   (vm-mime-error "Opaque transfer encoding used with multipart or message type: %s, %s" (car type) encoding))
		  ((and (string-match "^message/partial$" (car type))
			(null (string-match "^7bit$" encoding)))
		   (vm-mime-error "Non-7BIT transfer encoding used with message/partial message: %s" encoding))
		  ((string-match "^multipart/digest" (car type))
		   (setq c-t '("message/rfc822")
			 c-t-e "7bit"))
		  ((string-match "^multipart/" (car type))
		   (setq c-t '("text/plain" "charset=us-ascii")
			 c-t-e "7bit")) ; below
		  ((string-match "^message/\\(rfc822\\|news\\)" (car type))
		   (setq c-t '("text/plain" "charset=us-ascii")
			 c-t-e "7bit")
		   (goto-char (point-min))
		   (or (re-search-forward "^\n\\|\n\\'" nil t)
		       (vm-mime-error "MIME part missing header/body separator line"))
		   (throw 'return-value
			  (vector type qtype encoding id description
				  disposition qdisposition
				  (vm-marker (point-min))
				  (vm-marker (point))
				  (vm-marker (point-max))
				  (list
				   (save-restriction
				     (narrow-to-region (point) (point-max))
				     (vm-mime-parse-entity-safe nil c-t
								c-t-e)))
				  nil nil )))
		  (t
		   (goto-char (point-min))
		   (or (re-search-forward "^\n\\|\n\\'" nil t)
		       (vm-mime-error "MIME part missing header/body separator line"))
		   (throw 'return-value
			  (vector type qtype encoding id description
				  disposition qdisposition
				  (vm-marker (point-min))
				  (vm-marker (point))
				  (vm-marker (point-max))
				  nil nil nil ))))
	    (setq p (cdr type)
		  boundary nil)
	    (while p
	      (if (string-match "^boundary=" (car p))
		  (setq boundary (car (vm-parse (car p) "=\\(.+\\)"))
			p nil)
		(setq p (cdr p))))
	    (or boundary
		(vm-mime-error
		 "Boundary parameter missing in %s type specification"
		 (car type)))
	    ;; the \' in the regexp is to "be liberal" in the
	    ;; face of broken software that does not add a line
	    ;; break after the final boundary of a nested
	    ;; multipart entity.
	    (setq boundary-regexp
		  (concat "^--" (regexp-quote boundary)
			  "\\(--\\)?[ \t]*\\(\n\\|\\'\\)"))
	    (goto-char (point-min))
	    (setq start nil
		  multipart-list nil
		  done nil)
	    (while (and (not done) (re-search-forward boundary-regexp nil t))
	      (cond ((null start)
		     (setq start (match-end 0)))
		    (t
		     (and (match-beginning 1)
			  (setq done t))
		     (save-excursion
		       (save-restriction
			 (narrow-to-region start (1- (match-beginning 0)))
			 (setq start (match-end 0))
			 (setq multipart-list
			       (cons (vm-mime-parse-entity-safe nil c-t c-t-e)
				     multipart-list)))))))
	    (if (not done)
		(vm-mime-error "final %s boundary missing" boundary))
	    (goto-char (point-min))
	    (or (re-search-forward "^\n\\|\n\\'" nil t)
		(vm-mime-error "MIME part missing header/body separator line"))
	    (vector type qtype encoding id description
		    disposition qdisposition
		    (vm-marker (point-min))
		    (vm-marker (point))
		    (vm-marker (point-max))
		    (nreverse multipart-list)
		    nil nil )))))))

(defun vm-mime-parse-entity-safe (&optional m c-t c-t-e)
  (or c-t (setq c-t '("text/plain" "charset=us-ascii")))
  ;; don't let subpart parse errors make the whole parse fail.  use default
  ;; type if the parse fails.
  (condition-case error-data
      (vm-mime-parse-entity nil c-t c-t-e)
    (vm-mime-error
     (let ((header (if m
		       (vm-headers-of m)
		     (vm-marker (point-min))))
	   (text (if m
		     (vm-text-of m)
		   (save-excursion
		     (re-search-forward "^\n\\|\n\\'"
					nil 0)
		     (vm-marker (point)))))
	   (text-end (if m
			 (vm-text-end-of m)
		       (vm-marker (point-max)))))
     (vector c-t c-t
	     (vm-determine-proper-content-transfer-encoding text text-end)
	     nil
	     ;; cram the error message into the description slot
	     (car (cdr error-data))
	     ;; mark as an attachment to improve the chance that the user
	     ;; will see the description.
	     '("attachment") '("attachment")
	     header
	     text
	     text-end
	     nil nil nil)))))

(defun vm-mime-get-xxx-parameter (layout name param-list)
  (let ((match-end (1+ (length name)))
	(name-regexp (concat (regexp-quote name) "="))
	(case-fold-search t)
	(done nil))
    (while (and param-list (not done))
      (if (and (string-match name-regexp (car param-list))
	       (= (match-end 0) match-end))
	  (setq done t)
	(setq param-list (cdr param-list))))
    (and (car param-list) (car (vm-parse (car param-list) "=\\(.*\\)")))))

(defun vm-mime-get-parameter (layout name)
  (vm-mime-get-xxx-parameter layout name (cdr (vm-mm-layout-type layout))))

(defun vm-mime-get-disposition-parameter (layout name)
  (vm-mime-get-xxx-parameter layout name
			     (cdr (vm-mm-layout-disposition layout))))

(defun vm-mime-insert-mime-body (layout)
  (vm-insert-region-from-buffer (marker-buffer (vm-mm-layout-body-start layout))
				(vm-mm-layout-body-start layout)
				(vm-mm-layout-body-end layout)))

(defun vm-mime-insert-mime-headers (layout)
  (vm-insert-region-from-buffer (marker-buffer (vm-mm-layout-body-start layout))
				(vm-mm-layout-header-start layout)
				(vm-mm-layout-body-start layout))
  (if (and (not (bobp)) (char-equal (char-after (1- (point))) ?\n))
      (delete-char -1)))

(defun vm-make-presentation-copy (m)
  (let ((mail-buffer (current-buffer))
	b mm
	(real-m (vm-real-message-of m))
	(modified (buffer-modified-p)))
    (cond ((or (null vm-presentation-buffer-handle)
	       (null (buffer-name vm-presentation-buffer-handle)))
	   (setq b (generate-new-buffer (concat (buffer-name)
						" Presentation")))
	   (save-excursion
	     (set-buffer b)
	     (if (fboundp 'buffer-disable-undo)
		 (buffer-disable-undo (current-buffer))
	       ;; obfuscation to make the v19 compiler not whine
	       ;; about obsolete functions.
	       (let ((x 'buffer-flush-undo))
		 (funcall x (current-buffer))))
	     (setq mode-name "VM Presentation"
		   major-mode 'vm-presentation-mode
		   vm-message-pointer (list nil)
		   vm-mail-buffer mail-buffer
		   mode-popup-menu (and vm-use-menus vm-popup-menu-on-mouse-3
					(vm-menu-support-possible-p)
					(vm-menu-mode-menu))
		   ;; Default to binary file type for DOS/NT.
		   buffer-file-type t
		   ;; Tell XEmacs/MULE not to mess with the text on writes.
		   buffer-read-only t
		   mode-line-format vm-mode-line-format)
	     ;; scroll in place messes with scroll-up and this loses
	     (defvar scroll-in-place)
	     (make-local-variable 'scroll-in-place)
	     (setq scroll-in-place nil)
	     (and vm-xemacs-mule-p
		  (set-buffer-file-coding-system 'binary t))
	     (cond (vm-fsfemacs-19-p
		    ;; need to do this outside the let because
		    ;; loading disp-table initializes
		    ;; standard-display-table.
		    (require 'disp-table)
		    (let* ((standard-display-table
			    (copy-sequence standard-display-table)))
		      (standard-display-european t)
		      (setq buffer-display-table standard-display-table))))
	     (if (and vm-mutable-frames vm-frame-per-folder
		      (vm-multiple-frames-possible-p))
		 (vm-set-hooks-for-frame-deletion))
	     (use-local-map vm-mode-map)
	     (and (vm-toolbar-support-possible-p) vm-use-toolbar
		  (vm-toolbar-install-toolbar))
	     (and (vm-menu-support-possible-p)
		  (vm-menu-install-menus))
	     (run-hooks 'vm-presentation-mode-hook))
	   (setq vm-presentation-buffer-handle b)))
    (setq b vm-presentation-buffer-handle
	  vm-presentation-buffer vm-presentation-buffer-handle
	  vm-mime-decoded nil)
    (save-excursion
      (set-buffer (vm-buffer-of real-m))
      (save-restriction
	(widen)
	;; must reference this now so that headers will be in
	;; their final position before the message is copied.
	;; otherwise the vheader offset computed below will be
	;; wrong.
	(vm-vheaders-of real-m)
	(set-buffer b)
	(widen)
	(let ((buffer-read-only nil)
	      ;; disable read-only text properties
	      (inhibit-read-only t)
	      (modified (buffer-modified-p)))
	  (unwind-protect
	      (progn
		(erase-buffer)
		(insert-buffer-substring (vm-buffer-of real-m)
					 (vm-start-of real-m)
					 (vm-end-of real-m)))
	    (set-buffer-modified-p modified)))
	(setq mm (copy-sequence m))
	(vm-set-location-data-of mm (vm-copy (vm-location-data-of m)))
	(set-marker (vm-start-of mm) (point-min))
	(set-marker (vm-headers-of mm) (+ (vm-start-of mm)
					  (- (vm-headers-of real-m)
					     (vm-start-of real-m))))
	(set-marker (vm-vheaders-of mm) (+ (vm-start-of mm)
					   (- (vm-vheaders-of real-m)
					      (vm-start-of real-m))))
	(set-marker (vm-text-of mm) (+ (vm-start-of mm)
				       (- (vm-text-of real-m)
					  (vm-start-of real-m))))
	(set-marker (vm-text-end-of mm) (+ (vm-start-of mm)
					   (- (vm-text-end-of real-m)
					      (vm-start-of real-m))))
	(set-marker (vm-end-of mm) (+ (vm-start-of mm)
				      (- (vm-end-of real-m)
					 (vm-start-of real-m))))
	(setcar vm-message-pointer mm)))))

(fset 'vm-presentation-mode 'vm-mode)
(put 'vm-presentation-mode 'mode-class 'special)

(defvar buffer-file-coding-system)

(defun vm-determine-proper-charset (beg end)
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (catch 'done
	(goto-char (point-min))
	(if vm-xemacs-mule-p
	    (let ((charsets (delq 'ascii (charsets-in-region beg end))))
	      (cond ((null charsets)
		     "us-ascii")
		    ((cdr charsets)
		     (or (car (cdr
			       (assq (coding-system-name
				      buffer-file-coding-system)
				     vm-mime-mule-coding-to-charset-alist)))
			 "iso-2022-jp"))
		    (t
		     (or (car (cdr
			       (assoc
				(car charsets)
				vm-mime-mule-charset-to-charset-alist)))
			 "unknown"))))
	  (and (re-search-forward "[^\000-\177]" nil t)
	       (throw 'done (or vm-mime-8bit-composition-charset
				"iso-8859-1")))
	  (throw 'done "us-ascii"))))))

(defun vm-determine-proper-content-transfer-encoding (beg end)
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (catch 'done
	(goto-char (point-min))
	(and (re-search-forward "[\000\015]" nil t)
	     (throw 'done "binary"))

	(let ((toolong nil) bol)
	  (goto-char (point-min))
	  (setq bol (point))
	  (while (and (not (eobp)) (not toolong))
	    (forward-line)
	    (setq toolong (> (- (point) bol) 998)
		  bol (point)))
	  (and toolong (throw 'done "binary")))
	 
	(goto-char (point-min))
	(and (re-search-forward "[\200-\377]" nil t)
	     (throw 'done "8bit"))

	"7bit"))))

(defun vm-mime-types-match (type type/subtype)
  (let ((case-fold-search t))
    (cond ((string-match "/" type)
	   (if (and (string-match (regexp-quote type) type/subtype)
		    (equal 0 (match-beginning 0))
		    (equal (length type/subtype) (match-end 0)))
	       t
	     nil ))
	  ((and (string-match (regexp-quote type) type/subtype)
		(equal 0 (match-beginning 0))
		(equal (save-match-data
			 (string-match "/" type/subtype (match-end 0)))
		       (match-end 0)))))))

(defvar native-sound-only-on-console)

(defun vm-mime-can-display-internal (layout)
  (let ((type (car (vm-mm-layout-type layout))))
    (cond ((vm-mime-types-match "image/jpeg" type)
	   (and vm-xemacs-p
		(featurep 'jpeg)
		(eq (device-type) 'x)))
	  ((vm-mime-types-match "image/gif" type)
	   (and vm-xemacs-p
		(featurep 'gif)
		(eq (device-type) 'x)))
	  ((vm-mime-types-match "image/png" type)
	   (and vm-xemacs-p
		(featurep 'png)
		(eq (device-type) 'x)))
	  ((vm-mime-types-match "image/tiff" type)
	   (and vm-xemacs-p
		(featurep 'tiff)
		(eq (device-type) 'x)))
	  ((vm-mime-types-match "audio/basic" type)
	   (and vm-xemacs-p
		(or (featurep 'native-sound)
		    (featurep 'nas-sound))
		(or (device-sound-enabled-p)
		    (and (featurep 'native-sound)
			 (not native-sound-only-on-console)
			 (eq (device-type) 'x)))))
	  ((vm-mime-types-match "multipart" type) t)
	  ((vm-mime-types-match "message/external-body" type) nil)
	  ((vm-mime-types-match "message" type) t)
	  ((or (vm-mime-types-match "text/plain" type)
	       (vm-mime-types-match "text/enriched" type))
	   (let ((charset (or (vm-mime-get-parameter layout "charset")
			      "us-ascii")))
	     (vm-mime-charset-internally-displayable-p charset)))
	  ((vm-mime-types-match "text/html" type)
	   (condition-case ()
	       (progn (require 'w3)
		      (fboundp 'w3-region))
	     (error nil)))
	  (t nil))))

(defun vm-mime-can-convert (type)
  (let ((alist vm-mime-type-converter-alist)
	;; fake layout. make it the wrong length so an error will
	;; be signaled if vm-mime-can-display-internal ever asks
	;; for one of the other fields
	(fake-layout (make-vector 1 (list nil)))
	(done nil))
    (while (and alist (not done))
      (cond ((and (vm-mime-types-match (car (car alist)) type)
		  (or (progn
			(setcar (aref fake-layout 0) (nth 1 (car alist)))
			(vm-mime-can-display-internal fake-layout))
		      (vm-mime-find-external-viewer (nth 1 (car alist)))))
	     (setq done t))
	    (t (setq alist (cdr alist)))))
    (and alist (car alist))))

(defun vm-mime-convert-undisplayable-layout (layout)
  (let ((ooo (vm-mime-can-convert (car (vm-mm-layout-type layout)))))
    (message "Converting %s to %s..."
			(car (vm-mm-layout-type layout))
			(nth 1 ooo))
    (save-excursion
      (set-buffer (generate-new-buffer " *mime object*"))
      (setq vm-message-garbage-alist
	    (cons (cons (current-buffer) 'kill-buffer)
		  vm-message-garbage-alist))
      (vm-mime-insert-mime-body layout)
      (vm-mime-transfer-decode-region layout (point-min) (point-max))
      (call-process-region (point-min) (point-max) shell-file-name
			   t t nil shell-command-switch (nth 2 ooo))
      (goto-char (point-min))
      (insert "Content-Type: " (nth 1 ooo) "\n")
      (insert "Content-Transfer-Encoding: binary\n\n")
      (set-buffer-modified-p nil)
      (message "Converting %s to %s... done"
			(car (vm-mm-layout-type layout))
			(nth 1 ooo))
      (vector (list (nth 1 ooo))
	      (list (nth 1 ooo))
	      "binary"
	      (vm-mm-layout-id layout)
	      (vm-mm-layout-description layout)
	      (vm-mm-layout-disposition layout)
	      (vm-mm-layout-qdisposition layout)
	      (vm-marker (point-min))
	      (vm-marker (point))
	      (vm-marker (point-max))
	      nil
	      nil
	      nil))))

(defun vm-mime-should-display-button (layout dont-honor-content-disposition)
  (if (and vm-honor-mime-content-disposition
	   (not dont-honor-content-disposition)
	   (vm-mm-layout-disposition layout))
      (let ((case-fold-search t))
	(string-match "^attachment$" (car (vm-mm-layout-disposition layout))))
    (let ((i-list vm-auto-displayed-mime-content-types)
	  (type (car (vm-mm-layout-type layout)))
	  (matched nil))
      (if (eq i-list t)
	  nil
	(while (and i-list (not matched))
	  (if (vm-mime-types-match (car i-list) type)
	      (setq matched t)
	    (setq i-list (cdr i-list))))
	(not matched) ))))

(defun vm-mime-should-display-internal (layout dont-honor-content-disposition)
  (if (and vm-honor-mime-content-disposition
	   (not dont-honor-content-disposition)
	   (vm-mm-layout-disposition layout))
      (let ((case-fold-search t))
	(string-match "^inline$" (car (vm-mm-layout-disposition layout))))
    (let ((i-list vm-mime-internal-content-types)
	  (type (car (vm-mm-layout-type layout)))
	  (matched nil))
      (if (eq i-list t)
	  t
	(while (and i-list (not matched))
	  (if (vm-mime-types-match (car i-list) type)
	      (setq matched t)
	    (setq i-list (cdr i-list))))
	matched ))))

(defun vm-mime-find-external-viewer (type)
  (let ((e-alist vm-mime-external-content-types-alist)
	(matched nil))
    (while (and e-alist (not matched))
      (if (and (vm-mime-types-match (car (car e-alist)) type)
	       (cdr (car e-alist)))
	  (setq matched (cdr (car e-alist)))
	(setq e-alist (cdr e-alist))))
    matched ))
(fset 'vm-mime-should-display-external 'vm-mime-find-external-viewer)

(defun vm-mime-delete-button-maybe (extent)
  (let ((buffer-read-only))
    ;; if displayed MIME object should replace the button
    ;; remove the button now.
    (cond ((vm-extent-property extent 'vm-mime-disposable)
	   (delete-region (vm-extent-start-position extent)
			  (vm-extent-end-position extent))
	   (vm-detach-extent extent)))))

(defun vm-decode-mime-message ()
  "Decode the MIME objects in the current message.

The first time this command is run on a message, decoding is done.
The second time, buttons for all the objects are displayed instead.
The third time, the raw, undecoded data is displayed.

If decoding, the decoded objects might be displayed immediately, or
buttons might be displayed that you need to activate to view the
object.  See the documentation for the variables

    vm-auto-displayed-mime-content-types
    vm-mime-internal-content-types
    vm-mime-external-content-types-alist

to see how to control whether you see buttons or objects.

If the variable vm-mime-display-function is set, then its value
is called as a function with no arguments, and none of the
actions mentioned in the preceding paragraphs are done.  At the
time of the call, the current buffer will be the presentation
buffer for the folder and a copy of the current message will be
in the buffer.  The function is expected to make the message
`MIME presentable' to the user in whatever manner it sees fit."
  (interactive)
  (vm-follow-summary-cursor)
  (vm-select-folder-buffer)
  (vm-check-for-killed-summary)
  (vm-check-for-killed-presentation)
  (vm-error-if-folder-empty)
  (if (and (not vm-display-using-mime)
	   (null vm-mime-display-function))
      (error "MIME display disabled, set vm-display-using-mime non-nil to enable."))
  (if vm-mime-display-function
      (progn
	(vm-make-presentation-copy (car vm-message-pointer))
	(set-buffer vm-presentation-buffer)
	(funcall vm-mime-display-function))
    (if vm-mime-decoded
	(if (eq vm-mime-decoded 'decoded)
	    (let ((vm-preview-read-messages nil)
		  (vm-auto-decode-mime-messages t)
		  (vm-honor-mime-content-disposition nil)
		  (vm-auto-displayed-mime-content-types '("multipart")))
	      (setq vm-mime-decoded nil)
	      (intern (buffer-name) vm-buffers-needing-display-update)
	      (save-excursion
		(vm-preview-current-message))
	      (setq vm-mime-decoded 'buttons))
	  (let ((vm-preview-read-messages nil)
		(vm-auto-decode-mime-messages nil))
	    (intern (buffer-name) vm-buffers-needing-display-update)
	    (vm-preview-current-message)))
      (let ((layout (vm-mm-layout (car vm-message-pointer)))
	    (m (car vm-message-pointer)))
	(message "Decoding MIME message...")
	(cond ((stringp layout)
	       (error "Invalid MIME message: %s" layout)))
	(if (vm-mime-plain-message-p m)
	    (error "Message needs no decoding."))
	(or vm-presentation-buffer
	    ;; maybe user killed it
	    (error "No presentation buffer."))
	(set-buffer vm-presentation-buffer)
	(if (and (interactive-p) (eq vm-system-state 'previewing))
	    (let ((vm-display-using-mime nil))
	      (vm-show-current-message)))
	(setq m (car vm-message-pointer))
	(vm-save-restriction
	 (widen)
	 (goto-char (vm-text-of m))
	 (let ((buffer-read-only nil)
	       (modified (buffer-modified-p)))
	   (unwind-protect
	       (save-excursion
		 (and (not (eq (vm-mm-encoded-header m) 'none))
		      (vm-decode-mime-message-headers m))
		 (if (vectorp layout)
		     (progn
		       (vm-decode-mime-layout layout)
		       (delete-region (point) (point-max))))
		 (vm-energize-urls)
		 (vm-highlight-headers-maybe)
		 (vm-energize-headers-and-xfaces))
	     (set-buffer-modified-p modified))))
	(save-excursion (set-buffer vm-mail-buffer)
			(setq vm-mime-decoded 'decoded))
	(intern (buffer-name vm-mail-buffer) vm-buffers-needing-display-update)
	(vm-update-summary-and-mode-line)
	(message "Decoding MIME message... done"))))
  (vm-display nil nil '(vm-decode-mime-message)
	      '(vm-decode-mime-message reading-message)))

(defun vm-decode-mime-layout (layout &optional dont-honor-c-d)
  (let ((modified (buffer-modified-p)) type type-no-subtype (extent nil))
    (unwind-protect
	(progn
	  (if (not (vectorp layout))
	      (progn
		(setq extent layout
		      layout (vm-extent-property extent 'vm-mime-layout))
		(goto-char (vm-extent-start-position extent))))
	  (setq type (downcase (car (vm-mm-layout-type layout)))
		type-no-subtype (car (vm-parse type "\\([^/]+\\)")))
	  (cond ((and (vm-mime-should-display-button layout dont-honor-c-d)
		      (or (condition-case nil
			      (funcall (intern
					(concat "vm-mime-display-button-"
						type))
				       layout)
			    (void-function nil))
			  (condition-case nil
			      (funcall (intern
					(concat "vm-mime-display-button-"
						type-no-subtype))
				       layout)
			    (void-function nil)))))
		((and (vm-mime-should-display-internal layout dont-honor-c-d)
		      (condition-case nil
			      (funcall (intern
					(concat "vm-mime-display-internal-"
						type))
				       layout)
			    (void-function nil))))
		((vm-mime-types-match "multipart" type)
		 (or (condition-case nil
			 (funcall (intern
				   (concat "vm-mime-display-internal-"
					   type))
				  layout)
		       (void-function nil))
		     (vm-mime-display-internal-multipart/mixed layout)))
		((and (vm-mime-should-display-external type)
		      (vm-mime-display-external-generic layout))
		 (and extent (vm-set-extent-property
			      extent 'vm-mime-disposable nil)))
		((vm-mime-can-convert type)
		 (vm-decode-mime-layout
		  (vm-mime-convert-undisplayable-layout layout)))
		((and (or (vm-mime-types-match "message" type)
			  (vm-mime-types-match "text" type))
		      ;; display unmatched message and text types as
		      ;; text/plain.
		      (vm-mime-display-internal-text/plain layout)))
		(t (and extent (vm-mime-rewrite-failed-button
				extent
				(or (vm-mm-layout-display-error layout)
				    "no external viewer defined for type")))
		   (vm-mime-display-internal-application/octet-stream
		    (or extent layout))))
	  (and extent (vm-mime-delete-button-maybe extent)))
      (set-buffer-modified-p modified)))
  t )

(defun vm-mime-display-button-text (layout)
  (vm-mime-display-button-xxxx layout t))

(defun vm-mime-display-internal-text/html (layout)
  (if (fboundp 'w3-region)
      (let ((buffer-read-only nil)
	    (work-buffer nil))
	(message "Inlining text/html, be patient...")
	;; w3-region is not as tame as we would like.
	;; make sure the yoke is firmly attached.
	(unwind-protect
	    (progn
	      (save-excursion
		(set-buffer (setq work-buffer
				  (generate-new-buffer " *workbuf*")))
		(vm-mime-insert-mime-body layout)
		(vm-mime-transfer-decode-region layout (point-min) (point-max))
		(save-excursion
		  (save-window-excursion
		    (w3-region (point-min) (point-max)))))
	      (insert-buffer-substring work-buffer))
	  (and work-buffer (kill-buffer work-buffer)))
	(message "Inlining text/html... done")
	t )
    (vm-set-mm-layout-display-error layout "Need W3 to inline HTML")
    nil ))

(defun vm-mime-display-internal-text/plain (layout &optional no-highlighting)
  (let ((start (point)) end old-size
	(buffer-read-only nil)
	(charset (or (vm-mime-get-parameter layout "charset") "us-ascii")))
    (if (not (vm-mime-charset-internally-displayable-p charset))
	(progn
	  (vm-set-mm-layout-display-error
	   layout (concat "Undisplayable charset: " charset))
	  nil)
      (vm-mime-insert-mime-body layout)
      (setq end (point-marker))
      (vm-mime-transfer-decode-region layout start end)
      (setq old-size (buffer-size))
      (vm-mime-charset-decode-region charset start end)
      (set-marker end (+ end (- (buffer-size) old-size)))
      (or no-highlighting (vm-energize-urls-in-message-region start end))
      (goto-char end)
      t )))

(defun vm-mime-display-internal-text/enriched (layout)
  (require 'enriched)
  (let ((start (point)) end
	(buffer-read-only nil)
	(enriched-verbose t))
    (message "Decoding text/enriched, be patient...")
    (vm-mime-insert-mime-body layout)
    (setq end (point-marker))
    (vm-mime-transfer-decode-region layout start end)
    ;; enriched-decode expects a couple of headers at the top of
    ;; the region and will remove anything that looks like a
    ;; header.  Put a header section here for it to eat so it
    ;; won't eat message text instead.
    (goto-char start)
    (insert "Comment: You should not see this header\n\n")
    (enriched-decode start end)
    (vm-energize-urls-in-message-region start end)
    (goto-char end)
    (message "Decoding text/enriched... done")
    t ))

(defun vm-mime-display-external-generic (layout)
  (let ((program-list (vm-mime-find-external-viewer
		       (car (vm-mm-layout-type layout))))
	(buffer-read-only nil)
	(start (point))
	process	tempfile cache end)
    (setq cache (cdr (assq 'vm-mime-display-external-generic
			   (vm-mm-layout-cache layout)))
	  process (nth 0 cache)
	  tempfile (nth 1 cache))
    (if (and (processp process) (eq (process-status process) 'run))
	t
      (cond ((or (null tempfile) (null (file-exists-p tempfile)))
	     (vm-mime-insert-mime-body layout)
	     (setq end (point-marker))
	     (vm-mime-transfer-decode-region layout start end)
	     (setq tempfile (vm-make-tempfile-name))
	     (let ((buffer-file-type buffer-file-type)
		   buffer-file-coding-system)
	       ;; Tell DOS/Windows NT whether the file is binary
	       (setq buffer-file-type (not (vm-mime-text-type-p layout)))
	       ;; Tell XEmacs/MULE not to mess with the bits unless
	       ;; this is a text type.
	       (if vm-xemacs-mule-p
		   (if (vm-mime-text-type-p layout)
		       (set-buffer-file-coding-system 'no-conversion nil)
		     (set-buffer-file-coding-system 'binary t)))
               ;; Write an empty tempfile out to disk and set its
               ;; permissions to 0600, then write the actual buffer
               ;; contents to tempfile.
               (write-region start start tempfile nil 0)
               (set-file-modes tempfile 384)
	       (write-region start end tempfile nil 0))
	     (delete-region start end)
	     (save-excursion
	       (vm-select-folder-buffer)
	       (setq vm-folder-garbage-alist
		     (cons (cons tempfile 'delete-file)
			   vm-folder-garbage-alist)))))
      (message "Launching %s..." (mapconcat 'identity program-list " "))
      (setq process
	    (apply 'start-process
		   (format "view %25s" (vm-mime-layout-description layout))
		   nil (append program-list (list tempfile))))
      (process-kill-without-query process t)
      (message "Launching %s... done" (mapconcat 'identity
							    program-list
							    " "))
      (save-excursion
	(vm-select-folder-buffer)
	(setq vm-message-garbage-alist
	      (cons (cons process 'delete-process)
		    vm-message-garbage-alist)))
      (vm-set-mm-layout-cache
       layout
       (nconc (vm-mm-layout-cache layout)
	      (list (cons 'vm-mime-display-external-generic
			  (list process tempfile)))))))
  t )

(defun vm-mime-display-internal-application/octet-stream (layout)
  (if (vectorp layout)
      (let ((buffer-read-only nil)
	    (description (vm-mm-layout-description layout)))
	(vm-mime-insert-button
	 (format "%-35.35s [%s to save to a file]"
		 (vm-mime-layout-description layout)
		 (if (vm-mouse-support-possible-here-p)
		     "Click mouse-2"
		   "Press RETURN"))
	 (function
	  (lambda (layout)
	    (save-excursion
	      (vm-mime-display-internal-application/octet-stream layout))))
	 layout nil))
    (goto-char (vm-extent-start-position layout))
    (setq layout (vm-extent-property layout 'vm-mime-layout))
    ;; support old "name" paramater for application/octet-stream
    ;; but don't override the "filename" parameter extracted from
    ;; Content-Disposition, if any.
    (let ((default-filename
	    (if (vm-mime-get-disposition-parameter layout "filename")
		nil
	      (vm-mime-get-parameter layout "name"))))
      (vm-mime-send-body-to-file layout default-filename)))
  t )
(fset 'vm-mime-display-button-application/octet-stream
      'vm-mime-display-internal-application/octet-stream)

(defun vm-mime-display-button-application (layout)
  (vm-mime-display-button-xxxx layout nil))

(defun vm-mime-display-button-image (layout)
  (vm-mime-display-button-xxxx layout t))

(defun vm-mime-display-button-audio (layout)
  (vm-mime-display-button-xxxx layout nil))

(defun vm-mime-display-button-video (layout)
  (vm-mime-display-button-xxxx layout t))

(defun vm-mime-display-button-message (layout)
  (vm-mime-display-button-xxxx layout t))

(defun vm-mime-display-button-multipart (layout)
  (vm-mime-display-button-xxxx layout t))

(defun vm-mime-display-internal-multipart/mixed (layout)
  (let ((part-list (vm-mm-layout-parts layout)))
    (while part-list
      (vm-decode-mime-layout (car part-list))
      (setq part-list (cdr part-list)))
    t ))

(defun vm-mime-display-internal-multipart/alternative (layout)
  (let (best-layout)
    (cond ((eq vm-mime-alternative-select-method 'best)
	   (let ((done nil)
		 (best nil)
		 part-list type)
	     (setq part-list (vm-mm-layout-parts layout)
		   part-list (nreverse (copy-sequence part-list)))
	     (while (and part-list (not done))
	       (setq type (car (vm-mm-layout-type (car part-list))))
	       (if (or (vm-mime-can-display-internal (car part-list))
		       (vm-mime-find-external-viewer type))
		   (setq best (car part-list)
			 done t)
		 (setq part-list (cdr part-list))))
	     (setq best-layout (or best (car (vm-mm-layout-parts layout))))))
	  ((eq vm-mime-alternative-select-method 'best-internal)
	   (let ((done nil)
		 (best nil)
		 (second-best nil)
		 part-list type)
	     (setq part-list (vm-mm-layout-parts layout)
		   part-list (nreverse (copy-sequence part-list)))
	     (while (and part-list (not done))
	       (setq type (car (vm-mm-layout-type (car part-list))))
	       (cond ((vm-mime-can-display-internal (car part-list))
		      (setq best (car part-list)
			    done t))
		     ((and (null second-best)
			   (vm-mime-find-external-viewer type))
		      (setq second-best (car part-list))))
	       (setq part-list (cdr part-list)))
	     (setq best-layout (or best second-best
				   (car (vm-mm-layout-parts layout)))))))
  (vm-decode-mime-layout best-layout)))

(defun vm-mime-display-button-multipart/parallel (layout)
  (vm-mime-insert-button
   (format "%-35.35s [%s to display in parallel]"
	   (vm-mime-layout-description layout)
	   (if (vm-mouse-support-possible-here-p)
	       "Click mouse-2"
	     "Press RETURN"))
   (function
    (lambda (layout)
      (save-excursion
	(let ((vm-auto-displayed-mime-content-types t))
	  (vm-decode-mime-layout layout t)))))
   layout t))

(fset 'vm-mime-display-internal-multipart/parallel
      'vm-mime-display-internal-multipart/mixed)

(defun vm-mime-display-internal-multipart/digest (layout)
  (if (vectorp layout)
      (let ((buffer-read-only nil))
	(vm-mime-insert-button
	 (format "%-35.35s [%s to display]"
		 (vm-mime-layout-description layout)
		 (if (vm-mouse-support-possible-here-p)
		     "Click mouse-2"
		   "Press RETURN"))
	 (function
	  (lambda (layout)
	    (save-excursion
	      (vm-mime-display-internal-multipart/digest layout))))
	 layout nil))
    (goto-char (vm-extent-start-position layout))
    (setq layout (vm-extent-property layout 'vm-mime-layout))
    (set-buffer (generate-new-buffer (format "digest from %s/%s"
					     (buffer-name vm-mail-buffer)
					     (vm-number-of
					      (car vm-message-pointer)))))
    (setq vm-folder-type vm-default-folder-type)
    (vm-mime-burst-layout layout nil)
    (vm-save-buffer-excursion
     (vm-goto-new-folder-frame-maybe 'folder)
     (vm-mode))
    ;; temp buffer, don't offer to save it.
    (setq buffer-offer-save nil)
    (vm-display (or vm-presentation-buffer (current-buffer)) t
		(list this-command) '(vm-mode startup)))
  t )
(fset 'vm-mime-display-button-multipart/digest
      'vm-mime-display-internal-multipart/digest)

(defun vm-mime-display-button-message/rfc822 (layout)
  (let ((buffer-read-only nil))
    (vm-mime-insert-button
     (format "%-35.35s [%s to display]"
	     (vm-mime-layout-description layout)
	     (if (vm-mouse-support-possible-here-p)
		 "Click mouse-2"
	       "Press RETURN"))
     (function
      (lambda (layout)
	(save-excursion
	  (vm-mime-display-internal-message/rfc822 layout))))
     layout nil)))
(fset 'vm-mime-display-button-message/news
      'vm-mime-display-button-message/rfc822)

(defun vm-mime-display-internal-message/rfc822 (layout)
  (if (vectorp layout)
      (let ((start (point))
	    (buffer-read-only nil))
	(vm-mime-insert-mime-headers (car (vm-mm-layout-parts layout)))
	(insert ?\n)
	(save-excursion
	  (goto-char start)
	  (vm-reorder-message-headers nil vm-visible-headers
				      vm-invisible-header-regexp))
	(save-restriction
	  (narrow-to-region start (point))
	  (vm-decode-mime-encoded-words))
	(vm-mime-display-internal-multipart/mixed layout))
    (goto-char (vm-extent-start-position layout))
    (setq layout (vm-extent-property layout 'vm-mime-layout))
    (set-buffer (generate-new-buffer
		 (format "message from %s/%s"
			 (buffer-name vm-mail-buffer)
			 (vm-number-of
			  (car vm-message-pointer)))))
    (setq vm-folder-type vm-default-folder-type)
    (vm-mime-burst-layout layout nil)
    (set-buffer-modified-p nil)
    (vm-save-buffer-excursion
     (vm-goto-new-folder-frame-maybe 'folder)
     (vm-mode))
    ;; temp buffer, don't offer to save it.
    (setq buffer-offer-save nil)
    (vm-display (or vm-presentation-buffer (current-buffer)) t
		(list this-command) '(vm-mode startup)))
  t )
(fset 'vm-mime-display-internal-message/news
      'vm-mime-display-internal-message/rfc822)

(defun vm-mime-display-internal-message/partial (layout)
  (if (vectorp layout)
      (let ((buffer-read-only nil)
	    (number (vm-mime-get-parameter layout "number"))
	    (total (vm-mime-get-parameter layout "total")))
	(vm-mime-insert-button
	 (format "%-35.35s [%s to attempt assembly]"
		 (concat (vm-mime-layout-description layout)
			 (and number (concat ", part " number))
			 (and number total (concat " of " total)))
		 (if (vm-mouse-support-possible-here-p)
		     "Click mouse-2"
		   "Press RETURN"))
	 (function
	  (lambda (layout)
	    (save-excursion
	      (vm-mime-display-internal-message/partial layout))))
	 layout nil))
    (message "Assembling message...")
    (let ((parts nil)
	  (missing nil)
	  (work-buffer nil)
	  extent id o number total m i prev part-header-pos
	  p-id p-number p-total p-list)
      (setq extent layout
	    layout (vm-extent-property extent 'vm-mime-layout)
	    id (vm-mime-get-parameter layout "id"))
      (if (null id)
	  (vm-mime-error
	   "message/partial message missing id parameter"))
      (save-excursion
	(set-buffer (marker-buffer (vm-mm-layout-body-start layout)))
	(save-excursion
	  (save-restriction
	    (widen)
	    (goto-char (point-min))
	    (while (and (search-forward id nil t)
			(setq m (vm-message-at-point)))
	      (setq o (vm-mm-layout m))
	      (if (not (vectorp o))
		  nil
		(setq p-list (vm-mime-find-message/partials o id))
		(while p-list
		  (setq p-id (vm-mime-get-parameter (car p-list) "id"))
		  (setq p-total (vm-mime-get-parameter (car p-list) "total"))
		  (if (null p-total)
		      nil
		    (setq p-total (string-to-int p-total))
		    (if (< p-total 1)
			(vm-mime-error "message/partial specified part total < 0, %d" p-total))
		    (if total
			(if (not (= total p-total))
			    (vm-mime-error "message/partial speificed total differs between parts, (%d != %d)" p-total total))
		      (setq total p-total)))
		  (setq p-number (vm-mime-get-parameter (car p-list) "number"))
		  (if (null p-number)
		      (vm-mime-error
		       "message/partial message missing number parameter"))
		  (setq p-number (string-to-int p-number))
		  (if (< p-number 1)
		      (vm-mime-error "message/partial part number < 0, %d"
				     p-number))
		  (if (and total (> p-number total))
		      (vm-mime-error "message/partial part number greater than expected number of parts, (%d > %d)" p-number total))
		  (setq parts (cons (list p-number (car p-list)) parts)
			p-list (cdr p-list))))
	      (goto-char (vm-mm-layout-body-end o))))))
      (if (null total)
	  (vm-mime-error "total number of parts not specified in any message/partial part"))
      (setq parts (sort parts
			(function
			 (lambda (p q)
			   (< (car p)
			      (car q))))))
      (setq i 0
	    p-list parts)
      (while p-list
	(cond ((< i (car (car p-list)))
	       (vm-increment i)
	       (cond ((not (= i (car (car p-list))))
		      (setq missing (cons i missing)))
		     (t (setq prev p-list
			      p-list (cdr p-list)))))
	      (t
	       ;; remove duplicate part
	       (setcdr prev (cdr p-list))
	       (setq p-list (cdr p-list)))))
      (while (< i total)
	(vm-increment i)
	(setq missing (cons i missing)))
      (if missing
	  (vm-mime-error "part%s %s%s missing"
			 (if (cdr missing) "s" "")
			 (mapconcat
			  (function identity)
			  (nreverse (mapcar 'int-to-string
					    (or (cdr missing) missing)))
			  ", ")
			 (if (cdr missing)
			     (concat " and " (car missing))
			   "")))
      (set-buffer (generate-new-buffer "assembled message"))
      (setq vm-folder-type vm-default-folder-type)
      (vm-mime-insert-mime-headers (car (cdr (car parts))))
      (goto-char (point-min))
      (vm-reorder-message-headers
       nil nil
"\\(Encrypted\\|Content-\\|MIME-Version\\|Message-ID\\|Subject\\|X-VM-\\|Status\\)")
      (goto-char (point-max))
      (setq part-header-pos (point))
      (while parts
	(vm-mime-insert-mime-body (car (cdr (car parts))))
	(setq parts (cdr parts)))
      (goto-char part-header-pos)
      (vm-reorder-message-headers
       nil '("Subject" "MIME-Version" "Content-" "Message-ID" "Encrypted") nil)
      (vm-munge-message-separators vm-folder-type (point-min) (point-max))
      (goto-char (point-min))
      (insert (vm-leading-message-separator))
      (goto-char (point-max))
      (insert (vm-trailing-message-separator))
      (set-buffer-modified-p nil)
      (message "Assembling message... done")
      (vm-save-buffer-excursion
       (vm-goto-new-folder-frame-maybe 'folder)
       (vm-mode))
      ;; temp buffer, don't offer to save it.
      (setq buffer-offer-save nil)
      (vm-display (or vm-presentation-buffer (current-buffer)) t
		  (list this-command) '(vm-mode startup)))
    t ))
(fset 'vm-mime-display-button-message/partial
      'vm-mime-display-internal-message/partial)

(defun vm-mime-display-internal-image-xxxx (layout feature name)
  (if (and vm-xemacs-p
	   (featurep feature)
	   (eq (device-type) 'x))
      (let ((start (point)) end tempfile g e
	    (buffer-read-only nil))
	(if (setq g (cdr (assq 'vm-mime-display-internal-image-xxxx
			       (vm-mm-layout-cache layout))))
	    nil
	  (vm-mime-insert-mime-body layout)
	  (setq end (point-marker))
	  (vm-mime-transfer-decode-region layout start end)
	  (setq tempfile (vm-make-tempfile-name))
	  ;; Write an empty tempfile out to disk and set its
	  ;; permissions to 0600, then write the actual buffer
	  ;; contents to tempfile.
	  (write-region start start tempfile nil 0)
	  (set-file-modes tempfile 384)
	  ;; coding system for presentation buffer is binary so
	  ;; we don't need to set it here.
	  (write-region start end tempfile nil 0)
	  (message "Creating %s glyph..." name)
;; `((LOCALE (TAG-SET . INSTANTIATOR) ...) ...)'.  This function accepts
	  (setq g (make-glyph
		   (list
		    (cons (list 'win)
			  (vector feature ':file tempfile))
		    (cons (list 'win)
			  (vector 'string
				  ':data
				  (format "[Unknown/Bsd %s image encoding]\n"
					  name)))
		    (cons nil
			  (vector 'string
				  ':data
				  (format "[%s image]\n" name))))))
	  (message "")
	  (vm-set-mm-layout-cache
	   layout
	   (nconc (vm-mm-layout-cache layout)
		  (list (cons 'vm-mime-display-internal-image-xxxx g))))
	  (save-excursion
	    (vm-select-folder-buffer)
	    (setq vm-folder-garbage-alist
		  (cons (cons tempfile 'delete-file)
			vm-folder-garbage-alist)))
	  (delete-region start end))
	(if (not (bolp))
	    (insert-char ?\n 2)
	  (insert-char ?\n 1))
	(setq e (vm-make-extent (1- (point)) (point)))
	(vm-set-extent-property e 'begin-glyph g)
	t )))

(defun vm-mime-display-internal-image/gif (layout)
  (vm-mime-display-internal-image-xxxx layout 'gif "GIF"))

(defun vm-mime-display-internal-image/jpeg (layout)
  (vm-mime-display-internal-image-xxxx layout 'jpeg "JPEG"))

(defun vm-mime-display-internal-image/png (layout)
  (vm-mime-display-internal-image-xxxx layout 'png "PNG"))

(defun vm-mime-display-internal-image/tiff (layout)
  (vm-mime-display-internal-image-xxxx layout 'tiff "TIFF"))

(defun vm-mime-display-internal-audio/basic (layout)
  (if (and vm-xemacs-p
	   (or (featurep 'native-sound)
	       (featurep 'nas-sound))
	   (or (device-sound-enabled-p)
	       (and (featurep 'native-sound)
		    (not native-sound-only-on-console)
		    (eq (device-type) 'x))))
      (let ((start (point)) end tempfile
	    (buffer-read-only nil))
	(if (setq tempfile (cdr (assq 'vm-mime-display-internal-audio/basic
				      (vm-mm-layout-cache layout))))
	    nil
	  (vm-mime-insert-mime-body layout)
	  (setq end (point-marker))
	  (vm-mime-transfer-decode-region layout start end)
	  (setq tempfile (vm-make-tempfile-name))
	  ;; Write an empty tempfile out to disk and set its
	  ;; permissions to 0600, then write the actual buffer
	  ;; contents to tempfile.
	  (write-region start start tempfile nil 0)
	  (set-file-modes tempfile 384)
	  ;; coding system for presentation buffer is binary, so
	  ;; we don't need to set it here.
	  (write-region start end tempfile nil 0)
	  (vm-set-mm-layout-cache
	   layout
	   (nconc (vm-mm-layout-cache layout)
		  (list (cons 'vm-mime-display-internal-audio/basic
			      tempfile))))
	  (save-excursion
	    (vm-select-folder-buffer)
	    (setq vm-folder-garbage-alist
		  (cons (cons tempfile 'delete-file)
			vm-folder-garbage-alist)))
	  (delete-region start end))
	(start-itimer "audioplayer"
		      (list 'lambda nil (list 'play-sound-file tempfile))
		      1)
	t )
    nil ))

(defun vm-mime-display-button-xxxx (layout disposable)
  (let ((description (vm-mime-layout-description layout)))
    (vm-mime-insert-button
     (format "%-35.35s [%s to attempt display]"
	     description
	     (if (vm-mouse-support-possible-here-p)
		 "Click mouse-2"
	       "Press RETURN"))
     (function
      (lambda (layout)
	(save-excursion
	  (let ((vm-auto-displayed-mime-content-types t))
	    (vm-decode-mime-layout layout t)))))
     layout disposable)
    t ))

(defun vm-mime-run-display-function-at-point (&optional function dispose)
  (interactive)
  ;; save excursion to keep point from moving.  its motion would
  ;; drag window point along, to a place arbitrarily far from
  ;; where it was when the user triggered the button.
  (save-excursion
    (cond (vm-fsfemacs-19-p
	   (let (o-list o (found nil))
	     (setq o-list (overlays-at (point)))
	     (while (and o-list (not found))
	       (cond ((overlay-get (car o-list) 'vm-mime-layout)
		      (setq found t)
		      (funcall (or function (overlay-get (car o-list)
							 'vm-mime-function))
			       (car o-list))))
	       (setq o-list (cdr o-list)))))
	  (vm-xemacs-p
	   (let ((e (extent-at (point) nil 'vm-mime-layout)))
	     (funcall (or function (extent-property e 'vm-mime-function))
		      e))))))

;; for the karking compiler
(defvar vm-menu-mime-dispose-menu)

(defun vm-mime-set-extent-glyph-for-type (e type)
  (if (and vm-xemacs-p
	   (featurep 'xpm)
	   (eq (device-type) 'x)
	   (> (device-bitplanes) 7))
      (let ((dir vm-image-directory)
	    (colorful (> (device-bitplanes) 15))
	    (tuples
	     '(("text" "document-simple.xpm" "document-colorful.xpm")
	       ("image" "mona_stamp-simple.xpm" "mona_stamp-colorful.xpm")
	       ("audio" "audio_stamp-simple.xpm" "audio_stamp-colorful.xpm")
	       ("video" "film-simple.xpm" "film-colorful.xpm")
	       ("message" "message-simple.xpm" "message-colorful.xpm")
	       ("application" "gear-simple.xpm" "gear-colorful.xpm")
	       ("multipart" "stuffed_box-simple.xpm"
		"stuffed_box-colorful.xpm")))
	    glyph file sym p)
	(setq file (catch 'done
		     (while tuples
		       (if (vm-mime-types-match (car (car tuples)) type)
			   (throw 'done (car tuples))
			 (setq tuples (cdr tuples))))
		     nil)
	      file (and file (if colorful (nth 2 file) (nth 1 file)))
	      sym (and file (intern file vm-image-obarray))
	      glyph (and sym (boundp sym) (symbol-value sym))
	      glyph (or glyph
			(and file
			     (make-glyph
			      (vector 'autodetect
				      ':data (expand-file-name file dir))))))
	(and sym (not (boundp sym)) (set sym glyph))
	(and glyph (set-extent-begin-glyph e glyph)))))

(defun vm-mime-insert-button (caption action layout disposable)
  (let ((start (point))	e
	(keymap (make-sparse-keymap))
	(buffer-read-only nil))
    (if (fboundp 'set-keymap-parents)
	(if (current-local-map)
	    (set-keymap-parents keymap (list (current-local-map))))
      (setq keymap (nconc keymap (current-local-map))))
    (define-key keymap "\r" 'vm-mime-run-display-function-at-point)
    (if (and (vm-mouse-xemacs-mouse-p) vm-popup-menu-on-mouse-3)
	(define-key keymap 'button3 'vm-menu-popup-mime-dispose-menu))
    (if (not (bolp))
	(insert "\n"))
    (insert caption "\n")
    ;; we must use the same interface that the vm-extent functions
    ;; use.  if they use overlays, then we call make-overlay.
    (if (eq (symbol-function 'vm-make-extent) 'make-overlay)
	;; we MUST have the five arg make-overlay.  overlays must
	;; advance when text is inserted at their start position or
	;; inline text and graphics will seep into the button
	;; overlay and then be removed when the button is removed.
	(setq e (make-overlay start (point) nil t nil))
      (setq e (make-extent start (point)))
      (set-extent-property e 'start-open t)
      (set-extent-property e 'end-open t))
    (vm-mime-set-extent-glyph-for-type e (car (vm-mm-layout-type layout)))
    ;; for emacs
    (vm-set-extent-property e 'mouse-face 'highlight)
    (vm-set-extent-property e 'local-map keymap)
    ;; for xemacs
    (vm-set-extent-property e 'highlight t)
    (vm-set-extent-property e 'keymap keymap)
    (vm-set-extent-property e 'balloon-help 'vm-mouse-3-help)
    ;; for all
    (vm-set-extent-property e 'vm-mime-disposable disposable)
    (vm-set-extent-property e 'face vm-mime-button-face)
    (vm-set-extent-property e 'vm-mime-layout layout)
    (vm-set-extent-property e 'vm-mime-function action)))

(defun vm-mime-rewrite-failed-button (button error-string)
  (let* ((buffer-read-only nil)
	 (start (point)))
    (goto-char (vm-extent-start-position button))
    (insert (format "DISPLAY FAILED -- %s\n" error-string))
    (vm-set-extent-endpoints button start (vm-extent-end-position button))
    (delete-region (point) (vm-extent-end-position button))))

(defun vm-mime-send-body-to-file (layout &optional default-filename)
  (if (not (vectorp layout))
      (setq layout (vm-extent-property layout 'vm-mime-layout)))
  (or default-filename
      (setq default-filename
	    (vm-mime-get-disposition-parameter layout "filename")))
  (and default-filename
       (setq default-filename (file-name-nondirectory default-filename)))
  (let ((work-buffer nil)
	;; evade the XEmacs dialog box, yeccch.
	(use-dialog-box nil)
	(dir vm-mime-attachment-save-directory)
	(done nil)
	file)
    (while (not done)
      (setq file
	    (read-file-name
	     (if default-filename
		 (format "Write MIME body to file (default %s): "
			 default-filename)
	       "Write MIME body to file: ")
	     dir default-filename)
	  file (expand-file-name file dir))
      (if (not (file-directory-p file))
	  (setq done t)
	(if default-filename
	    (message "%s is a directory" file)
	  (error "%s is a directory" file))
	(sit-for 2)
	(setq dir file
	      default-filename (if (string-match "/$" file)
				   (concat file default-filename)
				 (concat file "/" default-filename)))))
    (save-excursion
      (unwind-protect
	  (progn
	    (setq work-buffer (generate-new-buffer " *vm-work*"))
	    (buffer-disable-undo work-buffer)
	    (set-buffer work-buffer)
	    ;; Tell DOS/Windows NT whether the file is binary
	    (setq buffer-file-type (not (vm-mime-text-type-p layout)))
	    ;; Tell XEmacs/MULE not to mess with the bits unless
	    ;; this is a text type.
	    (if vm-xemacs-mule-p
		(if (vm-mime-text-type-p layout)
		    (set-buffer-file-coding-system 'no-conversion nil)
		  (set-buffer-file-coding-system 'binary t)))
	    (vm-mime-insert-mime-body layout)
	    (vm-mime-transfer-decode-region layout (point-min) (point-max))
	    (or (not (file-exists-p file))
		(y-or-n-p "File exists, overwrite? ")
		(error "Aborted"))
	    (write-region (point-min) (point-max) file nil nil))
	(and work-buffer (kill-buffer work-buffer))))))

(defun vm-mime-pipe-body-to-command (command layout &optional discard-output)
  (if (not (vectorp layout))
      (setq layout (vm-extent-property layout 'vm-mime-layout)))
  (let ((output-buffer (if discard-output
			   0
			 (get-buffer-create "*Shell Command Output*")))
	(work-buffer nil))
    (save-excursion
      (if (bufferp output-buffer)
	  (progn
	    (set-buffer output-buffer)
	    (erase-buffer)))
      (unwind-protect
	  (progn
	    (setq work-buffer (generate-new-buffer " *vm-work*"))
	    (buffer-disable-undo work-buffer)
	    (set-buffer work-buffer)
	    (vm-mime-insert-mime-body layout)
	    (vm-mime-transfer-decode-region layout (point-min) (point-max))
	    (let ((pop-up-windows (and pop-up-windows
				       (eq vm-mutable-windows t)))
		  ;; Tell DOS/Windows NT whether the input is binary
		  (binary-process-input (not (vm-mime-text-type-p layout))))
	      (call-process-region (point-min) (point-max)
				   (or shell-file-name "sh")
				   nil output-buffer nil
				   shell-command-switch command)))
	(and work-buffer (kill-buffer work-buffer)))
      (if (bufferp output-buffer)
	  (progn
	    (set-buffer output-buffer)
	    (if (not (zerop (buffer-size)))
		(vm-display output-buffer t (list this-command)
			    '(vm-pipe-message-to-command))
	      (vm-display nil nil (list this-command)
			  '(vm-pipe-message-to-command)))))))
  t )

(defun vm-mime-pipe-body-to-queried-command (layout &optional discard-output)
  (let ((command (read-string "Pipe to command: ")))
    (vm-mime-pipe-body-to-command command layout discard-output)))

(defun vm-mime-pipe-body-to-queried-command-discard-output (layout)
  (vm-mime-pipe-body-to-queried-command layout t))

(defun vm-mime-send-body-to-printer (layout)
  (vm-mime-pipe-body-to-command (mapconcat (function identity)
					   (nconc (list vm-print-command)
						  vm-print-command-switches)
					   " ")
				layout))

(defun vm-mime-display-body-as-text (button)
  (let ((vm-auto-displayed-mime-content-types '("text/plain"))
	(layout (copy-sequence (vm-extent-property button 'vm-mime-layout))))
    (vm-set-extent-property button 'vm-mime-disposable t)
    (vm-set-extent-property button 'vm-mime-layout layout)
    ;; not universally correct, but close enough.
    (vm-set-mm-layout-type layout '("text/plain" "charset=us-ascii"))
    (goto-char (vm-extent-start-position button))
    (vm-decode-mime-layout button t)))

(defun vm-mime-display-body-using-external-viewer (button)
  (let ((layout (vm-extent-property button 'vm-mime-layout)))
    (goto-char (vm-extent-start-position button))
    (if (not (vm-mime-find-external-viewer (car (vm-mm-layout-type layout))))
	(error "No viewer defined for type %s"
	       (car (vm-mm-layout-type layout)))
      (vm-mime-display-external-generic layout))))

(defun vm-mime-scrub-description (string)
  (let ((work-buffer nil))
      (save-excursion
       (unwind-protect
	   (progn
	     (setq work-buffer (generate-new-buffer " *vm-work*"))
	     (buffer-disable-undo work-buffer)
	     (set-buffer work-buffer)
	     (insert string)
	     (while (re-search-forward "[ \t\n]+" nil t)
	       (replace-match " "))
	     (buffer-string))
	 (and work-buffer (kill-buffer work-buffer))))))

(defun vm-mime-layout-description (layout)
  (let ((type (car (vm-mm-layout-type layout)))
	description name)
    (setq description
	  (if (vm-mm-layout-description layout)
	      (vm-mime-scrub-description (vm-mm-layout-description layout))))
    (concat
     (if description description "")
     (if description ", " "")
     (cond ((vm-mime-types-match "multipart/digest" type)
	    (let ((n (length (vm-mm-layout-parts layout))))
	      (format "digest (%d message%s)" n (if (= n 1) "" "s"))))
	   ((vm-mime-types-match "multipart/alternative" type)
	    "multipart alternative")
	   ((vm-mime-types-match "multipart" type)
	    (let ((n (length (vm-mm-layout-parts layout))))
	      (format "multipart message (%d part%s)" n (if (= n 1) "" "s"))))
	   ((vm-mime-types-match "text/plain" type)
	    (format "plain text%s"
		    (let ((charset (vm-mime-get-parameter layout "charset")))
		      (if charset
			  (concat ", " charset)
			""))))
	   ((vm-mime-types-match "text/enriched" type)
	    "enriched text")
	   ((vm-mime-types-match "text/html" type)
	    "HTML")
	   ((vm-mime-types-match "image/gif" type)
	    "GIF image")
	   ((vm-mime-types-match "image/jpeg" type)
	    "JPEG image")
	   ((and (vm-mime-types-match "application/octet-stream" type)
		 (setq name (vm-mime-get-parameter layout "name"))
		 (save-match-data (not (string-match "^[ \t]*$" name))))
	    name)
	   (t type)))))

(defun vm-mime-layout-contains-type (layout type)
  (if (vm-mime-types-match type (car (vm-mm-layout-type layout)))
      layout
    (let ((p (vm-mm-layout-parts layout))
	  (result nil)
	  (done nil))
      (while (and p (not done))
	(if (setq result (vm-mime-layout-contains-type (car p) type))
	    (setq done t)
	  (setq p (cdr p))))
      result )))

;; breadth first traversal
(defun vm-mime-find-digests-in-layout (layout)
  (let ((layout-list (list layout))
	layout-type
	(result nil))
    (while layout-list
      (setq layout-type (car (vm-mm-layout-type (car layout-list))))
      (cond ((string-match "^multipart/digest\\|message/\\(rfc822\\|news\\)"
			   layout-type)
	     (setq result (nconc result (list (car layout-list)))))
	    ((vm-mime-composite-type-p layout-type)
	     (setq layout-list (nconc layout-list
				      (copy-sequence
				       (vm-mm-layout-parts
					(car layout-list)))))))
      (setq layout-list (cdr layout-list)))
    result ))
  
(defun vm-mime-plain-message-p (m)
  (save-match-data
    (let ((o (vm-mm-layout m))
	  (case-fold-search t))
      (and (eq (vm-mm-encoded-header m) 'none)
	   (or (not (vectorp o))
	       (and (vm-mime-types-match "text/plain"
					 (car (vm-mm-layout-type o)))
		    (let* ((charset (or (vm-mime-get-parameter o "charset")
				      "us-ascii")))
		      (vm-string-member charset vm-mime-default-face-charsets))
		    (string-match "^\\(7bit\\|8bit\\|binary\\)$"
				  (vm-mm-layout-encoding o))))))))

(defun vm-mime-text-type-p (layout)
  (or (vm-mime-types-match "text" (car (vm-mm-layout-type layout)))
      (vm-mime-types-match "message" (car (vm-mm-layout-type layout)))))

(defun vm-mime-charset-internally-displayable-p (name)
  (cond ((and vm-xemacs-mule-p (eq (device-type) 'x))
	 (vm-string-assoc name vm-mime-mule-charset-to-coding-alist))
	((vm-multiple-fonts-possible-p)
	 (or (vm-string-member name vm-mime-default-face-charsets)
	     (vm-string-assoc name vm-mime-charset-font-alist)))
	(t
	 (vm-string-member name vm-mime-default-face-charsets))))

(defun vm-mime-find-message/partials (layout id)
  (let ((list nil)
	(type (vm-mm-layout-type layout)))
    (cond ((vm-mime-types-match "multipart" (car type))
	   (let ((parts (vm-mm-layout-parts layout)) o)
	     (while parts
	       (setq o (vm-mime-find-message/partials (car parts) id))
	       (if o
		   (setq list (nconc o list)))
	       (setq parts (cdr parts)))))
	  ((vm-mime-types-match "message/partial" (car type))
	   (if (equal (vm-mime-get-parameter layout "id") id)
	       (setq list (cons layout list)))))
    list ))

(defun vm-message-at-point ()
  (let ((mp vm-message-list)
	(point (point))
	(done nil))
    (while (and mp (not done))
      (if (and (>= point (vm-start-of (car mp)))
	       (<= point (vm-end-of (car mp))))
	  (setq done t)
	(setq mp (cdr mp))))
    (car mp)))

(defun vm-mime-make-multipart-boundary ()
  (let ((boundary (make-string 10 ?a))
	(i 0))
    (random t)
    (while (< i (length boundary))
      (aset boundary i (aref vm-mime-base64-alphabet
			     (% (vm-abs (lsh (random) -8))
				(length vm-mime-base64-alphabet))))
      (vm-increment i))
    boundary ))

(defun vm-mime-attach-file (file type &optional charset description)
  "Attach a file to a VM composition buffer to be sent along with the message.
The file is not inserted into the buffer and MIME encoded until
you execute vm-mail-send or vm-mail-send-and-exit.  A visible tag
indicating the existence of the attachment is placed in the
composition buffer.  You can move the attachment around or remove
it entirely with normal text editing commands.  If you remove the
attachment tag, the attachment will not be sent.

First argument, FILE, is the name of the file to attach.  Second
argument, TYPE, is the MIME Content-Type of the file.  Optional
third argument CHARSET is the character set of the attached
document.  This argument is only used for text types, and it is
ignored for other types.  Optional fourth argument DESCRIPTION
should be a one line description of the file.

When called interactively all arguments are read from the
minibuffer.

This command is for attaching files that do not have a MIME
header section at the top.  For files with MIME headers, you
should use vm-mime-attach-mime-file to attach such a file.  VM
will extract the content type information from the headers in
this case and not prompt you for it in the minibuffer."
  (interactive
   ;; protect value of last-command and this-command
   (let ((last-command last-command)
	 (this-command this-command)
	 (charset nil)
	 description file default-type type)
     (if (null vm-send-using-mime)
	 (error "MIME attachments disabled, set vm-send-using-mime non-nil to enable."))
     (setq file (vm-read-file-name "Attach file: " nil nil t)
	   default-type (or (vm-mime-default-type-from-filename file)
			    "application/octet-stream")
	   type (completing-read
		 (format "Content type (default %s): "
			 default-type)
		 vm-mime-type-completion-alist)
	   type (if (> (length type) 0) type default-type))
     (if (vm-mime-types-match "text" type)
	 (setq charset (completing-read "Character set (default US-ASCII): "
					vm-mime-charset-completion-alist)
	       charset (if (> (length charset) 0) charset)))
     (setq description (read-string "One line description: "))
     (if (string-match "^[ \t]*$" description)
	 (setq description nil))
     (list file type charset description)))
  (if (null vm-send-using-mime)
      (error "MIME attachments disabled, set vm-send-using-mime non-nil to enable."))
  (if (file-directory-p file)
      (error "%s is a directory, cannot attach" file))
  (if (not (file-exists-p file))
      (error "No such file: %s" file))
  (if (not (file-readable-p file))
      (error "You don't have permission to read %s" file))
  (and charset (setq charset (list (concat "charset=" charset))))
  (and description (setq description (vm-mime-scrub-description description)))
  (vm-mime-attach-object file type charset description nil))

(defun vm-mime-attach-mime-file (file)
  "Attach a MIME encoded file to a VM composition buffer to be sent
along with the message.

The file is not inserted into the buffer until you execute
vm-mail-send or vm-mail-send-and-exit.  A visible tag indicating
the existence of the attachment is placed in the composition
buffer.  You can move the attachment around or remove it entirely
with normal text editing commands.  If you remove the attachment
tag, the attachment will not be sent.

The sole argument, FILE, is the name of the file to attach.
When called interactively the FILE argument is read from the
minibuffer.

This command is for attaching files that have a MIME
header section at the top.  For files without MIME headers, you
should use vm-mime-attach-file to attach such a file.  VM
will interactively query you for the file type information."
  (interactive
   ;; protect value of last-command and this-command
   (let ((last-command last-command)
	 (this-command this-command)
	 file)
     (if (null vm-send-using-mime)
	 (error "MIME attachments disabled, set vm-send-using-mime non-nil to enable."))
     (setq file (vm-read-file-name "Attach file: " nil nil t))
     (list file)))
  (if (null vm-send-using-mime)
      (error "MIME attachments disabled, set vm-send-using-mime non-nil to enable."))
  (if (file-directory-p file)
      (error "%s is a directory, cannot attach" file))
  (if (not (file-exists-p file))
      (error "No such file: %s" file))
  (if (not (file-readable-p file))
      (error "You don't have permission to read %s" file))
  (vm-mime-attach-object file nil nil nil t))

(defun vm-mime-attach-object (object type params description mimed)
  (if (not (eq major-mode 'mail-mode))
      (error "Command must be used in a VM Mail mode buffer."))
  (let (start end e tag-string disposition)
    (if (< (point) (save-excursion (mail-text) (point)))
	(mail-text))
    (setq start (point)
	  tag-string (format "[ATTACHMENT %s, %s]" object
			     (or type "MIME file")))
    (insert tag-string "\n")
    (setq end (1- (point)))
    (if (and (stringp object) (not mimed))
	(progn
	  (if (or (vm-mime-types-match "application" type)
		  (vm-mime-types-match "model" type))
	      (setq disposition (list "attachment"))
	    (setq disposition (list "inline")))
	  (setq disposition (nconc disposition
				   (list
				    (concat "filename=\""
					    (file-name-nondirectory object)
					    "\"")))))
      (setq disposition (list "unspecified")))
    (cond (vm-fsfemacs-19-p
	   (put-text-property start end 'front-sticky nil)
	   (put-text-property start end 'rear-nonsticky t)
;; can't be intangible because menu clicking at a position needs
;; to set point inside the tag so that a command can access the
;; text properties there.
;;	   (put-text-property start end 'intangible object)
	   (put-text-property start end 'face vm-mime-button-face)
	   (put-text-property start end 'vm-mime-type type)
	   (put-text-property start end 'vm-mime-object object)
	   (put-text-property start end 'vm-mime-parameters params)
	   (put-text-property start end 'vm-mime-description description)
	   (put-text-property start end 'vm-mime-disposition disposition)
	   (put-text-property start end 'vm-mime-encoded mimed)
	   (put-text-property start end 'vm-mime-object object))
	  (vm-xemacs-p
	   (setq e (make-extent start end))
	   (vm-mime-set-extent-glyph-for-type e (or type "text/plain"))
	   (set-extent-property e 'start-open t)
	   (set-extent-property e 'face vm-mime-button-face)
	   (set-extent-property e 'duplicable t)
	   (let ((keymap (make-sparse-keymap)))
	     (if vm-popup-menu-on-mouse-3
		 (define-key keymap 'button3
		   'vm-menu-popup-content-disposition-menu))
	     (set-extent-property e 'keymap keymap)
	     (set-extent-property e 'balloon-help 'vm-mouse-3-help))
	   (set-extent-property e 'vm-mime-type type)
	   (set-extent-property e 'vm-mime-object object)
	   (set-extent-property e 'vm-mime-parameters params)
	   (set-extent-property e 'vm-mime-description description)
	   (set-extent-property e 'vm-mime-disposition disposition)
	   (set-extent-property e 'vm-mime-encoded mimed)))))

(defun vm-mime-attachment-disposition-at-point ()
  (cond (vm-fsfemacs-19-p
	 (let ((disp (get-text-property (point) 'vm-mime-disposition)))
	   (intern (car disp))))
	(vm-xemacs-p
	 (let* ((e (extent-at (point) nil 'vm-mime-disposition))
		(disp (extent-property e 'vm-mime-disposition)))
	   (intern (car disp))))))

(defun vm-mime-set-attachment-disposition-at-point (sym)
  (cond (vm-fsfemacs-19-p
	 (let ((disp (get-text-property (point) 'vm-mime-disposition)))
	   (setcar disp (symbol-name sym))))
	(vm-xemacs-p
	 (let* ((e (extent-at (point) nil 'vm-mime-disposition))
		(disp (extent-property e 'vm-mime-disposition)))
	   (setcar disp (symbol-name sym))))))

(defun vm-disallow-overlay-endpoint-insertion (overlay after start end
					       &optional old-size)
  (cond ((null after) nil)
	((= start (overlay-start overlay))
	 (move-overlay overlay end (overlay-end overlay)))
	((= start (overlay-end overlay))
	 (move-overlay overlay (overlay-start overlay) start))))

(defun vm-mime-fake-attachment-overlays (start end)
  (let ((o-list nil)
	(done nil)
	(pos start)
	object props o)
    (save-excursion
      (save-restriction
	(narrow-to-region start end)
	(while (not done)
	  (setq object (get-text-property pos 'vm-mime-object))
	  (setq pos (next-single-property-change pos 'vm-mime-object))
	  (or pos (setq pos (point-max) done t))
	  (if object
	      (progn
		(setq o (make-overlay start pos))
		(overlay-put o 'insert-in-front-hooks
			     '(vm-disallow-overlay-endpoint-insertion))
		(overlay-put o 'insert-behind-hooks
			     '(vm-disallow-overlay-endpoint-insertion))
		(setq props (text-properties-at start))
		(while props
		  (overlay-put o (car props) (car (cdr props)))
		  (setq props (cdr (cdr props))))
		(setq o-list (cons o o-list))))
	  (setq start pos))
	o-list ))))

(defun vm-mime-default-type-from-filename (file)
  (let ((alist vm-mime-attachment-auto-type-alist)
	(case-fold-search t)
	(done nil))
    (while (and alist (not done))
      (if (string-match (car (car alist)) file)
	  (setq done t)
	(setq alist (cdr alist))))
    (and alist (cdr (car alist)))))

(defun vm-remove-mail-mode-header-separator ()
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward (concat "^" mail-header-separator "$") nil t)
	(progn
	  (delete-region (match-beginning 0) (match-end 0))
	   t )
      nil )))

(defun vm-add-mail-mode-header-separator ()
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^$" nil t)
	(replace-match mail-header-separator t t))))

(defun vm-mime-transfer-encode-region (encoding beg end crlf)
  (let ((case-fold-search t)
	(armor-from (and vm-mime-composition-armor-from-lines
			 (let ((case-fold-search nil))
			   (save-excursion
			     (goto-char beg)
			     (re-search-forward "^From " nil t)))))
	(armor-dot (let ((case-fold-search nil))
		     (save-excursion
		       (goto-char beg)
		       (re-search-forward "^\\.\\n" nil t)))))
    (cond ((string-match "^binary$" encoding)
	   (vm-mime-base64-encode-region beg end crlf)
	   (setq encoding "base64"))
	  ((and (not armor-from) (not armor-dot)
		(string-match "^7bit$" encoding)) t)
	  ((string-match "^base64$" encoding) t)
	  ((string-match "^quoted-printable$" encoding) t)
	  ((eq vm-mime-8bit-text-transfer-encoding 'quoted-printable)
	   (vm-mime-qp-encode-region beg end nil armor-from)
	   (setq encoding "quoted-printable"))
	  ((eq vm-mime-8bit-text-transfer-encoding 'base64)
	   (vm-mime-base64-encode-region beg end crlf)
	   (setq encoding "base64"))
	  (armor-from (vm-mime-qp-encode-region beg end nil armor-from))
	  ((eq vm-mime-8bit-text-transfer-encoding '8bit) t))
    encoding ))

(defun vm-mime-transfer-encode-layout (layout)
  (let ((list (vm-mm-layout-parts layout))
	(type (car (vm-mm-layout-type layout)))
	(encoding "7bit")
	(vm-mime-8bit-text-transfer-encoding
	 vm-mime-8bit-text-transfer-encoding))
  (cond ((vm-mime-composite-type-p type)
	 ;; MIME messages of type "message" and
	 ;; "multipart" are required to have a non-opaque
	 ;; content transfer encoding.  This means that
	 ;; if the user only wants to send out 7bit data,
	 ;; then any subpart that contains 8bit data must
	 ;; have an opaque (qp or base64) 8->7bit
	 ;; conversion performed on it so that the
	 ;; enclosing entity can use a non-opaque
	 ;; encoding.
	 ;;
	 ;; message/partial requires a "7bit" encoding so
	 ;; force 8->7 conversion in that case.
	 (cond ((memq vm-mime-8bit-text-transfer-encoding
		      '(quoted-printable base64))
		t)
	       ((vm-mime-types-match "message/partial" type)
		(setq vm-mime-8bit-text-transfer-encoding
		      'quoted-printable)))
	 (while list
	   (if (equal (vm-mime-transfer-encode-layout (car list)) "8bit")
	       (setq encoding "8bit"))
	   (setq list (cdr list))))
	(t
	 (if (and (vm-mime-types-match "message/partial" type)
		  (not (memq vm-mime-8bit-text-transfer-encoding
			     '(quoted-printable base64))))
		(setq vm-mime-8bit-text-transfer-encoding
		      'quoted-printable))
	 (setq encoding
	       (vm-mime-transfer-encode-region (vm-mm-layout-encoding layout)
					       (vm-mm-layout-body-start layout)
					       (vm-mm-layout-body-end layout)
					       (vm-mime-text-type-p layout)))))
  (save-excursion
    (save-restriction
      (goto-char (vm-mm-layout-header-start layout))
      (narrow-to-region (point) (vm-mm-layout-body-start layout))
      (vm-reorder-message-headers nil nil "Content-Transfer-Encoding:")
      (if (not (equal encoding "7bit"))
	  (insert "CONTENT-TRANSFER-ENCODING: " encoding "\n"))
      encoding ))))

(defun vm-mime-encode-composition ()
 "MIME encode the current mail composition buffer.
Attachment tags added to the buffer with vm-mime-attach-file are expanded
and the approriate content-type and boundary markup information is added."
  (interactive)
  (cond (vm-xemacs-mule-p
	 (vm-mime-xemacs-encode-composition))
	(vm-xemacs-p
	 (vm-mime-xemacs-encode-composition))
	(vm-fsfemacs-19-p
	 (vm-mime-fsfemacs-encode-composition))
	(t
	 (error "don't know how to MIME encode composition for %s"
		(emacs-version)))))

(defvar enriched-mode)

(defun vm-mime-xemacs-encode-composition ()
  (save-restriction
    (widen)
    (if (not (eq major-mode 'mail-mode))
	(error "Command must be used in a VM Mail mode buffer."))
    (or (null (vm-mail-mode-get-header-contents "MIME-Version:"))
	(error "Message is already MIME encoded."))
    (let ((8bit nil)
	  (just-one nil)
	  (boundary-positions nil)
	  (enriched (and (boundp 'enriched-mode) enriched-mode))
	  already-mimed layout e e-list boundary
	  type encoding charset params description disposition object
	  opoint-min)
      (mail-text)
      (setq e-list (extent-list nil (point) (point-max))
	    e-list (vm-delete (function
			       (lambda (e)
				 (extent-property e 'vm-mime-object)))
			      e-list t)
	    e-list (sort e-list (function
				 (lambda (e1 e2)
				   (< (extent-end-position e1)
				      (extent-end-position e2))))))
      ;; If there's just one attachment and no other readable
      ;; text in the buffer then make the message type just be
      ;; the attachment type rather than sending a multipart
      ;; message with one attachment
      (setq just-one (and (= (length e-list) 1)
			  (looking-at "[ \t\n]*")
			  (= (match-end 0)
			     (extent-start-position (car e-list)))
			  (save-excursion
			    (goto-char (extent-end-position (car e-list)))
			    (looking-at "[ \t\n]*\\'"))))
      (if (null e-list)
	  (progn
	    (narrow-to-region (point) (point-max))
	    ;; support enriched-mode for text/enriched composition
	    (if enriched
		(let ((enriched-initial-annotation ""))
		  (enriched-encode (point-min) (point-max))))
	    (setq charset (vm-determine-proper-charset (point-min)
						       (point-max)))
	    (if vm-xemacs-mule-p
		(encode-coding-region (point-min) (point-max)
				      buffer-file-coding-system))
	    (setq encoding (vm-determine-proper-content-transfer-encoding
			    (point-min)
			    (point-max))
		  encoding (vm-mime-transfer-encode-region encoding
							   (point-min)
							   (point-max)
							   t))
	    (widen)
	    (vm-remove-mail-mode-header-separator)
	    (goto-char (point-min))
	    (vm-reorder-message-headers
	     nil nil "\\(Content-Type:\\|Content-Transfer-Encoding\\|MIME-Version:\\)")
	    (insert "MIME-Version: 1.0\n")
	    (if enriched
		(insert "Content-Type: text/enriched; charset=" charset "\n")
	      (insert "Content-Type: text/plain; charset=" charset "\n"))
	    (insert "Content-Transfer-Encoding: " encoding "\n")
	    (vm-add-mail-mode-header-separator))
	(while e-list
	  (setq e (car e-list))
	  (if (or just-one (= (point) (extent-start-position e)))
	      nil
	    (narrow-to-region (point) (extent-start-position e))
	    (if enriched
		(let ((enriched-initial-annotation ""))
		  (enriched-encode (point-min) (point-max))))
	    (setq charset (vm-determine-proper-charset (point-min)
						       (point-max)))
	    (if vm-xemacs-mule-p
		(encode-coding-region (point-min) (point-max)
				      buffer-file-coding-system))
	    (setq encoding (vm-determine-proper-content-transfer-encoding
			    (point-min)
			    (point-max))
		  encoding (vm-mime-transfer-encode-region encoding
							   (point-min)
							   (point-max)
							   t))
	    (setq boundary-positions (cons (point-marker) boundary-positions))
	    (if enriched
		(insert "Content-Type: text/enriched; charset=" charset "\n")
	      (insert "Content-Type: text/plain; charset=" charset "\n"))
	    (insert "Content-Transfer-Encoding: " encoding "\n\n")
	    (widen))
	  (goto-char (extent-start-position e))
	  (narrow-to-region (point) (point))
	  (setq object (extent-property e 'vm-mime-object))
	  ;; insert the object
	  (cond ((bufferp object)
		 (insert-buffer-substring object))
		((stringp object)
		 (let ((coding-system-for-read 'no-conversion)
		       ;; don't let buffer-file-coding-system be changed
		       ;; by insert-file-contents-literally.  The
		       ;; value we bind to it to here isn't important.
		       (buffer-file-coding-system 'no-conversion))
		   (insert-file-contents-literally object))))
	  ;; gather information about the object from the extent.
	  (if (setq already-mimed (extent-property e 'vm-mime-encoded))
	      (setq layout (vm-mime-parse-entity
			    nil (list "text/plain" "charset=us-ascii")
			    "7bit")
		    type (or (extent-property e 'vm-mime-type)
			     (car (vm-mm-layout-type layout)))
		    params (or (extent-property e 'vm-mime-parameters)
			       (cdr (vm-mm-layout-qtype layout)))
		    description (extent-property e 'vm-mime-description)
		    disposition
		      (if (not
			   (equal
			    (car (extent-property e 'vm-mime-disposition))
			    "unspecified"))
			  (extent-property e 'vm-mime-disposition)
			(vm-mm-layout-qdisposition layout)))
	    (setq type (extent-property e 'vm-mime-type)
		  params (extent-property e 'vm-mime-parameters)
		  description (extent-property e 'vm-mime-description)
		  disposition
		    (if (not (equal
			      (car (extent-property e 'vm-mime-disposition))
			      "unspecified"))
			(extent-property e 'vm-mime-disposition)
		      nil)))
	  (cond ((vm-mime-types-match "text" type)
		 (setq encoding
		       (vm-determine-proper-content-transfer-encoding
			(if already-mimed
			    (vm-mm-layout-body-start layout)
			  (point-min))
			(point-max))
		       encoding (vm-mime-transfer-encode-region
				 encoding
				 (if already-mimed
				     (vm-mm-layout-body-start layout)
				   (point-min))
				 (point-max)
				 t))
		 (setq 8bit (or 8bit (equal encoding "8bit"))))
		((vm-mime-composite-type-p type)
		 (setq opoint-min (point-min))
		 (if (not already-mimed)
		     (setq layout (vm-mime-parse-entity
				   nil (list "text/plain" "charset=us-ascii")
				   "7bit")))
		 (setq encoding (vm-mime-transfer-encode-layout layout))
		 (setq 8bit (or 8bit (equal encoding "8bit")))
		 (goto-char (point-max))
		 (widen)
		 (narrow-to-region opoint-min (point)))
		(t
		 (vm-mime-base64-encode-region
		  (if already-mimed
		      (vm-mm-layout-body-start layout)
		    (point-min))
		  (point-max))
		 (setq encoding "base64")))
	  (if just-one
	      nil
	    (goto-char (point-min))
	    (setq boundary-positions (cons (point-marker) boundary-positions))
	    (if (not already-mimed)
		nil
	      ;; trim headers
	      (vm-reorder-message-headers
	       nil (nconc (list "Content-Disposition:" "Content-ID:")
			  (if description
			      (list "Content-Description:")
			    nil))
	       nil)
	      ;; remove header/text separator
	      (goto-char (1- (vm-mm-layout-body-start layout)))
	      (if (looking-at "\n")
		  (delete-char 1)))
	    (insert "Content-Type: " type)
	    (if params
		(if vm-mime-avoid-folding-content-type
		    (insert "; " (mapconcat 'identity params "; ") "\n")
		  (insert ";\n\t" (mapconcat 'identity params ";\n\t") "\n"))
	      (insert "\n"))
	    (and description
		 (insert "Content-Description: " description "\n"))
	    (if disposition
		(progn
		  (insert "Content-Disposition: " (car disposition))
		  (if (cdr disposition)
		      (insert ";\n\t" (mapconcat 'identity
						 (cdr disposition)
						 ";\n\t")))
		  (insert "\n")))
	    (insert "Content-Transfer-Encoding: " encoding "\n\n"))
	  (goto-char (point-max))
	  (widen)
	  (save-excursion
	    (goto-char (extent-start-position e))
	    (vm-assert (looking-at "\\[ATTACHMENT")))
	  (delete-region (extent-start-position e)
			 (extent-end-position e))
	  (detach-extent e)
	  (if (looking-at "\n")
	      (delete-char 1))
	  (setq e-list (cdr e-list)))
	;; handle the remaining chunk of text after the last
	;; extent, if any.
	(if (or just-one (= (point) (point-max)))
	    nil
	  (if enriched
	      (let ((enriched-initial-annotation ""))
		(enriched-encode (point) (point-max))))
	  (setq charset (vm-determine-proper-charset (point)
						     (point-max)))
	  (if vm-xemacs-mule-p
	      (encode-coding-region (point) (point-max)
				    buffer-file-coding-system))
	  (setq encoding (vm-determine-proper-content-transfer-encoding
			  (point)
			  (point-max))
		encoding (vm-mime-transfer-encode-region encoding
							 (point)
							 (point-max)
							 t))
	  (setq 8bit (or 8bit (equal encoding "8bit")))
	  (setq boundary-positions (cons (point-marker) boundary-positions))
	  (if enriched
	      (insert "Content-Type: text/enriched; charset=" charset "\n")
	    (insert "Content-Type: text/plain; charset=" charset "\n"))
	  (insert "Content-Transfer-Encoding: " encoding "\n\n")
	  (goto-char (point-max)))
	(setq boundary (vm-mime-make-multipart-boundary))
	(mail-text)
	(while (re-search-forward (concat "^--"
					  (regexp-quote boundary)
					  "\\(--\\)?$")
				  nil t)
	  (setq boundary (vm-mime-make-multipart-boundary))
	  (mail-text))
	(goto-char (point-max))
	(or just-one (insert "\n--" boundary "--\n"))
	(while boundary-positions
	  (goto-char (car boundary-positions))
	  (insert "\n--" boundary "\n")
	  (setq boundary-positions (cdr boundary-positions)))
	(if (and just-one already-mimed)
	    (progn
	      (goto-char (vm-mm-layout-header-start layout))
	      ;; trim headers
	      (vm-reorder-message-headers
	       nil '("Content-Description:" "Content-ID:") nil)
	      ;; remove header/text separator
	      (goto-char (1- (vm-mm-layout-body-start layout)))
	      (if (looking-at "\n")
		  (delete-char 1))
	      ;; copy remainder to enclosing entity's header section
	      (insert-buffer-substring (current-buffer)
				       (vm-mm-layout-header-start layout)
				       (vm-mm-layout-body-start layout))
	      (delete-region (vm-mm-layout-header-start layout)
			     (vm-mm-layout-body-start layout))))
	(goto-char (point-min))
	(vm-remove-mail-mode-header-separator)
	(vm-reorder-message-headers
	 nil nil "\\(Content-Type:\\|MIME-Version:\\|Content-Transfer-Encoding\\)")
	(vm-add-mail-mode-header-separator)
	(insert "MIME-Version: 1.0\n")
	(if (not just-one)
	    (insert (if vm-mime-avoid-folding-content-type
			"Content-Type: multipart/mixed; boundary=\""
		      "Content-Type: multipart/mixed;\n\tboundary=\"")
		    boundary "\"\n")
	  (insert "Content-Type: " type)
	  (if params
	      (if vm-mime-avoid-folding-content-type
		  (insert "; " (mapconcat 'identity params "; ") "\n")
		(insert ";\n\t" (mapconcat 'identity params ";\n\t") "\n"))
	    (insert "\n")))
	(if just-one
	    (and description
		 (insert "Content-Description: " description "\n")))
	(if (and just-one disposition)
	    (progn
	      (insert "Content-Disposition: " (car disposition))
	      (if (cdr disposition)
		  (if vm-mime-avoid-folding-content-type
		      (insert "; " (mapconcat 'identity (cdr disposition) "; ")
			      "\n")
		    (insert ";\n\t" (mapconcat 'identity (cdr disposition)
					       ";\n\t")))
		(insert "\n"))))
	(if just-one
	    (insert "Content-Transfer-Encoding: " encoding "\n")
	  (if 8bit
	      (insert "Content-Transfer-Encoding: 8bit\n")
	    (insert "Content-Transfer-Encoding: 7bit\n")))))))

(defun vm-mime-fsfemacs-encode-composition ()
  (save-restriction
    (widen)
    (if (not (eq major-mode 'mail-mode))
	(error "Command must be used in a VM Mail mode buffer."))
    (or (null (vm-mail-mode-get-header-contents "MIME-Version:"))
	(error "Message is already MIME encoded."))
    (let ((8bit nil)
	  (just-one nil)
	  (boundary-positions nil)
	  (enriched (and (boundp 'enriched-mode) enriched-mode))
	  already-mimed layout o o-list boundary
	  type encoding charset params description disposition object
	  opoint-min)
      (mail-text)
      (setq o-list (vm-mime-fake-attachment-overlays (point) (point-max))
	    o-list (vm-delete (function
			       (lambda (o)
				 (overlay-get o 'vm-mime-object)))
			      o-list t)
	    o-list (sort o-list (function
				 (lambda (e1 e2)
				   (< (overlay-end e1)
				      (overlay-end e2))))))
      ;; If there's just one attachment and no other readable
      ;; text in the buffer then make the message type just be
      ;; the attachment type rather than sending a multipart
      ;; message with one attachment
      (setq just-one (and (= (length o-list) 1)
			  (looking-at "[ \t\n]*")
			  (= (match-end 0)
			     (overlay-start (car o-list)))
			  (save-excursion
			    (goto-char (overlay-end (car o-list)))
			    (looking-at "[ \t\n]*\\'"))))
      (if (null o-list)
	  (progn
	    (narrow-to-region (point) (point-max))
	    ;; support enriched-mode for text/enriched composition
	    (if enriched
		(let ((enriched-initial-annotation ""))
		  (enriched-encode (point-min) (point-max))))
	    (setq charset (vm-determine-proper-charset (point-min)
						       (point-max)))
	    (setq encoding (vm-determine-proper-content-transfer-encoding
			    (point-min)
			    (point-max))
		  encoding (vm-mime-transfer-encode-region encoding
							   (point-min)
							   (point-max)
							   t))
	    (widen)
	    (vm-remove-mail-mode-header-separator)
	    (goto-char (point-min))
	    (vm-reorder-message-headers
	     nil nil "\\(Content-Type:\\|Content-Transfer-Encoding\\|MIME-Version:\\)")
	    (insert "MIME-Version: 1.0\n")
	    (if enriched
		(insert "Content-Type: text/enriched; charset=" charset "\n")
	      (insert "Content-Type: text/plain; charset=" charset "\n"))
	    (insert "Content-Transfer-Encoding: " encoding "\n")
	    (vm-add-mail-mode-header-separator))
	(while o-list
	  (setq o (car o-list))
	  (if (or just-one (= (point) (overlay-start o)))
	      nil
	    (narrow-to-region (point) (overlay-start o))
	    ;; support enriched-mode for text/enriched composition
	    (if enriched
		(let ((enriched-initial-annotation ""))
		  (save-excursion
		    ;; insert/delete trick needed to avoid
		    ;; enriched-mode tags from seeping into the
		    ;; attachment overlays.  I really wish
		    ;; front-advance / rear-advance overlay
		    ;; endpoint properties actually worked.
		    (goto-char (point-max))
		    (insert-before-markers "\n")
		    (enriched-encode (point-min) (1- (point)))
		    (goto-char (point-max))
		    (delete-char -1)
		    '(goto-char (point-min)))))
	    (setq charset (vm-determine-proper-charset (point-min)
						       (point-max)))
	    (setq encoding (vm-determine-proper-content-transfer-encoding
			    (point-min)
			    (point-max))
		  encoding (vm-mime-transfer-encode-region encoding
							   (point-min)
							   (point-max)
							   t))
	    (setq boundary-positions (cons (point-marker) boundary-positions))
	    (if enriched
		(insert "Content-Type: text/enriched; charset=" charset "\n")
	      (insert "Content-Type: text/plain; charset=" charset "\n"))
	    (insert "Content-Transfer-Encoding: " encoding "\n\n")
	    (widen))
	  (goto-char (overlay-start o))
	  (narrow-to-region (point) (point))
	  (setq object (overlay-get o 'vm-mime-object))
	  ;; insert the object
	  (cond ((bufferp object)
		 ;; as of FSF Emacs 19.34, even with the hooks
		 ;; we've attached to the attachment overlays,
		 ;; text STILL can be inserted into them when
		 ;; font-lock is enabled.  Explaining why is
		 ;; beyond the scope of this comment and I
		 ;; don't know the answer anyway.  This works
		 ;; to prevent it.
		 (insert-before-markers " ")
		 (forward-char -1)
		 (insert-buffer-substring object)
		 (delete-char 1))
		((stringp object)
		 (insert-before-markers " ")
		 (forward-char -1)
		 (insert-file-contents object)
		 (goto-char (point-max))
		 (delete-char -1)))
	  ;; gather information about the object from the extent.
	  (if (setq already-mimed (overlay-get o 'vm-mime-encoded))
	      (setq layout (vm-mime-parse-entity
			    nil (list "text/plain" "charset=us-ascii")
			    "7bit")
		    type (or (overlay-get o 'vm-mime-type)
			     (car (vm-mm-layout-type layout)))
		    params (or (overlay-get o 'vm-mime-parameters)
			       (cdr (vm-mm-layout-qtype layout)))
		    description (overlay-get o 'vm-mime-description)
		    disposition
		      (if (not
			   (equal
			    (car (overlay-get o 'vm-mime-disposition))
			    "unspecified"))
			  (overlay-get o 'vm-mime-disposition)
			(vm-mm-layout-qdisposition layout)))
	    (setq type (overlay-get o 'vm-mime-type)
		  params (overlay-get o 'vm-mime-parameters)
		  description (overlay-get o 'vm-mime-description)
		  disposition
		    (if (not (equal
			      (car (overlay-get o 'vm-mime-disposition))
			      "unspecified"))
			(overlay-get o 'vm-mime-disposition)
		      nil)))
	  (cond ((vm-mime-types-match "text" type)
		 (setq encoding
		       (vm-determine-proper-content-transfer-encoding
			(if already-mimed
			    (vm-mm-layout-body-start layout)
			  (point-min))
			(point-max))
		       encoding (vm-mime-transfer-encode-region
				 encoding
				 (if already-mimed
				     (vm-mm-layout-body-start layout)
				   (point-min))
				 (point-max)
				 t))
		 (setq 8bit (or 8bit (equal encoding "8bit"))))
		((vm-mime-composite-type-p type)
		 (setq opoint-min (point-min))
		 (if (not already-mimed)
		     (setq layout (vm-mime-parse-entity
				   nil (list "text/plain" "charset=us-ascii")
				   "7bit")))
		 (setq encoding (vm-mime-transfer-encode-layout layout))
		 (setq 8bit (or 8bit (equal encoding "8bit")))
		 (goto-char (point-max))
		 (widen)
		 (narrow-to-region opoint-min (point)))
		(t
		 (vm-mime-base64-encode-region
		  (if already-mimed
		      (vm-mm-layout-body-start layout)
		    (point-min))
		  (point-max))
		 (setq encoding "base64")))
	  (if just-one
	      nil
	    (goto-char (point-min))
	    (setq boundary-positions (cons (point-marker) boundary-positions))
	    (if (not already-mimed)
		nil
	      ;; trim headers
	      (vm-reorder-message-headers
	       nil (nconc (list "Content-Disposition:" "Content-ID:")
			  (if description
			      (list "Content-Description:")
			    nil))
	       nil)
	      ;; remove header/text separator
	      (goto-char (1- (vm-mm-layout-body-start layout)))
	      (if (looking-at "\n")
		  (delete-char 1)))
	    (insert "Content-Type: " type)
	    (if params
		(if vm-mime-avoid-folding-content-type
		    (insert "; " (mapconcat 'identity params "; ") "\n")
		  (insert ";\n\t" (mapconcat 'identity params ";\n\t") "\n"))
	      (insert "\n"))
	    (and description
		 (insert "Content-Description: " description "\n"))
	    (if disposition
		(progn
		  (insert "Content-Disposition: " (car disposition))
		  (if (cdr disposition)
		      (insert ";\n\t" (mapconcat 'identity
						 (cdr disposition)
						 ";\n\t")))
		  (insert "\n")))
	    (insert "Content-Transfer-Encoding: " encoding "\n\n"))
	  (goto-char (point-max))
	  (widen)
	  (save-excursion
	    (goto-char (overlay-start o))
	    (vm-assert (looking-at "\\[ATTACHMENT")))
	  (delete-region (overlay-start o)
			 (overlay-end o))
	  (delete-overlay o)
	  (if (looking-at "\n")
	      (delete-char 1))
	  (setq o-list (cdr o-list)))
	;; handle the remaining chunk of text after the last
	;; extent, if any.
	(if (or just-one (= (point) (point-max)))
	    nil
	  ;; support enriched-mode for text/enriched composition
	  (if enriched
	      (let ((enriched-initial-annotation ""))
		(enriched-encode (point) (point-max))))
	  (setq charset (vm-determine-proper-charset (point)
						     (point-max)))
	  (setq encoding (vm-determine-proper-content-transfer-encoding
			  (point)
			  (point-max))
		encoding (vm-mime-transfer-encode-region encoding
							 (point)
							 (point-max)
							 t))
	  (setq 8bit (or 8bit (equal encoding "8bit")))
	  (setq boundary-positions (cons (point-marker) boundary-positions))
	  (if enriched
	      (insert "Content-Type: text/enriched; charset=" charset "\n")
	    (insert "Content-Type: text/plain; charset=" charset "\n"))
	  (insert "Content-Transfer-Encoding: " encoding "\n\n")
	  (goto-char (point-max)))
	(setq boundary (vm-mime-make-multipart-boundary))
	(mail-text)
	(while (re-search-forward (concat "^--"
					  (regexp-quote boundary)
					  "\\(--\\)?$")
				  nil t)
	  (setq boundary (vm-mime-make-multipart-boundary))
	  (mail-text))
	(goto-char (point-max))
	(or just-one (insert "\n--" boundary "--\n"))
	(while boundary-positions
	  (goto-char (car boundary-positions))
	  (insert "\n--" boundary "\n")
	  (setq boundary-positions (cdr boundary-positions)))
	(if (and just-one already-mimed)
	    (progn
	      (goto-char (vm-mm-layout-header-start layout))
	      ;; trim headers
	      (vm-reorder-message-headers
	       nil '("Content-Description:" "Content-ID:") nil)
	      ;; remove header/text separator
	      (goto-char (1- (vm-mm-layout-body-start layout)))
	      (if (looking-at "\n")
		  (delete-char 1))
	      ;; copy remainder to enclosing entity's header section
	      (insert-buffer-substring (current-buffer)
				       (vm-mm-layout-header-start layout)
				       (vm-mm-layout-body-start layout))
	      (delete-region (vm-mm-layout-header-start layout)
			     (vm-mm-layout-body-start layout))))
	(goto-char (point-min))
	(vm-remove-mail-mode-header-separator)
	(vm-reorder-message-headers
	 nil nil "\\(Content-Type:\\|MIME-Version:\\|Content-Transfer-Encoding\\)")
	(vm-add-mail-mode-header-separator)
	(insert "MIME-Version: 1.0\n")
	(if (not just-one)
	    (insert (if vm-mime-avoid-folding-content-type
			"Content-Type: multipart/mixed; boundary=\""
		      "Content-Type: multipart/mixed;\n\tboundary=\"")
		    boundary "\"\n")
	  (insert "Content-Type: " type)
	  (if params
	      (if vm-mime-avoid-folding-content-type
		  (insert "; " (mapconcat 'identity params "; ") "\n")
		(insert ";\n\t" (mapconcat 'identity params ";\n\t") "\n"))
	    (insert "\n")))
	(if just-one
	    (and description
		 (insert "Content-Description: " description "\n")))
	(if (and just-one disposition)
	    (progn
	      (insert "Content-Disposition: " (car disposition))
	      (if (cdr disposition)
		  (if vm-mime-avoid-folding-content-type
		      (insert "; " (mapconcat 'identity (cdr disposition) "; ")
			      "\n")
		    (insert ";\n\t" (mapconcat 'identity (cdr disposition)
					       ";\n\t")))
		(insert "\n"))))
	(if just-one
	    (insert "Content-Transfer-Encoding: " encoding "\n")
	  (if 8bit
	      (insert "Content-Transfer-Encoding: 8bit\n")
	    (insert "Content-Transfer-Encoding: 7bit\n")))))))

(defun vm-mime-fragment-composition (size)
  (save-restriction
    (widen)
    (message "Fragmenting message...")
    (let ((buffers nil)
	  (id (vm-mime-make-multipart-boundary))
	  (n 1)
	  (the-end nil)
	  b header-start header-end master-buffer start end)
      (vm-remove-mail-mode-header-separator)
      ;; message/partial must have "7bit" content transfer
      ;; encoding, so force everything to be encoded for
      ;; 7bit transmission.
      (let ((vm-mime-8bit-text-transfer-encoding
	     (if (eq vm-mime-8bit-text-transfer-encoding '8bit)
		 'quoted-printable
	       vm-mime-8bit-text-transfer-encoding)))
	(vm-mime-transfer-encode-layout
	 (vm-mime-parse-entity nil (list "text/plain" "charset=us-ascii")
			       "7bit")))
      (goto-char (point-min))
      (setq header-start (point))
      (search-forward "\n\n")
      (setq header-end (1- (point)))
      (setq master-buffer (current-buffer))
      (goto-char (point-min))
      (setq start (point))
      (while (not (eobp))
	(condition-case nil
	    (progn
	      (forward-char (max (- size 150) 2000))
	      (beginning-of-line))
	  (end-of-buffer (setq the-end t)))
	(setq end (point))
	(setq b (generate-new-buffer (concat (buffer-name) " part "
					     (int-to-string n))))
	(setq buffers (cons b buffers))
	(set-buffer b)
	(make-local-variable 'vm-send-using-mime)
	(setq vm-send-using-mime nil)
	(insert-buffer-substring master-buffer header-start header-end)
	(goto-char (point-min))
	(vm-reorder-message-headers nil nil
         "\\(Content-Type:\\|MIME-Version:\\|Content-Transfer-Encoding\\)")
	(insert "MIME-Version: 1.0\n")
	(insert (format
		 (if vm-mime-avoid-folding-content-type
		     "Content-Type: message/partial; id=%s; number=%d"
		   "Content-Type: message/partial;\n\tid=%s;\n\tnumber=%d")
		 id n))
	(if the-end
	    (if vm-mime-avoid-folding-content-type
		(insert (format "; total=%d\n" n))
	      (insert (format ";\n\ttotal=%d\n" n)))
	  (insert "\n"))
	(insert "Content-Transfer-Encoding: 7bit\n")
	(goto-char (point-max))
	(insert mail-header-separator "\n")
	(insert-buffer-substring master-buffer start end)
	(vm-increment n)
	(set-buffer master-buffer)
	(setq start (point)))
      (vm-add-mail-mode-header-separator)
      (message "Fragmenting message... done")
      (nreverse buffers))))

(defun vm-mime-preview-composition ()
  "Show how the current composition buffer might be displayed
in a MIME-aware mail reader.  VM copies and encodes the current
mail composition buffer and displays it as a mail folder.
Type `q' to quit this temp folder and return to composing your
message."
  (interactive)
  (if (not (eq major-mode 'mail-mode))
      (error "Command must be used in a VM Mail mode buffer."))
  (let ((temp-buffer nil)
	(mail-buffer (current-buffer))
	(enriched (and (boundp 'enriched-mode) enriched-mode))
	e-list)
    (unwind-protect
	(progn
	  (setq temp-buffer (generate-new-buffer "composition preview"))
	  (set-buffer temp-buffer)
	  ;; so vm-mime-xxxx-encode-composition won't complain
	  (setq major-mode 'mail-mode)
	  (set (make-local-variable 'enriched-mode) enriched)
	  (vm-insert-region-from-buffer mail-buffer)
	  (goto-char (point-min))
	  (or (vm-mail-mode-get-header-contents "From")
	      (insert "From: " (user-login-name) "\n"))
	  (or (vm-mail-mode-get-header-contents "Message-ID")
	      (insert "Message-ID: <fake@fake.fake>\n"))
	  (or (vm-mail-mode-get-header-contents "Date")
	      (insert "Date: "
		      (format-time-string "%a, %d %b %Y %H%M%S %Z"
					  (current-time))
		      "\n"))
	  (and vm-send-using-mime
	       (null (vm-mail-mode-get-header-contents "MIME-Version:"))
	       (vm-mime-encode-composition))
	  (vm-remove-mail-mode-header-separator)
	  (goto-char (point-min))
	  (insert (vm-leading-message-separator 'From_))
	  (goto-char (point-max))
	  (insert (vm-trailing-message-separator 'From_))
	  (set-buffer-modified-p nil)
	  ;; point of no return, don't kill it if the user quits
	  (setq temp-buffer nil)
	  (let ((vm-auto-decode-mime-messages t)
		(vm-auto-displayed-mime-content-types t))
	    (vm-save-buffer-excursion
	     (vm-goto-new-folder-frame-maybe 'folder)
	     (vm-mode)))
	  (message
	   (substitute-command-keys
	    "Type \\[vm-quit] to continue composing your message"))
	  ;; temp buffer, don't offer to save it.
	  (setq buffer-offer-save nil)
	  (vm-display (or vm-presentation-buffer (current-buffer)) t
		      (list this-command) '(vm-mode startup)))
      (and temp-buffer (kill-buffer temp-buffer)))))

(defun vm-mime-composite-type-p (type)
  (or (and (vm-mime-types-match "message" type)
	   (not (vm-mime-types-match "message/partial" type))
	   (not (vm-mime-types-match "message/external-body" type)))
      (vm-mime-types-match "multipart" type)))

;; Unused currrently.
;;
;;(defun vm-mime-map-atomic-layouts (function list)
;;  (while list
;;    (if (vm-mime-composite-type-p (car (vm-mm-layout-type (car list))))
;;	(vm-mime-map-atomic-layouts function (vm-mm-layout-parts (car list)))
;;      (funcall function (car list)))
;;    (setq list (cdr list))))
