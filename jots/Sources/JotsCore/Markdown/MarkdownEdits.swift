import Foundation

/// A single replacement produced by an editing command.
public struct TextEdit: Equatable, Sendable {
    /// The range to replace, in the original text.
    public var range: NSRange
    public var replacement: String
    /// The selection to set afterwards, in the edited text.
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Markdown-aware editing commands. Each returns the edit to apply rather than mutating text, so
/// the editor can route it through undo and the logic can be tested without a text view.
public enum MarkdownEdits {
    public enum LineStyle: Sendable {
        case bullet, numbered, task, quote
    }

    static let indentUnit = "    "

    // MARK: - Inline

    /// Wraps the selection in `marker` (`**`, `*`, `~~`, `` ` ``), or unwraps it if it is already
    /// wrapped. With no selection, inserts an empty pair and puts the caret between them.
    public static func toggleWrap(_ marker: String, in text: NSString, selection: NSRange) -> TextEdit {
        let markerLength = (marker as NSString).length
        let selected = text.substring(with: selection)

        if selection.length == 0 {
            let before = NSRange(location: selection.location - markerLength, length: markerLength)
            let after = NSRange(location: selection.location, length: markerLength)
            if before.location >= 0, NSMaxRange(after) <= text.length,
                text.substring(with: before) == marker, text.substring(with: after) == marker
            {
                let pair = NSRange(location: before.location, length: markerLength * 2)
                return TextEdit(range: pair, replacement: "", selection: NSRange(location: before.location, length: 0))
            }
            return TextEdit(
                range: selection, replacement: marker + marker,
                selection: NSRange(location: selection.location + markerLength, length: 0))
        }

        // Already wrapped outside the selection: **|text|**
        if isWrapped(text, range: selection, marker: marker) {
            let outer = NSRange(
                location: selection.location - markerLength, length: selection.length + markerLength * 2)
            return TextEdit(
                range: outer, replacement: selected,
                selection: NSRange(location: outer.location, length: selection.length))
        }

        // Markers are part of the selection: |**text**|
        let selectedNS = selected as NSString
        if selection.length > markerLength * 2,
            isWrapped(
                selectedNS, range: NSRange(location: markerLength, length: selection.length - markerLength * 2),
                marker: marker)
        {
            let inner = selectedNS.substring(
                with: NSRange(location: markerLength, length: selection.length - markerLength * 2))
            return TextEdit(
                range: selection, replacement: inner,
                selection: NSRange(location: selection.location, length: (inner as NSString).length))
        }

        return TextEdit(
            range: selection, replacement: marker + selected + marker,
            selection: NSRange(location: selection.location + markerLength, length: selection.length))
    }

    /// Inserts `[label](url)`, using the selection as the label (or as the URL, if it looks like
    /// one), and leaves the caret where the missing part goes.
    public static func insertLink(in text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        let length = (selected as NSString).length
        if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
            return TextEdit(
                range: selection, replacement: "[](\(selected))",
                selection: NSRange(location: selection.location + 1, length: 0))
        }
        if length == 0 {
            return TextEdit(
                range: selection, replacement: "[]()", selection: NSRange(location: selection.location + 1, length: 0))
        }
        return TextEdit(
            range: selection, replacement: "[\(selected)]()",
            selection: NSRange(location: selection.location + length + 3, length: 0))
    }

    // MARK: - Line prefixes

    /// Turns the selected lines into (or back out of) a bulleted, numbered, task, or quote list.
    public static func toggleLineStyle(_ style: LineStyle, in text: NSString, selection: NSRange) -> TextEdit {
        let lines = targetLines(in: text, selection: selection)
        let prefixes = lines.map { ListPrefix(text: text, line: $0) }
        let allStyled = prefixes.allSatisfy { $0.has(style) }

        var changes: [PrefixChange] = []
        var number = 1
        for (line, prefix) in zip(lines, prefixes) {
            switch style {
            case .quote:
                if allStyled {
                    changes.append(PrefixChange(location: line.start, length: prefix.quoteLength, replacement: ""))
                } else {
                    changes.append(PrefixChange(location: line.start, length: 0, replacement: "> "))
                }
            case .bullet, .numbered, .task:
                let markerStart = line.start + prefix.indentLength
                let replacement: String
                if allStyled {
                    replacement = ""
                } else {
                    switch style {
                    case .bullet: replacement = "- "
                    case .numbered: replacement = "\(number). "
                    default: replacement = prefix.kind == .task(checked: true) ? "- [x] " : "- [ ] "
                    }
                    number += 1
                }
                changes.append(
                    PrefixChange(location: markerStart, length: prefix.markerLength, replacement: replacement))
            }
        }
        return apply(changes, in: text, lines: lines, selection: selection)
    }

