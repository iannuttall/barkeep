import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    var onToggle: (() -> Void)?
    var onSearch: (() -> Void)?

    private var handler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    func start() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        register(keyCode: UInt32(kVK_ANSI_Backslash), modifiers: UInt32(cmdKey), id: 1)
        register(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), id: 2)
    }

    func stop() {
        for hotKey in hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        hotKeys.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: 0x424B4550, id: id) // BKEP
        if RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        ) == noErr, let reference {
            hotKeys.append(reference)
        }
    }

    private func handle(id: UInt32) {
        switch id {
        case 1: onToggle?()
        case 2: onSearch?()
        default: break
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard result == noErr else { return result }
        let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in center.handle(id: hotKeyID.id) }
        return noErr
    }
}
