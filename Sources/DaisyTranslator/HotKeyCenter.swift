import Carbon.HIToolbox
import Foundation
import LeafiyUICore

final class HotKeyCenter {
    enum HotKey: UInt32 {
        case quickTranslateSelection = 2
        case toggleAlwaysOnTop = 3
    }

    var onHotKey: ((HotKey) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerUPP: EventHandlerUPP?

    func register(quickTranslateEnabled: Bool, quickTranslateShortcut: String) {
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

        register(keyCode: UInt32(kVK_ANSI_O), modifiers: cmdKey | shiftKey, id: .toggleAlwaysOnTop)
        if quickTranslateEnabled, let shortcut = Self.parseShortcut(quickTranslateShortcut) {
            register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, id: .quickTranslateSelection)
        }
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

    static func isShortcutSupported(_ shortcut: String) -> Bool {
        parseShortcut(shortcut) != nil
    }

    private func register(keyCode: UInt32, modifiers: Int, id: HotKey) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("TTTR"), id: id.rawValue)
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

    private static func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: Int)? {
        guard let spec = KeyboardShortcutSpec(parsing: shortcut),
              let keyCode = keyCode(for: spec.key.lowercased()) else {
            return nil
        }
        return (UInt32(keyCode), modifierFlags(for: spec))
    }

    private static func modifierFlags(for spec: KeyboardShortcutSpec) -> Int {
        modifierFlag(for: spec.first) | modifierFlag(for: spec.second)
    }

    private static func modifierFlag(for modifier: KeyboardShortcutSpec.Modifier) -> Int {
        switch modifier {
        case .command:
            return cmdKey
        case .shift:
            return shiftKey
        case .option:
            return optionKey
        case .control:
            return controlKey
        }
    }

    private static func keyCode(for token: String) -> Int? {
        let letters: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9
        ]
        return letters[token]
    }

    deinit {
        unregister()
    }
}
