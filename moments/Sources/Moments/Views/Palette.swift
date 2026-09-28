import AppKit
import MomentsCore
import SwiftUI

/// Moment colors are stored as `RRGGBB`, or empty for the accent color.
enum Palette {
    /// The choices in the editor: the default, then the system colors in their dark variants,
    /// which is what the original app stores.
    static let swatches = [
        "", "FF453A", "FF9F0A", "FFD60A", "32D74B", "63E6E2", "64D2FF", "0A84FF", "5E5CE6", "BF5AF2", "FF375F",
        "AC8E68",
    ]

    static func color(hex: String) -> Color {
        parse(hex).map(Color.init(nsColor:)) ?? .accentColor
    }

    static func nsColor(hex: String) -> NSColor {
        parse(hex) ?? .controlAccentColor
    }

    private static func parse(_ hex: String) -> NSColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension Moment {
    var tint: Color { Palette.color(hex: colorHex) }
}

/// A moment's picture: its photo, its emoji, or a symbol for its kind, in a circle. Progress bars
/// without a picture show a ring of how far along they are.
struct AvatarView: View {
    let moment: Moment
    var fraction: Double?
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            if let image = PhotoCache.image(for: moment.imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !moment.emoji.isEmpty {
                Circle().fill(moment.tint.opacity(0.16))
                Text(moment.emoji)
                    .font(.system(size: size * 0.54))
            } else if let fraction {
                Circle().stroke(moment.tint.opacity(0.18), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(moment.tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(0.5)
            } else {
                Circle().fill(moment.tint.opacity(0.16))
                Image(systemName: moment.kind == .life ? "birthday.cake.fill" : "calendar")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(moment.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Decoded photos, so the list doesn't decode PNGs every time it redraws.
@MainActor
enum PhotoCache {
    private static var images: [Data: NSImage] = [:]

    static func image(for data: Data?) -> NSImage? {
        guard let data else { return nil }
        if let image = images[data] {
            return image
        }
        guard let image = NSImage(data: data) else { return nil }
        if images.count > 64 {
            images.removeAll()
        }
        images[data] = image
        return image
    }

    /// A square PNG of the middle of `image`, small enough to sync comfortably.
    static func thumbnail(of image: NSImage, side: CGFloat = 160) -> Data? {
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = image.size
        let scale = max(side / max(size.width, 1), side / max(size.height, 1))
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        image.draw(
            in: NSRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height),
            from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
