import AppKit
import JotsCore

/// A TextKit 2 text view that styles Markdown as you type.
///
/// Styling is incremental: an edit restyles only the lines it touched (or everything after it,
/// if it touched a code fence), and moving the caret restyles only the lines whose hidden syntax
/// needs to appear or disappear.
final class MarkdownTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    /// Handles Escape. When unset, Escape keeps NSTextView's default (the completion list).
    var onCancel: (() -> Void)?

    private(set) var styler = MarkdownStyler()
    /// Lines currently styled with their syntax revealed.
    private var revealedLines: [NSRange] = []
    /// Characters edited since the last restyle.
    private var dirtyRange: NSRange?
    /// An edit touched a code fence (or arrived without `shouldChangeText`), so everything after
    /// it may parse differently.
    private var needsRestyleToEnd = false
    private var sawShouldChangeText = false
    /// An edit arrived without `didChangeText` (undo and redo do this) and still needs to be
    /// styled and reported.
    private var hasUnannouncedEdit = false
    private var isReplacingAllText = false
    /// Fenced code blocks, kept current across edits so restyling a line doesn't rescan the
    /// whole document. `nil` means they must be recomputed.
    private var codeBlocks: [NSRange]?

    // MARK: - Setup

    func configure(theme: MarkdownTheme) {
        styler.theme = theme
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        insertionPointColor = .controlAccentColor
        textContainer?.lineFragmentPadding = 0
        typingAttributes = theme.baseAttributes
        textStorage?.delegate = self
        textLayoutManager?.delegate = self
        updateInsets()
    }

    /// Replaces the whole text without registering undo, then styles it.
    func setMarkdown(_ markdown: String) {
        isReplacingAllText = true
        string = markdown
        isReplacingAllText = false
        undoManager?.removeAllActions()
        dirtyRange = nil
        needsRestyleToEnd = false
        codeBlocks = nil
        restyleAll()
    }

    func apply(theme: MarkdownTheme) {
        guard theme != styler.theme else { return }
        styler.theme = theme
        typingAttributes = theme.baseAttributes
        updateInsets()
        restyleAll()
    }

    // MARK: - Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    /// Centers a column no wider than the theme's maximum line width.
    private func updateInsets() {
        let horizontal = max(28, ((bounds.width - styler.theme.maxLineWidth) / 2).rounded())
        let inset = NSSize(width: horizontal, height: 28)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    // MARK: - Styling

    private func restyleAll() {
        guard let storage = textStorage else { return }
        revealedLines = currentRevealedLines()
        styler.style(
            storage, in: NSRange(location: 0, length: storage.length), revealed: revealedLines,
            codeBlocks: currentCodeBlocks(in: storage))
        typingAttributes = styler.theme.baseAttributes
    }

    private func restyle(_ ranges: [NSRange]) {
        guard let storage = textStorage else { return }
        let length = storage.length
        let blocks = currentCodeBlocks(in: storage)
        for range in Self.merged(ranges.map { Self.clamp($0, to: length) }) {
            styler.style(storage, in: range, revealed: revealedLines, codeBlocks: blocks)
        }
        typingAttributes = styler.theme.baseAttributes
    }

    private func currentCodeBlocks(in storage: NSTextStorage) -> [NSRange] {
        if let codeBlocks { return codeBlocks }
        let blocks = MarkdownParser.codeBlocks(in: storage.mutableString)
        codeBlocks = blocks
        return blocks
    }

    /// Moves cached code blocks to account for an edit that didn't touch a fence line. Such an
    /// edit can't change where blocks start or end, only shift them or change their length.
    private func shiftCodeBlocks(for editedRange: NSRange, changeInLength delta: Int, newLength: Int) {
        guard let blocks = codeBlocks else { return }
        let oldEditEnd = NSMaxRange(editedRange) - delta
        let oldLength = newLength - delta
        codeBlocks = blocks.map { block in
            var block = block
            // Text appended to an unclosed block at the end of the document joins that block.
            let appendsToOpenBlock = NSMaxRange(block) == oldLength && editedRange.location == oldLength
            if NSMaxRange(block) <= editedRange.location && !appendsToOpenBlock {
                return block
            }
            if block.location >= oldEditEnd {
                block.location += delta
            } else {
                block.length += delta
            }
            return block
        }
    }

    private func restyleAfterEdit() {
        guard !hasMarkedText(), let storage = textStorage, let edited = dirtyRange else { return }
        dirtyRange = nil
        let text = storage.mutableString
        var dirty = Self.clamp(edited, to: text.length)
        if needsRestyleToEnd || MarkdownParser.containsFence(text, in: dirty) {
            let start = text.lineRange(for: dirty).location
            dirty = NSRange(location: start, length: text.length - start)
            codeBlocks = nil
        }
        needsRestyleToEnd = false

        let previouslyRevealed = revealedLines
        revealedLines = currentRevealedLines()
        restyle([dirty] + previouslyRevealed + revealedLines)
    }

    private func updateRevealedLines() {
        // While an edit is pending, `didChangeText` restyles the revealed lines itself.
        guard styler.theme.hidesSyntax, dirtyRange == nil, !hasMarkedText(), textStorage != nil else { return }
        let lines = currentRevealedLines()
        guard lines != revealedLines else { return }
        let previous = revealedLines
        revealedLines = lines
        restyle(previous + lines)
    }

    private func currentRevealedLines() -> [NSRange] {
        guard let storage = textStorage else { return [] }
        let text = storage.mutableString
        return selectedRanges.map { text.lineRange(for: Self.clamp($0.rangeValue, to: text.length)) }
    }

    // MARK: - Editing lifecycle

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        guard super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else {
            return false
        }
        sawShouldChangeText = true
        if !needsRestyleToEnd, let text = textStorage?.mutableString {
            needsRestyleToEnd = affectedRanges.contains { value in
                MarkdownParser.containsFence(text, in: Self.clamp(value.rangeValue, to: text.length))
            }
        }
        return true
    }

    override func didChangeText() {
        super.didChangeText()
        hasUnannouncedEdit = false
        restyleAfterEdit()
        onTextChange?(string)
    }

    private func handleUnannouncedEdit() {
        guard !hasUnannouncedEdit, !isReplacingAllText else { return }
        hasUnannouncedEdit = true
        Task { @MainActor [weak self] in
            guard let self, self.hasUnannouncedEdit else { return }
            self.hasUnannouncedEdit = false
            self.restyleAfterEdit()
            self.onTextChange?(self.string)
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Revealing syntax reflows the line, so wait until a drag-selection is finished.
        if !stillSelecting {
            updateRevealedLines()
        }
    }

    override func unmarkText() {
        super.unmarkText()
        restyleAfterEdit()
    }

    /// Replaces text as a single undoable change.
    func apply(_ edit: TextEdit) {
        guard let storage = textStorage, shouldChangeText(in: edit.range, replacementString: edit.replacement) else {
            return
        }
        storage.replaceCharacters(in: edit.range, with: edit.replacement)
        setSelectedRange(edit.selection)
        didChangeText()
        scrollRangeToVisible(edit.selection)
    }

    private func perform(_ command: (NSString, NSRange) -> TextEdit?) {
        guard isEditable, let text = textStorage?.mutableString, let edit = command(text, selectedRange()) else {
            return
        }
        apply(edit)
    }

    // MARK: - Keys

    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), let text = textStorage?.mutableString,
            let edit = MarkdownEdits.continueList(in: text, selection: selectedRange())
        {
            apply(edit)
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if let text = textStorage?.mutableString,
            let edit = MarkdownEdits.indent(in: text, selection: selectedRange(), outdent: false)
        {
            apply(edit)
            return
        }
        super.insertTab(sender)
    }

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        // Never fall through: the default moves focus out of the editor.
        perform { MarkdownEdits.indent(in: $0, selection: $1, outdent: true) }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if handleCheckboxClick(at: point) {
            return
        }
        if event.modifierFlags.contains(.command), let url = link(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    private func handleCheckboxClick(at point: NSPoint) -> Bool {
        guard isEditable, let storage = textStorage,
            let range = attributeRange(.markdownCheckbox, near: point, in: storage)
        else { return false }
        let text = storage.mutableString
        guard let edit = MarkdownEdits.toggleCheckbox(in: text, onLineAt: range.location, selection: selectedRange())
        else { return false }
        apply(edit)
        return true
    }

    private func link(at point: NSPoint) -> URL? {
        guard let storage = textStorage, let range = attributeRange(.markdownLink, near: point, in: storage),
            let string = storage.attribute(.markdownLink, at: range.location, effectiveRange: nil) as? String
        else { return nil }
        if let url = URL(string: string), url.scheme != nil {
            return url
        }
        return URL(string: "https://" + string)
    }

    /// The run of `key` under `point`, checked against the run's drawn rectangle so clicks in
    /// empty space next to it don't count.
    private func attributeRange(_ key: NSAttributedString.Key, near point: NSPoint, in storage: NSTextStorage)
        -> NSRange?
    {
        let index = characterIndexForInsertion(at: point)
        for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange()
            guard
                storage.attribute(
                    key, at: candidate, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
                    != nil
            else { continue }
            if rect(for: range).insetBy(dx: -3, dy: -2).contains(point) {
                return range
            }
        }
        return nil
    }

    private func rect(for range: NSRange) -> NSRect {
        guard let window else { return .zero }
        let screenRect = firstRect(forCharacterRange: range, actualRange: nil)
        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }

    // MARK: - Format commands

    @objc func formatBold(_ sender: Any?) {
        perform { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) }
    }

    @objc func formatItalic(_ sender: Any?) {
        perform { MarkdownEdits.toggleWrap("*", in: $0, selection: $1) }
    }

    @objc func formatStrikethrough(_ sender: Any?) {
        perform { MarkdownEdits.toggleWrap("~~", in: $0, selection: $1) }
    }

    @objc func formatInlineCode(_ sender: Any?) {
        perform { MarkdownEdits.toggleWrap("`", in: $0, selection: $1) }
    }

    @objc func formatLink(_ sender: Any?) {
        perform { MarkdownEdits.insertLink(in: $0, selection: $1) }
    }

    @objc func formatHeading1(_ sender: Any?) {
        perform { MarkdownEdits.setHeading(1, in: $0, selection: $1) }
    }

    @objc func formatHeading2(_ sender: Any?) {
        perform { MarkdownEdits.setHeading(2, in: $0, selection: $1) }
    }

    @objc func formatHeading3(_ sender: Any?) {
        perform { MarkdownEdits.setHeading(3, in: $0, selection: $1) }
    }

    @objc func formatBody(_ sender: Any?) {
        perform { MarkdownEdits.setHeading(0, in: $0, selection: $1) }
    }

    @objc func formatBulletList(_ sender: Any?) {
        perform { MarkdownEdits.toggleLineStyle(.bullet, in: $0, selection: $1) }
    }

    @objc func formatNumberedList(_ sender: Any?) {
        perform { MarkdownEdits.toggleLineStyle(.numbered, in: $0, selection: $1) }
    }

    @objc func formatChecklist(_ sender: Any?) {
        perform { MarkdownEdits.toggleLineStyle(.task, in: $0, selection: $1) }
    }

    @objc func formatQuote(_ sender: Any?) {
        perform { MarkdownEdits.toggleLineStyle(.quote, in: $0, selection: $1) }
    }

    @objc func formatToggleDone(_ sender: Any?) {
        perform { MarkdownEdits.toggleTaskCompletion(in: $0, selection: $1) }
    }

    // MARK: - Range helpers

    static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location < $1.location }
        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1] = NSUnionRange(last, range)
            } else {
                result.append(range)
            }
        }
        return result
    }
}

// MARK: - NSTextStorageDelegate

extension MarkdownTextView: NSTextStorageDelegate {
    nonisolated func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let newLength = textStorage.length
        MainActor.assumeIsolated {
            if var dirty = dirtyRange {
                if dirty.location > editedRange.location {
                    dirty.location = max(editedRange.location, dirty.location + delta)
                }
                dirtyRange = NSUnionRange(dirty, editedRange)
            } else {
                dirtyRange = editedRange
            }
            if !sawShouldChangeText {
                needsRestyleToEnd = true
                handleUnannouncedEdit()
            }
            sawShouldChangeText = false
            if needsRestyleToEnd {
                codeBlocks = nil
            } else {
                shiftCodeBlocks(for: editedRange, changeInLength: delta, newLength: newLength)
            }
        }
    }
}

// MARK: - NSTextLayoutManagerDelegate

extension MarkdownTextView: NSTextLayoutManagerDelegate {
    nonisolated func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
