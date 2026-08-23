import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.showSettings()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-permission-guide") {
            DispatchQueue.main.async {
                PermissionAssistant.shared.presentAccessibilityGuide(keepVisibleForTesting: true)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--request-accessibility") {
            DispatchQueue.main.async {
                AccessibilityPermission.request()
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--show-hidden-items") {
            DispatchQueue.main.async { [weak self] in
                self?.coordinator.revealHiddenItemsForLaunchTest()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
