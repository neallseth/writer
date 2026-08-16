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

// MARK: - Themes

/// "System" follows macOS light/dark with standard colors. "Natural" is a
/// warm paper-and-ink look, like writing in a notebook.
enum Theme: String {
    case system, natural

    var background: NSColor {
        self == .natural
            ? NSColor(calibratedRed: 0.96, green: 0.925, blue: 0.85, alpha: 1)
            : .textBackgroundColor
    }
    /// The area outside the page when the window is wider than the text
    /// column. Natural frames the sepia page with a lighter cream; System
    /// uses the standard darker under-page color (light mode's page is
    /// already white — there's no lighter shade to frame it with).
    var gutter: NSColor {
        self == .natural
            ? NSColor(calibratedRed: 0.995, green: 0.985, blue: 0.955, alpha: 1)
            : .underPageBackgroundColor
    }
    var ink: NSColor {
        self == .natural
            ? NSColor(calibratedRed: 0.24, green: 0.19, blue: 0.13, alpha: 1)
            : .textColor
    }
    var dimInk: NSColor {
        self == .natural
            ? NSColor(calibratedRed: 0.60, green: 0.53, blue: 0.44, alpha: 1)
            : .secondaryLabelColor
    }
    var caret: NSColor {
        self == .natural
            ? NSColor(calibratedRed: 0.85, green: 0.52, blue: 0.13, alpha: 1)
            : .textColor
    }
}

// MARK: - Scratch-out text view

/// Double-clicking a word crosses it out — permanently, like ink.
final class ScratchTextView: NSTextView {

