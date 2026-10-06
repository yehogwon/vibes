import AppKit
import CountsCore

/// Owns the menu bar item and the panel under it.
///
/// The item reads the timer that ends first, or shows an icon when there are none. Rest the
/// pointer on it to see the timers; right-click (or Control-click) for a menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private var panel: PanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With no windows open, macOS would otherwise consider the app idle and quit it,
        // taking the menu bar item with it.
        ProcessInfo.processInfo.disableAutomaticTermination("Counts lives in the menu bar")
        NSApp.mainMenu = MainMenu.make()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Counts"
        let button = statusItem.button!
        // The menu bar's own size, with digits of one width so the item doesn't jitter as it counts.
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        // The title alone ("4:59", "Done") doesn't say whose it is.
        button.setAccessibilityHelp("Counts")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel = PanelController(state: state, button: button)

        state.closePanel = { [weak self] in self?.panel.close() }
        state.timersDidChange = { [weak self] in self?.updateStatusItem() }
        state.start()
    }

    /// The timer that ends first, as "4:59" or "Done", or the app's icon when there are none.
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let title = state.store.timers.first?.clock(at: state.now) ?? ""
        guard title != button.title || title.isEmpty != (button.image != nil) else { return }
        button.title = title
        button.image =
            title.isEmpty ? NSImage(systemSymbolName: "timer", accessibilityDescription: "Counts") : nil
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Don't peek under the menu.
            panel.cancelPeek()
            showStatusMenu(from: sender)
        } else {
            panel.clicked()
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Timer…", action: #selector(newTimer(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sync Now", action: #selector(syncNow(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Counts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        // Attaching the menu for one click shows it the way the system shows status item menus.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc func newTimer(_ sender: Any?) {
        state.route = .newTimer
        panel.open()
    }

    @objc func showSettings(_ sender: Any?) {
        state.route = .settings
        panel.open()
    }

    @objc func syncNow(_ sender: Any?) {
        state.store.sync()
    }

    @objc func closePanel(_ sender: Any?) {
        panel.close()
    }
}
