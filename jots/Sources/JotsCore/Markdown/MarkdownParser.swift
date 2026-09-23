import Foundation

/// A small, line-oriented Markdown highlighter.
///
/// It is not a CommonMark renderer: it finds the constructs a writer sees while typing (headings,
/// emphasis, code, links, lists, tasks, quotes, rules, tables, fenced code) and reports where they
/// are, so the editor can style the source in place. Fenced code is the only construct that spans
/// lines; everything else is decided one line at a time, which keeps re-styling after an edit
/// local to the edited lines.
public enum MarkdownParser {
    public struct Result: Sendable {
        /// The range that was parsed: the requested range grown to whole lines and whole code
        /// blocks. Callers should reset styling across all of it.
        public var range: NSRange
        public var spans: [MarkdownSpan]
    }

    /// Parses the lines that intersect `range`.
    ///
    /// - Parameter codeBlocks: The result of ``codeBlocks(in:)`` for `text`, if the caller keeps
    ///   it up to date; computed otherwise.
    public static func parse(_ text: NSString, in range: NSRange, codeBlocks knownBlocks: [NSRange]? = nil) -> Result {
        let length = text.length
        let clamped = NSRange(
            location: min(max(range.location, 0), length),
            length: max(0, min(range.length, length - min(max(range.location, 0), length))))
        var target = text.lineRange(for: clamped)

        let blocks = knownBlocks ?? codeBlocks(in: text)
        for block in blocks where intersects(block, target) {
            target = NSUnionRange(target, block)
        }

        var spans: [MarkdownSpan] = []
        var location = target.location
        let end = NSMaxRange(target)
        var blockIndex = blocks.firstIndex { NSMaxRange($0) > location } ?? blocks.endIndex
        repeat {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = Line(start: location, contentsEnd: contentsEnd, end: lineEnd)

            while blockIndex < blocks.endIndex, NSMaxRange(blocks[blockIndex]) <= location {
                blockIndex += 1
            }
            if blockIndex < blocks.endIndex, NSLocationInRange(location, blocks[blockIndex]) {
                parseCodeLine(line, in: blocks[blockIndex], text: text, into: &spans)
            } else {
                LineParser(text: text, line: line).parse(into: &spans)
            }
            location = lineEnd
        } while location < end

        return Result(range: target, spans: spans)
    }

    /// Ranges of fenced code blocks, each covering whole lines from the opening fence through the
    /// closing fence (or the end of the text, if the fence is never closed).
    public static func codeBlocks(in text: NSString) -> [NSRange] {
        var blocks: [NSRange] = []
        var open: (start: Int, fence: Fence)?
        var location = 0
        let length = text.length
        while location < length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            if let fence = Fence(text: text, start: location, contentsEnd: contentsEnd) {
                if let opening = open {
                    if fence.closes(opening.fence) {
                        blocks.append(NSRange(location: opening.start, length: lineEnd - opening.start))
                        open = nil
                    }
                } else if fence.canOpen {
                    open = (location, fence)
                }
            }
            location = lineEnd
        }
        if let opening = open {
            blocks.append(NSRange(location: opening.start, length: length - opening.start))
        }
        return blocks
    }

    /// Whether any line intersecting `range` is a code fence. Edits that touch a fence can change
    /// how the rest of the document parses.
    public static func containsFence(_ text: NSString, in range: NSRange) -> Bool {
        let lines = text.lineRange(for: range)
        var location = lines.location
        repeat {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            if Fence(text: text, start: location, contentsEnd: contentsEnd) != nil {
                return true
            }
            location = lineEnd
        } while location < NSMaxRange(lines)
        return false
    }

    /// Whether a line (without its line break) is a thematic break such as `---` or `* * *`.
    public static func isHorizontalRule(_ line: String) -> Bool {
        let ns = line as NSString
        return Patterns.rule.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func parseCodeLine(_ line: Line, in block: NSRange, text: NSString, into spans: inout [MarkdownSpan])
    {
        let isFirst = line.start == block.location
        let isLast = line.end >= NSMaxRange(block)
        let position: MarkdownSpan.CodeBlockPosition =
            switch (isFirst, isLast) {
            case (true, true): .single
            case (true, false): .first
            case (false, true): .last
            case (false, false): .middle
            }
        spans.append(MarkdownSpan(.codeBlock(position), line.fullRange))
        let isFence =
            (isFirst || isLast) && Fence(text: text, start: line.start, contentsEnd: line.contentsEnd) != nil
        if isFence, line.contentsRange.length > 0 {
            spans.append(MarkdownSpan(.marker, line.contentsRange))
        }
    }

    private static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        b.length == 0 ? NSLocationInRange(b.location, a) : NSIntersectionRange(a, b).length > 0
    }
}

