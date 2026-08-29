import AppKit
import CoreGraphics
import Foundation

struct ScreenGeometry: Sendable {
    let coordinates: ScreenCoordinateSpace

    var frame: CGRect {
        coordinates.quartzFrame
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
                    try Self.validate(
                        sourceFrame: sourceFrame,
                        target: target,
                        screens: screens
                    )
                    try Self.postCommandDrag(
                        from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
                        to: target,
                        restore: originalPointer,
                        eventTap: .cgSessionEventTap
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func validate(
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
    }

    private static func postCommandDrag(
        from start: CGPoint,
        to end: CGPoint,
        restore originalPointer: CGPoint,
        eventTap: CGEventTapLocation
    ) throws {
        guard let moveToStart = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: start,
            mouseButton: .left
        ), let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        ) else {
            throw BarkeepError.invalidGeometry
        }

        CGDisplayHideCursor(CGMainDisplayID())
        defer { CGDisplayShowCursor(CGMainDisplayID()) }

        moveToStart.post(tap: eventTap)
        usleep(60_000)
        down.flags = .maskCommand
        down.post(tap: eventTap)
        usleep(80_000)

        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = min(max(Int(ceil(distance / 22)), 10), 14)
        for step in 1...steps {
            let amount = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * amount,
                y: start.y + (end.y - start.y) * amount
            )
            guard let drag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else {
                throw BarkeepError.invalidGeometry
            }
            drag.flags = .maskCommand
            drag.post(tap: eventTap)
            usleep(15_000)
        }

        guard let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        ), let restore = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalPointer,
            mouseButton: .left
        ) else {
            throw BarkeepError.invalidGeometry
        }
        up.flags = .maskCommand
        up.post(tap: eventTap)
        usleep(140_000)
        restore.post(tap: eventTap)
    }
}
