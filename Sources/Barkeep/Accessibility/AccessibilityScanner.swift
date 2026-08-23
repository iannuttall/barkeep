import AppKit
import ApplicationServices
import Foundation

struct RunningAppDescriptor: Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
}

final class AccessibilityScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "is.ian.barkeep.accessibility", qos: .userInitiated)
    private var elementsByID: [String: AXUIElement] = [:]

    func scan(apps: [RunningAppDescriptor]) async -> [MenuBarItemSnapshot] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: scanNow(apps: apps))
            }
        }
    }

    func press(itemID: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let element = elementsByID[itemID] else {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(
                    returning: AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                )
            }
        }
    }

    private func scanNow(apps: [RunningAppDescriptor]) -> [MenuBarItemSnapshot] {
        var snapshots: [MenuBarItemSnapshot] = []
        var newElements: [String: AXUIElement] = [:]

        for app in apps where app.bundleIdentifier != "is.ian.barkeep" {
            let application = AXUIElementCreateApplication(app.pid)
            // AXMenuBar is the app's File/Edit/View menu. AXExtrasMenuBar contains
            // the status items that appear on the right side of the macOS menu bar.
            guard let menuBar: AXUIElement = copyAttribute(
                application,
                kAXExtrasMenuBarAttribute as CFString
            ) else {
                continue
            }

            let children: [AXUIElement] = copyArrayAttribute(
                menuBar,
                kAXChildrenAttribute as CFString,
                limit: 256
            )
            for (index, element) in children.enumerated() {
                guard let snapshot = makeSnapshot(element: element, app: app, ordinal: index) else {
                    continue
                }
                if snapshots.contains(where: { existing in
                    existing.bundleIdentifier == snapshot.bundleIdentifier &&
                    abs(existing.frame.midX - snapshot.frame.midX) < 1 &&
                    abs(existing.frame.midY - snapshot.frame.midY) < 1
                }) {
                    continue
                }
                snapshots.append(snapshot)
                newElements[snapshot.id] = element
            }
        }

        elementsByID = newElements
        return snapshots.sorted { lhs, rhs in
            if abs(lhs.frame.midY - rhs.frame.midY) > 2 {
                return lhs.frame.midY > rhs.frame.midY
            }
            return lhs.frame.midX > rhs.frame.midX
        }
    }

    private func makeSnapshot(
        element: AXUIElement,
        app: RunningAppDescriptor,
        ordinal: Int
    ) -> MenuBarItemSnapshot? {
        let role: String? = copyAttribute(element, kAXRoleAttribute as CFString)
        guard role == (kAXMenuBarItemRole as String) else {
            return nil
        }

        guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else {
            return nil
        }

        let title: String? = copyAttribute(element, kAXTitleAttribute as CFString)
        let description: String? = copyAttribute(element, kAXDescriptionAttribute as CFString)
        let identifier: String? = copyAttribute(element, "AXIdentifier" as CFString)
        let cleanTitle = [title, description, identifier, app.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Menu bar item"

        let stablePart = identifier?.isEmpty == false ? identifier! : "\(cleanTitle)|\(ordinal)"
        let id = "\(app.bundleIdentifier ?? "pid:\(app.pid)")|\(stablePart)"
        let enabled: Bool = copyAttribute(element, kAXEnabledAttribute as CFString) ?? true

        return MenuBarItemSnapshot(
            id: id,
            displayName: cleanTitle,
            ownerName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            frame: frame,
            isEnabled: enabled
        )
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copyAttribute(element, kAXPositionAttribute as CFString),
              let sizeValue: AXValue = copyAttribute(element, kAXSizeAttribute as CFString) else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func copyAttribute<T>(_ element: AXUIElement, _ name: CFString) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value as? T
    }

    private func copyArrayAttribute(
        _ element: AXUIElement,
        _ name: CFString,
        limit: Int
    ) -> [AXUIElement] {
        var count: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(element, name, &count) == .success,
              count > 0 else {
            return []
        }
        var value: CFArray?
        let result = AXUIElementCopyAttributeValues(
            element,
            name,
            0,
            min(count, limit),
            &value
        )
        guard result == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
