;;; gosavetool.el --- Subtitles, word count and case changes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 GoSaveTool

;; Author: GoSaveTool <https://www.gosavetool.com/>
;; Assisted-by: Codebuff:claude
;; Maintainer: GoSaveTool <https://www.gosavetool.com/>
;; URL: https://github.com/mitolocya/gosavetool.el
;; Version: 1.0.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: convenience, wp, multimedia

;; This file is not part of GNU Emacs.

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

;;; Commentary:

;; Subtitle and text tools from GoSaveTool (https://www.gosavetool.com/):
;;
;; - `gosavetool-subtitles-to-vtt', `gosavetool-subtitles-to-srt': convert the
;;   SRT or WebVTT subtitles of the buffer and show them in a new buffer.
;; - `gosavetool-subtitles-shift': move every cue earlier or later.
;; - `gosavetool-subtitles-repair': sort cues, fix overlaps and end times
;;   before the start, drop empty cues and renumber.
;; - `gosavetool-count': words, characters, sentences, lines, reading time
;;   and the characters left for X posts, Instagram and TikTok captions,
;;   YouTube titles and descriptions, LinkedIn posts, Pinterest descriptions,
;;   SEO titles and meta descriptions, for the region or the buffer.
;; - `gosavetool-title-case', `gosavetool-sentence-case', `gosavetool-slug',
;;   `gosavetool-camel-case', `gosavetool-snake-case', `gosavetool-kebab-case'
;;   and `gosavetool-clean-spaces' change the region or the current line.
;; - `gosavetool-count-mode' shows the word count in the mode line.
;;
;; Everything runs inside Emacs, offline.  The rules are the same as the
;; @gosavetool/subtitles and @gosavetool/text JavaScript packages.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'ucs-normalize)

(defgroup gosavetool nil
  "Subtitles, word count and case changes."
  :group 'convenience
  :link '(url-link "https://www.gosavetool.com/"))

(defcustom gosavetool-words-per-minute 238
  "Reading speed for the reading time, in words a minute."
  :type 'integer)

;;;; Text

(defconst gosavetool-limits
  '(("x-post" . 280)
    ("instagram-caption" . 2200)
    ("tiktok-caption" . 4000)
    ("youtube-title" . 100)
    ("youtube-description" . 5000)
    ("linkedin-post" . 3000)
    ("pinterest-description" . 500)
    ("seo-title" . 60)
    ("meta-description" . 160))
  "Character limits of common fields.
SEO values are the length search results show before cutting.")

(defconst gosavetool--limit-names
  '(("x-post" . "X post") ("instagram-caption" . "Instagram caption")
    ("tiktok-caption" . "TikTok caption") ("youtube-title" . "YouTube title")
    ("youtube-description" . "YouTube description") ("linkedin-post" . "LinkedIn post")
    ("pinterest-description" . "Pinterest description") ("seo-title" . "SEO title")
    ("meta-description" . "Meta description")))

(defconst gosavetool--small-words
  '("a" "an" "and" "as" "at" "but" "by" "for" "in" "nor" "of" "on" "or" "so"
    "the" "to" "up" "yet" "via" "vs")
  "Words Title Case keeps in lower case unless they start a phrase.")

;; Whitespace as JavaScript's \s sees it; [:space:] would depend on the syntax table
(defconst gosavetool--ws "\t\n\v\f\r    -     　﻿")

(defun gosavetool--count-matches (regexp s)
  "Number of non-overlapping matches of REGEXP in S."
  (let ((case-fold-search nil) (n 0) (pos 0))
    (while (and (< pos (length s)) (string-match regexp s pos))
      (setq n (1+ n)
            pos (max (match-end 0) (1+ (match-beginning 0)))))
    n))

(defun gosavetool-stats (s)
  "Words, characters, lines, sentences and reading time of S, as a plist.
Keys: :words :chars :chars-no-spaces :lines :sentences :read-seconds."
  (let ((words (gosavetool--count-matches "[[:alnum:]][[:alnum:]'’_-]*" s)))
    (list :words words
          :chars (length s)
          :chars-no-spaces (length (replace-regexp-in-string (concat "[" gosavetool--ws "]") "" s))
          :lines (if (string-empty-p s) 0 (1+ (gosavetool--count-matches "\r\n\\|\r\\|\n" s)))
          :sentences (gosavetool--count-matches "[^.!?…]+[.!?…]+" s)
          :read-seconds (floor (+ (/ (* words 60.0) gosavetool-words-per-minute) 0.5)))))

(defun gosavetool-limits (s &optional only)
  "How S meets each limit in `gosavetool-limits', or only those named in ONLY.
Returns an alist of (NAME :limit N :used N :left N :fits BOOL)."
  (let ((used (length s)))
    (cl-loop for (name . limit) in gosavetool-limits
             when (or (null only) (member name only))
             collect (list name :limit limit :used used :left (- limit used) :fits (<= used limit)))))

