import AppKit
import UniformTypeIdentifiers

// MARK: - Forward-only enforcement

/// Delegate that only permits appending text at the very end of the document.
/// Deletions are rejected outright; insertions attempted anywhere else are
/// redirected to the end, so typing always moves forward.
final class ForwardOnlyDelegate: NSObject, NSTextViewDelegate {

    func textView(_ textView: NSTextView,
                  shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        // nil replacement means an attribute-only change (no characters touched)
        guard let replacement = replacementString else { return true }

        // Empty replacement over any range is a deletion; empty over an empty
        // range is a no-op. Block both — nothing ever comes out.
        if replacement.isEmpty { return false }

        let end = textView.textStorage?.length ?? 0
        let isAppend = affectedCharRange.location == end && affectedCharRange.length == 0
        if isAppend { return true }

        // Insertion anywhere else (mid-document click, paste over a selection,
        // dictation revising earlier words): redirect the new text to the end.
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.insertText(replacement, replacementRange: NSRange(location: end, length: 0))
        return false
    }
}

// MARK: - Scratch-out text view

/// Double-clicking a word crosses it out — permanently, like ink.
final class ScratchTextView: NSTextView {

    static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular),
        .foregroundColor: NSColor.textColor,
    ]

    // Typing attributes normally inherit from the character before the
    // insertion point; pin them so text typed after a struck word doesn't
    // come out struck too.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { Self.baseAttributes }
        set {}
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            scratchOutWord(at: event)
            return
        }
        super.mouseDown(with: event)
    }

    private func scratchOutWord(at event: NSEvent) {
        guard let storage = textStorage else { return }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length else { return }

        let wordRange = selectionRange(
            forProposedRange: NSRange(location: index, length: 0),
            granularity: .selectByWord
        )
        guard wordRange.length > 0 else { return }

        // Ignore double-clicks on whitespace between words.
        let word = (storage.string as NSString).substring(with: wordRange)
        guard word.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else { return }

        storage.addAttributes([
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.secondaryLabelColor,
        ], range: wordRange)
    }

    /// The document as markdown: struck ranges become ~~strikethrough~~.
    var markdown: String {
        guard let storage = textStorage, storage.length > 0 else { return string }
        let text = storage.string as NSString
        var result = ""
        storage.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let chunk = text.substring(with: range)
            let isStruck = ((value as? Int) ?? 0) != 0
            guard isStruck else {
                result += chunk
                return
            }
            // Keep surrounding whitespace outside the markers — "~~word ~~"
            // is not valid markdown strikethrough.
            let leading = String(chunk.prefix(while: \.isWhitespace))
            let trailingCount = chunk.reversed().prefix(while: \.isWhitespace).count
            let core = String(chunk.dropFirst(leading.count).dropLast(trailingCount))
            let trailing = String(chunk.suffix(trailingCount))
            result += core.isEmpty ? chunk : leading + "~~" + core + "~~" + trailing
        }
        return result
    }
}

// MARK: - Text view construction

func makeTextView() -> (scrollView: NSScrollView, textView: ScratchTextView) {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true

    let textView = ScratchTextView()
    textView.autoresizingMask = [.width]
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.textContainerInset = NSSize(width: 48, height: 40)

    textView.font = ScratchTextView.baseAttributes[.font] as? NSFont
    textView.isRichText = false
    textView.allowsUndo = false

    // Raw input: no corrections, substitutions, or checking of any kind.
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isAutomaticTextCompletionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.smartInsertDeleteEnabled = false

    scrollView.documentView = textView
    return (scrollView, textView)
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textView: ScratchTextView!
    let forwardOnly = ForwardOnlyDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (scrollView, textView) = makeTextView()
        self.textView = textView
        textView.delegate = forwardOnly

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Writer"
        window.contentView = scrollView
        window.center()
        window.setFrameAutosaveName("WriterMainWindow")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: New Page (Cmd+N)

    @objc func newPage(_ sender: Any?) {
        guard !textView.string.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Start a new page?"
        alert.informativeText = "The current page will be discarded. Save it first if you want to keep it."
        alert.addButton(withTitle: "New Page")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            // Direct storage assignment bypasses the forward-only delegate,
            // so the app can clear the page even though the user can't.
            self.textView.string = ""
            self.window.makeFirstResponder(self.textView)
        }
    }

    // MARK: Save (Cmd+S)

    @objc func saveDocument(_ sender: Any?) {
        let markdown = UTType(filenameExtension: "md") ?? .plainText
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "writing.md"
        panel.allowedContentTypes = [markdown]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let text = self?.textView.markdown else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Menu bar (needed for Cmd+C / Cmd+V / Cmd+S / Cmd+Q in a programmatic app)

func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit Writer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let fileMenuItem = NSMenuItem()
    let fileMenu = NSMenu(title: "File")
    fileMenu.addItem(withTitle: "New Page", action: #selector(AppDelegate.newPage(_:)), keyEquivalent: "n")
    fileMenu.addItem(withTitle: "Save…", action: #selector(AppDelegate.saveDocument(_:)), keyEquivalent: "s")
    fileMenuItem.submenu = fileMenu
    mainMenu.addItem(fileMenuItem)

    let editMenuItem = NSMenuItem()
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(withTitle: "Start Dictation…", action: Selector(("startDictation:")), keyEquivalent: "")
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    return mainMenu
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = makeMainMenu()
app.run()
