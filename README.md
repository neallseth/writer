# Writer

A forward-only writing app for macOS. Like writing with a pen: you can only
write forward — no backspace, no delete, no undo. Words can't be erased, but
double-clicking a word scratches it out, permanently, the way you'd strike
a word on paper.

## Rules of the page

- Typing always appends at the end of the document. Clicking mid-text and
  typing sends the characters to the end, not where you clicked.
- Nothing deletes: backspace, forward-delete, cut, and undo are all inert.
- Input is raw — no autocorrect, smart quotes, spell check, or substitutions.
- Paste and dictation work, and can only append.
- Double-click a word to scratch it out. There is no un-scratching.
- Select and copy freely; you just can't change what's written.
- The page autosaves continuously and reopens where you left off, even
  after a crash or reboot. There is only ever one page — clearing it
  erases the stored copy too.
- Two themes under View ▸ Theme: System (follows macOS light/dark) and
  Natural (warm paper and ink, like a notebook).

## Keys

| Key | Action |
| --- | --- |
| Cmd+N | Clear page (confirms first if the page has text) |
| Cmd+S | Save as markdown (scratch-outs export as `~~strikethrough~~`) |
| Cmd+C / Cmd+V / Cmd+A | Copy / paste / select all |
| Cmd+Q | Quit |

## Build and install

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh              # builds build/Writer.app
./build.sh install      # builds and copies it to /Applications
```

The build is a direct `swiftc` invocation — no Xcode project, no SwiftPM,
no dependencies. The whole app is [Sources/Writer/main.swift](Sources/Writer/main.swift).

## App icon

`Assets/AppIcon.icns` is generated. To regenerate after editing
[tools/makeicon.swift](tools/makeicon.swift):

```sh
./tools/makeicon.sh
```
