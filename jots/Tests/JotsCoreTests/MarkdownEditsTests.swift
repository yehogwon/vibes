import Foundation
import Testing

@testable import JotsCore

/// Applies an edit and renders the result with `|` marking the caret, or `[` `]` around a
/// selection.
private func render(_ text: String, _ edit: TextEdit?) -> String? {
    guard let edit else { return nil }
    let result = NSMutableString(string: text)
    result.replaceCharacters(in: edit.range, with: edit.replacement)
    if edit.selection.length == 0 {
        result.insert("|", at: edit.selection.location)
    } else {
        result.insert("]", at: NSMaxRange(edit.selection))
        result.insert("[", at: edit.selection.location)
    }
    return result as String
}

/// Splits a string written with a `|` caret (or `[` `]` selection) into text and selection.
private func parse(_ marked: String) -> (NSString, NSRange) {
    let ns = NSMutableString(string: marked)
    let caret = ns.range(of: "|")
    if caret.location != NSNotFound {
        ns.deleteCharacters(in: caret)
        return (ns, NSRange(location: caret.location, length: 0))
    }
    let open = ns.range(of: "[")
    ns.deleteCharacters(in: open)
    let close = ns.range(of: "]", options: .backwards)
    ns.deleteCharacters(in: close)
    return (ns, NSRange(location: open.location, length: close.location - open.location))
}

private func run(_ marked: String, _ command: (NSString, NSRange) -> TextEdit?) -> String? {
    let (text, selection) = parse(marked)
    return render(text as String, command(text, selection))
}

@Suite("Wrapping")
struct WrapTests {
    @Test func wrapsAndUnwrapsSelection() {
        #expect(run("a [word] b") { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) } == "a **[word]** b")
        #expect(run("a **[word]** b") { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) } == "a [word] b")
    }

    @Test func unwrapsWhenMarkersAreSelected() {
        #expect(run("a [**word**] b") { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) } == "a [word] b")
    }

    @Test func emptySelectionInsertsPairAndRemovesIt() {
        #expect(run("a | b") { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) } == "a **|** b")
        #expect(run("a **|** b") { MarkdownEdits.toggleWrap("**", in: $0, selection: $1) } == "a | b")
    }

    @Test func italicInsideBoldWrapsInsteadOfUnwrapping() {
        #expect(run("**[word]**") { MarkdownEdits.toggleWrap("*", in: $0, selection: $1) } == "***[word]***")
        #expect(run("***[word]***") { MarkdownEdits.toggleWrap("*", in: $0, selection: $1) } == "**[word]**")
    }

    @Test func links() {
        #expect(run("[site]") { MarkdownEdits.insertLink(in: $0, selection: $1) } == "[site](|)")
        #expect(run("[https://a.b]") { MarkdownEdits.insertLink(in: $0, selection: $1) } == "[|](https://a.b)")
        #expect(run("x |") { MarkdownEdits.insertLink(in: $0, selection: $1) } == "x [|]()")
    }
}

@Suite("Line styles")
struct LineStyleTests {
    @Test func bulletsToggleOnAndOff() {
        #expect(run("a|") { MarkdownEdits.toggleLineStyle(.bullet, in: $0, selection: $1) } == "- a|")
        #expect(run("- a|") { MarkdownEdits.toggleLineStyle(.bullet, in: $0, selection: $1) } == "a|")
    }

    @Test func numbersAreSequentialAndSkipBlankLines() {
        let result = run("[a\n\nb\nc]") { MarkdownEdits.toggleLineStyle(.numbered, in: $0, selection: $1) }
        #expect(result == "[1. a\n\n2. b\n3. c]")
    }

    @Test func tasksConvertExistingBullets() {
        #expect(run("  - a|") { MarkdownEdits.toggleLineStyle(.task, in: $0, selection: $1) } == "  - [ ] a|")
        #expect(run("- [x] a|") { MarkdownEdits.toggleLineStyle(.task, in: $0, selection: $1) } == "a|")
    }

    @Test func quotes() {
        #expect(run("[a\nb]") { MarkdownEdits.toggleLineStyle(.quote, in: $0, selection: $1) } == "[> a\n> b]")
        #expect(run("> a|") { MarkdownEdits.toggleLineStyle(.quote, in: $0, selection: $1) } == "a|")
    }

