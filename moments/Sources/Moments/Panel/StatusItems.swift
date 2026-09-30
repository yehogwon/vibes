import AppKit
import MomentsCore

/// The menu bar items: the app's own icon, and one for each moment shown in the menu bar.
///
/// Resting the pointer on any of them shows the list; right-clicking (or Control-clicking) shows
/// a menu.
@MainActor
final class StatusItems: NSObject {
    struct Handlers {
        var pointerEntered: (NSStatusBarButton) -> Void
        var pointerExited: (NSStatusBarButton) -> Void
        var clicked: (NSStatusBarButton) -> Void
        var menu: () -> NSMenu
    }

    private let handlers: Handlers
    private(set) var main: NSStatusItem!
    private var items: [UUID: NSStatusItem] = [:]
    /// What each moment's item shows, so unchanged items aren't redrawn every tick.
    private var shown: [UUID: ItemContent] = [:]
    /// The item the pointer is on, if any.
    private weak var hovered: NSStatusBarButton?
    private var pointerMonitors: [Any] = []

    init(handlers: Handlers) {
        self.handlers = handlers
        super.init()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Moments"
        item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Moments")
        configure(item)
        main = item
        watchPointer()
    }

    /// Adds, updates, and removes the moments' own items.
    func update(_ moments: [Moment], now: Date) {
        let pinned = moments.filter(\.inMenubar)
        let ids = Set(pinned.map(\.id))
        for (id, item) in items where !ids.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
            shown[id] = nil
        }
        for moment in pinned {
            let item = items[moment.id] ?? makeItem(for: moment)
            let content = ItemContent(moment: moment, now: now)
            guard shown[moment.id] != content else { continue }
            shown[moment.id] = content
            item.button?.image = content.image(for: moment)
            item.button?.imagePosition = .imageLeading
            item.button?.title = content.title
            item.button?.toolTip = moment.displayName
        }
    }

    private func makeItem(for moment: Moment) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers where the item was dragged to (⌘-drag) between launches.
        item.autosaveName = "Moment \(moment.id.uuidString)"
        configure(item)
        items[moment.id] = item
        return item
    }

    private func configure(_ item: NSStatusItem) {
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(buttonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Don't peek under the menu.
            handlers.pointerExited(sender)
            showMenu(from: sender)
        } else {
            handlers.clicked(sender)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        guard let item = ([main] + Array(items.values)).first(where: { $0.button === button }) else { return }
        // Attaching the menu for one click shows it the way the system shows status item menus.
        item.menu = handlers.menu()
        button.performClick(nil)
        item.menu = nil
    }

    // MARK: - Hover

    /// Follows the pointer to tell when it arrives on or leaves an item.
    ///
    /// The system draws every app's items into one menu bar, and a tracking area on an item's
    /// button doesn't reliably hear the pointer arrive, so this watches the pointer move instead:
    /// everywhere (the global monitor), and over this app's own windows (the local one). Neither
    /// needs any permission for mouse movement.
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
        let location = NSEvent.mouseLocation
        let buttons = ([main] + Array(items.values)).compactMap(\.button)
        let over = buttons.first { button in
            guard let window = button.window else { return false }
            return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(location)
        }
        guard over !== hovered else { return }
        if let hovered {
            handlers.pointerExited(hovered)
        }
        hovered = over
        if let over {
            handlers.pointerEntered(over)
        }
    }
}


/// What a moment's menu bar item shows: "🎂 D-12", a photo and "D-12", a ring and "74%".
private struct ItemContent: Equatable {
    var title: String
    var fraction: Double?
    var colorHex: String
    var imageHash: Int?

    init(moment: Moment, now: Date) {
        colorHex = moment.colorHex
        imageHash = moment.imageData?.hashValue
        if moment.kind == .progress {
            let progress = moment.progress(at: now)
            fraction = (progress.fraction * 100).rounded(.down) / 100
            title = progress.percent
        } else {
            fraction = nil
            let days = moment.dayCount(on: now).days
            let count = Moment.dDay(days)
            title =
                if moment.imageData != nil { count }
                else if !moment.emoji.isEmpty { "\(moment.emoji) \(count)" }
                else { "\(String(moment.displayName.prefix(14))) \(count)" }
        }
        if moment.imageData != nil || fraction != nil {
            title = " " + title
        }
    }

    func image(for moment: Moment) -> NSImage? {
        if let data = moment.imageData, let photo = NSImage(data: data) {
            return Self.circular(photo, side: 16)
        }
        if let fraction {
            return Self.ring(fraction, color: Palette.inkNSColor(hex: colorHex), side: 15)
        }
        return nil
    }

    private static func circular(_ photo: NSImage, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            let size = photo.size
            let scale = max(rect.width / max(size.width, 1), rect.height / max(size.height, 1))
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            photo.draw(
                in: NSRect(
                    x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width,
                    height: drawn.height))
            return true
        }
    }

    private static func ring(_ fraction: Double, color: NSColor, side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let lineWidth: CGFloat = 2.5
            let circle = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.2).setStroke()
            track.stroke()
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: NSPoint(x: circle.midX, y: circle.midY), radius: circle.width / 2, startAngle: 90,
                endAngle: 90 - 360 * fraction, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            return true
        }
    }
}
