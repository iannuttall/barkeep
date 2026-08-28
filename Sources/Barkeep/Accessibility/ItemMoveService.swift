import AppKit
import CoreGraphics
import Foundation

struct ScreenGeometry: Sendable {
    let coordinates: ScreenCoordinateSpace
    let safeAreaTop: CGFloat

    var frame: CGRect {
        coordinates.quartzFrame
    }

    var notchRect: CGRect? {
        guard safeAreaTop > 0 else { return nil }
        let width = min(220, frame.width * 0.22)
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.minY - 4,
            width: width,
            height: safeAreaTop + 8
        )
    }
}

final class ItemMoveService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "is.ian.barkeep.item-move", qos: .userInitiated)

    func move(
        from sourceFrame: CGRect,
        to target: CGPoint,
        originalPointer: CGPoint,
        screens: [ScreenGeometry]
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try Self.validate(sourceFrame: sourceFrame, target: target, screens: screens)
                    try Self.postCommandDrag(
                        from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                        to: target,
                        restore: originalPointer
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func validate(
        sourceFrame: CGRect,
        target: CGPoint,
        screens: [ScreenGeometry]
    ) throws {
        guard sourceFrame.width > 0,
              sourceFrame.height > 0,
              sourceFrame.width < 300,
              screens.contains(where: { screen in
                  screen.frame.insetBy(dx: -2, dy: -2).contains(
                      CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
                  )
              }),
              screens.contains(where: { $0.frame.insetBy(dx: -2, dy: -2).contains(target) }) else {
            throw BarkeepError.invalidGeometry
        }

        let start = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        for screen in screens {
            if let notch = screen.notchRect,
               MenuBarGeometry.line(from: start, to: target, intersects: notch) {
                throw BarkeepError.notchBlocksMove
            }
        }
    }

    private static func postCommandDrag(
        from start: CGPoint,
        to end: CGPoint,
        restore originalPointer: CGPoint
    ) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let moveToStart = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: start,
            mouseButton: .left
        ), let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        ) else {
            throw BarkeepError.invalidGeometry
        }

        moveToStart.post(tap: .cghidEventTap)
        usleep(40_000)
        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(60_000)

        for step in 1...12 {
            let amount = CGFloat(step) / 12
            let point = CGPoint(
                x: start.x + (end.x - start.x) * amount,
                y: start.y + (end.y - start.y) * amount
            )
            guard let drag = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                throw BarkeepError.invalidGeometry
            }
            drag.flags = .maskCommand
            drag.post(tap: .cghidEventTap)
            usleep(16_000)
        }

        guard let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        ), let restore = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalPointer,
            mouseButton: .left
        ) else {
            throw BarkeepError.invalidGeometry
        }
        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)
        usleep(50_000)
        restore.post(tap: .cghidEventTap)
    }
}
