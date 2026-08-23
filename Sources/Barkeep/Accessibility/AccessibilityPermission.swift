import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    static func request() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        Task { @MainActor in
            // The trust request is asynchronous. Give macOS time to register this
            // signed bundle before System Settings reads its list.
            try? await Task.sleep(for: .milliseconds(600))
            PermissionAssistant.shared.presentAccessibilityGuide()
        }
    }
}
