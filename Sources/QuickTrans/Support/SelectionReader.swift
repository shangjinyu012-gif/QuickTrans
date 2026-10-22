import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 读取其它应用中选中的文字。
/// 先走辅助功能接口（不碰剪贴板）；读不到时（Electron、终端等）模拟一次 ⌘C，读完把剪贴板恢复原样。
@MainActor
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func read() async -> String? {
        if let text = axSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return await copyViaPasteboard()?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func copyViaPasteboard() async -> String? {
        let pb = NSPasteboard.general
        let saved: [NSPasteboardItem] = (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let before = pb.changeCount

        // 等用户松开快捷键里的修饰键，否则部分应用会把它当成 ⌥⌘C 之类的组合
        for _ in 0..<15 where !NSEvent.modifierFlags.intersection([.option, .control, .shift, .command]).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        postCommandC()

        for _ in 0..<20 where pb.changeCount == before {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pb.changeCount != before else { return nil }
        let text = pb.string(forType: .string)

        pb.clearContents()
        if !saved.isEmpty { pb.writeObjects(saved) }
        return text
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
