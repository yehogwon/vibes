import AppKit
import SwiftUI

/// The Settings window. A menu bar app has no SwiftUI `Settings` scene to open, so this hosts
/// `SettingsView` in a plain window that's created once and reused.
@MainActor
final class SettingsWindowController {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(state)))
        window.title = "Jots Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
