# gosavetool.el

Subtitle and text tools for Emacs: convert **SRT ↔ WebVTT**, **shift** and **repair** subtitle timings, **count words** with **social media and SEO character limits**, change **text case**, and show a live **word count** in the mode line. One file, no dependencies, works offline.

Made by [GoSaveTool](https://www.gosavetool.com/), free online tools for creators.

## Install

From [MELPA](https://melpa.org/): `M-x package-install RET gosavetool RET`, or with `use-package`:

```elisp
(use-package gosavetool
  :ensure t
  :hook (text-mode . gosavetool-count-mode)
  :bind (("C-c g c" . gosavetool-count)
         ("C-c g t" . gosavetool-title-case)))
```

Manually: put `gosavetool.el` on your `load-path` and `(require 'gosavetool)`. Requires Emacs 26.1 or newer.

## Commands

| Command | What it does |
| --- | --- |
| `gosavetool-count` | Words, characters, sentences, lines, reading time and the characters left for X, Instagram, TikTok, YouTube, LinkedIn, Pinterest, SEO title and meta description, for the region or the buffer |
| `gosavetool-title-case`, `gosavetool-sentence-case`, `gosavetool-upcase`, `gosavetool-downcase` | Change the region, or the current line |
| `gosavetool-slug-region`, `gosavetool-camel-case`, `gosavetool-snake-case`, `gosavetool-kebab-case` | `Ölçü Birimi` → `olcu-birimi`, `best posting time` → `bestPostingTime` |
| `gosavetool-clean-spaces` | Remove trailing spaces, runs of spaces and extra blank lines |
| `gosavetool-subtitles-to-vtt`, `gosavetool-subtitles-to-srt` | Show the converted subtitles in a new buffer visiting `name.vtt` / `name.srt`; save with `C-x C-s` |
| `gosavetool-subtitles-shift` | Move every cue by the seconds you enter (`1.5` later, `-2` earlier) |
| `gosavetool-subtitles-repair` | Sort cues, fix overlaps and end times before the start, drop empty cues, renumber |
| `gosavetool-count-mode` | Minor mode: the word count of the buffer in the mode line |

## Library

```elisp
(gosavetool-convert srt-text "vtt")
(gosavetool-repair (gosavetool-parse text))   ; => (CUES . NUMBER-OF-FIXES)
(gosavetool-stats "Hello world.")             ; => (:words 2 :chars 12 ...)
(gosavetool-title "the lord of the rings")    ; => "The Lord of the Rings"
```

The rules are the same as the [`@gosavetool/subtitles`](https://www.npmjs.com/package/@gosavetool/subtitles) and [`@gosavetool/text`](https://www.npmjs.com/package/@gosavetool/text) packages.

## Tests

```bash
emacs -Q --batch -L . -l gosavetool-test.el -f ert-run-tests-batch-and-exit
```

## Online tools

[VTT Subtitle Generator](https://www.gosavetool.com/vtt-subtitle-generator), [Auto Captions Generator](https://www.gosavetool.com/auto-captions-generator), [Character Counter](https://www.gosavetool.com/character-counter)

## License

MIT
