import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class PermissionAssistant {
    static let shared = PermissionAssistant()
    static let accessibilityChanged = Notification.Name("BarkeepAccessibilityChanged")

    private var panel: NSPanel?
    private var timer: Timer?
    private var keepsGuideVisible = false

    func presentAccessibilityGuide(keepVisibleForTesting: Bool = false) {
        close()
        keepsGuideVisible = keepVisibleForTesting
        openAccessibilitySettings()

        let guide = AccessibilityGuideView(
            appName: "Barkeep",
            appURL: Bundle.main.bundleURL,
            icon: NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path),
            dismiss: { [weak self] in self?.close() }
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 146),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: guide)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel

        positionPanel()
        panel.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AccessibilityPermission.isGranted && !self.keepsGuideVisible {
                    self.close()
                    NotificationCenter.default.post(name: Self.accessibilityChanged, object: nil)
                } else {
                    self.positionPanel()
                }
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        keepsGuideVisible = false
    }

    private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let settingsFrame = systemSettingsWindowFrame()
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let host = settingsFrame ?? visible.insetBy(dx: 80, dy: 70)
        let contentLeft = host.minX + min(220, host.width * 0.32)
        let availableWidth = max(340, host.maxX - contentLeft - 18)
        let width = min(680, availableWidth)
        let x = max(visible.minX + 8, host.maxX - width - 10)
        // Keep the Add and Remove buttons at the bottom of System Settings visible.
        let y = max(visible.minY + 8, host.minY + 64)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: 146), display: true)
    }

    private func systemSettingsWindowFrame() -> CGRect? {
        guard let settingsPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences"
        ).first?.processIdentifier,
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else {
            return nil
        }

        let candidates = windows.compactMap { window -> CGRect? in
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == settingsPID,
                  (window[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds] as? NSDictionary,
                  let cgFrame = CGRect(dictionaryRepresentation: bounds),
                  cgFrame.width > 320,
                  cgFrame.height > 240 else {
                return nil
            }
            return appKitFrame(fromCGFrame: cgFrame)
        }
        return candidates.max { $0.width * $0.height < $1.width * $1.height }
    }

    private func appKitFrame(fromCGFrame frame: CGRect) -> CGRect {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            if displayFrame.intersects(frame) {
                return CGRect(
                    x: screen.frame.minX + frame.minX - displayFrame.minX,
                    y: screen.frame.maxY - (frame.minY - displayFrame.minY) - frame.height,
                    width: frame.width,
                    height: frame.height
                )
            }
        }
        let top = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }
}

private struct AccessibilityGuideView: View {
    let appName: String
    let appURL: URL
    let icon: NSImage
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.up.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Accessibility").font(.headline)
                    Text("Turn on Barkeep in the list above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close guide")
            }

            AppPermissionDragSource(appName: appName, appURL: appURL, icon: icon)
                .frame(height: 44)

            Text("If Barkeep is missing, select + below. You can also drag this app tile into the list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
    }
}

private struct AppPermissionDragSource: NSViewRepresentable {
    let appName: String
    let appURL: URL
    let icon: NSImage

    func makeNSView(context: Context) -> PermissionDragView {
        PermissionDragView(appName: appName, appURL: appURL, icon: icon)
    }

    func updateNSView(_ nsView: PermissionDragView, context: Context) {}
}

private final class PermissionDragView: NSView, NSDraggingSource, NSPasteboardItemDataProvider {
    private let appURL: URL
    private let iconView: NSImageView
    private let nameLabel: NSTextField
    private let hintLabel: NSTextField

    init(appName: String, appURL: URL, icon: NSImage) {
        self.appURL = appURL
        iconView = NSImageView(image: icon)
        nameLabel = NSTextField(labelWithString: appName)
        hintLabel = NSTextField(labelWithString: "Drag into Accessibility")
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        for view in [iconView, nameLabel, hintLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            hintLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            hintLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(self, forTypes: [.fileURL])
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(
            NSRect(x: event.locationInWindow.x - 24, y: event.locationInWindow.y - 24, width: 48, height: 48),
            contents: NSWorkspace.shared.icon(forFile: appURL.path)
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func pasteboard(
        _ pasteboard: NSPasteboard?,
        item: NSPasteboardItem,
        provideDataForType type: NSPasteboard.PasteboardType
    ) {
        guard type == .fileURL else { return }
        item.setData((appURL as NSURL).dataRepresentation, forType: type)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
