import AppKit
import SwiftUI

/// File menu commands for the scratchpad.
struct FileCommands: Commands {
    let app: AppState

    var body: some Commands {
        // There is only ever one scratchpad, so there's nothing to make new.
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .importExport) {
            Button("Copy All") { app.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Export as Markdown…") { app.export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Show in Finder") { app.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

/// Markdown formatting commands. They travel the responder chain to the focused
/// `MarkdownTextView`, so they do nothing when no editor has focus.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") { send(#selector(MarkdownTextView.formatBold(_:))) }
                .keyboardShortcut("b")
            Button("Italic") { send(#selector(MarkdownTextView.formatItalic(_:))) }
                .keyboardShortcut("i")
            Button("Strikethrough") { send(#selector(MarkdownTextView.formatStrikethrough(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Code") { send(#selector(MarkdownTextView.formatInlineCode(_:))) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Link") { send(#selector(MarkdownTextView.formatLink(_:))) }
                .keyboardShortcut("k")

            Divider()

            Button("Title") { send(#selector(MarkdownTextView.formatHeading1(_:))) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading") { send(#selector(MarkdownTextView.formatHeading2(_:))) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Subheading") { send(#selector(MarkdownTextView.formatHeading3(_:))) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Body") { send(#selector(MarkdownTextView.formatBody(_:))) }
                .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Checklist") { send(#selector(MarkdownTextView.formatChecklist(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Mark as Done") { send(#selector(MarkdownTextView.formatToggleDone(_:))) }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Bulleted List") { send(#selector(MarkdownTextView.formatBulletList(_:))) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Numbered List") { send(#selector(MarkdownTextView.formatNumberedList(_:))) }
                .keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Quote") { send(#selector(MarkdownTextView.formatQuote(_:))) }
                .keyboardShortcut("'")
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
