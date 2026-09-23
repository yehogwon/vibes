import AppKit
import JotsCore

/// Turns parsed Markdown spans into text attributes. The source text is never changed: syntax is
/// dimmed, or shrunk and made transparent when it is hidden, and `MarkdownLayoutFragment` draws
/// checkboxes, bullets, and backgrounds on top.
@MainActor
struct MarkdownStyler {
    var theme = MarkdownTheme() {
        didSet { cache = StyleCache(theme: theme) }
    }
    private var cache = StyleCache(theme: MarkdownTheme())

    /// Restyles every line intersecting `range` and returns the range actually restyled.
    ///
    /// - Parameters:
    ///   - revealed: Line ranges that keep their syntax visible (the caret's lines).
    ///   - codeBlocks: The text's fenced code blocks, if known.
    @discardableResult
    func style(
        _ storage: NSTextStorage, in range: NSRange, revealed: [NSRange], codeBlocks: [NSRange]? = nil
    ) -> NSRange {
        let text = storage.mutableString
        let result = MarkdownParser.parse(text, in: range, codeBlocks: codeBlocks)
        guard result.range.length > 0 else { return result.range }

        storage.beginEditing()
        storage.setAttributes(cache.baseAttributes, range: result.range)

        // Style one line at a time, in document order. Attribute runs live in a single array, so
        // splitting runs only at the end of the finished region keeps large jots linear; a
        // whole-range pass per phase made every split shift the rest of the array.
        var spanIndex = result.spans.startIndex
        var location = result.range.location
        while location < NSMaxRange(result.range) {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let first = spanIndex
            while spanIndex < result.spans.endIndex, result.spans[spanIndex].range.location < NSMaxRange(lineRange) {
                spanIndex += 1
            }
            styleLine(lineRange, spans: result.spans[first..<spanIndex], storage: storage, revealed: revealed)
            location = NSMaxRange(lineRange)
        }
        storage.endEditing()
        return result.range
    }

    // MARK: - Phases

    private struct LineInfo {
        var headingLevel: Int?
        var isCode = false
        var indent: NSRange?
    }

    /// Applies a line's spans in phases so later phases build on earlier ones: block fonts first,
    /// then inline traits, then markers (which may hide text), then the paragraph style, whose
    /// hanging indent depends on the final width of the line's prefix.
    private func styleLine(
        _ lineRange: NSRange, spans: ArraySlice<MarkdownSpan>, storage: NSTextStorage, revealed: [NSRange]
    ) {
        guard !spans.isEmpty else { return }
        var info = LineInfo()
        for span in spans {
            applyBlock(span, to: storage, info: &info, revealed: revealed)
        }
        for span in spans {
            applyInline(span, to: storage)
        }
        for span in spans {
            applyMarker(span, to: storage, revealed: revealed)
        }
        // A thematic break's `---` is drawn as a line instead, unless the caret is on it.
        for span in spans where span.kind == .horizontalRule && !isRevealed(span.range, in: revealed) {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
        }
        guard info.indent != nil || info.headingLevel != nil || info.isCode else { return }
        let indent = info.indent.map { cache.width(of: storage.attributedSubstring(from: $0)) } ?? 0
        let style = cache.paragraphStyle(
            ParagraphKey(
                headIndent: indent,
                headingLevel: info.headingLevel,
                isFirstLine: lineRange.location == 0,
                isCode: info.isCode))
        storage.addAttribute(.paragraphStyle, value: style, range: lineRange)
    }

    private func applyBlock(
        _ span: MarkdownSpan, to storage: NSTextStorage, info: inout LineInfo, revealed: [NSRange]
    ) {
        let range = span.range
        switch span.kind {
        case .heading(let level):
            info.headingLevel = level
            storage.addAttribute(.font, value: cache.headingFonts[min(max(level, 1), 6) - 1], range: range)
        case .codeBlock(let position):
            info.isCode = true
            storage.addAttributes(
                [
                    .font: cache.codeFont(matching: cache.bodyFont),
                    .markdownCodeBlock: position.rawValue,
                ], range: range)
        case .tableRow:
            storage.addAttribute(.font, value: cache.codeFont(matching: cache.bodyFont), range: range)
        case .blockquote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .horizontalRule where !isRevealed(range, in: revealed):
            storage.addAttribute(.markdownRule, value: true, range: range)
        case .indent:
            info.indent = range
        default:
            break
        }
    }

