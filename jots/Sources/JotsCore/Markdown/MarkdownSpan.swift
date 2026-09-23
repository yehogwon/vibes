import Foundation

/// A styled region of Markdown source. Ranges are UTF-16 offsets into the parsed text, so they can
/// be applied to an `NSTextStorage` directly.
public struct MarkdownSpan: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        // Line-level kinds. Their range covers the whole line, including its line break, so that
        // paragraph styles and full-width decorations apply to blank lines too.
        case heading(level: Int)
        case blockquote(depth: Int)
        case codeBlock(CodeBlockPosition)
        case horizontalRule
        case tableRow

        /// The body of a task-list item, after the checkbox.
        case taskItem(checked: Bool)
        /// Leading list or quote markup; wrapped lines hang-indent to its width.
        case indent

        /// Markup that can be hidden when the caret is elsewhere: `**`, `#`, `[`, `](url)`, …
        case syntax
        /// Markup that always stays visible but de-emphasized: code fences, table pipes, …
        case marker
        /// The `-`, `*`, or `+` of a bullet list item.
        case bullet(level: Int)
        /// The `1.` or `1)` of an ordered list item.
        case orderedMarker
        /// One `>` of a blockquote.
        case quoteMarker
        /// The `[ ]` or `[x]` of a task-list item.
        case checkbox(checked: Bool)

        case strong
        case emphasis
        case strikethrough
        case inlineCode
        case link(String)
    }

    public enum CodeBlockPosition: Int, Hashable, Sendable {
        case single, first, middle, last
    }

    public var kind: Kind
    public var range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}