    /// Makes the selected lines headings of `level` (1–6), or plain text for level 0. Applying
    /// the same level to a single heading turns it back into plain text.
    public static func setHeading(_ level: Int, in text: NSString, selection: NSRange) -> TextEdit {
        let lines = targetLines(in: text, selection: selection)
        let existing = lines.map { headingPrefix(in: text, line: $0) }
        let toggleOff = lines.count == 1 && existing[0].level == level
        let marker = level > 0 && !toggleOff ? String(repeating: "#", count: level) + " " : ""
        let changes = zip(lines, existing).map { line, heading in
            PrefixChange(location: line.start, length: heading.length, replacement: marker)
        }
        return apply(changes, in: text, lines: lines, selection: selection)
    }

    /// Checks or unchecks the task on the line containing `location`.
    public static func toggleCheckbox(in text: NSString, onLineAt location: Int, selection: NSRange) -> TextEdit? {
        let line = Line(text: text, containing: location)
        let prefix = ListPrefix(text: text, line: line)
        guard case .task(let checked) = prefix.kind, let box = prefix.checkboxRange else { return nil }
        let mark = NSRange(location: box.location + 1, length: 1)
        return TextEdit(range: mark, replacement: checked ? " " : "x", selection: selection)
    }

    /// Checks every task in the selection, or unchecks them all if they are already checked.
    public static func toggleTaskCompletion(in text: NSString, selection: NSRange) -> TextEdit? {
        let lines = targetLines(in: text, selection: selection)
        let tasks = lines.compactMap { line -> (NSRange, Bool)? in
            let prefix = ListPrefix(text: text, line: line)
            guard case .task(let checked) = prefix.kind, let box = prefix.checkboxRange else { return nil }
            return (NSRange(location: box.location + 1, length: 1), checked)
        }
        guard !tasks.isEmpty else { return nil }
        let check = tasks.contains { !$0.1 }
        let changes = tasks.map { PrefixChange(location: $0.0.location, length: 1, replacement: check ? "x" : " ") }
        return apply(changes, in: text, lines: lines, selection: selection)
    }

    // MARK: - Return and Tab

    /// What Return should do inside a list or quote: continue it with a new marker, or end it when
    /// the current item is empty. Returns `nil` to fall back to a plain line break.
    public static func continueList(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let line = Line(text: text, containing: selection.location)
        let caret = selection.location - line.start
        let prefix = ListPrefix(text: text, line: line)
        let contentLength = line.contentsEnd - line.start

        if let kind = prefix.kind {
            let prefixEnd = prefix.indentLength + prefix.markerLength
            guard caret >= prefixEnd else { return nil }
            let content = text.substring(
                with: NSRange(location: line.start + prefixEnd, length: contentLength - prefixEnd))
            if content.allSatisfy(\.isWhitespace) {
                return endListItem(prefix, line: line)
            }
            let indent = text.substring(with: NSRange(location: line.start, length: prefix.indentLength))
            let marker: String
            switch kind {
            case .bullet(let character): marker = "\(character) "
            case .task: marker = "\(prefix.bulletCharacter ?? "-") [ ] "
            case .numbered(let number, let delimiter): marker = "\(number + 1)\(delimiter) "
            }
            return insertion("\n" + indent + marker, at: selection.location)
        }

        if prefix.quoteLength > 0 {
            guard caret >= prefix.quoteLength else { return nil }
            let quote = text.substring(with: NSRange(location: line.start, length: prefix.quoteLength))
            let content = text.substring(
                with: NSRange(location: line.start + prefix.quoteLength, length: contentLength - prefix.quoteLength))
            if content.allSatisfy(\.isWhitespace) {
                let whole = NSRange(location: line.start, length: contentLength)
                return TextEdit(range: whole, replacement: "", selection: NSRange(location: line.start, length: 0))
            }
            let normalized = quote.hasSuffix(" ") ? quote : quote + " "
            return insertion("\n" + normalized, at: selection.location)
        }

        if prefix.indentLength > 0, caret >= prefix.indentLength {
            return insertion(
                "\n" + text.substring(with: NSRange(location: line.start, length: prefix.indentLength)),
                at: selection.location)
        }
        return nil
    }