// MARK: - Lines

struct Line {
    var start: Int
    var contentsEnd: Int
    var end: Int

    var contentsRange: NSRange { NSRange(location: start, length: contentsEnd - start) }
    var fullRange: NSRange { NSRange(location: start, length: end - start) }
}

/// A code fence: up to three spaces, then three or more backticks or tildes.
struct Fence {
    var character: unichar
    var count: Int
    /// Nothing but whitespace follows the fence characters.
    var isBare: Bool
    /// Backtick fences can't have backticks in their info string.
    var canOpen: Bool

    init?(text: NSString, start: Int, contentsEnd: Int) {
        var index = start
        while index < contentsEnd, index - start < 3, text.character(at: index) == Ascii.space {
            index += 1
        }
        guard index < contentsEnd else { return nil }
        let character = text.character(at: index)
        guard character == Ascii.backtick || character == Ascii.tilde else { return nil }
        var count = 0
        while index < contentsEnd, text.character(at: index) == character {
            count += 1
            index += 1
        }
        guard count >= 3 else { return nil }

        var isBare = true
        var canOpen = true
        while index < contentsEnd {
            let next = text.character(at: index)
            if next != Ascii.space && next != Ascii.tab {
                isBare = false
            }
            if character == Ascii.backtick && next == Ascii.backtick {
                canOpen = false
            }
            index += 1
        }
        self.character = character
        self.count = count
        self.isBare = isBare
        self.canOpen = canOpen
    }

    func closes(_ opening: Fence) -> Bool {
        isBare && character == opening.character && count >= opening.count
    }
}

enum Ascii {
    static let tab = unichar(0x09)
    static let space = unichar(0x20)
    static let backslash = unichar(0x5C)
    static let backtick = unichar(0x60)
    static let tilde = unichar(0x7E)
    static let pipe = unichar(0x7C)
    static let greaterThan = unichar(0x3E)
}

// MARK: - Patterns

/// A compiled regular expression that can live in a `static let`. `NSRegularExpression` is
/// immutable and thread-safe, but not every SDK marks it `Sendable`.
struct Pattern: @unchecked Sendable {
    private let expression: NSRegularExpression

    init(_ pattern: String) {
        do {
            expression = try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid pattern \(pattern): \(error)")
        }
    }

    func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        expression.firstMatch(in: string, range: range)
    }

    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        expression.matches(in: string, range: range)
    }
}

struct EmphasisRule: Sendable {
    var pattern: Pattern
    var markerLength: Int
    var kinds: [MarkdownSpan.Kind]
}

