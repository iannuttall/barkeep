import AppKit

enum BarkeepIconFactory {
    static func image(for style: BarkeepIconStyle, expanded: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.labelColor
            color.setStroke()
            color.setFill()

            let center = NSPoint(x: rect.midX, y: rect.midY)
            switch style {
            case .dot:
                let diameter = expanded ? 6.0 : 5.0
                NSBezierPath(ovalIn: NSRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )).fill()
            case .ring:
                let path = NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8))
                path.lineWidth = 1.7
                path.stroke()
            case .ellipsis:
                for x in [4.0, 9.0, 14.0] {
                    NSBezierPath(ovalIn: NSRect(x: x - 1.4, y: 7.6, width: 2.8, height: 2.8)).fill()
                }
            case .diamond:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 9, y: 3.5))
                path.line(to: NSPoint(x: 14.5, y: 9))
                path.line(to: NSPoint(x: 9, y: 14.5))
                path.line(to: NSPoint(x: 3.5, y: 9))
                path.close()
                path.lineWidth = 1.6
                path.stroke()
            case .chevrons:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 3, y: 6))
                path.line(to: NSPoint(x: 6, y: 9))
                path.line(to: NSPoint(x: 3, y: 12))
                path.move(to: NSPoint(x: 15, y: 6))
                path.line(to: NSPoint(x: 12, y: 9))
                path.line(to: NSPoint(x: 15, y: 12))
                path.lineWidth = 1.7
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            case .line:
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 9, y: 3.5))
                path.line(to: NSPoint(x: 9, y: 14.5))
                path.lineWidth = 2
                path.lineCapStyle = .round
                path.stroke()
            case .sparkle:
                drawSparkle(at: center)
            case .grid:
                for x in [5.5, 12.5] {
                    for y in [5.5, 12.5] {
                        NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)).fill()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = style.title
        return image
    }

    static func dividerImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 18), flipped: false) { _ in
            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2.25, y: 3.5))
            path.line(to: NSPoint(x: 5.75, y: 14.5))
            path.lineWidth = 1.25
            path.lineCapStyle = .round
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawSparkle(at center: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: 2.5))
        path.curve(
            to: NSPoint(x: center.x + 6.5, y: center.y),
            controlPoint1: NSPoint(x: center.x + 1, y: center.y - 1),
            controlPoint2: NSPoint(x: center.x + 1, y: center.y - 1)
        )
        path.curve(
            to: NSPoint(x: center.x, y: 15.5),
            controlPoint1: NSPoint(x: center.x + 1, y: center.y + 1),
            controlPoint2: NSPoint(x: center.x + 1, y: center.y + 1)
        )
        path.curve(
            to: NSPoint(x: center.x - 6.5, y: center.y),
            controlPoint1: NSPoint(x: center.x - 1, y: center.y + 1),
            controlPoint2: NSPoint(x: center.x - 1, y: center.y + 1)
        )
        path.curve(
            to: NSPoint(x: center.x, y: 2.5),
            controlPoint1: NSPoint(x: center.x - 1, y: center.y - 1),
            controlPoint2: NSPoint(x: center.x - 1, y: center.y - 1)
        )
        path.close()
        path.fill()
    }
}
