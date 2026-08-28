import AppKit

@MainActor
final class StatusBarEngine: NSObject {
    enum State: String, Sendable {
        case hidden
        case revealed
        case revealedAll
    }

    var onPrimaryAction: ((NSEvent) -> Void)?
    var menuProvider: (() -> NSMenu)?
    private(set) var state: State = .hidden

    private let statusBar = NSStatusBar.system
    private let controlItem: NSStatusItem
    private let hiddenBoundary: NSStatusItem
    private let alwaysHiddenBoundary: NSStatusItem
    private var iconStyle: BarkeepIconStyle = .dot

    private static let openBoundaryLength: CGFloat = 14
    private static let closedBoundaryLength: CGFloat = 10_000
    private static let controlAutosaveName = "Barkeep.Control.v3"
    private static let hiddenBoundaryAutosaveName = "Barkeep.HiddenBoundary.v3"
    private static let alwaysHiddenBoundaryAutosaveName = "Barkeep.AlwaysHiddenBoundary.v3"

    override init() {
        Self.seedInitialPositions()

        controlItem = statusBar.statusItem(withLength: NSStatusItem.squareLength)
        hiddenBoundary = statusBar.statusItem(withLength: Self.openBoundaryLength)
        alwaysHiddenBoundary = statusBar.statusItem(withLength: Self.openBoundaryLength)
        super.init()

        configure(controlItem, name: Self.controlAutosaveName, label: "Barkeep")
        configure(hiddenBoundary, name: Self.hiddenBoundaryAutosaveName, label: "Hidden items boundary")
        configure(
            alwaysHiddenBoundary,
            name: Self.alwaysHiddenBoundaryAutosaveName,
            label: "Always hidden items boundary"
        )

        controlItem.button?.target = self
        controlItem.button?.action = #selector(handleControlClick(_:))
        controlItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        controlItem.button?.toolTip = "Barkeep"

        hiddenBoundary.button?.image = BarkeepIconFactory.dividerImage()
        hiddenBoundary.button?.alphaValue = 0.7
        alwaysHiddenBoundary.button?.image = BarkeepIconFactory.dividerImage()
        alwaysHiddenBoundary.button?.alphaValue = 0.5
        setState(.hidden)
    }

    private static func seedInitialPositions() {
        let defaults = UserDefaults.standard
        let positions: [(name: String, position: Double)] = [
            (controlAutosaveName, 0),
            (hiddenBoundaryAutosaveName, 1),
        ]

        for entry in positions {
            let key = "NSStatusItem Preferred Position \(entry.name)"
            if defaults.object(forKey: key) == nil {
                defaults.set(entry.position, forKey: key)
            }
        }
    }

    func setIconStyle(_ style: BarkeepIconStyle) {
        iconStyle = style
        updateControlImage()
    }

    func toggleHidden() {
        setState(state == .hidden ? .revealed : .hidden)
    }

    func toggleAll() {
        setState(state == .revealedAll ? .hidden : .revealedAll)
    }

    func revealHidden() {
        setState(.revealed)
    }

    func revealAll() {
        setState(.revealedAll)
    }

    func hide() {
        setState(.hidden)
    }

    func setState(_ newState: State) {
        state = newState
        switch newState {
        case .hidden:
            hiddenBoundary.length = Self.closedBoundaryLength
            alwaysHiddenBoundary.length = Self.openBoundaryLength
        case .revealed:
            hiddenBoundary.length = Self.closedBoundaryLength
            alwaysHiddenBoundary.length = Self.closedBoundaryLength
            hiddenBoundary.length = Self.openBoundaryLength
        case .revealedAll:
            hiddenBoundary.length = Self.closedBoundaryLength
            alwaysHiddenBoundary.length = Self.openBoundaryLength
            hiddenBoundary.length = Self.openBoundaryLength
        }
        hiddenBoundary.button?.image = newState == .hidden ? nil : BarkeepIconFactory.dividerImage()
        alwaysHiddenBoundary.button?.image = newState == .revealed ? nil : BarkeepIconFactory.dividerImage()
        updateControlImage()
    }

    func boundaryFrames() -> BoundaryFrames? {
        guard let control = controlItem.button?.window?.frame,
              let hidden = hiddenBoundary.button?.window?.frame,
              let alwaysHidden = alwaysHiddenBoundary.button?.window?.frame,
              control.width > 0,
              hidden.width > 0,
              alwaysHidden.width > 0 else {
            return nil
        }
        return BoundaryFrames(control: control, hidden: hidden, alwaysHidden: alwaysHidden)
    }

    func targetPoint(for zone: VisibilityZone) -> CGPoint? {
        boundaryFrames()?.targetPoint(for: zone)
    }

    private func configure(_ item: NSStatusItem, name: String, label: String) {
        item.autosaveName = name
        item.isVisible = true
        item.button?.setAccessibilityLabel(label)
    }

    private func updateControlImage() {
        controlItem.button?.image = BarkeepIconFactory.image(for: iconStyle, expanded: state != .hidden)
        controlItem.button?.setAccessibilityValue(state == .hidden ? "Hidden" : "Shown")
    }

    @objc private func handleControlClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            defer {
                sender.highlight(false)
                sender.state = .off
            }
            if let menu = menuProvider?() {
                NSMenu.popUpContextMenu(menu, with: event, for: sender)
            }
        } else {
            onPrimaryAction?(event)
        }
    }
}