enum Patterns {
    static let heading = Pattern(#"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    static let rule = Pattern(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let quote = Pattern(#"^ {0,3}>[ \t]?"#)
    static let task = Pattern(#"^([ \t]*)([-*+])([ \t]+)(\[[ xX]\])(?:[ \t]+|$)"#)
    static let bullet = Pattern(#"^([ \t]*)([-*+])(?:[ \t]+|$)"#)
    static let ordered = Pattern(#"^([ \t]*)(\d{1,9}[.)])(?:[ \t]+|$)"#)
    static let tableRow = Pattern(#"^[ \t]*\|.*\|[ \t]*$"#)
    static let tableDelimiter = Pattern(#"^[ \t]*\|?(?:[ \t]*:?-+:?[ \t]*\|)+(?:[ \t]*:?-+:?[ \t]*)?$"#)

    static let link = Pattern(
        #"(!?\[)([^\[\]\n]*)(\]\()([^()\s]*(?:\([^()\s]*\)[^()\s]*)*)((?:[ \t]+"[^"\n]*")?\))"#)
    static let autolink = Pattern(#"<(https?://[^\s<>]+)>"#)
    static let bareURL = Pattern(#"(?<![\w/])https?://[^\s<>\[\]]+"#)

    /// Tried in order. Each accepted match masks its markers so later rules can't reuse them,
    /// which is how `***both***` and `**bold *and italic***` resolve.
    static let emphasis: [EmphasisRule] = [
        EmphasisRule(
            pattern: Pattern(#"(?<!\*)\*\*\*(?![\s*])(.+?)(?<![\s*])\*\*\*(?!\*)"#), markerLength: 3,
            kinds: [.strong, .emphasis]),
        EmphasisRule(
            pattern: Pattern(#"(?<![\w_])___(?![\s_])(.+?)(?<![\s_])___(?![\w_])"#), markerLength: 3,
            kinds: [.strong, .emphasis]),
        EmphasisRule(
            pattern: Pattern(#"(?<!\*)\*\*(?![\s*])(.+?)(?<![\s*])\*\*(?!\*)"#), markerLength: 2, kinds: [.strong]),
        EmphasisRule(
            pattern: Pattern(#"(?<![\w_])__(?![\s_])(.+?)(?<![\s_])__(?![\w_])"#), markerLength: 2, kinds: [.strong]),
        EmphasisRule(
            pattern: Pattern(#"(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)"#), markerLength: 1, kinds: [.emphasis]),
        EmphasisRule(
            pattern: Pattern(#"(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])"#), markerLength: 1, kinds: [.emphasis]),
        EmphasisRule(
            pattern: Pattern(#"(?<!~)~~(?![\s~])(.+?)(?<![\s~])~~(?!~)"#), markerLength: 2, kinds: [.strikethrough]),
    ]
}

// MARK: - Line parser

/// Parses one line that is not inside a fenced code block.
struct LineParser {
    let text: NSString
    let line: Line
    /// The line's characters without the line break. Offsets into it are relative to
    /// `line.start`.
    let source: NSString
    let string: String

    init(text: NSString, line: Line) {
        self.text = text
        self.line = line
        self.source = text.substring(with: line.contentsRange) as NSString
        self.string = source as String
    }

    func parse(into spans: inout [MarkdownSpan]) {
        var position = 0
        var indentEnd = 0

        // Blockquote markers, possibly nested: "> > text".
        var depth = 0
        while let match = Patterns.quote.firstMatch(in: string, range: remaining(from: position)) {
            let marker = source.range(of: ">", range: match.range)
            spans.append(MarkdownSpan(.quoteMarker, absolute(marker)))
            position = NSMaxRange(match.range)
            indentEnd = position
            depth += 1
        }
        if depth > 0 {
            spans.append(MarkdownSpan(.blockquote(depth: depth), line.fullRange))
        }

        let rest = remaining(from: position)

        if let match = Patterns.heading.firstMatch(in: string, range: rest) {
            let level = match.range(at: 1).length
            spans.append(MarkdownSpan(.heading(level: level), line.fullRange))
            let content = remaining(from: NSMaxRange(match.range))
            // An empty heading keeps its "#" visible; hiding it would leave nothing to click on.
            let hasContent = source.substring(with: content).contains { !$0.isWhitespace }
            spans.append(MarkdownSpan(hasContent ? .syntax : .marker, absolute(match.range)))
            parseInline(in: content, into: &spans)
            addIndent(upTo: indentEnd, into: &spans)
            return
        }

        if Patterns.rule.firstMatch(in: string, range: rest) != nil {
            spans.append(MarkdownSpan(.horizontalRule, line.fullRange))
            spans.append(MarkdownSpan(.marker, absolute(rest)))
            return
        }

        if depth == 0, Patterns.tableRow.firstMatch(in: string, range: rest) != nil {
            parseTableRow(in: rest, into: &spans)
            return
        }

        if let match = Patterns.task.firstMatch(in: string, range: rest) {
            let checkbox = match.range(at: 4)
            let checked = source.substring(with: checkbox).lowercased() == "[x]"
            let bulletAndSpace = NSRange(
                location: match.range(at: 2).location,
                length: checkbox.location - match.range(at: 2).location)
            spans.append(MarkdownSpan(.syntax, absolute(bulletAndSpace)))
            spans.append(MarkdownSpan(.checkbox(checked: checked), absolute(checkbox)))
            position = NSMaxRange(match.range)
            indentEnd = position
            let content = remaining(from: position)
            if content.length > 0 {
                spans.append(MarkdownSpan(.taskItem(checked: checked), absolute(content)))
            }
        } else if let match = Patterns.bullet.firstMatch(in: string, range: rest) {
            let level = Self.indentLevel(columns: columns(in: match.range(at: 1)))
            spans.append(MarkdownSpan(.bullet(level: level), absolute(match.range(at: 2))))
            position = NSMaxRange(match.range)
            indentEnd = position
        } else if let match = Patterns.ordered.firstMatch(in: string, range: rest) {
            spans.append(MarkdownSpan(.orderedMarker, absolute(match.range(at: 2))))
            position = NSMaxRange(match.range)
            indentEnd = position
        }

        addIndent(upTo: indentEnd, into: &spans)
        parseInline(in: remaining(from: position), into: &spans)
    }

    private func parseTableRow(in range: NSRange, into spans: inout [MarkdownSpan]) {
        spans.append(MarkdownSpan(.tableRow, line.fullRange))
        if Patterns.tableDelimiter.firstMatch(in: string, range: range) != nil {
            spans.append(MarkdownSpan(.marker, absolute(range)))
            return
        }
        var index = range.location
        while index < NSMaxRange(range) {
            let character = source.character(at: index)
            if character == Ascii.backslash {
                index += 2
                continue
            }
            if character == Ascii.pipe {
                spans.append(MarkdownSpan(.marker, absolute(NSRange(location: index, length: 1))))
            }
            index += 1
        }
        parseInline(in: range, into: &spans)
    }

    private func addIndent(upTo end: Int, into spans: inout [MarkdownSpan]) {
        if end > 0 {
            spans.append(MarkdownSpan(.indent, absolute(NSRange(location: 0, length: end))))
        }
    }

    // MARK: Inline

    private func parseInline(in range: NSRange, into spans: inout [MarkdownSpan]) {
        guard range.length > 0 else { return }
        // Protected regions are replaced by a placeholder so that later patterns can't match
        // inside code, URLs, escapes, or markers that were already claimed.
        let masked = NSMutableString(string: source)

        parseCodeSpans(in: range, masked: masked, into: &spans)
        parseEscapes(in: range, masked: masked, into: &spans)
        parseLinks(in: range, masked: masked, into: &spans)
        parseEmphasis(in: range, masked: masked, into: &spans)
    }

    private func parseCodeSpans(in range: NSRange, masked: NSMutableString, into spans: inout [MarkdownSpan]) {
        let end = NSMaxRange(range)
        var index = range.location
        while index < end {
            guard source.character(at: index) == Ascii.backtick else {
                index += 1
                continue
            }
            let openLength = backtickRun(at: index, end: end)
            var search = index + openLength
            var closing: Int?
            while search < end {
                if source.character(at: search) == Ascii.backtick {
                    let runLength = backtickRun(at: search, end: end)
                    if runLength == openLength {
                        closing = search
                        break
                    }
                    search += runLength
                } else {
                    search += 1
                }
            }
            guard let close = closing else {
                index += openLength
                continue
            }
            let whole = NSRange(location: index, length: close + openLength - index)
            spans.append(MarkdownSpan(.inlineCode, absolute(whole)))
            spans.append(MarkdownSpan(.syntax, absolute(NSRange(location: index, length: openLength))))
            spans.append(MarkdownSpan(.syntax, absolute(NSRange(location: close, length: openLength))))
            mask(whole, in: masked)
            index = NSMaxRange(whole)
        }
    }

    private func backtickRun(at start: Int, end: Int) -> Int {
        var index = start
        while index < end, source.character(at: index) == Ascii.backtick {
            index += 1
        }
        return index - start
    }

    private func parseEscapes(in range: NSRange, masked: NSMutableString, into spans: inout [MarkdownSpan]) {
        var index = range.location
        let end = NSMaxRange(range)
        while index < end - 1 {
            if masked.character(at: index) == Ascii.backslash, Self.isEscapable(masked.character(at: index + 1)) {
                spans.append(MarkdownSpan(.syntax, absolute(NSRange(location: index, length: 1))))
                mask(NSRange(location: index, length: 2), in: masked)
                index += 2
            } else {
                index += 1
            }
        }
    }

    private func parseLinks(in range: NSRange, masked: NSMutableString, into spans: inout [MarkdownSpan]) {
        let snapshot = masked as String
        for match in Patterns.link.matches(in: snapshot, range: range) {
            let open = match.range(at: 1)
            let label = match.range(at: 2)
            let url = source.substring(with: match.range(at: 4))
            let tail = NSRange(
                location: match.range(at: 3).location, length: NSMaxRange(match.range) - match.range(at: 3).location)
            // An empty label would leave nothing visible once the syntax is hidden.
            let syntaxKind: MarkdownSpan.Kind = label.length > 0 ? .syntax : .marker
            spans.append(MarkdownSpan(syntaxKind, absolute(open)))
            spans.append(MarkdownSpan(syntaxKind, absolute(tail)))
            spans.append(MarkdownSpan(.link(url), absolute(label.length > 0 ? label : match.range(at: 4))))
            mask(open, in: masked)
            mask(tail, in: masked)
        }

        for match in Patterns.autolink.matches(in: masked as String, range: range) {
            let inner = match.range(at: 1)
            spans.append(MarkdownSpan(.syntax, absolute(NSRange(location: match.range.location, length: 1))))
            spans.append(MarkdownSpan(.syntax, absolute(NSRange(location: NSMaxRange(match.range) - 1, length: 1))))
            spans.append(MarkdownSpan(.link(source.substring(with: inner)), absolute(inner)))
            mask(match.range, in: masked)
        }

        for match in Patterns.bareURL.matches(in: masked as String, range: range) {
            let trimmed = Self.trimTrailingPunctuation(match.range, in: source)
            guard trimmed.length > 0 else { continue }
            spans.append(MarkdownSpan(.link(source.substring(with: trimmed)), absolute(trimmed)))
            mask(trimmed, in: masked)
        }
    }

    private func parseEmphasis(in range: NSRange, masked: NSMutableString, into spans: inout [MarkdownSpan]) {
        for rule in Patterns.emphasis {
            for match in rule.pattern.matches(in: masked as String, range: range) {
                let open = NSRange(location: match.range.location, length: rule.markerLength)
                let close = NSRange(location: NSMaxRange(match.range) - rule.markerLength, length: rule.markerLength)
                let content = match.range(at: 1)
                for kind in rule.kinds {
                    spans.append(MarkdownSpan(kind, absolute(content)))
                }
                spans.append(MarkdownSpan(.syntax, absolute(open)))
                spans.append(MarkdownSpan(.syntax, absolute(close)))
                mask(open, in: masked)
                mask(close, in: masked)
            }
        }
    }

    // MARK: Helpers

    private func remaining(from position: Int) -> NSRange {
        NSRange(location: position, length: source.length - position)
    }

    private func absolute(_ range: NSRange) -> NSRange {
        NSRange(location: line.start + range.location, length: range.length)
    }

    private func mask(_ range: NSRange, in masked: NSMutableString) {
        masked.replaceCharacters(in: range, with: String(repeating: "\u{E000}", count: range.length))
    }

    private func columns(in range: NSRange) -> Int {
        var columns = 0
        for index in range.location..<NSMaxRange(range) {
            columns += source.character(at: index) == Ascii.tab ? 4 - columns % 4 : 1
        }
        return columns
    }

    /// Nesting depth for four-space (or tab) indentation; two spaces also count as one level.
    static func indentLevel(columns: Int) -> Int {
        (columns + 2) / 4
    }

    static func isEscapable(_ character: unichar) -> Bool {
        guard character < 128, let scalar = Unicode.Scalar(character) else { return false }
        return "\\`*_{}[]()#+-.!~|>".unicodeScalars.contains(scalar)
    }

    static func trimTrailingPunctuation(_ range: NSRange, in source: NSString) -> NSRange {
        var length = range.length
        while length > 0 {
            let last = source.character(at: range.location + length - 1)
            guard let scalar = Unicode.Scalar(last), ".,:;!?'\")*_~".unicodeScalars.contains(scalar) else { break }
            if scalar == ")" {
                let candidate = source.substring(with: NSRange(location: range.location, length: length))
                let opens = candidate.filter { $0 == "(" }.count
                let closes = candidate.filter { $0 == ")" }.count
                if opens >= closes { break }
            }
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}
