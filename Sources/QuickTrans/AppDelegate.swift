import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum HotKeyID: UInt32 { case translate = 1, input = 2 }

    private let settings = AppSettings.shared
    private let panel = PanelController()
    private let ball = BallController()
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        setUpStatusItem()

        ball.onClick = { [weak self] in self?.toggleFromBall() }
        panel.onClose = { [weak self] in self?.ball.state.active = false }
        panel.onOpenSettings = { [weak self] in self?.openSettings() }

        settings.$showBall.removeDuplicates().sink { [weak self] show in
            show ? self?.ball.show() : self?.ball.hide()
        }.store(in: &cancellables)
        settings.$translateHotkey.removeDuplicates().sink { [weak self] s in
            HotKeyCenter.shared.register(id: HotKeyID.translate.rawValue, shortcut: s) { self?.translateSelection() }
        }.store(in: &cancellables)
        settings.$inputHotkey.removeDuplicates().sink { [weak self] s in
            HotKeyCenter.shared.register(id: HotKeyID.input.rawValue, shortcut: s) { self?.openInput() }
        }.store(in: &cancellables)

        if settings.apiKey.isEmpty { openSettings() }
        runDemoIfRequested()
    }

    /// 调试用：QT_DEMO=input | text:<内容> | settings，启动后直接打开对应界面，方便截图检查
    private func runDemoIfRequested() {
        guard let demo = ProcessInfo.processInfo.environment["QT_DEMO"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if demo == "input" {
                toggleFromBall()
            } else if demo == "settings" {
                openSettings()
            } else if demo.hasPrefix("text:") {
                panel.showSelection(String(demo.dropFirst(5)))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: - 入口

    private func toggleFromBall() {
        if panel.isVisible, panel.model.source == .input {
            panel.close()
            return
        }
        ball.state.active = true
        panel.showFromBall(ballFrame: ball.ballFrame, screen: ball.screen)
    }

    @objc private func openInput() {
        if panel.isVisible, panel.model.source == .input {
            panel.close()
        } else if settings.showBall {
            toggleFromBall()
        } else {
            panel.showCentered()
        }
    }

    @objc private func translateSelection() {
        Task { @MainActor in
            guard SelectionReader.isTrusted else {
                SelectionReader.requestTrust()
                panel.showPermissionHint()
                return
            }
            guard let text = await SelectionReader.read(), !text.isEmpty else {
                panel.showMessage("没有读到选中的文字。先选中一段文字，再按快捷键。")
                return
            }
            panel.showSelection(text)
        }
    }

    @objc private func toggleBall() {
        settings.showBall.toggle()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "QuickTrans 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 680, height: 480))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKey()
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let view = HistoryView { [weak self] item in self?.panel.showHistory(item) }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "历史记录"
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 460, height: 560))
            window.isReleasedWhenClosed = false
            window.center()
            historyWindow = window
        }
        NSApp.activate()
        historyWindow?.orderFrontRegardless()
        historyWindow?.makeKey()
    }

    // MARK: - 菜单栏图标

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "QuickTrans")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("打开输入框", #selector(openInput), shortcut: settings.inputHotkey))
        menu.addItem(item("翻译选中文本", #selector(translateSelection), shortcut: settings.translateHotkey))
        menu.addItem(.separator())
        menu.addItem(item(settings.showBall ? "隐藏悬浮球" : "显示悬浮球", #selector(toggleBall)))
        menu.addItem(item("历史记录…", #selector(openHistory)))
        let prefs = item("设置…", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 QuickTrans", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, shortcut: Shortcut? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let shortcut, shortcut.key.count == 1 {
            item.keyEquivalent = shortcut.key.lowercased()
            item.keyEquivalentModifierMask = shortcut.flags
        } else if let shortcut {
            // 菜单的快捷键提示不支持 Space 之类的键名，放进标题里
            item.title = "\(title)    \(shortcut.display)"
        }
        return item
    }

    /// 菜单栏应用默认没有主菜单，这样文本框里的 ⌘C / ⌘V / ⌘A 不会生效，所以补一个
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "退出 QuickTrans", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
