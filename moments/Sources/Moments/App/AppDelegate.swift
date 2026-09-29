import AppKit
import MomentsCore

/// Owns the menu bar items and the panel they open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var panel: PanelController!
    private var statusItems: StatusItems!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With no windows open, macOS would otherwise consider the app idle and quit it,
        // taking the menu bar items with it.
        ProcessInfo.processInfo.disableAutomaticTermination("Moments lives in the menu bar")
        NSApp.mainMenu = MainMenu.make()

        panel = PanelController(state: state)
        statusItems = StatusItems(
            handlers: StatusItems.Handlers(
                pointerEntered: { [weak self] in self?.panel.pointerEntered($0) },
                pointerExited: { [weak self] in self?.panel.pointerExited($0) },
                clicked: { [weak self] in self?.panel.clicked($0) },
                menu: { [weak self] in self?.makeStatusMenu() ?? NSMenu() }))
        panel.fallbackAnchor = { [weak self] in self?.statusItems.main.button }
        state.momentsDidChange = { [weak self] in
            guard let self else { return }
            self.statusItems.update(self.state.store.moments, now: self.state.now)
        }
        state.start()
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "New D-Day…", action: #selector(newDate(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Birthday…", action: #selector(newBirthday(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Progress Bar…", action: #selector(newProgress(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Sync Now", action: #selector(syncNow(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Moments", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        return menu
    }

    // MARK: - Actions

    private func openPanel() {
        guard let button = statusItems.main.button else { return }
        panel.open(from: button)
    }

    @objc func newDate(_ sender: Any?) {
        state.newMoment(.date)
        openPanel()
    }

    @objc func newBirthday(_ sender: Any?) {
        state.newMoment(.life)
        openPanel()
    }

    @objc func newProgress(_ sender: Any?) {
        state.newMoment(.progress)
        openPanel()
    }

    @objc func showSettings(_ sender: Any?) {
        state.route = .settings
        openPanel()
    }

    @objc func syncNow(_ sender: Any?) {
        state.store.sync()
    }

    @objc func closePanel(_ sender: Any?) {
        panel.close()
    }
}