    static var currentTheme = Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular),
            .foregroundColor: currentTheme.ink,
        ]
    }

    // Burnt-sienna ink, echoing the icon's scratch stroke; lifted to a
    // warm clay in dark mode so it stays visible against a dark background.
    static let scratchColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.74, green: 0.54, blue: 0.42, alpha: 1)
            : NSColor(calibratedRed: 0.50, green: 0.31, blue: 0.21, alpha: 1)
    }

    static var scratchAttributes: [NSAttributedString.Key: Any] {
        [
            .strikethroughStyle: NSUnderlineStyle.thick.rawValue,
            .strikethroughColor: scratchColor,
            .foregroundColor: currentTheme.dimInk,
        ]
    }

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

    /// Breathing room between the text column and the page edge.
    static let pageMargin: CGFloat = 48

    /// Whether the page is framed by gutters when the window is wide.
    static var guttersEnabled = UserDefaults.standard.object(forKey: "gutters") as? Bool ?? true

    // Keep the text column centered and capped at maxLineWidth by growing
    // the horizontal inset as the window widens. The height is clamped to
    // the viewport here, in the setter itself — NSTextView's internal
    // sizing passes reset frame and minSize on their own schedule, and a
    // view even a few points shorter than the clip view lets the gutter
    // fill bleed into the uncovered strip as a band along the bottom.
    override func setFrameSize(_ newSize: NSSize) {
        var newSize = newSize
        if let clipHeight = superview?.bounds.height {
            newSize.height = max(newSize.height, ceil(clipHeight))
        }
        super.setFrameSize(newSize)
        let horizontal = max(Self.pageMargin, (newSize.width - Self.maxLineWidth) / 2)
        textContainerInset = NSSize(width: horizontal, height: 40)
    }

    // Draw the page as its own surface: the text column plus margin sits
    // on the theme's background color, and anything wider becomes gutter —
    // like a notepad on a desk. (drawsBackground is off; this fills it all.)
    override func draw(_ dirtyRect: NSRect) {
        let theme = Self.currentTheme
        guard Self.guttersEnabled else {
            theme.background.setFill()
            dirtyRect.fill()
            super.draw(dirtyRect)
            return
        }
        theme.gutter.setFill()
        dirtyRect.fill()

        var page = bounds
        let overhang = textContainerInset.width - Self.pageMargin
        page.origin.x = overhang
        page.size.width = bounds.width - 2 * overhang
        theme.background.setFill()
        page.intersection(dirtyRect).fill()

        if overhang > 0 {
            NSColor.separatorColor.setFill()
            NSRect(x: page.minX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
            NSRect(x: page.maxX, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        }

        super.draw(dirtyRect)
    }

    // The caret only ever lives at the end of the document — clicks and
    // arrow keys can't park it mid-text (typing there is redirected anyway).
    // Ranged selections pass through untouched so select-to-copy still
    // works, and intermediate (stillSelecting) updates are left alone so
    // drag-selection tracking isn't disturbed.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if !stillSelecting,
           ranges.count == 1,
           let range = ranges.first?.rangeValue,
           range.length == 0,
           range.location != (textStorage?.length ?? 0) {
            ranges = [NSValue(range: NSRange(location: textStorage?.length ?? 0, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else {
            super.mouseDown(with: event)
            return
        }

        let start = convert(event.locationInWindow, from: nil)
        guard let storage = textStorage,
              let anchor = wordRange(at: start) else { return }

        // Anything already struck before this gesture is committed ink —
        // a retreating stroke must never lift it.
        var preStruck = IndexSet()
        storage.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if ((value as? Int) ?? 0) != 0 { preStruck.insert(integersIn: Range(range)!) }
        }

        var stroke = anchor
        scratch(anchor)

        // Keep the pen down: the stroke is a live preview while dragging —
        // it extends from the anchor word through neighboring words and
        // retreats (un-scratching) when dragged back. Release commits it.
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
              next.type == .leftMouseDragged {
            autoscroll(with: next)
            let point = convert(next.locationInWindow, from: nil)
            guard let current = wordRange(at: point) else { continue }
            let lower = min(anchor.location, current.location)
            let upper = max(anchor.location + anchor.length, current.location + current.length)
            let newStroke = NSRange(location: lower, length: upper - lower)

            let lifted = IndexSet(integersIn: Range(stroke)!)
                .subtracting(IndexSet(integersIn: Range(newStroke)!))
                .subtracting(preStruck)
            for gap in lifted.rangeView {
                storage.setAttributes(Self.baseAttributes, range: NSRange(gap))
            }
            scratch(newStroke)
            stroke = newStroke
        }
    }

    /// The word under the given point, or nil over whitespace or past the end.
    private func wordRange(at point: NSPoint) -> NSRange? {
        guard let storage = textStorage else { return nil }
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length else { return nil }
        let range = selectionRange(
            forProposedRange: NSRange(location: index, length: 0),
            granularity: .selectByWord
        )
        guard range.length > 0 else { return nil }
        let word = (storage.string as NSString).substring(with: range)
        guard word.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil else { return nil }
        return range
    }

    private func scratch(_ range: NSRange) {
        textStorage?.addAttributes(Self.scratchAttributes, range: range)
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
            // Keep surrounding whitespace outside the markers ("~~word ~~"
            // is not valid markdown), and close/reopen the markers at
            // newlines since strikethrough can't span lines.
            result += chunk.components(separatedBy: "\n").map { line -> String in
                let leading = String(line.prefix(while: \.isWhitespace))
                let trailingCount = line.reversed().prefix(while: \.isWhitespace).count
                let core = String(line.dropFirst(leading.count).dropLast(trailingCount))
                let trailing = String(line.suffix(trailingCount))
                return core.isEmpty ? line : leading + "~~" + core + "~~" + trailing
            }.joined(separator: "\n")
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

    // The view draws its own two-tone background (page + gutters).
    textView.drawsBackground = false

    // Keep the text view at least as tall as the viewport so the page
    // surface always extends to the bottom of the window.
    scrollView.contentView.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(
        forName: NSView.frameDidChangeNotification,
        object: scrollView.contentView, queue: .main
    ) { [weak textView, weak scrollView] _ in
        guard let textView, let scrollView else { return }
        // Round up and resize immediately — waiting for the next layout
        // pass leaves a sliver of scroll-view backing visible below the
        // page after a window resize.
        let height = ceil(scrollView.contentView.bounds.height)
        textView.minSize = NSSize(width: 0, height: height)
        if textView.frame.height < height {
            textView.setFrameSize(NSSize(width: textView.frame.width, height: height))
        }
    }

    scrollView.documentView = textView
    return (scrollView, textView)
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
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
        applyTheme(ScratchTextView.currentTheme)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        savePageNow()
    }

    // MARK: Themes

    @objc func selectSystemTheme(_ sender: Any?) { applyTheme(.system) }
    @objc func selectNaturalTheme(_ sender: Any?) { applyTheme(.natural) }

    @objc func toggleGutters(_ sender: Any?) {
        ScratchTextView.guttersEnabled.toggle()
        UserDefaults.standard.set(ScratchTextView.guttersEnabled, forKey: "gutters")
        applyTheme(ScratchTextView.currentTheme)
    }

    func applyTheme(_ theme: Theme) {
        ScratchTextView.currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "theme")

        // Natural is inherently a light look — pin the window chrome to
        // light appearance so scrollbars and dialogs match the paper.
        window.appearance = theme == .natural ? NSAppearance(named: .aqua) : nil
        textView.enclosingScrollView?.backgroundColor =
            ScratchTextView.guttersEnabled ? theme.gutter : theme.background
        textView.insertionPointColor = theme.caret
        textView.needsDisplay = true

        // Recolor what's already on the page, respecting scratch dimming.
        if let storage = textView.textStorage, storage.length > 0 {
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.enumerateAttribute(.strikethroughStyle, in: full) { value, range, _ in
                let struck = ((value as? Int) ?? 0) != 0
                storage.addAttribute(.foregroundColor, value: struck ? theme.dimInk : theme.ink, range: range)
            }
            storage.endEditing()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectSystemTheme(_:)) {
            menuItem.state = ScratchTextView.currentTheme == .system ? .on : .off
        } else if menuItem.action == #selector(selectNaturalTheme(_:)) {
            menuItem.state = ScratchTextView.currentTheme == .natural ? .on : .off
        } else if menuItem.action == #selector(toggleGutters(_:)) {
            menuItem.title = ScratchTextView.guttersEnabled ? "Hide Gutters" : "Show Gutters"
        }
        return true
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
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
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

    let viewMenuItem = NSMenuItem()
    let viewMenu = NSMenu(title: "View")
    let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
    let themeMenu = NSMenu(title: "Theme")
    themeMenu.addItem(withTitle: "System", action: #selector(AppDelegate.selectSystemTheme(_:)), keyEquivalent: "")
    themeMenu.addItem(withTitle: "Natural", action: #selector(AppDelegate.selectNaturalTheme(_:)), keyEquivalent: "")
    themeItem.submenu = themeMenu
    viewMenu.addItem(themeItem)
    viewMenu.addItem(withTitle: "Hide Gutters", action: #selector(AppDelegate.toggleGutters(_:)), keyEquivalent: "")
    viewMenuItem.submenu = viewMenu
    mainMenu.addItem(viewMenuItem)

    return mainMenu
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = makeMainMenu()
app.run()
