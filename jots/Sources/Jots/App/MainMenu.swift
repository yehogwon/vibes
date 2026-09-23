import AppKit

/// The main menu. A menu bar app never shows it, but AppKit still routes key equivalents
/// through it, so this is what makes ⌘C, ⌘Z, ⌘F, and the Markdown shortcuts work.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(
            submenu(
                "Jots",
                [
                    item("About Jots", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
                    .separator(),
                    item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
                    .separator(),
                    item("Quit Jots", #selector(NSApplication.terminate(_:)), "q"),
                ]))
        main.addItem(
            submenu(
                "File",
                [
                    item("Copy All", #selector(AppDelegate.copyAll(_:)), "c", [.command, .shift]),
                    item("Export as Markdown…", #selector(AppDelegate.exportMarkdown(_:)), "e", [.command, .shift]),
                    item("Show in Finder", #selector(AppDelegate.showInFinder(_:)), "r", [.command, .shift]),
                    .separator(),
                    item("Close", #selector(AppDelegate.closeScratchpad(_:)), "w"),
                ]))
        main.addItem(submenu("Edit", editItems()))
        main.addItem(submenu("Format", formatItems()))
        return main
    }

    private static func editItems() -> [NSMenuItem] {
        [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item(
                "Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            submenu(
                "Find",
                [
                    item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: .showFindInterface),
                    item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: .nextMatch),
                    item(
                        "Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift],
                        tag: .previousMatch),
                    item(
                        "Use Selection for Find", #selector(NSTextView.performFindPanelAction(_:)), "e",
                        tag: .setSearchString),
                ]),
        ]
    }

    private static func formatItems() -> [NSMenuItem] {
        [
            item("Bold", #selector(MarkdownTextView.formatBold(_:)), "b"),
            item("Italic", #selector(MarkdownTextView.formatItalic(_:)), "i"),
            item("Strikethrough", #selector(MarkdownTextView.formatStrikethrough(_:)), "x", [.command, .shift]),
            item("Code", #selector(MarkdownTextView.formatInlineCode(_:)), "c", [.command, .option]),
            item("Link", #selector(MarkdownTextView.formatLink(_:)), "k"),
            .separator(),
            item("Title", #selector(MarkdownTextView.formatHeading1(_:)), "1", [.command, .option]),
            item("Heading", #selector(MarkdownTextView.formatHeading2(_:)), "2", [.command, .option]),
            item("Subheading", #selector(MarkdownTextView.formatHeading3(_:)), "3", [.command, .option]),
            item("Body", #selector(MarkdownTextView.formatBody(_:)), "0", [.command, .option]),
            .separator(),
            item("Checklist", #selector(MarkdownTextView.formatChecklist(_:)), "l", [.command, .shift]),
            item("Mark as Done", #selector(MarkdownTextView.formatToggleDone(_:)), "u", [.command, .shift]),
            item("Bulleted List", #selector(MarkdownTextView.formatBulletList(_:)), "7", [.command, .shift]),
            item("Numbered List", #selector(MarkdownTextView.formatNumberedList(_:)), "9", [.command, .shift]),
            item("Quote", #selector(MarkdownTextView.formatQuote(_:)), "'"),
        ]
    }

    // MARK: - Builders

    /// A menu item sent to the first responder, so it reaches the focused text view or the app
    /// delegate (the last stop in the responder chain).
    private static func item(
        _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
        tag: NSTextFinder.Action? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        if let tag {
            item.tag = tag.rawValue
        }
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        for item in items {
            menu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
