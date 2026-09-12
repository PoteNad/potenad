# PoteNad

PoteNad is a small, native macOS plain-text editor inspired by classic Windows 10 Notepad. It focuses on creating and editing text files without Markdown, rich text, accounts, plugins, or built-in online services. PoteNad requires macOS 13 or newer and has no third-party application dependencies.

## Install

When the first signed release is published, download it from [GitHub Releases](https://github.com/PoteNad/potenad/releases), or install it with Homebrew:

```sh
brew tap PoteNad/potenad https://github.com/PoteNad/potenad.git
brew install --cask PoteNad/potenad/potenad
```

## Features

- Familiar document actions including new windows and tabs, Open, Save, Save As, Revert, Duplicate, Rename, Move, Page Setup, and Print.
- Undo and redo, standard clipboard actions, text transformations, find and replace, Go to Line, Select Lines, and F5 Time/Date.
- `.LOG` timestamps when a file whose first line begins with `.LOG` is opened.
- Word wrapping, writing direction, font selection, zoom from 10–500%, and an optional status bar with line, column, encoding, and line-ending information.
- UTF-8, UTF-8 with BOM, UTF-16 LE/BE, Windows-1252, and Mac OS Roman text.
- Detection and preservation of LF, CRLF, and CR line endings, with encoding and line-ending choices in Save As.
- Native macOS menus, windows, tabs, settings, system/light/dark appearances, find bar, spelling, substitutions, speech, Services, autosave, recovery, optional previous-session restoration, document versions, and optional Apple Writing Tools that are off by default.
- Configurable page setup, printing, headers, and footers.

PoteNad uses standard AppKit controls so it feels at home on macOS while keeping the editor simple and distraction-free.

## Build from source

Run the build script, then open the resulting app:

```sh
./scripts/build.sh
open build/PoteNad.app
```

The build is optimized and ad-hoc signed for the current Mac. Open `Package.swift` in Xcode to work on the source. Run `./scripts/check.sh` to run the full local test suite.

## License

MIT — see [LICENSE](LICENSE).