    private func applyInline(_ span: MarkdownSpan, to storage: NSTextStorage) {
        let range = span.range
        switch span.kind {
        case .strong:
            addTrait(.bold, to: storage, in: range)
        case .emphasis:
            addTrait(.italic, to: storage, in: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            storage.enumerateAttribute(.font, in: range) { value, run, _ in
                let font = value as? NSFont ?? cache.bodyFont
                storage.addAttribute(.font, value: cache.codeFont(matching: font), range: run)
            }
            storage.addAttribute(.markdownInlineCode, value: true, range: range)
        case .link(let url):
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.linkColor.withAlphaComponent(0.4),
                    .markdownLink: url,
                    .toolTip: "⌘-click to open \(url)",
                ], range: range)
        case .taskItem(checked: true):
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: range)
        default:
            break
        }
    }

    private func applyMarker(_ span: MarkdownSpan, to storage: NSTextStorage, revealed: [NSRange]) {
        let range = span.range
        switch span.kind {
        case .marker:
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        case .orderedMarker:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .bullet(let level):
            storage.addAttributes([.foregroundColor: NSColor.clear, .markdownBullet: level], range: range)
        case .quoteMarker:
            storage.addAttributes([.foregroundColor: NSColor.clear, .markdownQuoteMarker: true], range: range)
        case .checkbox(let checked):
            storage.addAttributes(
                [
                    .font: cache.checkboxFont,
                    .foregroundColor: NSColor.clear,
                    .markdownCheckbox: checked,
                ], range: range)
        case .syntax:
            if isRevealed(range, in: revealed) {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            } else {
                storage.addAttributes(cache.hiddenAttributes, range: range)
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    private func isRevealed(_ range: NSRange, in revealed: [NSRange]) -> Bool {
        guard theme.hidesSyntax else { return true }
        return revealed.contains { line in
            NSLocationInRange(range.location, line) || (line.length == 0 && line.location == range.location)
        }
    }

    private func addTrait(_ trait: NSFontDescriptor.SymbolicTraits, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            let font = value as? NSFont ?? cache.bodyFont
            storage.addAttribute(.font, value: cache.font(font, adding: trait), range: run)
        }
    }
}

private struct ParagraphKey: Hashable {
    var headIndent: CGFloat
    var headingLevel: Int?
    var isFirstLine: Bool
    var isCode: Bool
}

/// Fonts, attribute dictionaries, paragraph styles, and measurements for one theme. Styling a
/// large jot touches hundreds of thousands of spans, and creating these objects each time
/// dominated the cost.
@MainActor
private final class StyleCache {
    let theme: MarkdownTheme
    let bodyFont: NSFont
    let headingFonts: [NSFont]
    let checkboxFont: NSFont
    let baseAttributes: [NSAttributedString.Key: Any]
    let hiddenAttributes: [NSAttributedString.Key: Any]

    private var codeFonts: [NSFont: NSFont] = [:]
    private var traitFonts: [TraitKey: NSFont] = [:]
    private var paragraphStyles: [ParagraphKey: NSParagraphStyle] = [:]
    private var widths: [NSAttributedString: CGFloat] = [:]

    private struct TraitKey: Hashable {
        var font: NSFont
        var trait: UInt32
    }

    init(theme: MarkdownTheme) {
        self.theme = theme
        bodyFont = theme.bodyFont
        headingFonts = (1...6).map(theme.headingFont(level:))
        checkboxFont = .monospacedSystemFont(ofSize: theme.size, weight: .regular)
        baseAttributes = theme.baseAttributes
        hiddenAttributes = [.font: MarkdownTheme.hiddenFont, .foregroundColor: NSColor.clear]
    }

    func codeFont(matching font: NSFont) -> NSFont {
        if let cached = codeFonts[font] { return cached }
        let code = theme.codeFont(matching: font)
        codeFonts[font] = code
        return code
    }

    func font(_ font: NSFont, adding trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let key = TraitKey(font: font, trait: trait.rawValue)
        if let cached = traitFonts[key] { return cached }
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        let converted = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        traitFonts[key] = converted
        return converted
    }

    func width(of prefix: NSAttributedString) -> CGFloat {
        if let cached = widths[prefix] { return cached }
        let width = prefix.size().width.rounded(.up)
        if widths.count > 4096 { widths.removeAll() }
        widths[prefix] = width
        return width
    }

    func paragraphStyle(_ key: ParagraphKey) -> NSParagraphStyle {
        if let cached = paragraphStyles[key] { return cached }
        let style = NSMutableParagraphStyle()
        style.setParagraphStyle(theme.paragraphStyle)
        style.headIndent = key.headIndent
        if let level = key.headingLevel {
            style.paragraphSpacingBefore = key.isFirstLine ? 0 : (theme.size * (level <= 2 ? 0.8 : 0.5)).rounded()
            style.paragraphSpacing = (theme.size * 0.2).rounded()
        }
        if key.isCode {
            let padding = (theme.size * 0.8).rounded()
            style.firstLineHeadIndent = padding
            style.headIndent = padding
            style.tailIndent = -padding
            style.lineSpacing = (theme.size * 0.15).rounded()
        }
        paragraphStyles[key] = style
        return style
    }
}
