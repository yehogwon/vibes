// Draws the app icon as an .iconset folder for `iconutil`, so the icon needs no Xcode asset
// catalog. Run with: swift Tools/MakeIcon.swift <output.iconset>
//
// The artwork is a checked box above three lines on a white tile, laid out on a 1024-point
// canvas with the origin at the top left.

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")

/// Draws the icon into a `side` × `side` pixel bitmap.
func drawIcon(side: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext

    // Work in the 1024-point canvas, top-left origin.
    let scale = CGFloat(side) / 1024
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)

    // macOS app icons sit on an 824-point tile centered in the canvas, leaving room for the shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
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
    context.drawLinearGradient(
        shade, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    context.restoreGState()

    // The glyph is drawn for the full canvas, so shrink it onto the tile.
    context.translateBy(x: tile.minX, y: tile.minY)
    context.scaleBy(x: tile.width / 1024, y: tile.height / 1024)

    let glyph = CGColor(gray: 0.45, alpha: 1)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(glyph)
    context.addPath(
        CGPath(
            roundedRect: CGRect(x: 226, y: 294, width: 188, height: 188),
            cornerWidth: 48, cornerHeight: 48, transform: nil))
    context.fillPath()
    // Punch the check mark out of the box.
    context.setBlendMode(.clear)
    context.setLineWidth(40)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addLines(between: [CGPoint(x: 282, y: 392), CGPoint(x: 320, y: 430), CGPoint(x: 372, y: 350)])
    context.strokePath()
    context.endTransparencyLayer()

    context.setStrokeColor(glyph)
    context.setLineWidth(56)
    context.setLineCap(.round)
    for (start, end, y) in [(500.0, 792.0, 388.0), (232, 792, 612), (232, 600, 752)] {
        context.move(to: CGPoint(x: start, y: y))
        context.addLine(to: CGPoint(x: end, y: y))
    }
    context.strokePath()

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
