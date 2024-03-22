;;; conn-embark --- Conn embark extension -*- lexical-binding: t -*-
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.
;;
;;; Code:

(require 'conn-mode)
(require 'embark)

(defun conn-complete-keys--get-bindings (prefix map)
  (let ((prefix-map (if (= 0 (seq-length prefix))
                        map
                      (keymap-lookup map (key-description prefix))))
        binds)
    (cond
     ((or (null prefix-map) (numberp prefix-map)))
     ((keymapp prefix-map)
      (map-keymap
       (lambda (key def)
         (cond
          ((and (numberp key)
                (= key 27)
                (keymapp def))
           (map-keymap
            (lambda (key2 def2)
              (unless (memq def (list 'undefined 'self-insert-command 'digit-argument
                                      'negative-argument 'embark-keymap-help nil))
                (push (cons (vconcat (vector key key2)) def2) binds)))
            def))
          (t (push (cons (vector key) def) binds))))
       (keymap-canonicalize prefix-map))))
    (nreverse binds)))

;; `embark--formatted-bindings' almost
(defun conn-complete-keys--formatted-bindings (map)
  "Return the formatted keybinding of KEYMAP.
The keybindings are returned in their order of appearance.
If NESTED is non-nil subkeymaps are not flattened."
  (let* ((commands
          (cl-loop for (key . def) in map
                   for name = (embark--command-name def)
                   for cmd = (keymap--menu-item-binding def)
                   unless (memq cmd '(nil embark-keymap-help
                                          negative-argument
                                          digit-argument
                                          self-insert-command
                                          undefined))
                   collect (list name cmd key
                                 (concat
                                  (if (eq (car-safe def) 'menu-item)
                                      "menu-item"
                                    (key-description key))))))
         (width (cl-loop for (_name _cmd _key desc) in commands
                         maximize (length desc)))
         (default)
         (candidates
          (cl-loop for item in commands
                   for (name cmd key desc) = item
                   for desc-rep =
                   (concat
                    (propertize desc 'face 'embark-keybinding)
                    (and (embark--action-repeatable-p cmd)
                         embark-keybinding-repeat))
                   for formatted =
                   (propertize
                    (concat desc-rep
                            (make-string (- width (length desc-rep) -1) ?\s)
                            name)
                    'embark-command cmd)
                   ;; when (equal key [13]) do (setq default formatted)
                   collect (cons formatted item))))
    candidates))

(defun conn-complete-keys--up ()
  (interactive)
  (delete-minibuffer-contents)
  (exit-minibuffer))

(defun conn--active-maps (maps)
  (pcase (car maps)
    ('keymap maps)
    ((pred consp)
     (seq-mapcat #'conn--active-maps maps))
    ((and (pred boundp) (pred symbol-value))
     (conn--active-maps (cdr maps)))))

(defcustom conn-complete-keys-toggle-display-keys
  "M-j"
  "Keys bound in `conn-complete-keys' to toggle between tree and flat display.
Value must satisfy `key-valid-p'."
  :type 'string)

(defun conn-complete-keys (prefix map)
  "Complete key sequence beginning with current keys using `completing-read'.
When called via \\[conn-complete-keys] and with a prefix argument restrict completion
to key bindings defined by `conn-mode'. `conn-complete-keys-toggle-display-keys' toggles
between a tree view and the embark flat view. In the default tree view DEL will navigate
up out of a keymap."
  (interactive
   (let* ((prefix (seq-subseq (this-command-keys-vector) 0 -1)))
     (list prefix
           (if current-prefix-arg
               (make-composed-keymap
                (conn--active-maps (list conn--transition-maps
                                         conn--local-mode-maps
                                         conn--major-mode-maps
                                         conn--local-maps
                                         conn--aux-maps
                                         conn--state-maps
                                         conn-mode-map)))
             (make-composed-keymap (current-active-maps t))))))
  (let* ((tree (lambda ()
                 (interactive)
                 (embark--quit-and-run
                  (lambda ()
                    (conn-complete-keys prefix map)))))
         (flat (lambda ()
                 (interactive)
                 (embark--quit-and-run
                  (lambda ()
                    (minibuffer-with-setup-hook
                        (lambda ()
                          (use-local-map
                           (define-keymap
                             :parent (current-local-map)
                             conn-complete-keys-toggle-display-keys tree)))
                      (embark-bindings-in-keymap
                       (if (seq-empty-p prefix)
                           map
                         (keymap-lookup map (key-description prefix)))))))))
         prompt choice cand)
    (while t
      (setq cand (conn-complete-keys--formatted-bindings
                  (conn-complete-keys--get-bindings prefix map))
            prompt (if (> (length prefix) 0)
                       (concat "Command: " (key-description prefix) "- ")
                     "Command: ")
            choice (minibuffer-with-setup-hook
                       (:append
                        (lambda ()
                          (use-local-map
                           (define-keymap
                             :parent (current-local-map)
                             "M-<backspace>" 'conn-complete-keys--up
                             "M-DEL" 'conn-complete-keys--up
                             conn-complete-keys-toggle-display-keys flat))))
                     (completing-read
                      prompt
                      (lambda (string predicate action)
                        (if (eq action 'metadata)
                            `(metadata (display-sort-function . ,(lambda (c) (sort c 'string<)))
                                       (category . embark-keybinding))
                          (complete-with-action action cand string predicate)))
                      nil nil)))
      (pcase (assoc choice cand)
        ('nil
         (if (not (string= choice ""))
             (cl-return-from conn-complete-keys)
           (setq prefix (ignore-errors (seq-subseq prefix 0 -1)))
           (when (and (> (length prefix) 0)
                      (= 27 (elt prefix (1- (length prefix)))))
             ;; This was a meta bind so we need to
             ;; remove the ESC key as well
             (setq prefix (ignore-errors (seq-subseq prefix 0 -1))))))
        (`(,_ ,_ ,cmd ,key ,_)
         (if (keymapp cmd)
             (setq prefix (vconcat prefix key))
           (cl-return-from conn-complete-keys (call-interactively cmd))))))))

(conn-define-extension conn-complete-keys-prefix-help-command
  (if conn-complete-keys-prefix-help-command
      (progn
        (setq conn-complete-keys--prefix-cmd-backup prefix-help-command)
        (setq prefix-help-command 'conn-complete-keys))
    (when (eq prefix-help-command 'conn-complete-keys)
      (setq prefix-help-command conn-complete-keys--prefix-cmd-backup))))

(keymap-set conn-mode-map "M-S-<iso-lefttab>" 'conn-complete-keys)

(setf (alist-get 'conn-replace-region-substring embark-target-injection-hooks)
      (list #'embark--ignore-target))

(add-to-list 'embark-target-injection-hooks
             '(conn-insert-pair embark--ignore-target))
(add-to-list 'embark-target-injection-hooks
             '(conn-change-pair embark--ignore-target))

(defun conn--embark-target-region ()
  (let ((start (region-beginning))
        (end (region-end)))
    `(region ,(buffer-substring start end) . (,start . ,end))))

(defun conn-embark-region ()
  (interactive)
  (let* ((mark-even-if-inactive t)
         (embark-target-finders
             (cons 'conn--embark-target-region
                   (remq 'embark-target-active-region
                         embark-target-finders))))
    (embark-act)))

(defun conn-embark-replace-region (string)
  (interactive (list (read-string "Replace with: ")))
  (delete-region (region-beginning) (region-end))
  (insert string))

(provide 'conn-embark)