import AppKit

/// Attributes the styler sets for `MarkdownLayoutFragment` to draw. Values are plain `NSNumber` or
/// `String` so attribute runs compare cheaply.
extension NSAttributedString.Key {
    /// `Bool`: whether the task is checked. Set on the `[ ]` characters.
    static let markdownCheckbox = NSAttributedString.Key("Jots.checkbox")
    /// `Int`: nesting level. Set on the `-`, `*`, or `+` of a bullet.
    static let markdownBullet = NSAttributedString.Key("Jots.bullet")
    /// `Bool`. Set on each `>` of a blockquote.
    static let markdownQuoteMarker = NSAttributedString.Key("Jots.quoteMarker")
    /// `Int`: a `MarkdownSpan.CodeBlockPosition` raw value. Set on whole lines.
    static let markdownCodeBlock = NSAttributedString.Key("Jots.codeBlock")
    /// `Bool`. Set on inline code, including its backticks.
    static let markdownInlineCode = NSAttributedString.Key("Jots.inlineCode")
    /// `Bool`. Set on whole thematic-break lines when their `---` is hidden.
    static let markdownRule = NSAttributedString.Key("Jots.rule")
    /// `String`: the destination URL. Set on link text.
    static let markdownLink = NSAttributedString.Key("Jots.link")
}
