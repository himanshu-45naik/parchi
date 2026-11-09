import AppKit
import Carbon.HIToolbox

/// Global shortcuts through Carbon, which unlike event taps needs no Accessibility permission.
final class HotKeyCenter {
    static var current: HotKeyCenter?

    var handler: ((HotKeyAction) -> Void)?
    private(set) var failed = Set<HotKeyAction>()

    private var references: [EventHotKeyRef] = []
    private var installed = false
    private static let signature: OSType = 0x5052_4348 // "PRCH"

    func register(_ combos: [String: KeyCombo]) {
        install()
        unregisterAll()
        failed.removeAll()
        for action in HotKeyAction.allCases {
            guard let combo = combos[action.rawValue] else { continue }
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: action.hotKeyID)
            let status = RegisterEventHotKey(
                combo.keyCode, combo.modifiers, identifier, GetApplicationEventTarget(), 0, &reference
            )
            if status == noErr, let reference {
                references.append(reference)
            } else {
                failed.insert(action)
            }
        }
    }

    func unregisterAll() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
    }

    private func install() {
        guard !installed else { return }
        installed = true
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
    }

    fileprivate func fire(_ identifier: UInt32) {
        guard let action = HotKeyAction.allCases.first(where: { $0.hotKeyID == identifier }) else { return }
        handler?(action)
    }
}

private nonisolated func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let value = identifier.id
    Task { @MainActor in
        HotKeyCenter.current?.fire(value)
    }
    return noErr
}

enum KeyNames {
    /// Builds a combination from a key press, or nil if it has no ⌘, ⌃ or ⌥.
    static func combo(from event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }

        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        label += name(for: event)
        return KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
    }

    private static func name(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
