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

    // Dark purple ink in light mode; lifted to lavender in dark mode so the
    // stroke stays visible against a dark background.
    static let scratchColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.70, green: 0.55, blue: 0.95, alpha: 1)
            : NSColor(calibratedRed: 0.36, green: 0.14, blue: 0.55, alpha: 1)
    }

    static let scratchAttributes: [NSAttributedString.Key: Any] = [
        .strikethroughStyle: NSUnderlineStyle.thick.rawValue,
        .strikethroughColor: scratchColor,
        .foregroundColor: NSColor.secondaryLabelColor,
    ]

    /// Called after a word is scratched out (attribute changes don't fire
    /// text-change notifications, so autosave hooks in here).
    var onScratch: (() -> Void)?

    // 66 characters per line — the typographic ideal (Bringhurst's 45-75
    // range; WCAG caps at 80). Measured in the actual font rather than
    // hardcoded in points.
    static let maxLineWidth: CGFloat = {
        let charWidth = ("n" as NSString).size(withAttributes: baseAttributes).width
        return ceil(charWidth * 66)
    }()

    // Typing attributes normally inherit from the character before the
    // insertion point; pin them so text typed after a struck word doesn't
    // come out struck too. The setter must write through to super (not
    // no-op) — the empty-document caret takes its height from the internal
    // storage, so it has to actually hold the 17pt base font.
    override var typingAttributes: [NSAttributedString.Key: Any] {
        get { Self.baseAttributes }
        set { super.typingAttributes = Self.baseAttributes }
    }

    // Keep the text column centered and capped at maxLineWidth by growing
    // the horizontal inset as the window widens.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let horizontal = max(48, (newSize.width - Self.maxLineWidth) / 2)
        textContainerInset = NSSize(width: horizontal, height: 40)
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

        storage.addAttributes(Self.scratchAttributes, range: wordRange)
        onScratch?()
    }

    /// Inverse of `markdown`: rebuilds the page from saved text, restoring
    /// ~~struck~~ ranges as scratch-outs.
    static func attributedString(fromMarkdown text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = text as NSString
        let struckAttrs = baseAttributes.merging(scratchAttributes) { _, new in new }
        let regex = try! NSRegularExpression(pattern: "~~([^~\\n]+)~~")
        var cursor = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                let before = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: ns.substring(with: before), attributes: baseAttributes))
            }
            result.append(NSAttributedString(string: ns.substring(with: match.range(at: 1)), attributes: struckAttrs))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(NSAttributedString(string: ns.substring(from: cursor), attributes: baseAttributes))
        }
        return result
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
    // Seed the internal typing attributes so the caret is full-height
    // from the first launch, before any text exists.
    textView.typingAttributes = ScratchTextView.baseAttributes
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
    private var pendingSave: DispatchWorkItem?

    /// The single active page, mirrored to disk for crash/quit recovery.
    static let pageURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Writer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("current-page.md")
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let (scrollView, textView) = makeTextView()
        self.textView = textView
        textView.delegate = forwardOnly

        // Restore the page from the last session, if there is one.
        if let saved = try? String(contentsOf: Self.pageURL, encoding: .utf8), !saved.isEmpty {
            textView.textStorage?.setAttributedString(ScratchTextView.attributedString(fromMarkdown: saved))
            textView.setSelectedRange(NSRange(location: textView.textStorage?.length ?? 0, length: 0))
        }

        // Autosave shortly after typing pauses, and after scratch-outs.
        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification, object: textView
        )
        textView.onScratch = { [weak self] in self?.scheduleAutosave() }

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

    func applicationWillTerminate(_ notification: Notification) {
        savePageNow()
    }

    // MARK: Autosave

    @objc private func textDidChange(_ notification: Notification) {
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.savePageNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func savePageNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let text = textView.markdown
        if text.isEmpty {
            try? FileManager.default.removeItem(at: Self.pageURL)
        } else {
            try? text.write(to: Self.pageURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Clear Page (Cmd+N)

    @objc func clearPage(_ sender: Any?) {
        guard !textView.string.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clear the page?"
        alert.informativeText = "Everything on the page will be erased. Save it first if you want to keep it."
        alert.addButton(withTitle: "Clear Page")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            // Direct storage assignment bypasses the forward-only delegate,
            // so the app can clear the page even though the user can't.
            self.textView.string = ""
            self.savePageNow() // empty page — removes the stored copy too
            self.window.makeFirstResponder(self.textView)
        }
    }

    // MARK: Save (Cmd+S)

    @objc func saveDocument(_ sender: Any?) {
        let markdown = UTType(filenameExtension: "md") ?? .plainText
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = formatter.string(from: Date()) + ".md"
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
    fileMenu.addItem(withTitle: "Clear Page", action: #selector(AppDelegate.clearPage(_:)), keyEquivalent: "n")
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
