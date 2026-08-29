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

    func testSystemItemsRightOfControlAreAlwaysVisible() {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            hidden: CGRect(x: 950, y: 876, width: 14, height: 24),
            alwaysHidden: CGRect(x: 400, y: 876, width: 14, height: 24)
        )
        let systemItem = CGRect(x: 920, y: 876, width: 20, height: 24)

        XCTAssertGreaterThan(systemItem.midX, boundaries.control.midX)
        XCTAssertLessThan(systemItem.midX, boundaries.hidden.midX)
        XCTAssertEqual(boundaries.zone(for: systemItem), .alwaysVisible)
    }

    func testBoundaryTargetsAllowEmptySections() throws {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            hidden: CGRect(x: 886, y: 876, width: 14, height: 24),
            alwaysHidden: CGRect(x: 872, y: 876, width: 14, height: 24)
        )

        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysVisible),
            CGPoint(x: 901, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .hidden),
            CGPoint(x: 887, y: 888)
        )
        XCTAssertEqual(
            boundaries.targetPoint(for: .alwaysHidden),
            CGPoint(x: 854, y: 888)
        )

        let visibleTarget = try XCTUnwrap(boundaries.targetPoint(for: .alwaysVisible))
        let insertedItem = CGRect(x: visibleTarget.x - 11, y: 876, width: 22, height: 24)
        XCTAssertEqual(boundaries.zone(for: insertedItem), .alwaysVisible)
    }

    func testTargetMovesItemOutOfAlwaysHidden() throws {
        let boundaries = BoundaryFrames(
            control: CGRect(x: 900, y: 876, width: 20, height: 24),
            hidden: CGRect(x: 700, y: 876, width: 14, height: 24),
            alwaysHidden: CGRect(x: 400, y: 876, width: 14, height: 24)
        )
        let initialFrame = CGRect(x: 250, y: 876, width: 22, height: 24)
        let hiddenTarget = try XCTUnwrap(boundaries.targetPoint(for: .hidden))
        let movedFrame = CGRect(x: hiddenTarget.x - 11, y: 876, width: 22, height: 24)

        XCTAssertEqual(boundaries.zone(for: initialFrame), .alwaysHidden)
        XCTAssertEqual(boundaries.zone(for: movedFrame), .hidden)
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

    func testAccessibilitySourceUsesMenuBarCoordinateCandidate() {
        let coordinates = ScreenCoordinateSpace(
            appKitFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            quartzFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(
            coordinates.quartzPoint(
                fromAccessibility: CGPoint(x: 100, y: 12),
                menuBarAnchorY: 12
            ),
            CGPoint(x: 100, y: 12)
        )
        XCTAssertEqual(
            coordinates.quartzPoint(
                fromAccessibility: CGPoint(x: 100, y: 888),
                menuBarAnchorY: 12
            ),
            CGPoint(x: 100, y: 12)
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

    func testNoNotchDisplayAllowsSettingsMove() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
            )
        )

        XCTAssertNoThrow(
            try ItemMoveService.validate(
                sourceFrame: CGRect(x: 1_500, y: 0, width: 22, height: 24),
                target: CGPoint(x: 1_200, y: 12),
                screens: [screen]
            )
        )
    }

    func testNotchedDisplayAllowsSettingsMoveAcrossCenter() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            )
        )
        let source = CGRect(x: 1_300, y: 0, width: 22, height: 24)
        let target = CGPoint(x: 200, y: 12)
        let cameraHousing = CGRect(x: 646, y: 0, width: 220, height: 40)

        // macOS owns overflow around the housing. Barkeep validates the landing
        // points and relies on the confirmation scan instead of blocking this path.
        XCTAssertGreaterThan(source.midX, cameraHousing.maxX)
        XCTAssertLessThan(target.x, cameraHousing.minX)
        XCTAssertTrue(cameraHousing.contains(CGPoint(x: cameraHousing.midX, y: target.y)))
        XCTAssertNoThrow(
            try ItemMoveService.validate(
                sourceFrame: source,
                target: target,
                screens: [screen]
            )
        )
    }

    func testSettingsMoveRejectsOffscreenTarget() {
        let screen = ScreenGeometry(
            coordinates: ScreenCoordinateSpace(
                appKitFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                quartzFrame: CGRect(x: 0, y: 0, width: 1_512, height: 982)
            )
        )

        XCTAssertThrowsError(
            try ItemMoveService.validate(
                sourceFrame: CGRect(x: 1_300, y: 0, width: 22, height: 24),
                target: CGPoint(x: -100, y: 12),
                screens: [screen]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                BarkeepError.invalidGeometry.localizedDescription
            )
        }
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
