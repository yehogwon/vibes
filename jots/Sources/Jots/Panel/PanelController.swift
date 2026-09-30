import AppKit
import SwiftUI

/// The panel that hangs under the menu bar icon and holds the scratchpad.
///
/// Resting the pointer on the icon *peeks* at the scratchpad: the panel zooms in from the icon
/// without taking focus from the app in front, and zooms back out to it once the pointer leaves
/// both the icon and the panel. Clicking the icon or the panel, or pressing the shortcut, *pins* it
/// for typing: it takes keyboard focus and stays until Esc, ⌘W, the shortcut, or a click elsewhere.
@MainActor
final class PanelController {
    enum Mode {
        case hidden
        case peeking
        case pinned
    }

    static let size = NSSize(width: 480, height: 560)

    private(set) var mode = Mode.hidden
    private let panel = MenuBarPanel(width: PanelController.size.width)
    private let state: AppState
    private let button: NSStatusBarButton
    private var pendingPeek: Task<Void, Never>?
    private var leaveTimer: Timer?
    private var pointerLeftAt: Date?
    private var isPointerOnItem = false
    private var pointerMonitors: [Any] = []
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// How long the pointer rests on the icon before the panel peeks, so it doesn't flash open
    /// as the pointer passes along the menu bar.
    private let peekDelay: Duration = .milliseconds(140)
    /// How long the pointer can be outside before a peeking panel closes.
    private let leaveGrace: TimeInterval = 0.08

    init(state: AppState, button: NSStatusBarButton) {
        self.state = state
        self.button = button
        let content = NSHostingView(rootView: ScratchpadView().environment(state))
        // The panel's size is fixed here; SwiftUI mustn't resize it.
        content.sizingOptions = []
        panel.setContent(content)
        panel.onMouseDown = { [weak self] in
            if self?.mode == .peeking { self?.pin() }
        }
        watchPointer()
    }

    // MARK: - Pointer and clicks

    /// Follows the pointer to tell when it arrives on or leaves the icon.
    ///
    /// A tracking area on a status item's button doesn't reliably hear the pointer arrive, so
    /// this watches the pointer move instead: everywhere (the global monitor), and over this app's
    /// own windows (the local one). Neither needs any permission for mouse movement.
    private func watchPointer() {
        pointerMonitors.append(
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved() }
            } as Any)
        pointerMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            } as Any)
    }

    private func pointerMoved() {
        let isOnItem = isPointerOverItem
        guard isOnItem != isPointerOnItem else { return }
        isPointerOnItem = isOnItem
        if isOnItem {
            pointerEntered()
        } else {
            pendingPeek?.cancel()
        }
    }

    private func pointerEntered() {
        guard mode == .hidden, opensOnHover, NSEvent.pressedMouseButtons == 0 else { return }
        pendingPeek?.cancel()
        pendingPeek = Task { [weak self] in
            try? await Task.sleep(for: self?.peekDelay ?? .zero)
            guard let self, !Task.isCancelled, self.mode == .hidden, self.isPointerOverItem else { return }
            self.show(pinned: false)
        }
    }

    /// Whether resting the pointer on the icon peeks, which Settings can turn off.
    private var opensOnHover: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.opensOnHover) as? Bool ?? true
    }

    /// A click on the icon opens the scratchpad for typing, and closes it once it's pinned.
    func clicked() {
        switch mode {
        case .hidden: open()
        case .peeking: pin()
        case .pinned: close()
        }
    }

    /// Opens the scratchpad for typing, e.g. from the shortcut or the status menu.
    func open() {
        pendingPeek?.cancel()
        if mode == .hidden {
            show(pinned: true)
        } else {
            pin()
        }
    }

    func toggle() {
        if mode == .pinned {
            close()
        } else {
            open()
        }
    }

    /// Cancels a peek that's waiting, e.g. because the status menu is about to open.
    func cancelPeek() {
        pendingPeek?.cancel()
    }

    // MARK: - Showing and hiding

    private func show(pinned: Bool) {
        NSApp.unhideWithoutActivation()
        if pinned {
            mode = .pinned
            // An accessory app has to activate itself before its panel can take keyboard focus.
            NSApp.activate()
            startPinnedMonitors()
        } else {
            mode = .peeking
            startLeaveTimer()
        }
        panel.zoomIn(to: targetFrame(), fromItemAt: itemMidX, key: pinned)
    }

    private func pin() {
        guard mode == .peeking else { return }
        mode = .pinned
        stopLeaveTimer()
        NSApp.activate()
        panel.makeKey()
        startPinnedMonitors()
    }

    func close() {
        guard mode != .hidden else { return }
        let wasActive = NSApp.isActive
        mode = .hidden
        pendingPeek?.cancel()
        stopLeaveTimer()
        stopPinnedMonitors()
        state.file.flush()
        let panel = panel
        panel.zoomOut(toItemAt: itemMidX) {
            // Hand focus back to the app that had it before the panel was pinned, unless one of
            // Jots' own windows, like Settings, takes over.
            let hasOtherWindows = NSApp.windows.contains { $0 !== panel && $0.isVisible }
            if wasActive, NSApp.isActive, !hasOtherWindows {
                NSApp.hide(nil)
            }
        }
    }

    // MARK: - Geometry

    private var itemRect: NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var isPointerOverItem: Bool {
        itemRect?.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) == true
    }

    /// The middle of the icon on screen, which the panel zooms in from and out to.
    private var itemMidX: CGFloat {
        itemRect?.midX ?? targetFrame().midX
    }

    /// Under the icon, centered on it, kept on its screen.
    private func targetFrame() -> NSRect {
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let item = itemRect ?? NSRect(x: visible.maxX - 100, y: visible.maxY, width: 0, height: 0)
        let size = Self.size
        let top = min(item.minY, visible.maxY) - 6
        let height = max(min(size.height, top - visible.minY - 12), 200)
        let x = min(max(item.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        return NSRect(x: x.rounded(), y: (top - height).rounded(), width: size.width, height: height.rounded())
    }

    // MARK: - Leaving a peek

    /// Tracking areas can miss the pointer leaving (a fast flick, a Space switch), so a peek
    /// watches where the pointer is instead.
    private func startLeaveTimer() {
        stopLeaveTimer()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        leaveTimer = timer
    }

    private func stopLeaveTimer() {
        leaveTimer?.invalidate()
        leaveTimer = nil
        pointerLeftAt = nil
    }

    private func checkPointer() {
        guard mode == .peeking else { return stopLeaveTimer() }
        // The icon, the panel, and the gap between them, with a little slack.
        let zone = (itemRect ?? .null).union(panel.frame).insetBy(dx: -8, dy: -8)
        if zone.contains(NSEvent.mouseLocation) {
            pointerLeftAt = nil
        } else if let leftAt = pointerLeftAt {
            if Date.now.timeIntervalSince(leftAt) >= leaveGrace {
                close()
            }
        } else {
            pointerLeftAt = .now
        }
    }

    // MARK: - Closing a pinned panel

    private func startPinnedMonitors() {
        stopPinnedMonitors()
        // Clicking another app or the desktop makes this app resign active. If the system didn't
        // let the app activate, it never resigns; then any click elsewhere closes the panel.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            MainActor.assumeIsolated {
                if !NSApp.isActive {
                    self?.close()
                }
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopPinnedMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        outsideClickMonitor = nil
        resignObserver = nil
    }
}