(defun gosavetool--words (s)
  "Words of S for camelCase and the like.
‘bestPostingTime 2’ -> (‘best’ ‘Posting’ ‘Time’ ‘2’)."

  (let ((case-fold-search nil))
    (split-string (replace-regexp-in-string "\\([[:lower:][:digit:]]\\)\\([[:upper:]]\\)" "\\1 \\2" s t)
                  "[^[:alnum:]]+" t)))

(defun gosavetool--capitalize (w)
  "W with its first character in upper case."
  (if (string-empty-p w) w (concat (upcase (substring w 0 1)) (substring w 1))))

(defun gosavetool-title (s)
  "S in Title Case: \"the lord of the rings\" -> \"The Lord of the Rings\"."
  (let ((case-fold-search nil)
        (low (downcase s))
        (pos 0) (first t) (out '()))
    (while (string-match "[[:alnum:]][[:alnum:]'’]*" low pos)
      (let* ((start (match-beginning 0)) (end (match-end 0))
             (w (match-string 0 low))
             (after-colon (string-match-p (concat "[:.!?][" gosavetool--ws "]*\\'") (substring low 0 start))))
        (push (substring low pos start) out)
        (push (if (or first after-colon (not (member w gosavetool--small-words))) (gosavetool--capitalize w) w) out)
        (setq pos end first nil)))
    (push (substring low pos) out)
    (apply #'concat (nreverse out))))

(defun gosavetool-sentence (s)
  "S in Sentence case: \"HELLO WORLD. how ARE you?\" -> \"Hello world. How are you?\"."
  (let ((case-fold-search nil))
    (replace-regexp-in-string
     (concat "\\(\\`[" gosavetool--ws "]*\\|[.!?…][" gosavetool--ws "]+\\)\\([[:alpha:]]\\)")
     (lambda (m) (concat (match-string 1 m) (upcase (match-string 2 m))))
     (downcase s) t t)))

(defconst gosavetool--slug-map
  '((?ı . "i") (?İ . "i") (?ş . "s") (?Ş . "s") (?ğ . "g") (?Ğ . "g") (?ç . "c") (?Ç . "c")
    (?ö . "o") (?Ö . "o") (?ü . "u") (?Ü . "u") (?ß . "ss") (?æ . "ae") (?ø . "o") (?đ . "d") (?ł . "l")))

(defun gosavetool-slug (s)
  "URL slug of S: \"Ölçü Birimi & Çeviri!\" -> \"olcu-birimi-ceviri\"."
  (let* ((case-fold-search nil)
         (mapped (mapconcat (lambda (c) (or (cdr (assq c gosavetool--slug-map)) (string c))) s ""))
         (plain (replace-regexp-in-string "[̀-ͯ]" "" (ucs-normalize-NFKD-string mapped)))
         (dashed (replace-regexp-in-string "[^a-z0-9]+" "-" (downcase plain) t t)))
    (replace-regexp-in-string "\\`-+\\|-+\\'" "" dashed t t)))

(defun gosavetool-camel (s)
  "S in camelCase."
  (let ((ws (gosavetool--words s)))
    (if (null ws) ""
      (concat (downcase (car ws)) (mapconcat (lambda (w) (gosavetool--capitalize (downcase w))) (cdr ws) "")))))

(defun gosavetool-snake (s)
  "S in snake_case."
  (mapconcat #'downcase (gosavetool--words s) "_"))

(defun gosavetool-kebab (s)
  "S in kebab-case."
  (mapconcat #'downcase (gosavetool--words s) "-"))

(defun gosavetool-clean (s)
  "S without trailing spaces, runs of spaces and more than one blank line in a row."
  (let* ((case-fold-search nil)
         (nl (if (string-match-p "\r\n" s) "\r\n" "\n"))
         (lines (mapcar (lambda (line)
                          (replace-regexp-in-string
                           (concat "\\([^" gosavetool--ws "]\\)[ \t]\\{2,\\}") "\\1 "
                           (replace-regexp-in-string "[ \t]+\\'" "" line t t) t))
                        (split-string s "\r\n\\|\n"))))
    (replace-regexp-in-string (concat "\\(?:" (regexp-quote nl) "\\)\\{3,\\}") (concat nl nl) (string-join lines nl) t t)))

;;;; Subtitles

(cl-defstruct (gosavetool-cue (:constructor gosavetool-cue-create) (:copier nil))
  "One subtitle cue; times in milliseconds."
  start end (settings "") (text ""))

(defconst gosavetool--stamp "\\(?:[0-9]\\{1,2\\}:\\)?[0-9]\\{1,2\\}:[0-9]\\{1,2\\}[,.][0-9]\\{1,3\\}")

(defun gosavetool-to-ms (stamp)
  "\"00:01:02,500\" or \"01:02.5\" -> 62500, or nil when STAMP is not a timestamp."
  (when (string-match "\\(?:\\([0-9]\\{1,2\\}\\):\\)?\\([0-9]\\{1,2\\}\\):\\([0-9]\\{1,2\\}\\)[,.]\\([0-9]\\{1,3\\}\\)" stamp)
    (let ((h (if (match-beginning 1) (string-to-number (match-string 1 stamp)) 0))
          (m (string-to-number (match-string 2 stamp)))
          (s (string-to-number (match-string 3 stamp)))
          (frac (match-string 4 stamp)))
      (+ (* (+ (* (+ (* h 60) m) 60) s) 1000)
         (string-to-number (concat frac (make-string (- 3 (length frac)) ?0)))))))

(defun gosavetool-from-ms (ms &optional sep)
  "MS as \"00:01:02,500\" (SEP \",\", SRT, the default) or \"00:01:02.500\" (SEP \".\")."
  (let ((ms (max 0 (round ms))))
    (format "%02d:%02d:%02d%s%03d" (/ ms 3600000) (% (/ ms 60000) 60) (% (/ ms 1000) 60) (or sep ",") (% ms 1000))))

(defun gosavetool-parse (src)
  "Cues of the SRT or WebVTT text SRC, a list of `gosavetool-cue'."
  (let* ((case-fold-search nil)
         (text (replace-regexp-in-string "\r" "\n" (replace-regexp-in-string "\r*\n" "\n" (string-remove-prefix "\uFEFF" src))))
         (arrow (concat "\\`[ \t]*\\(" gosavetool--stamp "\\)[ \t]*-->[ \t]*\\(" gosavetool--stamp "\\)\\(.*\\)\\'"))
         (cues '()))
    (dolist (block (split-string text "\n\\{2,\\}"))
      (let ((lines (split-string block "\n")) (found nil))
        (while (and lines (not found))
          (let ((line (pop lines)))
            (when (string-match arrow line)
              (setq found t)
              ;; `gosavetool-to-ms' resets the match data, so read the groups first
              (let ((start (match-string 1 line))
                    (end (match-string 2 line))
                    (settings (string-trim (match-string 3 line))))
                (push (gosavetool-cue-create
                       :start (gosavetool-to-ms start)
                       :end (gosavetool-to-ms end)
                       :settings settings
                       :text (string-trim (string-join lines "\n")))
                      cues)))))))
    (nreverse cues)))



(defun gosavetool-vtt-p (src)
  "Non-nil when SRC starts with the WEBVTT signature."
  (string-prefix-p "WEBVTT" (string-remove-prefix "﻿" src)))

(defun gosavetool-to-srt (cues)
  "SRT text of CUES, numbered from 1."
  (concat (mapconcat #'identity
                     (cl-loop for c in cues for i from 1
                              collect (format "%d\n%s --> %s\n%s" i
                                              (gosavetool-from-ms (gosavetool-cue-start c) ",")
                                              (gosavetool-from-ms (gosavetool-cue-end c) ",")
                                              (gosavetool-cue-text c)))
                     "\n\n")
          "\n"))

(defun gosavetool-to-vtt (cues)
  "WebVTT text of CUES; cue settings are kept."
  (concat "WEBVTT\n\n"
          (mapconcat (lambda (c)
                       (format "%s --> %s%s\n%s"
                               (gosavetool-from-ms (gosavetool-cue-start c) ".")
                               (gosavetool-from-ms (gosavetool-cue-end c) ".")
                               (if (string-empty-p (gosavetool-cue-settings c)) "" (concat " " (gosavetool-cue-settings c)))
                               (gosavetool-cue-text c)))
                     cues "\n\n")
          "\n"))

(defun gosavetool-convert (src to)
  "SRC converted to TO, \"srt\" or \"vtt\"."
  (pcase to
    ("vtt" (gosavetool-to-vtt (gosavetool-parse src)))
    ("srt" (gosavetool-to-srt (gosavetool-parse src)))
    (_ (error "The target format must be \"srt\" or \"vtt\""))))

(defun gosavetool-shift (cues ms)
  "CUES moved by MS milliseconds (negative = earlier).
Cues pushed before zero are clipped or dropped."
  (cl-loop for c in cues
           for end = (max 0 (+ (gosavetool-cue-end c) ms))
           when (> end 0)
           collect (gosavetool-cue-create :start (max 0 (+ (gosavetool-cue-start c) ms)) :end end
                                          :settings (gosavetool-cue-settings c) :text (gosavetool-cue-text c))))

(defun gosavetool-repair (cues &optional min-duration)
  "Repaired copy of CUES with MIN-DURATION for cues that are too short.
Sorts the cues, gives cues that end before they start MIN-DURATION
milliseconds (2000 by default), ends overlapping cues before the next
one and drops empty cues.  Returns (CUES . NUMBER-OF-FIXES)."

  (let* ((min-duration (or min-duration 2000))
         (fixed (cl-count-if (lambda (c) (string-empty-p (gosavetool-cue-text c))) cues))
         (out (cl-loop for c in cues unless (string-empty-p (gosavetool-cue-text c))
                       collect (gosavetool-cue-create :start (gosavetool-cue-start c) :end (gosavetool-cue-end c)
                                                      :settings (gosavetool-cue-settings c) :text (gosavetool-cue-text c))))
         (before (mapcar #'gosavetool-cue-start out)))
    ;; `sort' is stable, so cues with the same start keep their order
    (setq out (sort out (lambda (a b) (< (gosavetool-cue-start a) (gosavetool-cue-start b)))))
    (unless (equal before (mapcar #'gosavetool-cue-start out)) (cl-incf fixed))
    (cl-loop for (c next) on out
             do (unless (> (gosavetool-cue-end c) (gosavetool-cue-start c))
                  (setf (gosavetool-cue-end c) (+ (gosavetool-cue-start c) min-duration))
                  (cl-incf fixed))
             (when (and next (> (gosavetool-cue-end c) (gosavetool-cue-start next)))
               (setf (gosavetool-cue-end c) (max (1+ (gosavetool-cue-start c)) (1- (gosavetool-cue-start next))))
               (cl-incf fixed)))
    (cons out fixed)))

;;;; Commands

(defun gosavetool--bounds ()
  "The active region, or the current line."
  (if (use-region-p)
      (cons (region-beginning) (region-end))
    (cons (line-beginning-position) (line-end-position))))

(defun gosavetool--change (fn)
  "Replace the region or the current line with FN applied to it."
  (let* ((b (gosavetool--bounds))
         (before (buffer-substring-no-properties (car b) (cdr b)))
         (after (funcall fn before)))
    (unless (equal before after)
      (save-excursion
        (goto-char (car b))
        (delete-region (car b) (cdr b))
        (insert after)))))

(defmacro gosavetool--define-case (name fn doc)
  "Define the command NAME that applies FN to the region or line, with DOC."
  `(defun ,name ()
     ,(concat doc "\nWorks on the active region, or on the current line.")
     (interactive "*")
     (gosavetool--change #',fn)))

(gosavetool--define-case gosavetool-title-case gosavetool-title "Change to Title Case.")
(gosavetool--define-case gosavetool-sentence-case gosavetool-sentence "Change to Sentence case.")
(gosavetool--define-case gosavetool-upcase upcase "Change to UPPERCASE.")
(gosavetool--define-case gosavetool-downcase downcase "Change to lowercase.")
(gosavetool--define-case gosavetool-slug-region gosavetool-slug "Change to a URL slug.")
(gosavetool--define-case gosavetool-camel-case gosavetool-camel "Change to camelCase.")
(gosavetool--define-case gosavetool-snake-case gosavetool-snake "Change to snake_case.")
(gosavetool--define-case gosavetool-kebab-case gosavetool-kebab "Change to kebab-case.")
(gosavetool--define-case gosavetool-clean-spaces gosavetool-clean "Remove trailing spaces, runs of spaces and extra blank lines.")

(defun gosavetool-report (s)
  "Counts and limits of S as text."
  (let ((st (gosavetool-stats s)))
    (concat
     (format "Words: %d   Characters: %d   Without spaces: %d\nSentences: %d   Lines: %d   Reading time: %d min %d s\n\n"
             (plist-get st :words) (plist-get st :chars) (plist-get st :chars-no-spaces)
             (plist-get st :sentences) (plist-get st :lines)
             (/ (plist-get st :read-seconds) 60) (% (plist-get st :read-seconds) 60))
     (mapconcat (lambda (l)
                  (let ((left (plist-get (cdr l) :left)))
                    (format "%-22s %5d  %s" (cdr (assoc (car l) gosavetool--limit-names)) (plist-get (cdr l) :limit)
                            (if (plist-get (cdr l) :fits) (format "%d left" left) (format "%d over" (- left))))))
                (gosavetool-limits s) "\n")
     "\n\nOnline counter: https://www.gosavetool.com/character-counter\n")))

;;;###autoload
(defun gosavetool-count (beg end)
  "Show words, characters, reading time and social media limits.
Counts the region from BEG to END when it is active, else the buffer."
  (interactive (if (use-region-p) (list (region-beginning) (region-end)) (list (point-min) (point-max))))
  (let ((report (gosavetool-report (buffer-substring-no-properties beg end))))
    (with-help-window "*GoSaveTool Count*"
      (princ report))))

(defun gosavetool--cues ()
  "Text and cues of the buffer; signals a user error when it has no cues."
  (let* ((src (buffer-substring-no-properties (point-min) (point-max)))
         (cues (gosavetool-parse src)))
    (unless cues (user-error "No SRT or WebVTT cues in this buffer"))
    (cons src cues)))

(defun gosavetool--replace-buffer (text)
  "Replace the buffer contents with TEXT, keeping point near where it was."
  (let ((pos (point)))
    (erase-buffer)
    (insert text)
    (goto-char (min pos (point-max)))))

(defun gosavetool--convert (to)
  "Show the subtitles of the buffer converted to TO in a new buffer."
  (let* ((sc (gosavetool--cues))
         (base (if buffer-file-name (file-name-sans-extension (file-name-nondirectory buffer-file-name)) "subtitles"))
         (dir default-directory)
         (out (generate-new-buffer (concat base "." to))))
    (with-current-buffer out
      (insert (gosavetool-convert (car sc) to))
      (setq default-directory dir)
      (set-visited-file-name (expand-file-name (concat base "." to) dir) t)
      (goto-char (point-min)))
    (pop-to-buffer out)
    (message "%d cues converted; save with C-x C-s" (length (cdr sc)))))

;;;###autoload
(defun gosavetool-subtitles-to-vtt ()
  "Show the SRT subtitles of the buffer as WebVTT in a new buffer."
  (interactive)
  (gosavetool--convert "vtt"))

;;;###autoload
(defun gosavetool-subtitles-to-srt ()
  "Show the WebVTT subtitles of the buffer as SRT in a new buffer."
  (interactive)
  (gosavetool--convert "srt"))

;;;###autoload
(defun gosavetool-subtitles-shift (seconds)
  "Move every cue of the buffer by SECONDS (1.5 = later, -2 = earlier)."
  (interactive "*nShift subtitles by seconds (1.5 = later, -2 = earlier): ")
  (let* ((sc (gosavetool--cues))
         (moved (gosavetool-shift (cdr sc) (round (* seconds 1000)))))
    (gosavetool--replace-buffer (if (gosavetool-vtt-p (car sc)) (gosavetool-to-vtt moved) (gosavetool-to-srt moved)))
    (message "Moved %s s" seconds)))

;;;###autoload
(defun gosavetool-subtitles-repair ()
  "Sort cues, fix overlaps and bad times, drop empty cues and renumber."
  (interactive "*")
  (let* ((sc (gosavetool--cues))
         (r (gosavetool-repair (cdr sc))))
    (gosavetool--replace-buffer (if (gosavetool-vtt-p (car sc)) (gosavetool-to-vtt (car r)) (gosavetool-to-srt (car r))))
    (message "%s" (if (> (cdr r) 0) (format "%d problems fixed" (cdr r)) "No problems found"))))

;;;; Mode line

(defvar-local gosavetool--mode-line-words nil
  "Cached word count for the mode line.")

(defvar gosavetool--lighter '(:eval gosavetool--mode-line-words)
  "Mode line construct of `gosavetool-count-mode'.")
(put 'gosavetool--lighter 'risky-local-variable t)

(defun gosavetool--update-count (&rest _)
  "Recount the words of the buffer for the mode line."
  ;; Above this size recounting on every change would slow typing down
  (setq gosavetool--mode-line-words
        (when (< (buffer-size) 300000)
          (format " %dw" (plist-get (gosavetool-stats (buffer-substring-no-properties (point-min) (point-max))) :words)))))

;;;###autoload
(define-minor-mode gosavetool-count-mode
  "Show the word count of the buffer in the mode line."
  :lighter gosavetool--lighter
  (if gosavetool-count-mode
      (progn
        (gosavetool--update-count)
        (add-hook 'after-change-functions #'gosavetool--update-count nil t))
    (remove-hook 'after-change-functions #'gosavetool--update-count t)))

(provide 'gosavetool)
;;; gosavetool.el ends here
