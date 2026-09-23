import Foundation
import Testing

@testable import JotsCore

/// The substrings of `text` covered by spans of `kind`.
private func covered(_ kind: MarkdownSpan.Kind, in text: String) -> [String] {
    let ns = text as NSString
    return MarkdownParser.parse(ns, in: NSRange(location: 0, length: ns.length)).spans
        .filter { $0.kind == kind }
        .sorted { $0.range.location < $1.range.location }
        .map { ns.substring(with: $0.range) }
}

private func kinds(in text: String) -> [MarkdownSpan.Kind] {
    let ns = text as NSString
    return MarkdownParser.parse(ns, in: NSRange(location: 0, length: ns.length)).spans.map(\.kind)
}

@Suite("Inline")
struct InlineParsingTests {
    @Test func strongAndEmphasis() {
        #expect(covered(.strong, in: "a **bold** and __also__") == ["bold", "also"])
        #expect(covered(.emphasis, in: "an *italic* and _this_") == ["italic", "this"])
        #expect(covered(.syntax, in: "**b**") == ["**", "**"])
    }

    @Test func nestedAndCombinedEmphasis() {
        #expect(covered(.strong, in: "***both***") == ["both"])
        #expect(covered(.emphasis, in: "***both***") == ["both"])
        #expect(covered(.strong, in: "**bold *it* x**") == ["bold *it* x"])
        #expect(covered(.emphasis, in: "**bold *it* x**") == ["it"])
    }

    @Test func emphasisNeedsNonSpaceEdges() {
        #expect(covered(.emphasis, in: "2 * 3 * 4").isEmpty)
        #expect(covered(.strong, in: "** not bold **").isEmpty)
    }

    @Test func intrawordUnderscoresAreLiteral() {
        #expect(covered(.emphasis, in: "snake_case_name").isEmpty)
        #expect(covered(.strong, in: "__init__ vs a__b__c") == ["init"])
    }

    @Test func strikethrough() {
        #expect(covered(.strikethrough, in: "~~gone~~ ~kept~") == ["gone"])
    }

    @Test func codeSpansWinOverEmphasis() {
        let text = "`a*b*c` and *real*"
        #expect(covered(.inlineCode, in: text) == ["`a*b*c`"])
        #expect(covered(.emphasis, in: text) == ["real"])
    }

    @Test func codeSpanRunsMustMatch() {
        #expect(covered(.inlineCode, in: "``has ` inside``") == ["``has ` inside``"])
        #expect(covered(.inlineCode, in: "unclosed `tick").isEmpty)
    }

    @Test func escapesSuppressMarkup() {
        #expect(covered(.emphasis, in: #"\*not italic\*"#).isEmpty)
        #expect(covered(.syntax, in: #"\*x\*"#) == [#"\"#, #"\"#])
    }

    @Test func links() {
        let text = "see [the docs](https://example.com/a_b) now"
        #expect(covered(.link("https://example.com/a_b"), in: text) == ["the docs"])
        #expect(covered(.syntax, in: text) == ["[", "](https://example.com/a_b)"])
        #expect(covered(.emphasis, in: text).isEmpty)
    }

    @Test func emptyLinkLabelStaysVisible() {
        let text = "[](https://x.y)"
        #expect(covered(.syntax, in: text).isEmpty)
        #expect(covered(.link("https://x.y"), in: text) == ["https://x.y"])
    }

    @Test func bareAndAngleURLs() {
        #expect(covered(.link("https://a.b/c"), in: "go to https://a.b/c.") == ["https://a.b/c"])
        #expect(covered(.link("https://a.b"), in: "<https://a.b>") == ["https://a.b"])
        #expect(
            covered(.link("https://en.wikipedia.org/wiki/A_(b)"), in: "https://en.wikipedia.org/wiki/A_(b)") == [
                "https://en.wikipedia.org/wiki/A_(b)"
            ])
    }

    @Test func rangesAreUTF16() {
        let text = "한글 🎉 **굵게**"
        #expect(covered(.strong, in: text) == ["굵게"])
    }
}

@Suite("Blocks")
struct BlockParsingTests {
    @Test func headings() {
        #expect(kinds(in: "## Title").contains(.heading(level: 2)))
        #expect(covered(.syntax, in: "## Title") == ["## "])
        #expect(!kinds(in: "#hashtag").contains(.heading(level: 1)))
    }

    @Test func emptyHeadingMarkerStaysVisible() {
        #expect(covered(.marker, in: "## ") == ["## "])
    }