    /// Tab and Shift-Tab: indents or outdents list items and multi-line selections. Returns `nil`
    /// when there is nothing to do, so a plain Tab can insert a tab character.
    public static func indent(in text: NSString, selection: NSRange, outdent: Bool) -> TextEdit? {
        let lines = targetLines(in: text, selection: selection, includeBlank: true)
        let isMultiline = lines.count > 1
        if !outdent, !isMultiline, ListPrefix(text: text, line: lines[0]).kind == nil {
            return nil
        }

        var changes: [PrefixChange] = []
        for line in lines {
            let isBlank = line.contentsEnd == line.start
            if outdent {
                let removable = outdentLength(in: text, line: line)
                if removable > 0 {
                    changes.append(PrefixChange(location: line.start, length: removable, replacement: ""))
                }
            } else if !isBlank || !isMultiline {
                changes.append(PrefixChange(location: line.start, length: 0, replacement: indentUnit))
            }
        }
        guard !changes.isEmpty else { return nil }
        return apply(changes, in: text, lines: lines, selection: selection)
    }

    // MARK: - Helpers

    private static func endListItem(_ prefix: ListPrefix, line: Line) -> TextEdit {
        if prefix.indentLength > 0 {
            // Nested item: step out one level instead of ending the list.
            let removable = min(prefix.indentLength, prefix.firstIndentUnitLength)
            let change = PrefixChange(location: line.start, length: removable, replacement: "")
            let caret = line.contentsEnd - removable
            return TextEdit(range: change.range, replacement: "", selection: NSRange(location: caret, length: 0))
        }
        let whole = NSRange(location: line.start, length: line.contentsEnd - line.start)
        return TextEdit(range: whole, replacement: "", selection: NSRange(location: line.start, length: 0))
    }

    private static func insertion(_ string: String, at location: Int) -> TextEdit {
        TextEdit(
            range: NSRange(location: location, length: 0), replacement: string,
            selection: NSRange(location: location + (string as NSString).length, length: 0))
    }

    private static func isWrapped(_ text: NSString, range: NSRange, marker: String) -> Bool {
        let markerLength = (marker as NSString).length
        guard range.location >= markerLength, NSMaxRange(range) + markerLength <= text.length else { return false }
        let before = text.substring(with: NSRange(location: range.location - markerLength, length: markerLength))
        let after = text.substring(with: NSRange(location: NSMaxRange(range), length: markerLength))
        guard before == marker, after == marker else { return false }
        // A single "*" inside "**" is bold, not italic: count the whole run of marker characters.
        guard markerLength == 1, let character = marker.utf16.first else { return true }
        let runBefore = run(of: character, in: text, endingAt: range.location)
        let runAfter = run(of: character, in: text, startingAt: NSMaxRange(range))
        return min(runBefore, runAfter) % 2 == 1
    }

    private static func run(of character: unichar, in text: NSString, endingAt end: Int) -> Int {
        var index = end - 1
        while index >= 0, text.character(at: index) == character { index -= 1 }
        return end - 1 - index
    }

    private static func run(of character: unichar, in text: NSString, startingAt start: Int) -> Int {
        var index = start
        while index < text.length, text.character(at: index) == character { index += 1 }
        return index - start
    }

    /// The lines a command applies to. A selection that ends at the very start of a line doesn't
    /// include that line. Blank lines are skipped unless every line is blank.
    private static func targetLines(in text: NSString, selection: NSRange, includeBlank: Bool = false) -> [Line] {
        var range = selection
        if range.length > 0, NSMaxRange(range) <= text.length,
            NSMaxRange(range) > 0, isLineBreak(text.character(at: NSMaxRange(range) - 1))
        {
            range.length -= 1
        }
        var lines: [Line] = []
        let block = text.lineRange(for: range)
        var location = block.location
        repeat {
            let line = Line(text: text, containing: location)
            lines.append(line)
            location = line.end
        } while location < NSMaxRange(block)
        if includeBlank { return lines }
        let nonBlank = lines.filter { line in
            text.substring(with: line.contentsRange).contains { !$0.isWhitespace }
        }
        return nonBlank.isEmpty ? lines : nonBlank
    }

    private static func isLineBreak(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D || character == 0x2028 || character == 0x2029
    }

    private static func headingPrefix(in text: NSString, line: Line) -> (level: Int, length: Int) {
        let string = text.substring(with: line.contentsRange)
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard let match = Patterns.heading.firstMatch(in: string, range: range) else { return (0, 0) }
        return (match.range(at: 1).length, match.range.length)
    }

    private static func outdentLength(in text: NSString, line: Line) -> Int {
        var index = line.start
        var columns = 0
        while index < line.contentsEnd, columns < 4 {
            let character = text.character(at: index)
            if character == Ascii.tab {
                if columns == 0 { index += 1 }
                break
            }
            guard character == Ascii.space else { break }
            columns += 1
            index += 1
        }
        return index - line.start
    }

