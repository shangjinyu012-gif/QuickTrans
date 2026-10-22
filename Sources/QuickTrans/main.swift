import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // 只有菜单栏图标，不占 Dock
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
