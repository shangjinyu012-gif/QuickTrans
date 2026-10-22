import AppKit
import SwiftUI

/// 无边框、可以成为 key window 但不激活整个 App 的面板（和 Spotlight 一样，不抢走前台应用）
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    /// 面板相对什么定位：贴着悬浮球的左侧 / 右侧，或某个点（划词时的鼠标位置）
    private enum Anchor {
        case leftOf(x: CGFloat, top: CGFloat)
        case rightOf(x: CGFloat, top: CGFloat)
        case below(point: NSPoint)
        case centered(top: CGFloat)
    }

    let model = PanelModel()
    var onClose: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let panel: KeyPanel
    private var anchor: Anchor = .centered(top: 0)
    private var screen: NSScreen?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 34),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        let root = TranslatorView(
            model: model,
            onSize: { [weak self] size in self?.layout(size) },
            onClose: { [weak self] in self?.close() },
            onOpenSettings: { [weak self] in
                self?.close()
                self?.onOpenSettings?()
            }
        )
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
    }

    // MARK: - 打开

    /// 悬浮球入口：胶囊输入条与球顶部对齐，从球朝屏幕内侧伸出
    func showFromBall(ballFrame: NSRect, screen: NSScreen?) {
        model.reset()
        model.source = .input
        self.screen = screen
        anchorToBall(ballFrame)
        present(focus: true)
    }

    /// 悬浮球移动时调用：面板跟着球走，球过了屏幕中线就换到另一侧
    func followBall(_ ballFrame: NSRect) {
        guard panel.isVisible else { return }
        switch anchor {
        case .leftOf, .rightOf: break
        default: return
        }
        let center = NSPoint(x: ballFrame.midX, y: ballFrame.midY)
        screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) } ?? screen
        anchorToBall(ballFrame)
        layout(panel.frame.size)
    }

    private func anchorToBall(_ ballFrame: NSRect) {
        let gap: CGFloat = 6
        let onRightHalf = ballFrame.midX > (screen?.visibleFrame.midX ?? 0)
        anchor = onRightHalf
            ? .leftOf(x: ballFrame.minX - gap, top: ballFrame.maxY)
            : .rightOf(x: ballFrame.maxX + gap, top: ballFrame.maxY)
    }

    /// 没有悬浮球时用快捷键呼出：屏幕上方居中，类似 Spotlight
    func showCentered() {
        model.reset()
        model.source = .input
        screen = NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        anchor = .centered(top: frame.maxY - frame.height * 0.22)
        present(focus: true)
    }

    func showSelection(_ text: String) {
        model.reset()
        model.source = .selection
        model.quote = text
        placeNearMouse()
        present(focus: false)
        model.submit(text)
    }

    func showPermissionHint() {
        model.reset()
        model.source = .selection
        model.phase = .needsPermission
        placeNearMouse()
        present(focus: false)
    }

    func showMessage(_ message: String) {
        model.reset()
        model.source = .selection
        model.phase = .error(message, openSettings: false)
        placeNearMouse()
        present(focus: false)
    }

    func showHistory(_ item: HistoryItem) {
        model.show(item)
        screen = NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        anchor = .centered(top: frame.maxY - frame.height * 0.18)
        present(focus: false)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.reset()
        model.pinned = false
        removeMonitors()
        onClose?()
    }

    // MARK: - 布局

    private func placeNearMouse() {
        let mouse = NSEvent.mouseLocation
        screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        anchor = .below(point: mouse)
    }

    private func present(focus: Bool) {
        layout(model.isCompact ? CGSize(width: 280, height: 34) : CGSize(width: 380, height: 120))
        if focus {
            panel.makeKeyAndOrderFront(nil)
            model.focusToken += 1
        } else {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
        installMonitors()
    }

    /// SwiftUI 内容尺寸变化时回调。固定住锚定的那条边和顶部，只向下 / 向外伸展。
    private func layout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = NSRect(origin: .zero, size: size)

        switch anchor {
        case .leftOf(let x, let top):
            frame.origin = NSPoint(x: x - size.width, y: top - size.height)
        case .rightOf(let x, let top):
            frame.origin = NSPoint(x: x, y: top - size.height)
        case .centered(let top):
            frame.origin = NSPoint(x: visible.midX - size.width / 2, y: top - size.height)
        case .below(let p):
            frame.origin = NSPoint(x: p.x - 24, y: p.y - 16 - size.height)
            // 鼠标下方放不下就放到上方
            if frame.minY < visible.minY + 8 { frame.origin.y = p.y + 16 }
        }

        frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - size.width - 8)
        frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    // MARK: - 关闭时机：点击面板外部、按 Esc

    private func installMonitors() {
        removeMonitors()
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.pinned else { return }
                self.close()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        mouseMonitor = nil
        keyMonitor = nil
    }
}
