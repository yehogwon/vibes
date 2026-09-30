import AppKit
import SwiftUI

/// The panel that hangs under a menu bar item and lists the moments.
///
/// Resting the pointer on the item *peeks* at the list: the panel zooms in from the item without
/// taking focus from the app in front, and zooms back out to it once the pointer leaves both the
/// item and the panel.
/// Nothing needs a click on the item. Clicking in the panel (a moment, +, a field) *pins* it for
/// editing: it takes keyboard focus and stays until Esc or a click elsewhere.
@MainActor
final class PanelController {
    enum Mode {
        case hidden
        case peeking
        case pinned
    }

    static let width: CGFloat = 360

    private(set) var mode = Mode.hidden
    private let panel = MenuBarPanel(width: PanelController.width)
    private let state: AppState
    private weak var anchor: NSStatusBarButton?
    /// Where the panel hangs when its item goes away, e.g. a moment taken out of the menu bar
    /// while the panel was open under it. Set to the app's own item.
    var fallbackAnchor: () -> NSStatusBarButton? = { nil }
    /// The natural height of the SwiftUI content, which the panel follows.
    private var contentHeight: CGFloat = 120
    private var pendingPeek: Task<Void, Never>?
    private var leaveTimer: Timer?
    private var pointerLeftAt: Date?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// How long the pointer rests on an item before the panel peeks, so it doesn't flash open
    /// as the pointer passes along the menu bar.
    private let peekDelay: Duration = .milliseconds(140)
    /// How long the pointer can be outside before a peeking panel closes.
    private let leaveGrace: TimeInterval = 0.08

    init(state: AppState) {
        self.state = state
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
        state.closePanel = { [weak self] in self?.close() }
        state.lowerPanel = { [weak self] lowered in
            self?.panel.level = lowered ? .floating : MenuBarPanel.standardLevel
        }
    }

    // MARK: - Pointer and clicks

    func pointerEntered(_ button: NSStatusBarButton) {
        switch mode {
        case .hidden:
            guard state.opensOnHover, NSEvent.pressedMouseButtons == 0 else { return }
            pendingPeek?.cancel()
            pendingPeek = Task { [weak self] in
                try? await Task.sleep(for: self?.peekDelay ?? .zero)
                guard let self, !Task.isCancelled, self.mode == .hidden, Self.isPointer(over: button) else { return }
                self.show(from: button, pinned: false)
            }
        case .peeking where button !== anchor:
            // Slide over to the item the pointer moved to.
            anchor = button
            move(to: targetFrame(), animated: true)
        default:
            break
        }
    }

    func pointerExited(_ button: NSStatusBarButton) {
        if mode == .hidden {
            pendingPeek?.cancel()
        }
    }

    /// A click on an item does what resting the pointer on it does, without the wait: it shows
    /// the list. It never pins or closes it, so a habitual click can't get in the way. With
    /// hovering turned off in Settings, a click opens and closes the list instead.
    func clicked(_ button: NSStatusBarButton) {
        pendingPeek?.cancel()
        guard state.opensOnHover else {
            if mode == .hidden {
                show(from: button, pinned: true)
            } else {
                close()
            }
            return
        }
        switch mode {
        case .hidden:
            show(from: button, pinned: false)
        case .peeking where button !== anchor, .pinned where button !== anchor:
            anchor = button
            move(to: targetFrame(), animated: true)
        default:
            break
        }
    }

    /// Opens the panel pinned under `button`, e.g. to add a moment from the status menu.
    func open(from button: NSStatusBarButton) {
        pendingPeek?.cancel()
        if mode == .hidden {
            show(from: button, pinned: true)
        } else {
            pin()
        }
    }


    // MARK: - Showing and hiding

    private func show(from button: NSStatusBarButton, pinned: Bool) {
        anchor = button
        NSApp.unhideWithoutActivation()
        if pinned {
            mode = .pinned
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
            // An unsaved edit is still there next time; settings aren't.
            if self.state.route == .settings {
                self.state.route = .list
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
    /// items and heights.
    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The item the panel hangs from: its anchor, or the app's own item if that's gone from the
    /// menu bar.
    private var placement: NSStatusBarButton? {
        if let anchor, anchor.window != nil {
            return anchor
        }
        return fallbackAnchor()
    }

    /// The middle of the item the panel hangs from, on screen, which it zooms in from and out to.
    private var itemMidX: CGFloat {
        placement.flatMap(Self.screenRect)?.midX ?? targetFrame().midX
    }

    /// Under the item, centered on it, kept on its screen. Just under the menu bar if there's
    /// no item to hang from.
    private func targetFrame() -> NSRect {
        let item = placement
        let screen = item?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let itemRect = item.flatMap(Self.screenRect) ?? NSRect(x: visible.maxX - 100, y: visible.maxY, width: 0, height: 0)
        let top = min(itemRect.minY, visible.maxY) - MenuBarPanel.gap
        let height = max(min(contentHeight, top - visible.minY - 12), 60)
        let x = min(max(itemRect.midX - Self.width / 2, visible.minX + 8), visible.maxX - Self.width - 8)
        return NSRect(x: x.rounded(), y: (top - height).rounded(), width: Self.width, height: height.rounded())
    }

    /// Where the item is on screen, or `nil` if it isn't in the menu bar.
    private static func screenRect(of button: NSStatusBarButton) -> NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private static func isPointer(over button: NSStatusBarButton) -> Bool {
        screenRect(of: button)?.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) == true
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
        // The panel's frame is still moving while it glides to another item, so this goes by
        // where it's headed.
        let item = placement.flatMap(Self.screenRect)
        if MenuBarPanel.holdsPeek(NSEvent.mouseLocation, item: item, frame: targetFrame()) {
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
        // Clicking another app or the desktop makes this app resign active. Clicks in the
        // Emoji & Symbols viewer don't, so picking an emoji leaves the panel open.
        //
        // If the system didn't let the app activate, it never resigns; then any click elsewhere
        // closes the panel.
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
                guard let self, isOurs == ObjectIdentifier(self.panel), !Self.isComposingText else { return false }
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

    /// Esc while typing Hangul (or any input method) cancels the composition, not the panel.
    private static var isComposingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }
}
