;;; gosavetool-test.el --- Tests for gosavetool -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs -Q --batch -L . -l gosavetool-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'gosavetool)

(defconst gosavetool-test-srt
  "1\r\n00:00:01,000 --> 00:00:03,500\r\nHello\r\nworld\r\n\r\n2\r\n00:00:03,000 --> 00:00:02,000\r\nSecond\r\n\r\n3\r\n00:00:00,500 --> 00:00:00,900\r\nFirst\r\n")

(ert-deftest gosavetool-test-parse-and-write ()
  (let ((cues (gosavetool-parse gosavetool-test-srt)))
    (should (= (length cues) 3))
    (should (equal (gosavetool-cue-text (car cues)) "Hello\nworld"))
    (should (string-prefix-p "WEBVTT\n\n00:00:01.000 --> 00:00:03.500\nHello" (gosavetool-to-vtt cues))))
  (should (equal (gosavetool-convert "WEBVTT\n\nNOTE hi\n\n01:02.5 --> 01:04.000 align:start\nA\n" "srt")
                 "1\n00:01:02,500 --> 00:01:04,000\nA\n"))
  (should (equal (gosavetool-convert "WEBVTT\n\n01:02.5 --> 01:04.000 align:start\nA\n" "vtt")
                 "WEBVTT\n\n00:01:02.500 --> 00:01:04.000 align:start\nA\n"))
  (should-error (gosavetool-convert gosavetool-test-srt "ass")))

(ert-deftest gosavetool-test-shift-repair ()
  (let* ((cues (gosavetool-parse gosavetool-test-srt))
         (r (gosavetool-repair cues)))
    (should (equal (mapcar (lambda (c) (list (gosavetool-cue-start c) (gosavetool-cue-end c))) (gosavetool-shift cues -1000))
                   '((0 2500) (2000 1000))))
    (should (equal (mapcar #'gosavetool-cue-text (car r)) '("First" "Hello\nworld" "Second")))
    (should (= (cdr r) 3))
    (should (= (gosavetool-cue-end (nth 1 cues)) 2000))))

(ert-deftest gosavetool-test-times ()
  (should (equal (gosavetool-from-ms 3723004 ",") "01:02:03,004"))
  (should (= (gosavetool-to-ms "1:02:03.4") 3723400))
  (should-not (gosavetool-to-ms "nope"))
  (should (gosavetool-vtt-p "﻿WEBVTT\n")))

(ert-deftest gosavetool-test-stats ()
  (should (equal (gosavetool-stats "Hello world. It’s 2026!")
                 '(:words 4 :chars 23 :chars-no-spaces 20 :lines 1 :sentences 2 :read-seconds 1)))
  (let ((st (gosavetool-stats "Hello world. It’s 2026!\nSecond line.")))
    (should (equal (list (plist-get st :words) (plist-get st :lines) (plist-get st :sentences)) '(6 2 3))))
  (should (= (plist-get (gosavetool-stats "") :lines) 0))
  (should (= (plist-get (gosavetool-stats "Ölçü birimi çeviri") :words) 3))
  (should (equal (cdr (assoc "x-post" (gosavetool-limits (make-string 300 ?x) '("x-post"))))
                 '(:limit 280 :used 300 :left -20 :fits nil)))
  (should (= (length (gosavetool-limits "a")) 9)))

(ert-deftest gosavetool-test-cases ()
  (should (equal (gosavetool-title "the lord of the rings: return of the king") "The Lord of the Rings: Return of the King"))
  (should (equal (gosavetool-sentence "HELLO WORLD. how ARE you?") "Hello world. How are you?"))
  (should (equal (gosavetool-slug "Ölçü Birimi & Çeviri!") "olcu-birimi-ceviri"))
  (should (equal (gosavetool-slug "Straße café") "strasse-cafe"))
  (should (equal (gosavetool-camel "best posting time") "bestPostingTime"))
  (should (equal (gosavetool-snake "bestPostingTime") "best_posting_time"))
  (should (equal (gosavetool-kebab "Best Posting_Time") "best-posting-time"))
  (should (equal (gosavetool-clean "a   b  \n\n\n\nc\t") "a b\n\nc"))
  (should (equal (gosavetool-clean "a  \r\n\r\n\r\n\r\nb") "a\r\n\r\nb")))

(ert-deftest gosavetool-test-commands ()
  (with-temp-buffer
    (insert "the lord of the rings\nsecond")
    (goto-char (point-min))
    (gosavetool-title-case)
    (should (equal (buffer-string) "The Lord of the Rings\nsecond"))
    (erase-buffer)
    (insert "1\n00:00:02,000 --> 00:00:01,000\nB\n\n2\n00:00:00,500 --> 00:00:01,500\nA\n")
    (gosavetool-subtitles-repair)
    (should (string-prefix-p "1\n00:00:00,500 --> 00:00:01,500\nA" (buffer-string)))
    (gosavetool-subtitles-shift 1.5)
    (should (string-match-p "00:00:02,000 --> 00:00:03,000\nA" (buffer-string)))
    (gosavetool-count-mode 1)
    (should (string-match-p "\\` [0-9]+w\\'" gosavetool--mode-line-words))))

(provide 'gosavetool-test)
;;; gosavetool-test.el ends here
