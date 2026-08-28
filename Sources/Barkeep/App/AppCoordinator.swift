import AppKit
import Combine
import LocalAuthentication
import UniformTypeIdentifiers

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
        items.filter { currentZone(for: $0) == zone }
    }

    func moveItem(_ item: MenuBarItemSnapshot, to zone: VisibilityZone) async {
        guard movingItemID == nil, !isScanning else { return }
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
            try await Task.sleep(for: .milliseconds(160))
            let freshItems = await scanner.scan(apps: runningApps())
            guard let freshItem = freshItems.first(where: { matches($0, item) }) else {
                throw BarkeepError.itemNotFound
            }
            guard let target = statusBar.targetPoint(for: zone) else {
                throw BarkeepError.boundariesUnavailable
            }

            let screens = screenGeometries()
            guard let quartzTarget = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: target)
            }).first,
            let originalPointer = screens.lazy.compactMap({
                $0.coordinates.quartzPoint(fromAppKit: NSEvent.mouseLocation)
            }).first else {
                throw BarkeepError.invalidGeometry
            }
            try await mover.move(
                from: freshItem.frame,
                to: quartzTarget,
                originalPointer: originalPointer,
                screens: screens
            )
            try await Task.sleep(for: .milliseconds(260))
            let verifiedItems = await scanner.scan(apps: runningApps())
            guard let verified = verifiedItems.first(where: { matches($0, item) }),
                  let boundaries = statusBar.boundaryFrames(),
                  boundaries.zone(for: verified.frame) == zone else {
                throw BarkeepError.moveNotConfirmed
            }
            itemZones = zones(for: verifiedItems, boundaries: boundaries)
            items = verifiedItems
            store.setRule(for: verified, zone: zone)
            message = "\(verified.displayName) is now \(zone.title.lowercased())."
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
            guard !Task.isCancelled else { return }
            self?.hide()
        }
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
            return ScreenGeometry(
                coordinates: ScreenCoordinateSpace(
                    appKitFrame: screen.frame,
                    quartzFrame: CGDisplayBounds(displayID)
                ),
                safeAreaTop: screen.safeAreaInsets.top
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