    @Test func selectionEndingAtLineStartExcludesThatLine() {
        #expect(run("[a\n]b") { MarkdownEdits.toggleLineStyle(.bullet, in: $0, selection: $1) } == "[- a\n]b")
    }

    @Test func headings() {
        #expect(run("Title|") { MarkdownEdits.setHeading(2, in: $0, selection: $1) } == "## Title|")
        #expect(run("## Title|") { MarkdownEdits.setHeading(2, in: $0, selection: $1) } == "Title|")
        #expect(run("# Ti|tle") { MarkdownEdits.setHeading(3, in: $0, selection: $1) } == "### Ti|tle")
    }
}

@Suite("Tasks")
struct TaskEditTests {
    @Test func togglesCheckboxOnLine() {
        let text = "- [ ] a\n- [x] b" as NSString
        let first = MarkdownEdits.toggleCheckbox(in: text, onLineAt: 3, selection: NSRange(location: 0, length: 0))
        #expect(render(text as String, first) == "|- [x] a\n- [x] b")
        let second = MarkdownEdits.toggleCheckbox(in: text, onLineAt: 9, selection: NSRange(location: 0, length: 0))
        #expect(render(text as String, second) == "|- [ ] a\n- [ ] b")
        #expect(MarkdownEdits.toggleCheckbox(in: "plain" as NSString, onLineAt: 0, selection: NSRange()) == nil)
    }

    @Test func completionChecksAllUnlessAllChecked() {
        #expect(
            run("[- [ ] a\n- [x] b]") { MarkdownEdits.toggleTaskCompletion(in: $0, selection: $1) }
                == "[- [x] a\n- [x] b]")
        #expect(
            run("[- [x] a\n- [x] b]") { MarkdownEdits.toggleTaskCompletion(in: $0, selection: $1) }
                == "[- [ ] a\n- [ ] b]")
    }
}

@Suite("Return and Tab")
struct ContinuationTests {
    @Test func continuesBulletsTasksAndNumbers() {
        #expect(run("- a|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "- a\n- |")
        #expect(run("  * a|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "  * a\n  * |")
        #expect(run("- [x] a|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "- [x] a\n- [ ] |")
        #expect(run("9. a|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "9. a\n10. |")
        #expect(run("> a|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "> a\n> |")
    }

    @Test func splitsItemAtCaret() {
        #expect(run("- ab|cd") { MarkdownEdits.continueList(in: $0, selection: $1) } == "- ab\n- |cd")
    }

    @Test func emptyItemEndsListOrOutdents() {
        #expect(run("- a\n- |") { MarkdownEdits.continueList(in: $0, selection: $1) } == "- a\n|")
        #expect(run("- a\n    - |") { MarkdownEdits.continueList(in: $0, selection: $1) } == "- a\n- |")
        #expect(run("> |") { MarkdownEdits.continueList(in: $0, selection: $1) } == "|")
    }

    @Test func keepsPlainIndentation() {
        #expect(run("    code|") { MarkdownEdits.continueList(in: $0, selection: $1) } == "    code\n    |")
        #expect(run("plain|") { MarkdownEdits.continueList(in: $0, selection: $1) } == nil)
    }

    @Test func caretBeforeMarkerFallsBack() {
        #expect(run("|- a") { MarkdownEdits.continueList(in: $0, selection: $1) } == nil)
    }

    @Test func tabIndentsListItems() {
        #expect(run("- a|") { MarkdownEdits.indent(in: $0, selection: $1, outdent: false) } == "    - a|")
        #expect(run("    - a|") { MarkdownEdits.indent(in: $0, selection: $1, outdent: true) } == "- a|")
        #expect(run("plain|") { MarkdownEdits.indent(in: $0, selection: $1, outdent: false) } == nil)
        #expect(run("plain|") { MarkdownEdits.indent(in: $0, selection: $1, outdent: true) } == nil)
    }

    @Test func tabIndentsEveryLineOfMultilineSelection() {
        #expect(run("[a\n\nb]") { MarkdownEdits.indent(in: $0, selection: $1, outdent: false) } == "[    a\n\n    b]")
    }
}
