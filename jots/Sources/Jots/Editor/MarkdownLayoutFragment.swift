import AppKit
import JotsCore

/// Draws what text attributes alone can't: checkboxes and bullets in place of their source
/// characters, blockquote bars, thematic breaks, and rounded backgrounds for code.
///
/// Everything it draws comes from attributes set by `MarkdownStyler`, read at draw time, so it
/// stays correct when the text is restyled.
final class MarkdownLayoutFragment: NSTextLayoutFragment {
    /// How far code block backgrounds extend past the text column.
    private static let bleed: CGFloat = 10

    private var containerWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    private var paragraphAttributes: [NSAttributedString.Key: Any] {
        guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
            return [:]
        }
        return paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
    }

    override var renderingSurfaceBounds: CGRect {
        let fullWidth = CGRect(
            x: -Self.bleed, y: 0, width: containerWidth + Self.bleed * 2, height: layoutFragmentFrame.height)
        return super.renderingSurfaceBounds.union(fullWidth)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let attributes = paragraphAttributes

        if let raw = attributes[.markdownCodeBlock] as? Int,
            let position = MarkdownSpan.CodeBlockPosition(rawValue: raw)
        {
            drawCodeBlockBackground(position, at: point, in: context)
        }
        for run in runs(of: .markdownInlineCode, at: point) {
            drawInlineCodeBackground(run, in: context)
        }

        super.draw(at: point, in: context)

        if attributes[.markdownRule] != nil {
            drawRule(at: point, in: context)
        }
        for run in runs(of: .markdownQuoteMarker, at: point, firstLineOnly: true) {
            drawQuoteBar(run, at: point, in: context)
        }
        for run in runs(of: .markdownBullet, at: point) {
            drawBullet(run, level: run.value as? Int ?? 0, in: context)
        }
        for run in runs(of: .markdownCheckbox, at: point) {
            drawCheckbox(run, checked: run.value as? Bool ?? false, in: context)
        }
    }

    // MARK: - Geometry

    private struct Run {
        var value: Any
        /// The run's horizontal extent, spanning its line's full height, in drawing coordinates.
        var rect: CGRect
        var baseline: CGFloat
        var font: NSFont
    }

    private func runs(of key: NSAttributedString.Key, at point: CGPoint, firstLineOnly: Bool = false) -> [Run] {
        var result: [Run] = []
        for line in firstLineOnly ? Array(textLineFragments.prefix(1)) : textLineFragments {
            let string = line.attributedString
            let range = line.characterRange
            guard range.length > 0 else { continue }
            let bounds = line.typographicBounds
            string.enumerateAttribute(key, in: range) { value, run, _ in
                guard let value else { return }
                let start = line.locationForCharacter(at: run.location)
                let end = line.locationForCharacter(at: NSMaxRange(run))
                // The largest font in the run, so hidden (tiny) syntax at its edges doesn't count.
                var font: NSFont?
                string.enumerateAttribute(.font, in: run) { value, _, _ in
                    if let candidate = value as? NSFont, candidate.pointSize > font?.pointSize ?? 0 {
                        font = candidate
                    }
                }
                let resolvedFont = font ?? .systemFont(ofSize: NSFont.systemFontSize)
                let x0 = point.x + bounds.minX + start.x
                let x1 = point.x + bounds.minX + end.x
                result.append(
                    Run(
                        value: value,
                        rect: CGRect(x: x0, y: point.y + bounds.minY, width: max(0, x1 - x0), height: bounds.height),
                        baseline: point.y + bounds.minY + line.glyphOrigin.y,
                        font: resolvedFont))
            }
        }
        return result
    }

    // MARK: - Drawing

    private func drawCodeBlockBackground(
        _ position: MarkdownSpan.CodeBlockPosition, at point: CGPoint, in context: CGContext
    ) {
        let rect = CGRect(
            x: point.x - Self.bleed, y: point.y, width: containerWidth + Self.bleed * 2,
            height: layoutFragmentFrame.height)
        let roundTop = position == .first || position == .single
        let roundBottom = position == .last || position == .single
        context.addPath(Self.roundedRect(rect, radius: 6, top: roundTop, bottom: roundBottom))
        context.setFillColor(NSColor.quaternarySystemFill.cgColor)
        context.fillPath()
    }

    private func drawInlineCodeBackground(_ run: Run, in context: CGContext) {
        let top = run.baseline - run.font.ascender - 1
        let bottom = run.baseline - run.font.descender + 1
        let rect = CGRect(x: run.rect.minX - 2, y: top, width: run.rect.width + 4, height: bottom - top)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        context.setFillColor(NSColor.quaternarySystemFill.cgColor)
        context.fillPath()
    }

    private func drawRule(at point: CGPoint, in context: CGContext) {
        guard let line = textLineFragments.first else { return }
        let y = (point.y + line.typographicBounds.midY).rounded() + 0.5
        context.setStrokeColor(NSColor.separatorColor.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: point.x, y: y))
        context.addLine(to: CGPoint(x: point.x + containerWidth, y: y))
        context.strokePath()
    }

    private func drawQuoteBar(_ run: Run, at point: CGPoint, in context: CGContext) {
        let width: CGFloat = 3
        let rect = CGRect(x: run.rect.midX - width / 2, y: point.y, width: width, height: layoutFragmentFrame.height)
        context.setFillColor(NSColor.tertiaryLabelColor.cgColor)
        context.fill(rect)
    }

    private func drawBullet(_ run: Run, level: Int, in context: CGContext) {
        let diameter = (run.font.pointSize * 0.36).rounded()
        let center = CGPoint(x: run.rect.midX, y: run.baseline - run.font.xHeight / 2)
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let color = NSColor.secondaryLabelColor.cgColor
        switch level % 3 {
        case 0:
            context.setFillColor(color)
            context.fillEllipse(in: rect)
        case 1:
            context.setStrokeColor(color)
            context.setLineWidth(1.2)
            context.strokeEllipse(in: rect.insetBy(dx: 0.6, dy: 0.6))
        default:
            context.setFillColor(color)
            context.fill(rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func drawCheckbox(_ run: Run, checked: Bool, in context: CGContext) {
        let side = (run.font.pointSize * 1.0).rounded()
        let centerY = run.baseline - run.font.capHeight / 2
        let box = CGRect(
            x: run.rect.minX + (run.rect.width - side) / 2, y: centerY - side / 2, width: side, height: side
        )
        .integral
        let path = CGPath(roundedRect: box, cornerWidth: side * 0.25, cornerHeight: side * 0.25, transform: nil)
        if checked {
            context.addPath(path)
            context.setFillColor(NSColor.controlAccentColor.cgColor)
            context.fillPath()

            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(max(1.5, side * 0.12))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: box.minX + side * 0.26, y: box.midY + side * 0.02))
            context.addLine(to: CGPoint(x: box.minX + side * 0.43, y: box.minY + side * 0.72))
            context.addLine(to: CGPoint(x: box.minX + side * 0.76, y: box.minY + side * 0.3))
            context.strokePath()
        } else {
            context.addPath(
                CGPath(
                    roundedRect: box.insetBy(dx: 0.75, dy: 0.75), cornerWidth: side * 0.22, cornerHeight: side * 0.22,
                    transform: nil))
            context.setStrokeColor(NSColor.secondaryLabelColor.cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
        }
    }

    /// A rectangle with its top and/or bottom corners rounded. Drawing coordinates are flipped,
    /// so "top" is the smaller y.
    private static func roundedRect(_ rect: CGRect, radius: CGFloat, top: Bool, bottom: Bool) -> CGPath {
        let path = CGMutablePath()
        let topRadius = top ? radius : 0
        let bottomRadius = bottom ? radius : 0
        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY),
            radius: topRadius)
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
            radius: bottomRadius)
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY),
            radius: bottomRadius)
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
            radius: topRadius)
        path.closeSubpath()
        return path
    }
}
