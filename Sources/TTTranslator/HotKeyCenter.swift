import Carbon.HIToolbox
import Foundation

final class HotKeyCenter {
    enum HotKey: UInt32 {
        case translateClipboard = 1
        case pasteResult = 2
        case toggleAlwaysOnTop = 3
    }

    var onHotKey: ((HotKey) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerUPP: EventHandlerUPP?

    func register() {
        unregister()

        handlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            if let hotKey = HotKey(rawValue: hotKeyID.id) {
                DispatchQueue.main.async {
                    center.onHotKey?(hotKey)
                }
            }
            return noErr
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )

        register(keyCode: UInt32(kVK_ANSI_T), modifiers: cmdKey | shiftKey, id: .translateClipboard)
        register(keyCode: UInt32(kVK_ANSI_V), modifiers: cmdKey | shiftKey, id: .pasteResult)
        register(keyCode: UInt32(kVK_ANSI_O), modifiers: cmdKey | shiftKey, id: .toggleAlwaysOnTop)
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handlerUPP = nil
    }

    private func register(keyCode: UInt32, modifiers: Int, id: HotKey) {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: fourCharacterCode("TTTR"), id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        }
    }

    private func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }

    deinit {
        unregister()
    }
}
