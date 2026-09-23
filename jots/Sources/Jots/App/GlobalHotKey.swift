import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut that works from any app.
struct HotKeyShortcut: Equatable, RawRepresentable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags
    /// How the key is shown, e.g. "J" or "Space". Stored so the label doesn't depend on the
    /// keyboard layout that's active when it's displayed.
    var keyName: String

    static let standard = HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: [.control, .option], keyName: "J")

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
        self.keyName = keyName
    }

    /// A shortcut from a key press, or `nil` if it has no ⌘, ⌃, or ⌥ (a plain key would take over
    /// typing everywhere).
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let name = Self.specialKeyNames[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !name.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: name)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let keyCode = UInt32(parts[0]), let modifiers = UInt(parts[1]), !parts[2].isEmpty
        else { return nil }
        self.init(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers), keyName: String(parts[2]))
    }

    var rawValue: String { "\(keyCode);\(modifiers.rawValue);\(keyName)" }

    var label: String {
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + keyName
    }

    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Registers one system-wide shortcut with the Carbon Event Manager, which is still the only
/// public API for global hotkeys that works in the sandbox without Accessibility permission.
@MainActor
final class GlobalHotKey {
    var action: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Replaces the registered shortcut. Returns `false` if the system refused it, usually
    /// because another app already uses it.
    @discardableResult
    func register(_ shortcut: HotKeyShortcut?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let shortcut else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4A4F_5453), id: 1)  // "JOTS"
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let address = Int(bitPattern: context)
                // Carbon delivers application events on the main thread.
                MainActor.assumeIsolated {
                    guard let pointer = UnsafeRawPointer(bitPattern: address) else { return }
                    Unmanaged<GlobalHotKey>.fromOpaque(pointer).takeUnretainedValue().action()
                }
                return noErr
            }, 1, &eventType, context, &handlerRef)
    }
}
