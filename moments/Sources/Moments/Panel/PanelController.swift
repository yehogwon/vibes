import AppKit
import SwiftUI

/// The panel that hangs under a menu bar item and lists the moments.
///
/// Resting the pointer on the item *peeks* at the list: the panel fades in without taking focus
/// from the app in front, and fades out once the pointer leaves both the item and the panel.
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
    private let panel = FloatingPanel()
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
    /// Bumped by every show and hide, so a finished fade-out doesn't hide a panel that has
    /// since been shown again.
    private var generation = 0
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
        panel.contentView = Self.background(around: hosting)
        // Lay the content out now, so the first peek already knows how tall it is.
        hosting.frame = NSRect(x: 0, y: 0, width: Self.width, height: 600)
        hosting.layoutSubtreeIfNeeded()

        panel.onMouseDown = { [weak self] in
            if self?.mode == .peeking { self?.pin() }
        }
        state.closePanel = { [weak self] in self?.close() }
        state.lowerPanel = { [weak self] lowered in
            self?.panel.level = lowered ? .floating : FloatingPanel.standardLevel
        }
    }

    /// Liquid Glass where there is Liquid Glass; before it, the material menus and popovers use, in
    /// the same rounded shape.
    private static func background(around content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 18
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.state = .active
        material.maskImage = roundedMask(radius: 12)
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    /// A stretchable rounded rectangle. As a material's mask it also shapes the window's shadow.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
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
        generation += 1
        let frame = targetFrame()
        // Start a little higher and transparent, then settle into place.
        panel.alphaValue = 0
        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: false)
        NSApp.unhideWithoutActivation()
        if pinned {
            mode = .pinned
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            startPinnedMonitors()
        } else {
            mode = .peeking
            panel.orderFrontRegardless()
            startLeaveTimer()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
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
        generation += 1
        let current = generation
        let frame = panel.frame.offsetBy(dx: 0, dy: 5)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                guard current == self.generation else { return }
                self.panel.orderOut(nil)
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
    }

    // MARK: - Geometry

    private func contentHeightChanged(_ height: CGFloat) {
        guard abs(height - contentHeight) > 0.5 else { return }
        contentHeight = height
        guard mode != .hidden else { return }
        move(to: targetFrame(), animated: true)
    }

    private func move(to frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// The item the panel hangs from: its anchor, or the app's own item if that's gone from the
    /// menu bar.
    private var placement: NSStatusBarButton? {
        if let anchor, anchor.window != nil {
            return anchor
        }
        return fallbackAnchor()
    }

    /// Under the item, centered on it, kept on its screen. Just under the menu bar if there's
    /// no item to hang from.
    private func targetFrame() -> NSRect {
        let item = placement
        let screen = item?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let itemRect = item.flatMap(Self.screenRect) ?? NSRect(x: visible.maxX - 100, y: visible.maxY, width: 0, height: 0)
        let top = min(itemRect.minY, visible.maxY) - 6
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
        // The item, the panel, and the gap between them, with a little slack.
        let itemRect = placement.flatMap(Self.screenRect) ?? .null
        let zone = itemRect.union(targetFrame()).insetBy(dx: -8, dy: -8)
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

/// A borderless panel that can take keyboard focus without activating the app when it's shown,
/// and reports clicks so a peeking panel can pin itself before the click lands.
final class FloatingPanel: NSPanel {
    static let standardLevel = NSWindow.Level.statusBar

    var onMouseDown: () -> Void = {}

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelController.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = Self.standardLevel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            onMouseDown()
        }
        super.sendEvent(event)
    }
}
