import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// NSEvent.ModifierFlags 的 rawValue，只保留 ⌘⌥⌃⇧
    var modifiers: UInt
    var key: String

    static let defaultTranslate = Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: NSEvent.ModifierFlags.option.rawValue, key: "D")
    static let defaultInput = Shortcut(keyCode: UInt32(kVK_Space), modifiers: NSEvent.ModifierFlags.option.rawValue, key: "Space")

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
        key = Self.keyName(event)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + " " + key
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    private static func keyName(_ e: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(e.keyCode)] { return name }
        return (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// 基于 Carbon RegisterEventHotKey 的全局快捷键。不需要辅助功能权限。
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        var shortcut: Shortcut
        var handler: () -> Void
        var ref: EventHotKeyRef?
    }
    private var registrations: [UInt32: Registration] = [:]

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// 返回 false 表示该组合已被其它程序占用
    @discardableResult
    func register(id: UInt32, shortcut: Shortcut, handler: @escaping () -> Void) -> Bool {
        unregister(id: id)
        var reg = Registration(shortcut: shortcut, handler: handler, ref: nil)
        let ok = attach(id: id, &reg)
        registrations[id] = reg
        return ok
    }

    func unregister(id: UInt32) {
        if let ref = registrations.removeValue(forKey: id)?.ref { UnregisterEventHotKey(ref) }
    }

    /// 录制新快捷键期间暂时让出按键，否则按下已注册的组合会被这里吃掉
    func pauseAll() {
        for (id, reg) in registrations {
            if let ref = reg.ref { UnregisterEventHotKey(ref) }
            registrations[id]?.ref = nil
        }
    }

    func resumeAll() {
        for id in registrations.keys {
            guard var reg = registrations[id], reg.ref == nil else { continue }
            attach(id: id, &reg)
            registrations[id] = reg
        }
    }

    @discardableResult
    private func attach(id: UInt32, _ reg: inout Registration) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(reg.shortcut.keyCode, reg.shortcut.carbonModifiers,
                                         EventHotKeyID(signature: OSType(0x5154_4B59), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        reg.ref = status == noErr ? ref : nil
        return status == noErr
    }

    private func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }
}
