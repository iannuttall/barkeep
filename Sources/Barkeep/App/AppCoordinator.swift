import AppKit
import Combine
import LocalAuthentication
import UniformTypeIdentifiers
import os

private let moveLog = Logger(subsystem: "is.ian.barkeep", category: "move")

private struct MoveConfirmation {
    let items: [MenuBarItemSnapshot]
    let item: MenuBarItemSnapshot
    let boundaries: BoundaryFrames
}

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let store: StateStore
    let updater = UpdateService.shared

    @Published private(set) var items: [MenuBarItemSnapshot] = []
    @Published private(set) var itemZones: [String: VisibilityZone] = [:]
    @Published private(set) var isScanning = false
    @Published private(set) var movingItemID: String?
    @Published var message: String?

    private let statusBar = StatusBarEngine()
    private let scanner = AccessibilityScanner()
    private let mover = ItemMoveService()
    private let triggers = TriggerCenter()
    private let hotKeys = HotKeyCenter()
    private var settingsWindow: SettingsWindowController?
    private var searchPanel: SearchPanelController?
    private var rehideTask: Task<Void, Never>?
    private var authenticationContext: LAContext?
    private var permissionObserver: NSObjectProtocol?

    init(store: StateStore = StateStore()) {
        self.store = store
        super.init()
    }

    func start() {
        statusBar.onPrimaryAction = { [weak self] event in
            self?.handlePrimaryClick(event)
        }
        statusBar.menuProvider = { [weak self] in
            self?.makeMenu() ?? NSMenu()
        }
        triggers.onReveal = { [weak self] in self?.requestReveal(all: false) }
        triggers.onHide = { [weak self] in self?.hide() }
        hotKeys.onToggle = { [weak self] in
            guard let self else { return }
            statusBar.state == .hidden ? requestReveal(all: false) : hide()
        }
        hotKeys.onSearch = { [weak self] in self?.showSearch() }
        hotKeys.start()
        updater.onWillShowWindow = { [weak self] in
            self?.settingsWindow?.close()
            self?.searchPanel?.close()
        }
        permissionObserver = NotificationCenter.default.addObserver(
            forName: PermissionAssistant.accessibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
                Task { await self?.refreshItems(promptForPermission: false) }
            }
        }
        settingsDidChange()
        statusBar.hide()
    }

    func settingsDidChange() {
        let settings = store.settings
        statusBar.setIconStyle(settings.iconStyle)
        triggers.update(settings: settings)
        MenuBarSpacingService.apply(settings: settings)
        applyActivationPolicy()
        do {
            try LoginItemService.setEnabled(settings.launchAtLogin)
        } catch {
            message = "Barkeep could not change Launch at Login: \(error.localizedDescription)"
        }
    }

    func iconStyleDidChange() {
        statusBar.setIconStyle(store.settings.iconStyle)
    }

    func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(coordinator: self)
            controller.onClose = { [weak self] in
                guard let self else { return }
                self.settingsWindow = nil
                self.applyActivationPolicy()
            }
            settingsWindow = controller
        }
        applyActivationPolicy()
        settingsWindow?.show()
        Task { await refreshItems(promptForPermission: false) }
    }

    private func applyActivationPolicy() {
        let keepRegular = settingsWindow != nil || store.settings.showDockIcon
        NSApp.setActivationPolicy(keepRegular ? .regular : .accessory)
    }

    func showSearch() {
        guard canRevealWithoutPrompt || !store.settings.requireAuthentication else {
            authenticate { [weak self] in self?.showSearch() }
            return
        }
        if searchPanel == nil {
            let controller = SearchPanelController(coordinator: self)
            controller.onClose = { [weak self] in self?.searchPanel = nil }
            searchPanel = controller
        }
        searchPanel?.show()
        Task { await refreshItems(promptForPermission: true) }
    }

    func refreshItems(promptForPermission: Bool) async {
        guard !isScanning, movingItemID == nil else { return }
        guard AccessibilityPermission.isGranted else {
            if promptForPermission { AccessibilityPermission.request() }
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }

        isScanning = true
        let previousState = statusBar.state
        statusBar.revealAll()
        try? await Task.sleep(for: .milliseconds(140))
        let result = await scanner.scan(apps: runningApps())
        let boundaries = statusBar.boundaryFrames()
        itemZones = zones(for: result, boundaries: boundaries)
        items = result
        statusBar.setState(previousState)
        isScanning = false
        message = result.isEmpty ? "Barkeep did not find any menu bar items." : nil
    }

    func currentZone(for item: MenuBarItemSnapshot) -> VisibilityZone {
        itemZones[item.id] ?? store.rules[item.id]?.zone ?? .alwaysVisible
    }

    func items(in zone: VisibilityZone) -> [MenuBarItemSnapshot] {
        items.filter { !$0.isPinnedByMacOS && currentZone(for: $0) == zone }
    }

    func moveItem(_ item: MenuBarItemSnapshot, to zone: VisibilityZone) async {
        guard movingItemID == nil, !isScanning else { return }
        guard !item.isPinnedByMacOS else {
            message = BarkeepError.itemPinnedByMacOS.localizedDescription
            return
        }
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            message = BarkeepError.accessibilityRequired.localizedDescription
            return
        }

        movingItemID = item.id
        let previousState = statusBar.state
        rehideTask?.cancel()
        rehideTask = nil
        statusBar.revealAll()
        defer {
            statusBar.setState(previousState)
            movingItemID = nil
            if previousState != .hidden {
                scheduleRehide()
            }
        }

        do {
            let screens = screenGeometries()
            guard let originalPointer = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: NSEvent.mouseLocation)
            }).first else {
                throw BarkeepError.invalidGeometry
            }
            let reveal = try await waitForRevealedItem(matching: item, screens: screens)
            let freshItems = reveal.items
            let freshItem = reveal.item
            moveLog.notice("""
            move \(item.id, privacy: .public) -> \(zone.title, privacy: .public) \
            source=\(String(describing: freshItem.frame), privacy: .public)
            """)
            guard let target = statusBar.targetPoint(for: zone) else {
                throw BarkeepError.boundariesUnavailable
            }
            if let boundaries = statusBar.boundaryFrames() {
                moveLog.notice("""
                boundaries control=\(String(describing: boundaries.control), privacy: .public) \
                hidden=\(String(describing: boundaries.hidden), privacy: .public) \
                alwaysHidden=\(String(describing: boundaries.alwaysHidden), privacy: .public) \
                target=\(String(describing: target), privacy: .public)
                """)
            }
            guard let quartzTarget = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: target)
            }).first else {
                throw BarkeepError.invalidGeometry
            }
            let rawSourcePoint = CGPoint(x: freshItem.frame.midX, y: freshItem.frame.midY)
            guard let quartzSource = screens.compactMap({
                $0.coordinates.quartzPoint(
                    fromAccessibility: rawSourcePoint,
                    menuBarAnchorY: quartzTarget.y
                )
            }).min(by: {
                abs($0.y - quartzTarget.y) < abs($1.y - quartzTarget.y)
            }) else {
                throw BarkeepError.invalidGeometry
            }
            if screens.contains(where: {
                $0.hidesMenuBarPoint(quartzSource) || $0.hidesMenuBarPoint(quartzTarget)
            }) {
                throw BarkeepError.menuBarFull
            }
            let quartzSourceFrame = CGRect(
                x: quartzSource.x - freshItem.frame.width / 2,
                y: quartzSource.y - freshItem.frame.height / 2,
                width: freshItem.frame.width,
                height: freshItem.frame.height
            )

            if let boundaries = statusBar.boundaryFrames(),
               boundaries.zone(for: freshItem.frame) == zone {
                applyConfirmedMove(
                    MoveConfirmation(items: freshItems, item: freshItem, boundaries: boundaries),
                    to: zone
                )
                return
            }

            try await mover.move(
                from: quartzSourceFrame,
                to: quartzTarget,
                originalPointer: originalPointer,
                screens: screens
            )
            guard let confirmation = await confirmMove(item, to: zone) else {
                throw BarkeepError.moveNotConfirmed
            }
            applyConfirmedMove(confirmation, to: zone)
        } catch {
            message = error.localizedDescription
        }
    }

    func activate(_ item: MenuBarItemSnapshot) async {
        if await scanner.press(itemID: item.id) {
            searchPanel?.close()
            scheduleRehide()
            return
        }
        statusBar.revealAll()
        try? await Task.sleep(for: .milliseconds(140))
        await refreshItems(promptForPermission: true)
        if let refreshed = items.first(where: { matches($0, item) }),
           await scanner.press(itemID: refreshed.id) {
            searchPanel?.close()
            scheduleRehide()
        } else {
            message = BarkeepError.itemNotFound.localizedDescription
        }
    }

    func requestReveal(all: Bool) {
        guard movingItemID == nil else { return }
        if store.settings.requireAuthentication && statusBar.state == .hidden {
            authenticate { [weak self] in self?.reveal(all: all) }
        } else {
            reveal(all: all)
        }
    }

    func revealHiddenItemsForLaunchTest() {
        rehideTask?.cancel()
        rehideTask = nil
        statusBar.revealHidden()
    }

    func hide() {
        guard movingItemID == nil else { return }
        rehideTask?.cancel()
        rehideTask = nil
        statusBar.hide()
        authenticationContext = nil
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Barkeep Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            message = "Barkeep exported the settings."
        } catch {
            message = "Barkeep could not export the settings: \(error.localizedDescription)"
        }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importData(Data(contentsOf: url))
            settingsDidChange()
            message = "Barkeep imported the settings."
        } catch {
            message = "Barkeep could not import this file: \(error.localizedDescription)"
        }
    }

    private var canRevealWithoutPrompt: Bool {
        authenticationContext != nil
    }

    private func handlePrimaryClick(_ event: NSEvent) {
        guard movingItemID == nil else { return }
        if event.modifierFlags.contains(.option) {
            if statusBar.state == .revealedAll { hide() } else { requestReveal(all: true) }
        } else if statusBar.state == .hidden {
            requestReveal(all: false)
        } else {
            hide()
        }
    }

    private func reveal(all: Bool) {
        guard movingItemID == nil else { return }
        all ? statusBar.revealAll() : statusBar.revealHidden()
        scheduleRehide()
    }

    private func scheduleRehide() {
        rehideTask?.cancel()
        guard store.settings.autoRehide else { return }
        let delay = store.settings.rehideDelay
        rehideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            // Stay open while the pointer is in the menu bar area or a menu
            // is open, so the bar never hides mid-interaction.
            while !Task.isCancelled, Self.pointerIsBusyInMenuBar() {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private static func pointerIsBusyInMenuBar() -> Bool {
        let location = NSEvent.mouseLocation
        if NSScreen.screens.contains(where: {
            Self.isInMenuBarStrip(location: location, screenFrame: $0.frame)
        }) {
            return true
        }
        return menuIsOpen()
    }

    static func isInMenuBarStrip(location: CGPoint, screenFrame: CGRect) -> Bool {
        location.x >= screenFrame.minX &&
        location.x <= screenFrame.maxX &&
        location.y >= screenFrame.maxY - 38 &&
        location.y <= screenFrame.maxY
    }

    private static func menuIsOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == menuLayer }
    }

    private func authenticate(onSuccess: @escaping @MainActor () -> Void) {
        let context = LAContext()
        authenticationContext = context
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Show hidden menu bar items"
        ) { [weak self] success, _ in
            Task { @MainActor in
                if success {
                    onSuccess()
                } else {
                    self?.authenticationContext = nil
                    self?.message = BarkeepError.authenticationFailed.localizedDescription
                }
            }
        }
    }

    private func runningApps() -> [RunningAppDescriptor] {
        NSWorkspace.shared.runningApplications.map {
            RunningAppDescriptor(
                pid: $0.processIdentifier,
                name: $0.localizedName ?? $0.bundleIdentifier ?? "App",
                bundleIdentifier: $0.bundleIdentifier
            )
        }
    }

    private func screenGeometries() -> [ScreenGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let quartzFrame = CGDisplayBounds(displayID)
            var statusAreaMinX: CGFloat?
            if screen.safeAreaInsets.top > 0, let statusArea = screen.auxiliaryTopRightArea {
                statusAreaMinX = quartzFrame.minX + statusArea.minX - screen.frame.minX
            }
            return ScreenGeometry(
                coordinates: ScreenCoordinateSpace(
                    appKitFrame: screen.frame,
                    quartzFrame: quartzFrame
                ),
                statusAreaMinX: statusAreaMinX
            )
        }
    }

    private func zones(
        for snapshots: [MenuBarItemSnapshot],
        boundaries: BoundaryFrames?
    ) -> [String: VisibilityZone] {
        var result: [String: VisibilityZone] = [:]
        for item in snapshots {
            result[item.id] = boundaries?.zone(for: item.frame)
                ?? itemZones[item.id]
                ?? store.rules[item.id]?.zone
                ?? .alwaysVisible
        }
        return result
    }

    private func confirmMove(
        _ requestedItem: MenuBarItemSnapshot,
        to zone: VisibilityZone
    ) async -> MoveConfirmation? {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(100))
            let scannedItems = await scanner.scan(apps: runningApps())
            guard let verifiedItem = scannedItems.first(where: { matches($0, requestedItem) }),
                  let boundaries = statusBar.boundaryFrames() else {
                continue
            }
            moveLog.notice("""
            confirm scan frame=\(String(describing: verifiedItem.frame), privacy: .public) \
            zone=\(boundaries.zone(for: verifiedItem.frame).title, privacy: .public)
            """)
            if boundaries.zone(for: verifiedItem.frame) == zone {
                return MoveConfirmation(
                    items: scannedItems,
                    item: verifiedItem,
                    boundaries: boundaries
                )
            }
        }
        return nil
    }

    private func applyConfirmedMove(_ confirmation: MoveConfirmation, to zone: VisibilityZone) {
        itemZones = zones(for: confirmation.items, boundaries: confirmation.boundaries)
        items = confirmation.items
        store.setRule(for: confirmation.item, zone: zone)
        message = "\(confirmation.item.displayName) is now \(zone.title.lowercased())."
    }

    /// Always-hidden items slide in from off screen after revealAll, so a fixed delay
    /// can scan a frame that is still off screen or still animating. Poll until the
    /// item reports the same on-screen frame twice before using it as a drag source.
    private func waitForRevealedItem(
        matching item: MenuBarItemSnapshot,
        screens: [ScreenGeometry]
    ) async throws -> (items: [MenuBarItemSnapshot], item: MenuBarItemSnapshot) {
        var sawItem = false
        var previousFrame: CGRect?
        for _ in 0..<16 {
            try await Task.sleep(for: .milliseconds(140))
            let scannedItems = await scanner.scan(apps: runningApps())
            guard let match = scannedItems.first(where: { matches($0, item) }) else {
                previousFrame = nil
                continue
            }
            sawItem = true
            let source = CGPoint(x: match.frame.midX, y: match.frame.midY)
            let onScreen = screens.contains {
                $0.coordinates.quartzPoint(
                    fromAccessibility: source,
                    menuBarAnchorY: source.y
                ) != nil
            }
            guard onScreen else {
                moveLog.notice(
                    "reveal wait: off screen \(String(describing: match.frame), privacy: .public)"
                )
                previousFrame = nil
                continue
            }
            if let previous = previousFrame,
               abs(previous.midX - match.frame.midX) < 1,
               abs(previous.midY - match.frame.midY) < 1 {
                return (scannedItems, match)
            }
            previousFrame = match.frame
        }
        throw sawItem ? BarkeepError.itemNotRevealed : BarkeepError.itemNotFound
    }

    private func matches(_ lhs: MenuBarItemSnapshot, _ rhs: MenuBarItemSnapshot) -> Bool {
        lhs.id == rhs.id || (
            lhs.bundleIdentifier == rhs.bundleIdentifier &&
            lhs.displayName == rhs.displayName &&
            lhs.ownerName == rhs.ownerName
        )
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleTitle = statusBar.state == .hidden ? "Show Hidden Items" : "Hide Items"
        menu.addItem(withTitle: toggleTitle, action: #selector(menuToggle), keyEquivalent: "")
        menu.addItem(withTitle: "Show All Items", action: #selector(menuShowAll), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Find Item…", action: #selector(menuSearch), keyEquivalent: "f")
        menu.addItem(withTitle: "Arrange Items…", action: #selector(menuSettings), keyEquivalent: ",")
        if updater.isConfigured {
            let updateTitle = updater.pendingVersion.map { "Update to \($0)…" } ?? "Check for Updates…"
            menu.addItem(withTitle: updateTitle, action: #selector(menuUpdate), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Barkeep", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    @objc private func menuToggle() {
        statusBar.state == .hidden ? requestReveal(all: false) : hide()
    }

    @objc private func menuShowAll() { requestReveal(all: true) }
    @objc private func menuSearch() { showSearch() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuUpdate() {
        settingsWindow?.close()
        searchPanel?.close()
        updater.checkForUpdates()
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
