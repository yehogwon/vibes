import AppKit

/// The main menu. A menu bar app never shows it, but AppKit still routes key equivalents
/// through it, so this is what makes ⌘C, ⌘V, ⌘Z, and ⌘N work in the panel.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(
            submenu(
                "Moments",
                [
                    item("About Moments", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
                    .separator(),
                    item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
                    .separator(),
                    item("Quit Moments", #selector(NSApplication.terminate(_:)), "q"),
                ]))
        main.addItem(
            submenu(
                "File",
                [
                    item("New D-Day", #selector(AppDelegate.newDate(_:)), "n"),
                    item("New Birthday", #selector(AppDelegate.newBirthday(_:)), "n", [.command, .option]),
                    item("New Progress Bar", #selector(AppDelegate.newProgress(_:)), "n", [.command, .shift]),
                    .separator(),
                    item("Sync Now", #selector(AppDelegate.syncNow(_:)), "r"),
                    item("Close", #selector(AppDelegate.closePanel(_:)), "w"),
                ]))
        main.addItem(
            submenu(
                "Edit",
                [
                    item("Undo", Selector(("undo:")), "z"),
                    item("Redo", Selector(("redo:")), "z", [.command, .shift]),
                    .separator(),
                    item("Cut", #selector(NSText.cut(_:)), "x"),
                    item("Copy", #selector(NSText.copy(_:)), "c"),
                    item("Paste", #selector(NSText.paste(_:)), "v"),
                    item("Select All", #selector(NSText.selectAll(_:)), "a"),
                    .separator(),
                    item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]),
                ]))
        return main
    }

    // MARK: - Builders

    /// A menu item sent to the first responder, so it reaches the focused text field or the app
    /// delegate (the last stop in the responder chain).
    private static func item(
        _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
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
