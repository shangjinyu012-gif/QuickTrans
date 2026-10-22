import AppKit
import Combine
import SwiftUI

@MainActor
final class BallState: ObservableObject {
    @Published var active = false
    @Published var hovering = false
    @Published var pressed = false
}

/// 桌面悬浮球：34pt 透明玻璃珠。点击打开输入条，拖动后松手吸附到最近的左右边缘。
@MainActor
final class BallController {
    static let ballSize: CGFloat = 34
    /// 窗口比球大一圈，给悬停放大和阴影留空间
    static let windowSize: CGFloat = 46

    let state = BallState()
    var onClick: (() -> Void)?

    private let panel: NSPanel

    init() {
        let size = Self.windowSize
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let host = NSHostingView(rootView: BallView(state: state))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        // 透明的事件层盖在最上面，统一处理点击、拖动和悬停
        let drag = BallDragView(frame: container.bounds)
        drag.autoresizingMask = [.width, .height]
        drag.controller = self
        container.addSubview(drag)
        panel.contentView = container

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clampToScreen(animated: false) }
        }
    }

    /// 球本身（不含留白）在屏幕上的位置
    var ballFrame: NSRect {
        panel.frame.insetBy(dx: (Self.windowSize - Self.ballSize) / 2, dy: (Self.windowSize - Self.ballSize) / 2)
    }

    var screen: NSScreen? { panel.screen ?? NSScreen.main }

    func show() {
        if let saved = AppSettings.shared.ballOrigin {
            panel.setFrameOrigin(saved)
        } else if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - Self.windowSize, y: visible.maxY - 220))
        }
        clampToScreen(animated: false)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    // MARK: - 拖动

    fileprivate func move(to origin: NSPoint) {
        panel.setFrameOrigin(origin)
    }

    fileprivate var origin: NSPoint { panel.frame.origin }

    fileprivate func dragEnded() {
        clampToScreen(animated: true)
    }

    /// 吸附到所在屏幕的左边缘或右边缘，并保证不超出上下边界
    private func clampToScreen(animated: Bool) {
        let frame = panel.frame
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let inset = (Self.windowSize - Self.ballSize) / 2 - 2
        var target = frame.origin
        target.x = frame.midX < visible.midX ? visible.minX - inset : visible.maxX - Self.windowSize + inset
        target.y = min(max(frame.minY, visible.minY + 4), visible.maxY - Self.windowSize - 4)
        AppSettings.shared.ballOrigin = target
        guard target != frame.origin else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(target)
            }
        } else {
            panel.setFrameOrigin(target)
        }
    }
}

private final class BallDragView: NSView {
    weak var controller: BallController?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { controller?.state.hovering = true }
    override func mouseExited(with event: NSEvent) { controller?.state.hovering = false }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = controller?.origin ?? .zero
        moved = false
        controller?.state.pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x, dy = now.y - startMouse.y
        if !moved, abs(dx) + abs(dy) < 3 { return }
        moved = true
        controller?.move(to: NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.state.pressed = false
        if moved {
            controller?.dragEnded()
        } else {
            controller?.onClick?()
        }
    }
}

private struct BallView: View {
    @ObservedObject var state: BallState

    var body: some View {
        Image(systemName: "translate")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(state.active ? Color.white : Color.primary)
            .frame(width: BallController.ballSize, height: BallController.ballSize)
            .glassEffect(state.active ? .clear.tint(Theme.accent.opacity(0.75)) : .clear, in: Circle())
            .opacity(state.active || state.hovering ? 1 : 0.78)
            .scaleEffect(state.pressed ? 0.94 : (state.hovering ? 1.08 : 1))
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: state.hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: state.pressed)
            .animation(.easeOut(duration: 0.18), value: state.active)
            .frame(width: BallController.windowSize, height: BallController.windowSize)
    }
}
