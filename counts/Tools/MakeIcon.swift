// Draws the app icon as an .iconset folder for `iconutil`, so the icon needs no Xcode asset
// catalog. Run with: swift Tools/MakeIcon.swift <output.iconset>
//
// The artwork is a stopwatch on a white tile: a dark face with an orange wedge of time left,
// laid out on a 1024-point canvas. Rectangles are given from the top left, like the other icons in
// this repo.

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")

/// A rectangle on the canvas given from its top-left corner.
func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: 1024 - y - height, width: width, height: height)
}

/// Draws the icon into a `side` × `side` pixel bitmap.
func drawIcon(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)

    // macOS app icons sit on an 824-point tile centered in the canvas, leaving room for the shadow.
    let tile = rect(100, 100, 824, 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(tilePath)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // A faint top-to-bottom shade so the white tile doesn't look flat.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let shade = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceGray(),
        colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 0.93, alpha: 1)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(shade, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    context.restoreGState()

    // The button on top, and its stem.
    context.setFillColor(CGColor(gray: 0.32, alpha: 1))
    // Filling a rectangle clears the current path, so the stem goes first.
    context.fill(rect(487, 270, 50, 60))
    context.addPath(CGPath(roundedRect: rect(442, 218, 140, 64), cornerWidth: 32, cornerHeight: 32, transform: nil))
    context.fillPath()

    // The face.
    let face = rect(272, 320, 480, 480)
    let center = CGPoint(x: face.midX, y: face.midY)
    context.setFillColor(CGColor(gray: 0.22, alpha: 1))
    context.fillEllipse(in: face)

    // The time left: a wedge from twelve o'clock, a third of the way round.
    let radius: CGFloat = 196
    context.move(to: center)
    context.addArc(
        center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi / 3, clockwise: true)
    context.closePath()
    context.setFillColor(CGColor(srgbRed: 1, green: 0.58, blue: 0.0, alpha: 1))
    context.fillPath()

    // The hub.
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))

    NSGraphicsContext.current = nil
    return rep
}

try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = drawIcon(side: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
    }
}