    private static func apply(_ changes: [PrefixChange], in text: NSString, lines: [Line], selection: NSRange)
        -> TextEdit
    {
        let block = NSRange(location: lines[0].start, length: lines[lines.count - 1].end - lines[0].start)
        let result = NSMutableString(string: text.substring(with: block))
        for change in changes.sorted(by: { $0.location > $1.location }) {
            result.replaceCharacters(
                in: NSRange(location: change.location - block.location, length: change.length), with: change.replacement
            )
        }
        let end = map(NSMaxRange(selection), through: changes, isStart: false)
        let start = selection.length == 0 ? end : map(selection.location, through: changes, isStart: true)
        return TextEdit(
            range: block, replacement: result as String,
            selection: NSRange(location: start, length: max(0, end - start)))
    }

    /// Where an offset lands after the prefix changes are applied. A selection's start stays in
    /// front of text inserted at its position, so the new prefix ends up selected; its end (and a
    /// caret) moves past it.
    private static func map(_ offset: Int, through changes: [PrefixChange], isStart: Bool) -> Int {
        var delta = 0
        for change in changes {
            let newLength = (change.replacement as NSString).length
            if isStart ? offset <= change.location : offset < change.location {
                continue
            } else if offset >= change.location + change.length {
                delta += newLength - change.length
            } else {
                delta += (isStart ? change.location : change.location + newLength) - offset
            }
        }
        return offset + delta
    }
}

struct PrefixChange {
    var location: Int
    var length: Int
    var replacement: String

    var range: NSRange { NSRange(location: location, length: length) }
}

extension Line {
    init(text: NSString, containing location: Int) {
        var start = 0
        var end = 0
        var contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        self.init(start: start, contentsEnd: contentsEnd, end: end)
    }
}

/// The leading markup of one line: quote markers, indentation, and a list marker.
struct ListPrefix {
    enum Kind: Equatable {
        case bullet(Character)
        case numbered(Int, Character)
        case task(checked: Bool)
    }

    var quoteLength = 0
    /// Leading whitespace before a list marker.
    var indentLength = 0
    /// The list marker including its trailing whitespace, e.g. `- `, `12. `, `- [ ] `.
    var markerLength = 0
    var kind: Kind?
    var bulletCharacter: Character?
    /// Absolute range of `[ ]` for tasks.
    var checkboxRange: NSRange?
    /// Length of the first indentation step: one tab, or up to four spaces.
    var firstIndentUnitLength = 0

    init(text: NSString, line: Line) {
        let string = text.substring(with: line.contentsRange)
        let full = NSRange(location: 0, length: (string as NSString).length)

        var position = 0
        while let match = Patterns.quote.firstMatch(
            in: string, range: NSRange(location: position, length: full.length - position))
        {
            position = NSMaxRange(match.range)
        }
        quoteLength = position
        guard position == 0 else { return }

        if let match = Patterns.task.firstMatch(in: string, range: full) {
            indentLength = match.range(at: 1).length
            markerLength = NSMaxRange(match.range) - indentLength
            let box = match.range(at: 4)
            let checked = (string as NSString).substring(with: box).lowercased() == "[x]"
            kind = .task(checked: checked)
            bulletCharacter = (string as NSString).substring(with: match.range(at: 2)).first
            checkboxRange = NSRange(location: line.start + box.location, length: box.length)
        } else if let match = Patterns.bullet.firstMatch(in: string, range: full) {
            indentLength = match.range(at: 1).length
            markerLength = NSMaxRange(match.range) - indentLength
            let character = (string as NSString).substring(with: match.range(at: 2)).first ?? "-"
            kind = .bullet(character)
            bulletCharacter = character
        } else if let match = Patterns.ordered.firstMatch(in: string, range: full) {
            indentLength = match.range(at: 1).length
            markerLength = NSMaxRange(match.range) - indentLength
            let marker = (string as NSString).substring(with: match.range(at: 2))
            kind = .numbered(Int(marker.dropLast()) ?? 1, marker.last ?? ".")
        } else {
            indentLength = string.prefix { $0 == " " || $0 == "\t" }.utf16.count
        }

        let indent = string.prefix(indentLength)
        firstIndentUnitLength = indent.first == "\t" ? 1 : min(4, indent.prefix { $0 == " " }.count)
    }

    func has(_ style: MarkdownEdits.LineStyle) -> Bool {
        switch (style, kind) {
        case (.quote, _): quoteLength > 0
        case (.bullet, .bullet?): true
        case (.numbered, .numbered?): true
        case (.task, .task?): true
        default: false
        }
    }
}
