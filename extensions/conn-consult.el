;;; conn-consult.el --- Conn consult extension -*- lexical-binding: t -*-
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
(require 'consult)

(defmacro conn--each-thing (thing beg end &rest body)
  "Iterate over each THING in buffer.

THING BEG and END are bound in BODY."
  (declare (indent 3))
  (cl-with-gensyms (max bounds)
    `(save-excursion
       (let ((,max (point-max)))
         (goto-char (point-min))
         (unless (bounds-of-thing-at-point ,thing)
           (forward-thing ,thing 1))
         (while (< (point) ,max)
           (let* ((,bounds (bounds-of-thing-at-point ,thing))
                  (,beg (car ,bounds))
                  (,end (cdr ,bounds)))
             ,@body
             (forward-thing ,thing 1)))))))

(defun conn--thing-candidates (thing)
  "Return list of thing candidates."
  (consult--forbid-minibuffer)
  (consult--fontify-all)
  (let* ((buffer (current-buffer))
         default-cand candidates)
    (conn--each-thing thing beg end
      (let ((line (line-number-at-pos)))
        (push (consult--location-candidate
               (consult--buffer-substring beg end)
               (cons buffer beg) line line)
              candidates))
      (when (not default-cand)
        (setq default-cand candidates)))
    (unless candidates
      (user-error "No lines"))
    (nreverse candidates)))

(defun conn-consult-thing (&optional initial thing start)
  "Search for a matching top-level THING."
  (interactive (list nil
                     (intern
                      (completing-read
                       (format "Thing: ")
                       (conn--things 'conn--defined-thing-p) nil nil nil
                       'conn-thing-history))
                     (not (not current-prefix-arg))))
  (let* ((candidates (consult--slow-operation "Collecting things..."
                       (conn--thing-candidates thing))))
    (consult--read
     candidates
     :prompt "Goto thing: "
     :annotate (consult--line-prefix)
     :category 'consult-location
     :sort nil
     :require-match t
     ;; Always add last isearch string to future history
     :add-history (list (thing-at-point 'symbol) isearch-string)
     ;; :history '(:input consult--line-history)
     :lookup #'consult--line-match
     :default (car candidates)
     ;; Add isearch-string as initial input if starting from isearch
     :initial (or initial
                  (and isearch-mode
                       (prog1 isearch-string (isearch-done))))
     :state (consult--location-state candidates))))

(defun conn-consult-page ()
    "Search for a page."
    (interactive)
    (let* ((candidates (consult--slow-operation
                           "Collecting headings..."
                         (consult--page-candidates))))
      (consult--read
       candidates
       :prompt "Go to page: "
       :annotate (consult--line-prefix)
       :category 'consult-location
       :sort nil
       :require-match t
       :lookup #'consult--line-match
       :history '(:input consult--line-history)
       :add-history (thing-at-point 'symbol)
       :state (consult--location-state candidates))))

(defun conn-dot-consult-location-candidate (cand)
  (let ((marker (car (consult--get-location cand))))
    (with-current-buffer (marker-buffer marker)
      (goto-char marker)
      (unless (bolp) (beginning-of-line))
      (conn--create-dots (cons (point) (progn (end-of-line) (point)))))))

(defun conn-dot-consult-grep-candidate (cand)
  (let ((marker (car (consult--grep-position cand))))
    (with-current-buffer (marker-buffer marker)
      (goto-char marker)
      (unless (bolp) (beginning-of-line))
      (conn--create-dots (cons (point) (progn (end-of-line) (point)))))))

(defun conn-consult-ripgrep-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-ripgrep nil (buffer-substring-no-properties beg end)))

(defun conn-consult-line-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-line (buffer-substring-no-properties beg end)))

(defun conn-consult-line-multi-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-line-multi nil (buffer-substring-no-properties beg end)))

(defun conn-consult-locate-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-locate (buffer-substring-no-properties beg end)))

(defun conn-consult-git-grep-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-git-grep nil (buffer-substring-no-properties beg end)))

(defun conn-consult-find-region (beg end)
  (interactive (list (region-beginning)
                     (region-end)))
  (consult-find nil (buffer-substring-no-properties beg end)))

(defvar-keymap conn-consult-region-search-map
  :prefix 'conn-consult-region-search-map
  "l" 'conn-consult-line-region
  "L" 'conn-consult-line-multi-region
  "F" 'conn-consult-locate-region
  "g" 'conn-consult-git-grep-region
  "f" 'conn-consult-find-region
  "r" 'conn-consult-ripgrep-region)

(keymap-set conn-region-map "l" 'conn-consult-line-region)
(keymap-set conn-region-map "r" 'conn-consult-ripgrep-region)
(keymap-set conn-region-map "h" 'conn-consult-region-search-map)
(keymap-set conn-mode-map "M-s t" 'conn-consult-thing)
(keymap-set conn-mode-map "M-s p" 'conn-consult-page)

(provide 'conn-consult)