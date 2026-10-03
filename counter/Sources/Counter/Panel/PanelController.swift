import AppKit
import SwiftUI

/// The panel that hangs under the menu bar item and shows the timers.
///
/// Resting the pointer on the item *peeks* at them: the panel zooms in from the item without
/// taking focus from the app in front, and zooms back out to it once the pointer leaves both the
/// item and the panel. Clicking in the panel (+, a duration, a field) *pins* it: it takes keyboard
/// focus and stays until Esc or a click elsewhere.
@MainActor
final class PanelController {
    enum Mode {
        case hidden
        case peeking
        case pinned
    }

    static let width: CGFloat = 300

    private(set) var mode = Mode.hidden
    private let panel = MenuBarPanel(width: PanelController.width)
    private let state: AppState
    private let button: NSStatusBarButton
    /// The natural height of the SwiftUI content, which the panel follows.
    private var contentHeight: CGFloat = 120
    private var pendingPeek: Task<Void, Never>?
    private var leaveTimer: Timer?
    private var pointerLeftAt: Date?
    private var isPointerOnItem = false
    private var pointerMonitors: [Any] = []
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// How long the pointer rests on the item before the panel peeks, so it doesn't flash open
    /// as the pointer passes along the menu bar.
    private let peekDelay: Duration = .milliseconds(140)
    /// How long the pointer can be outside before a peeking panel closes.
    private let leaveGrace: TimeInterval = 0.08

    init(state: AppState, button: NSStatusBarButton) {
        self.state = state
        self.button = button
        let content = PanelView { [weak self] height in self?.contentHeightChanged(height) }
            .environment(state)
        let hosting = NSHostingView(rootView: content)
        // The panel's frame is set here, following the content; SwiftUI mustn't resize it.
        hosting.sizingOptions = []
        panel.setContent(hosting)
        // Lay the content out now, so the first peek already knows how tall it is.
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: 600)
        hosting.layoutSubtreeIfNeeded()

        panel.onMouseDown = { [weak self] in
            if self?.mode == .peeking { self?.pin() }
        }
        watchPointer()
    }

    // MARK: - Pointer and clicks

    /// Follows the pointer to tell when it arrives on or leaves the item.
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
        guard mode == .hidden, state.opensOnHover, NSEvent.pressedMouseButtons == 0 else { return }
        pendingPeek?.cancel()
        pendingPeek = Task { [weak self] in
            try? await Task.sleep(for: self?.peekDelay ?? .zero)
            guard let self, !Task.isCancelled, self.mode == .hidden, self.isPointerOverItem else { return }
            self.show(pinned: false)
        }
    }

    /// A click on the item does what resting the pointer on it does, without the wait: it shows
    /// the timers. It never pins or closes them, so a habitual click can't get in the way. With
    /// hovering turned off in Settings, a click opens and closes the panel instead.
    func clicked() {
        pendingPeek?.cancel()
        if mode == .hidden {
            show(pinned: !state.opensOnHover)
        } else if !state.opensOnHover {
            close()
        }
    }

    /// Opens the panel pinned, e.g. to start a timer from the status menu.
    func open() {
        pendingPeek?.cancel()
        if mode == .hidden {
            show(pinned: true)
        } else {
            pin()
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
        state.store.sync()
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
        panel.zoomOut(toItemAt: itemMidX) {
            // The timers show next time, not the page that was open.
            if self.state.route != .timers {
                self.state.route = .timers
            }
            // Hand focus back to the app that had it before the panel was pinned.
            if wasActive, NSApp.isActive {
                NSApp.hide(nil)
            }
        }
    }

    // MARK: - Geometry

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard mode != .hidden else { return }
        move(to: targetFrame(), animated: true)
    }

    private func move(to frame: NSRect, animated: Bool) {
        guard animated, !Self.reducesMotion else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// With Reduce Motion on, the panel only fades: it doesn't zoom in or out, or glide between
    /// heights.
    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var itemRect: NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var isPointerOverItem: Bool {
        itemRect?.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) == true
    }

    /// The middle of the item on screen, which the panel zooms in from and out to.
    private var itemMidX: CGFloat {
        itemRect?.midX ?? targetFrame().midX
    }

    /// Under the item, centered on it, kept on its screen. The item's width changes as it
    /// counts, so this is worked out again each time.
    private func targetFrame() -> NSRect {
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let item = itemRect ?? NSRect(x: visible.maxX - 100, y: visible.maxY, width: 0, height: 0)
        let top = min(item.minY, visible.maxY) - MenuBarPanel.gap
        let height = max(min(contentHeight, top - visible.minY - 12), 60)
        let x = min(max(item.midX - Self.width / 2, visible.minX + 8), visible.maxX - Self.width - 8)
        return NSRect(x: x.rounded(), y: (top - height).rounded(), width: Self.width, height: height.rounded())
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
        // The panel's frame may still be moving to a new height, so this goes by where it's headed.
        if MenuBarPanel.holdsPeek(NSEvent.mouseLocation, item: itemRect, frame: targetFrame()) {
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let isOurs = event.window.map(ObjectIdentifier.init)
            let handled = MainActor.assumeIsolated {
                guard let self, isOurs == ObjectIdentifier(self.panel) else { return false }
                self.state.goBack()
                return true
            }
            return handled ? nil : event
        }
    }

    private func stopPinnedMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        outsideClickMonitor = nil
        keyMonitor = nil
        resignObserver = nil
    }
}
