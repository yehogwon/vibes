import AppKit
import MomentsCore
import SwiftUI

/// Moment colors are stored as `RRGGBB`, or empty for the accent color.
///
/// Each color comes in two strengths: the color itself (the *fill*), for swatches and washes, and
/// an *ink* for what has to be read against the panel, such as counts, symbols, rings, and bars.
enum Palette {
    /// The choices in the editor: the default, then the system colors in their dark variants,
    /// which is what the original app stores.
    static let swatches = [
        "", "FF453A", "FF9F0A", "FFD60A", "32D74B", "63E6E2", "64D2FF", "0A84FF", "5E5CE6", "BF5AF2", "FF375F",
        "AC8E68",
    ]

    /// The system colors the swatches stand for. They adapt to the appearance and to Increase
    /// Contrast, where the stored values are only their dark variants.
    private static let systemColors: [String: (name: String, color: NSColor)] = [
        "FF453A": ("Red", .systemRed), "FF9F0A": ("Orange", .systemOrange), "FFD60A": ("Yellow", .systemYellow),
        "32D74B": ("Green", .systemGreen), "63E6E2": ("Mint", .systemMint), "64D2FF": ("Cyan", .systemCyan),
        "0A84FF": ("Blue", .systemBlue), "5E5CE6": ("Indigo", .systemIndigo), "BF5AF2": ("Purple", .systemPurple),
        "FF375F": ("Pink", .systemPink), "AC8E68": ("Brown", .systemBrown),
    ]

    /// What the color is called, for tooltips and VoiceOver.
    static func name(hex: String) -> String {
        let key = normalized(hex)
        if key.isEmpty { return "Accent Color" }
        return systemColors[key]?.name ?? "#\(key)"
    }

    static func color(hex: String) -> Color {
        Color(nsColor: nsColor(hex: hex))
    }

    static func nsColor(hex: String) -> NSColor {
        let key = normalized(hex)
        if key.isEmpty { return .controlAccentColor }
        return systemColors[key]?.color ?? parse(key) ?? .controlAccentColor
    }

    static func ink(hex: String) -> Color {
        Color(nsColor: inkNSColor(hex: hex))
    }

    /// The color, darkened in light appearances and lightened in dark ones until it contrasts
    /// 4.5:1 with the panel, so a yellow count stays legible on a light panel.
    static func inkNSColor(hex: String) -> NSColor {
        let fill = nsColor(hex: hex)
        return NSColor(name: nil) { appearance in
            ink(for: fill, in: appearance)
        }
    }

    private static func ink(for fill: NSColor, in appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var color = fill
        // The lightest panel a dark count sits on, or the lightest dark one a light count does.
        var surface = NSColor.white
        appearance.performAsCurrentDrawingAppearance {
            color = fill.usingColorSpace(.sRGB) ?? fill
            if isDark {
                surface = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .black
            }
        }
        let target: NSColor = isDark ? .white : .black
        var ink = color
        var fraction: CGFloat = 0
        while contrast(ink, surface) < 4.5, fraction < 1 {
            fraction = min(fraction + 0.05, 1)
            ink = color.blended(withFraction: fraction, of: target) ?? target
        }
        return ink
    }

    private static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (first, second) = (luminance(a), luminance(b))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// Relative luminance, as WCAG defines it.
    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    private static func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
    }

    private static func parse(_ digits: String) -> NSColor? {
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension Moment {
    /// The moment's color, for washes behind its symbol and bar.
    var tint: Color { Palette.color(hex: colorHex) }
    /// The moment's color where it has to be read: its count, symbol, ring, and bar.
    var ink: Color { Palette.ink(hex: colorHex) }
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
                    .stroke(moment.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(0.5)
            } else {
                Circle().fill(moment.tint.opacity(0.16))
                Image(systemName: moment.kind == .life ? "birthday.cake.fill" : "calendar")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(moment.ink)
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