    @Test func bulletsAndLevels() {
        let text = "- one\n    - two\n        * three"
        #expect(covered(.bullet(level: 0), in: text) == ["-"])
        #expect(covered(.bullet(level: 1), in: text) == ["-"])
        #expect(covered(.bullet(level: 2), in: text) == ["*"])
        #expect(covered(.indent, in: text) == ["- ", "    - ", "        * "])
    }

    @Test func orderedItems() {
        #expect(covered(.orderedMarker, in: "1. first\n10) tenth") == ["1.", "10)"])
    }

    @Test func tasks() {
        let text = "- [ ] todo\n- [x] done"
        #expect(covered(.checkbox(checked: false), in: text) == ["[ ]"])
        #expect(covered(.checkbox(checked: true), in: text) == ["[x]"])
        #expect(covered(.taskItem(checked: true), in: text) == ["done"])
        #expect(covered(.syntax, in: text) == ["- ", "- "])
    }

    @Test func horizontalRuleBeatsBullet() {
        #expect(kinds(in: "* * *").contains(.horizontalRule))
        #expect(kinds(in: "---").contains(.horizontalRule))
        #expect(!kinds(in: "--").contains(.horizontalRule))
    }

    @Test func blockquotes() {
        let text = "> quoted *text*\n> > nested"
        #expect(covered(.quoteMarker, in: text) == [">", ">", ">"])
        #expect(kinds(in: text).contains(.blockquote(depth: 2)))
        #expect(covered(.emphasis, in: text) == ["text"])
    }

    @Test func tables() {
        let text = "| a | b |\n|---|:-:|\n| 1 | **2** |"
        #expect(covered(.tableRow, in: text).count == 3)
        #expect(covered(.strong, in: text) == ["2"])
        #expect(covered(.marker, in: text).contains("|---|:-:|"))
    }
}

@Suite("Code blocks")
struct CodeBlockTests {
    @Test func fencedBlockCoversWholeLines() {
        let text = "before\n```swift\nlet *x* = 1\n```\nafter *y*"
        let blocks = MarkdownParser.codeBlocks(in: text as NSString)
        #expect(blocks.count == 1)
        #expect((text as NSString).substring(with: blocks[0]) == "```swift\nlet *x* = 1\n```\n")
        #expect(covered(.emphasis, in: text) == ["y"])
        #expect(covered(.codeBlock(.first), in: text) == ["```swift\n"])
        #expect(covered(.codeBlock(.middle), in: text) == ["let *x* = 1\n"])
        #expect(covered(.codeBlock(.last), in: text) == ["```\n"])
    }

    @Test func unclosedFenceRunsToEnd() {
        let text = "a\n~~~\ncode\nmore"
        let blocks = MarkdownParser.codeBlocks(in: text as NSString)
        #expect(blocks == [NSRange(location: 2, length: (text as NSString).length - 2)])
    }

    @Test func closingFenceMustMatch() {
        let text = "````\n```\nstill code\n````"
        #expect(MarkdownParser.codeBlocks(in: text as NSString).count == 1)
        #expect(covered(.codeBlock(.middle), in: text).count == 2)
    }

    @Test func partialParseExpandsToEnclosingBlock() {
        let text = "x\n```\none\ntwo\n```\ny" as NSString
        let two = text.range(of: "two")
        let result = MarkdownParser.parse(text, in: two)
        #expect(text.substring(with: result.range) == "```\none\ntwo\n```\n")
    }

    @Test func detectsFenceEdits() {
        let text = "a\n```\nb" as NSString
        #expect(MarkdownParser.containsFence(text, in: NSRange(location: 3, length: 0)))
        #expect(!MarkdownParser.containsFence(text, in: NSRange(location: 0, length: 1)))
    }
}

@Suite("Partial parsing")
struct PartialParsingTests {
    @Test func parsesOnlyTouchedLines() {
        let text = "**a**\nplain\n**c**" as NSString
        let result = MarkdownParser.parse(text, in: NSRange(location: 7, length: 0))
        #expect(text.substring(with: result.range) == "plain\n")
        #expect(result.spans.isEmpty)
    }

    @Test func emptyDocument() {
        let result = MarkdownParser.parse("" as NSString, in: NSRange(location: 0, length: 0))
        #expect(result.range == NSRange(location: 0, length: 0))
        #expect(result.spans.isEmpty)
    }

    @Test func clampsOutOfRangeRequests() {
        let text = "abc" as NSString
        let result = MarkdownParser.parse(text, in: NSRange(location: 10, length: 5))
        #expect(NSMaxRange(result.range) <= text.length)
    }
}
