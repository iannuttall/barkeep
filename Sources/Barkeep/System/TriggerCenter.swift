import AppKit

@MainActor
final class TriggerCenter {
    var onReveal: (() -> Void)?
    var onHide: (() -> Void)?

    private var settings = BarkeepSettings()
    private var hoverTimer: Timer?
    private var hoverStart: Date?
    private var globalMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    func update(settings newSettings: BarkeepSettings) {
        settings = newSettings
        stop()

        if settings.showOnHover {
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkHover()
                }
            }
        }

        var mask: NSEvent.EventTypeMask = []
        if settings.showOnScroll { mask.insert(.scrollWheel) }
        if settings.showOnMenuBarClick { mask.insert(.leftMouseDown) }
        if !mask.isEmpty {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor in
                    self?.handleGlobalEvent(event)
                }
            }
        }

        if settings.hideOnAppChange {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onHide?()
                }
            }
        }

        if settings.alwaysShowOnExternalDisplay {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.showForExternalDisplayIfNeeded()
                }
            }
            showForExternalDisplayIfNeeded()
        }
    }

    func stop() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverStart = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func checkHover() {
        let point = NSEvent.mouseLocation
        let isInMenuBar = NSScreen.screens.contains { screen in
            let menuBand = CGRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - NSStatusBar.system.thickness - 3,
                width: screen.frame.width,
                height: NSStatusBar.system.thickness + 3
            )
            return menuBand.contains(point)
        }

        if isInMenuBar {
            let start = hoverStart ?? Date()
            hoverStart = start
            if Date().timeIntervalSince(start) >= settings.hoverDelay {
                onReveal?()
                hoverStart = Date.distantFuture
            }
        } else {
            hoverStart = nil
        }
    }

    private func handleGlobalEvent(_ event: NSEvent) {
        let point = event.locationInWindow
        let inMenuBar = NSScreen.screens.contains { screen in
            point.y >= screen.frame.maxY - NSStatusBar.system.thickness - 3 &&
            point.y <= screen.frame.maxY + 1 &&
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX
        }
        guard inMenuBar else { return }
        if event.type == .scrollWheel {
            guard abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 1 else { return }
        }
        onReveal?()
    }

    private func showForExternalDisplayIfNeeded() {
        if NSScreen.screens.count > 1 {
            onReveal?()
        }
    }
}
