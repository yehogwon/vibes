import AppKit

enum EditorFontFamily: String, CaseIterable, Identifiable {
    case system, serif, rounded, monospaced

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        }
    }
}

enum SettingsKey {
    static let fontFamily = "editor.fontFamily"
    static let fontSize = "editor.fontSize"
    static let hidesSyntax = "editor.hidesSyntax"
    static let hotKey = "general.hotKey"
}

/// Fonts, colors, and spacing for the Markdown editor.
struct MarkdownTheme: Equatable {
    var family: EditorFontFamily = .system
    var size: CGFloat = 14
    /// Hide Markdown syntax on lines the caret isn't on.
    var hidesSyntax = true

    /// Lines never get wider than this, so long jots stay readable in a wide window.
    var maxLineWidth: CGFloat { size * 52 }

    var bodyFont: NSFont { font(size: size) }

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        switch family {
        case .system:
            return system
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .serif, .rounded:
            let design: NSFontDescriptor.SystemDesign = family == .serif ? .serif : .rounded
            guard let descriptor = system.fontDescriptor.withDesign(design) else { return system }
            return NSFont(descriptor: descriptor, size: size) ?? system
        }
    }

    func headingFont(level: Int) -> NSFont {
        let scales: [CGFloat] = [1.6, 1.35, 1.18, 1.06, 1, 1]
        let scale = scales[min(max(level, 1), 6) - 1]
        return font(size: (size * scale).rounded(), weight: level <= 3 ? .bold : .semibold)
    }

    func codeFont(matching font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        let weight: NSFont.Weight = traits.contains(.bold) ? .semibold : .regular
        return .monospacedSystemFont(ofSize: (font.pointSize * 0.92).rounded(), weight: weight)
    }

    /// Nearly zero-width, invisible text for hidden syntax.
    static var hiddenFont: NSFont { .systemFont(ofSize: 0.01) }

    var lineSpacing: CGFloat { (size * 0.3).rounded() }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
    }
}
