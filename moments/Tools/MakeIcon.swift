// Draws the app icon as an .iconset folder for `iconutil`, so the icon needs no Xcode asset
// catalog. Run with: swift Tools/MakeIcon.swift <output.iconset>
//
// The artwork is a tear-off calendar page with a bold "D" (for D-day) on a white tile, laid out on
// a 1024-point canvas. Rectangles are given from the top left, like the other icons in this repo.

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

    // The calendar page: gray, with a coral band across the top.
    let page = rect(262, 300, 500, 460)
    let pagePath = CGPath(roundedRect: page, cornerWidth: 84, cornerHeight: 84, transform: nil)
    context.saveGState()
    context.addPath(pagePath)
    context.clip()
    context.setFillColor(CGColor(gray: 0.45, alpha: 1))
    context.fill(page)
    context.setFillColor(CGColor(srgbRed: 1, green: 0.353, blue: 0.373, alpha: 1))
    context.fill(rect(262, 300, 500, 128))
    context.restoreGState()

    // The rings it hangs from.
    context.setFillColor(CGColor(gray: 0.32, alpha: 1))
    for x in [382.0, 598] {
        context.addPath(
            CGPath(roundedRect: rect(x, 262, 44, 92), cornerWidth: 22, cornerHeight: 22, transform: nil))
    }
    context.fillPath()

    // "D", centered in the page below the band.
    let base = NSFont.systemFont(ofSize: 290, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 290) } ?? base
    let letter = NSAttributedString(string: "D", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = letter.size()
    let body = rect(262, 428, 500, 332)
    letter.draw(at: CGPoint(x: body.midX - size.width / 2, y: body.midY - size.height / 2 + font.descender / 2))

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
