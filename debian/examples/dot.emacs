;-*-emacs-lisp-*-
;
; Various mail-related things I put in my .emacs file
;

; use abbrevs in (Resent-)?(To|Cc|Bcc): lines

(add-hook 'mail-setup-hook 'mail-abbrevs-setup)

; load my address book

(load-file "~/.abbrevs")

; set my email address

(setq user-mail-address "richard@elmail.co.uk")

; set quoting character for replies

(setq mail-yank-prefix ">")

; set default Fcc folder

(setq mail-archive-file-name "~/mail/sent-mail")

; see /usr/doc/examples/vm/README.hilit19 for what's going on here

(cond (window-system
       (setq hilit-mode-enable-list  '(not text-mode)
	     hilit-background-mode   'light
	     hilit-inhibit-hooks     nil
	     hilit-inhibit-rebinding nil)
       (require 'hilit19)
       (add-hook 'vm-summary-pointer-update-hook 'hilit-rehighlight-buffer)
       (add-hook 'vm-select-message-hook 'hilit-rehighlight-buffer)
       (hilit-translate comment 'firebrick-bold)
       (hilit-set-mode-patterns
	'outline-mode
	'(("^\*.*$" nil defun)
	  ))
       ))
;; This will return a list of all the buffers in VM mode:
; (let ((buffers (buffer-list))
;       (vm-buffers '()))
;   (while buffers
;     (if (eq (save-excursion
; 	      (set-buffer (car buffers))
; 	      major-mode)
; 	    'vm-mode)
; 	(setq vm-buffers
; 	      (cons (car buffers) vm-buffers)))
;     (setq buffers (cdr buffers)))
;   (nreverse vm-buffers))
