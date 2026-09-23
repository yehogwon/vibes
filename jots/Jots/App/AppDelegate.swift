import AppKit
import SwiftUI

/// Owns the menu bar icon and the scratchpad popover.
///
/// Click the icon to open or close the scratchpad; right-click (or Control-click) for a menu.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // With no windows open, macOS would otherwise consider the app idle and quit it,
        // taking the menu bar icon with it.
        ProcessInfo.processInfo.disableAutomaticTermination("Jots lives in the menu bar")
        NSApp.mainMenu = MainMenu.make()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Jots")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        state.closeScratchpad = { [weak self] in self?.closeScratchpad(nil) }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 480, height: 560)
        popover.delegate = self
        let content = NSHostingController(rootView: ScratchpadView().environment(state))
        // The popover's size is fixed here; don't let SwiftUI's ideal size override it.
        content.sizingOptions = []
        popover.contentViewController = content
    }

    func popoverDidClose(_ notification: Notification) {
        state.file.flush()
    }

    // MARK: - Status item

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu(from: sender)
        } else if popover.isShown {
            closeScratchpad(sender)
        } else {
            openScratchpad(sender)
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        guard let statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Jots", action: #selector(openScratchpad(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy All", action: #selector(copyAll(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Export as Markdown…", action: #selector(exportMarkdown(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Jots", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        // Attaching the menu for one click shows it the way the system shows status item menus.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc func openScratchpad(_ sender: Any?) {
        guard let button = statusItem?.button, !popover.isShown else { return }
        // An accessory app has to activate itself before its popover can take keyboard focus.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc func closeScratchpad(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        }
    }

    @objc func copyAll(_ sender: Any?) {
        state.copy()
    }

    @objc func exportMarkdown(_ sender: Any?) {
        state.export()
    }

    @objc func showInFinder(_ sender: Any?) {
        state.showInFinder()
    }

    @objc func showSettings(_ sender: Any?) {
        closeScratchpad(sender)
        state.showSettings()
    }
}
