import Foundation

enum VisibilityZone: String, Codable, CaseIterable, Identifiable, Sendable {
    case alwaysVisible
    case hidden
    case alwaysHidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysVisible: "Always visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always hidden"
        }
    }

    var help: String {
        switch self {
        case .alwaysVisible: "Barkeep never hides these items."
        case .hidden: "Click the Barkeep icon to show or hide these items."
        case .alwaysHidden: "Barkeep shows these items only when you ask."
        }
    }
}

enum BarkeepIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case dot
    case ring
    case ellipsis
    case diamond
    case chevrons
    case line
    case sparkle
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dot: "Dot"
        case .ring: "Ring"
        case .ellipsis: "Ellipsis"
        case .diamond: "Diamond"
        case .chevrons: "Chevrons"
        case .line: "Line"
        case .sparkle: "Sparkle"
        case .grid: "Grid"
        }
    }
}

struct BarkeepSettings: Codable, Equatable, Sendable {
    var launchAtLogin = false
    var showDockIcon = false
    var iconStyle: BarkeepIconStyle = .dot
    var autoRehide = true
    var rehideDelay: TimeInterval = 5
    var hideOnAppChange = false
    var showOnHover = false
    var hoverDelay: TimeInterval = 1
    var showOnScroll = false
    var showOnMenuBarClick = true

    var requireAuthentication = false
    var showOnLowBattery = false
    var lowBatteryLevel = 20
    var alwaysShowOnExternalDisplay = false

    var useCustomAppearance = false
    var appearanceOpacity = 0.16
    var appearanceCornerRadius = 8.0
    var appearanceBorder = false
    var reduceItemSpacing = false
    var itemSpacing = 4
    var itemPadding = 4
}

struct ItemRule: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var ownerName: String
    var bundleIdentifier: String?
    var zone: VisibilityZone
    var group: String?
}

struct BarkeepProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var rules: [String: ItemRule]
    var settings: BarkeepSettings
    let createdAt: Date

    init(name: String, rules: [String: ItemRule], settings: BarkeepSettings) {
        id = UUID()
        self.name = name
        self.rules = rules
        self.settings = settings
        createdAt = Date()
    }
}

struct BarkeepDocument: Codable, Sendable {
    var version = 1
    var settings = BarkeepSettings()
    var rules: [String: ItemRule] = [:]
    var groups: [String] = []
    var profiles: [BarkeepProfile] = []
}

struct MenuBarItemSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let ownerName: String
    let bundleIdentifier: String?
    let frame: CGRect
    let isEnabled: Bool
}

struct BoundaryFrames: Sendable {
    let control: CGRect
    let hidden: CGRect
    let alwaysHidden: CGRect

    func zone(for itemFrame: CGRect) -> VisibilityZone {
        if itemFrame.midX > hidden.midX {
            return .alwaysVisible
        }
        if itemFrame.midX > alwaysHidden.midX {
            return .hidden
        }
        return .alwaysHidden
    }

    func targetPoint(for zone: VisibilityZone) -> CGPoint? {
        guard alwaysHidden.midX < hidden.midX,
              hidden.midX < control.midX else {
            return nil
        }

        let y = control.midY
        switch zone {
        case .alwaysVisible:
            guard hidden.maxX <= control.minX else { return nil }
            return CGPoint(x: (hidden.maxX + control.minX) / 2, y: y)
        case .hidden:
            guard alwaysHidden.maxX <= hidden.minX else { return nil }
            return CGPoint(x: (alwaysHidden.maxX + hidden.minX) / 2, y: y)
        case .alwaysHidden:
            return CGPoint(x: alwaysHidden.minX - 18, y: y)
        }
    }
}

struct ScreenCoordinateSpace: Sendable {
    let appKitFrame: CGRect
    let quartzFrame: CGRect

    func quartzPoint(fromAppKit point: CGPoint) -> CGPoint? {
        guard appKitFrame.insetBy(dx: -2, dy: -2).contains(point) else {
            return nil
        }
        return CGPoint(
            x: quartzFrame.minX + point.x - appKitFrame.minX,
            y: quartzFrame.minY + appKitFrame.maxY - point.y
        )
    }
}

enum MenuBarGeometry {
    static func line(from start: CGPoint, to end: CGPoint, intersects rect: CGRect) -> Bool {
        guard !rect.isNull, !rect.isEmpty else { return false }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        var lowerBound: CGFloat = 0
        var upperBound: CGFloat = 1

        func clips(_ direction: CGFloat, _ distance: CGFloat) -> Bool {
            if abs(direction) < CGFloat.ulpOfOne {
                return distance >= 0
            }

            let ratio = distance / direction
            if direction < 0 {
                guard ratio <= upperBound else { return false }
                lowerBound = max(lowerBound, ratio)
            } else {
                guard ratio >= lowerBound else { return false }
                upperBound = min(upperBound, ratio)
            }
            return true
        }

        return clips(-deltaX, start.x - rect.minX)
            && clips(deltaX, rect.maxX - start.x)
            && clips(-deltaY, start.y - rect.minY)
            && clips(deltaY, rect.maxY - start.y)
    }
}

enum BarkeepError: LocalizedError {
    case accessibilityRequired
    case itemNotFound
    case boundariesUnavailable
    case invalidGeometry
    case notchBlocksMove
    case moveNotConfirmed
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired: "Give Barkeep Accessibility access to list and move menu bar items."
        case .itemNotFound: "Barkeep could not find this item in the current menu bar."
        case .boundariesUnavailable: "Barkeep could not find its section boundaries."
        case .invalidGeometry: "The current menu bar layout is not safe for this move."
        case .notchBlocksMove: "The camera notch blocks this move. Use Search or tighter item spacing."
        case .moveNotConfirmed: "macOS did not complete the move. Barkeep kept the old section."
        case .authenticationFailed: "Barkeep did not reveal the hidden items."
        }
    }
}
