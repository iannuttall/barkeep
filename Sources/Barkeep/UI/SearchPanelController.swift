import AppKit
import SwiftUI

@MainActor
final class SearchPanelController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(coordinator: AppCoordinator) {
        let rootView = SearchPanelView(coordinator: coordinator)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Find a menu bar item"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: rootView)
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        if let screen = NSScreen.main, let window {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: frame.maxX - window.frame.width - 18,
                y: frame.maxY - window.frame.height - 18
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
