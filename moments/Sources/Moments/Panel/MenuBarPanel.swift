import AppKit

/// A borderless panel that hangs under a menu bar item and zooms in from it and back out to it,
/// the way a popover opens from its arrow.
///
/// It can take keyboard focus without activating the app when it's shown, and reports clicks so a
/// peeking panel can pin itself before the click lands.
///
/// Jots and Moments open and close the same way, so each has a copy of this file. Keep the two
/// the same.
final class MenuBarPanel: NSPanel {
    static let standardLevel = NSWindow.Level.statusBar

    var onMouseDown: () -> Void = {}

    /// Holds the background and the content, and scales them as one, so the content isn't laid
    /// out again at every step of a zoom.
    private let zoomView = NSView()
    /// Where a zoom starts and ends, in the panel's coordinates: the top edge, under the item.
    private var zoomOrigin = NSPoint.zero
    /// Bumped by every zoom, so one that finishes late doesn't undo a newer one.
    private var generation = 0

    /// How small the panel is when it starts zooming in, and when it's gone zooming out.
    private let zoomedOutScale: CGFloat = 0.6

    init(width: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 120),
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
        zoomView.wantsLayer = true
        contentView = zoomView
    }

    /// Puts `content` on the panel's background, clipped to its rounded shape.
    func setContent(_ content: NSView) {
        let background = Self.background(around: Self.clipped(content))
        background.frame = zoomView.bounds
        background.autoresizingMask = [.width, .height]
        zoomView.subviews = [background]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
            onMouseDown()
        }
        super.sendEvent(event)
    }

    // MARK: - Placement

    /// The space between the menu bar and the panel's top edge.
    static let gap: CGFloat = 6

    /// Whether `point` (on screen) is where a peeking panel stays open: on the item it hangs from,
    /// on the panel at `frame` or just past its sides and bottom, or in the gap between the panel
    /// and the menu bar. The rest of the menu bar doesn't count, so moving along it away from the
    /// item closes the panel.
    static func holdsPeek(_ point: NSPoint, item: NSRect?, frame: NSRect) -> Bool {
        let slack: CGFloat = 8
        let panel = NSRect(
            x: frame.minX - slack, y: frame.minY - slack, width: frame.width + 2 * slack,
            height: frame.height + slack + gap)
        guard let item else { return panel.contains(point) }
        // Straight down from the item, in case the screen's edge pushed the panel aside.
        let below = NSRect(x: item.minX, y: frame.maxY, width: item.width, height: max(item.minY - frame.maxY, 0))
        return item.insetBy(dx: -1, dy: -1).contains(point) || panel.contains(point) || below.contains(point)
    }

    // MARK: - Zooming

    /// Orders the panel in at `frame`, zooming in from the point on its top edge under `itemMidX`
    /// (a screen x-coordinate). A key panel takes keyboard focus; the app should be active first.
    func zoomIn(to frame: NSRect, fromItemAt itemMidX: CGFloat, key: Bool) {
        generation += 1
        let current = generation
        setFrame(frame, display: false)
        setZoomOrigin(itemMidX: itemMidX)
        alphaValue = 0
        // The window's shadow keeps the panel's full size, so it waits until the zoom is done.
        hasShadow = false
        if key {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            animator().alphaValue = 1
            zoom(from: zoomedOutScale, to: 1, context: context)
        } completionHandler: {
            MainActor.assumeIsolated {
                guard current == self.generation else { return }
                self.hasShadow = true
                self.invalidateShadow()
            }
        }
    }

    /// Zooms the panel out to the point on its top edge under `itemMidX`, faster than it came in,
    /// then orders it out and calls `completion`. A panel shown again before then stays, and
    /// `completion` isn't called.
    func zoomOut(toItemAt itemMidX: CGFloat, completion: @escaping @MainActor @Sendable () -> Void) {
        generation += 1
        let current = generation
        setZoomOrigin(itemMidX: itemMidX)
        hasShadow = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            zoom(from: 1, to: zoomedOutScale, context: context)
        } completionHandler: {
            MainActor.assumeIsolated {
                guard current == self.generation else { return }
                self.orderOut(nil)
                completion()
            }
        }
    }

    private func setZoomOrigin(itemMidX: CGFloat) {
        zoomOrigin = NSPoint(x: min(max(itemMidX - frame.minX, 0), frame.width), y: frame.height)
    }

    /// Scales the background and content about the zoom origin. With Reduce Motion on, the panel
    /// only fades.
    private func zoom(from start: CGFloat, to end: CGFloat, context: NSAnimationContext) {
        guard let layer = zoomView.layer else { return }
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let from = reducesMotion ? CATransform3DIdentity : scale(start, of: layer)
        let to = reducesMotion ? CATransform3DIdentity : scale(end, of: layer)
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: to)
        animation.duration = context.duration
        animation.timingFunction = context.timingFunction
        layer.sublayerTransform = to
        layer.add(animation, forKey: "zoom")
    }

    /// A sublayer transform that scales by `factor` about the zoom origin. Sublayer transforms
    /// apply about the layer's anchor point, which AppKit puts at the corner.
    private func scale(_ factor: CGFloat, of layer: CALayer) -> CATransform3D {
        let bounds = layer.bounds
        let anchor = CGPoint(
            x: bounds.minX + layer.anchorPoint.x * bounds.width, y: bounds.minY + layer.anchorPoint.y * bounds.height)
        let dx = bounds.minX + zoomOrigin.x - anchor.x
        let dy = bounds.minY + zoomOrigin.y - anchor.y
        let toOrigin = CATransform3DMakeTranslation(-dx, -dy, 0)
        let scaled = CATransform3DScale(toOrigin, factor, factor, 1)
        return CATransform3DConcat(scaled, CATransform3DMakeTranslation(dx, dy, 0))
    }

    // MARK: - Background

    /// The surface's corner radius: 18 pt on Liquid Glass, 12 pt on the material before it.
    private static var cornerRadius: CGFloat {
        if #available(macOS 26, *) { 18 } else { 12 }
    }

    /// `content` in a view that clips it to the surface's corners, so opaque content, like a
    /// document's paper, doesn't poke out past them.
    private static func clipped(_ content: NSView) -> NSView {
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = cornerRadius
        if #available(macOS 26, *) {
            clip.layer?.cornerCurve = .continuous
        }
        clip.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            content.topAnchor.constraint(equalTo: clip.topAnchor),
            content.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])
        return clip
    }

    /// Liquid Glass where there is Liquid Glass; before it, the material menus and popovers use, in
    /// the same rounded shape.
    private static func background(around content: NSView) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView()
        material.material = .popover
        material.state = .active
        material.maskImage = roundedMask(radius: cornerRadius)
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
}
