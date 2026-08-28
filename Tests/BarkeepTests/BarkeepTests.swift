import XCTest
@testable import Barkeep

final class BarkeepTests: XCTestCase {
    func testBoundaryClassification() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 900, width: 20, height: 24),
            hidden: CGRect(x: 700, y: 900, width: 10, height: 24),
            alwaysHidden: CGRect(x: 400, y: 900, width: 10, height: 24)
        )

        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 800, y: 900, width: 20, height: 24)),
            .alwaysVisible
        )
        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 550, y: 900, width: 20, height: 24)),
            .hidden
        )
        XCTAssertEqual(
            boundaries.zone(for: CGRect(x: 250, y: 900, width: 20, height: 24)),
            .alwaysHidden
        )
    }

    func testBoundaryTargetsAllowEmptySections() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            hidden: CGRect(x: 886, y: 876, width: 14, height: 24),
            alwaysHidden: CGRect(x: 872, y: 876, width: 14, height: 24)
        )

        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysVisible),
            CGPoint(x: 900, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .hidden),
            CGPoint(x: 886, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysHidden),
            CGPoint(x: 854, y: 888)
        )
    }

    func testBoundaryTargetsRejectInvalidOrdering() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            hidden: CGRect(x: 872, y: 876, width: 14, height: 24),
            alwaysHidden: CGRect(x: 886, y: 876, width: 14, height: 24)
        )

        for zone in VisibilityZone.allCases {
            XCTAssertNil(boundaries.targetPoint(for: zone))
        }
    }

    func testAppKitPointsConvertToQuartzCoordinates() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 100, y: 888)),
            CGPoint(x: 100, y: 12)
        )
        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 500, y: 300)),
            CGPoint(x: 500, y: 600)
        )
    }

    func testAppKitPointsConvertAcrossOffsetDisplays() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 1440, y: 100, width: 1920, height: 1080),
            quartzFrame: CGRect(x: 1440, y: -280, width: 1920, height: 1080)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(fromAppKit: CGPoint(x: 1540, y: 1160)),
            CGPoint(x: 1540, y: -260)
        )
        XCTAssertNil(coordinates.quartzPoint(fromAppKit: CGPoint(x: 100, y: 100)))
    }

    func testLongDragPathDetectsNarrowNotch() {
        let notch = CGRect(x: 49, y: -1, width: 2, height: 2)

        XCTAssertTrue(
            MenuBarGeometry.line(
                from: CGPoint(x: 0, y: 0),
                to: CGPoint(x: 2_400, y: 0),
                intersects: notch
            )
        )
        XCTAssertFalse(
            MenuBarGeometry.line(
                from: CGPoint(x: 0, y: 2),
                to: CGPoint(x: 2_400, y: 2),
                intersects: notch
            )
        )
    }

    func testDefaultProductRules() {
        let settings = BarkeepSettings()
        XCTAssertEqual(settings.iconStyle, .dot)
        XCTAssertTrue(settings.autoRehide)
        XCTAssertEqual(settings.rehideDelay, 5)
        XCTAssertFalse(settings.showOnHover)
        XCTAssertFalse(settings.showOnScroll)
        XCTAssertFalse(settings.requireAuthentication)
        XCTAssertFalse(settings.reduceItemSpacing)
    }

    @MainActor
    func testStateRoundTrip() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let item = MenuBarItemSnapshot(
            id: "com.example.app|Status",
            displayName: "Status",
            ownerName: "Example",
            bundleIdentifier: "com.example.app",
            frame: CGRect(x: 10, y: 10, width: 20, height: 20),
            isEnabled: true
        )

        let first = StateStore(baseURL: baseURL)
        first.updateSettings { $0.iconStyle = .ring }
        first.setRule(for: item, zone: .alwaysVisible)

        let second = StateStore(baseURL: baseURL)
        XCTAssertEqual(second.settings.iconStyle, .ring)
        XCTAssertEqual(second.rules[item.id]?.zone, .alwaysVisible)
    }

    @MainActor
    func testSettingsUpdateNotifiesObservers() {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = StateStore(baseURL: baseURL)
        var notifications = 0
        let subscription = store.objectWillChange.sink { notifications += 1 }

        store.updateSettings { $0.showOnHover = true }

        XCTAssertTrue(store.settings.showOnHover)
        XCTAssertGreaterThanOrEqual(notifications, 1)
        withExtendedLifetime(subscription) {}
    }

    func testAllIconsRenderAtNativeSize() {
        for style in BarkeepIconStyle.allCases {
            let image = BarkeepIconFactory.image(for: style, expanded: false)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertTrue(image.isTemplate)
        }
    }
}
