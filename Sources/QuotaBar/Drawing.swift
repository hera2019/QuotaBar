import AppKit

/// Drawing shared by all three styles (menu bar icon, thin strip, card).
enum Painter {
    static func ring(_ r: RingInfo, center: NSPoint, diameter: CGFloat, lineWidth: CGFloat, fontSize: CGFloat) {
        let radius = (diameter - lineWidth) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        // Tint the track with the brand color (GPT green, Claude orange) so an empty ring still says whose it is.
        r.tint.withAlphaComponent(0.28).setStroke()
        track.stroke()

        if let rem = r.remaining, rem > 0.001 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * rem, clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            (rem < 0.15 ? NSColor.systemRed : r.tint).setStroke()
            arc.stroke()
        }

        // The number is percent used: 92 means 92% used.
        let text: String, color: NSColor
        if let w = r.window {
            text = "\(Int(w.usedPercent.rounded()))"; color = .labelColor
        } else if r.failed {
            text = "!"; color = .systemOrange
        } else {
            text = "–"; color = .secondaryLabelColor
        }
        let size = text.count >= 3 ? fontSize * 0.8 : fontSize
        centered(text, font: .monospacedDigitSystemFont(ofSize: size, weight: .semibold), color: color, at: center)
    }

    /// Center on cap height so digits sit visually in the middle of the ring.
    static func centered(_ s: String, font: NSFont, color: NSColor, at p: NSPoint) {
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let w = attr.size().width
        let baseline = p.y - font.capHeight / 2
        attr.draw(at: NSPoint(x: p.x - w / 2, y: baseline + font.descender))
    }

    static func textWidth(_ s: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: s, attributes: [.font: font]).size().width
    }
}

enum Layout {
    // Menu bar
    static let barDiameter: CGFloat = 17, barGap: CGFloat = 3, barGroupGap: CGFloat = 8, barPad: CGFloat = 2
    // Thin strip
    static let stripHeight: CGFloat = 26, stripDiameter: CGFloat = 19, stripPad: CGFloat = 9
    static let stripFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    // Card
    static let cardColumn: CGFloat = 76, cardPad: CGFloat = 10, cardGroupGap: CGFloat = 6, cardHeight: CGFloat = 102

    static func size(for style: DisplayStyle) -> NSSize {
        switch style {
        case .menuBar:
            return NSSize(width: barPad * 2 + barDiameter * 4 + barGap * 2 + barGroupGap, height: 18)
        case .strip:
            let labels = Painter.textWidth("GPT", font: stripFont) + Painter.textWidth("Claude", font: stripFont)
            let w = stripPad * 2 + labels + 5 * 2 + stripDiameter * 4 + 4 * 2 + 12
            return NSSize(width: ceil(w), height: stripHeight)
        case .card:
            return NSSize(width: cardPad * 2 + cardColumn * 4 + cardGroupGap, height: cardHeight)
        }
    }

    /// Ring order is fixed: GPT 5H, GPT 7D, Claude 5H, Claude 7D.
    static func draw(_ style: DisplayStyle, rings: [RingInfo], in bounds: NSRect) {
        switch style {
        case .menuBar: drawBar(rings, bounds)
        case .strip: drawStrip(rings, bounds)
        case .card: drawCard(rings, bounds)
        }
    }

    private static func drawBar(_ rings: [RingInfo], _ b: NSRect) {
        var x = b.minX + barPad
        for (i, r) in rings.enumerated() {
            if i == 2 { x += barGroupGap - barGap }
            Painter.ring(r, center: NSPoint(x: x + barDiameter / 2, y: b.midY), diameter: barDiameter, lineWidth: 2, fontSize: 7.5)
            x += barDiameter + barGap
        }
    }

    private static func drawStrip(_ rings: [RingInfo], _ b: NSRect) {
        var x = b.minX + stripPad
        for (g, name) in ["GPT", "Claude"].enumerated() {
            let group = Array(rings[(g * 2)..<(g * 2 + 2)])
            let color: NSColor = group.contains(where: \.failed) ? .systemOrange : .secondaryLabelColor
            let w = Painter.textWidth(name, font: stripFont)
            Painter.centered(name, font: stripFont, color: color, at: NSPoint(x: x + w / 2, y: b.midY))
            x += w + 5
            for r in group {
                Painter.ring(r, center: NSPoint(x: x + stripDiameter / 2, y: b.midY), diameter: stripDiameter, lineWidth: 2.2, fontSize: 8.5)
                x += stripDiameter + 4
            }
            x += 12 - 4
        }
    }

    private static func drawCard(_ rings: [RingInfo], _ b: NSRect) {
        let titleFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let captionFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        var x = b.minX + cardPad
        for (i, r) in rings.enumerated() {
            if i == 2 { x += cardGroupGap }
            let cx = x + cardColumn / 2
            let title = "\(r.provider.uppercased()) \(r.span.rawValue)"
            Painter.centered(title, font: titleFont, color: r.failed ? .systemOrange : .secondaryLabelColor,
                             at: NSPoint(x: cx, y: b.maxY - 14))
            Painter.ring(r, center: NSPoint(x: cx, y: b.midY + 1), diameter: 48, lineWidth: 4.5, fontSize: 16)
            Painter.centered(r.caption, font: captionFont, color: r.failed ? .systemOrange : .secondaryLabelColor,
                             at: NSPoint(x: cx, y: b.minY + 13))
            x += cardColumn
        }
    }
}

/// Content of the floating panel: drag anywhere to move, right-click for the menu (view.menu).
final class UsageView: NSView {
    var style: DisplayStyle = .strip { didSet { needsDisplay = true } }
    var rings: [RingInfo] = [] { didSet { needsDisplay = true } }

    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard rings.count == 4 else { return }
        Layout.draw(style, rings: rings, in: bounds)
    }
}
