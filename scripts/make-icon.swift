// 生成 Resources/AppIcon.icns：墨水蓝到紫的圆角方块 + 玻璃高光 + 白色「翻译」符号
// 用法：swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS 图标网格：内容区约占 80%，留出阴影边距
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.27, blue: 0.66, alpha: 1),
                        NSColor(srgbRed: 0.35, green: 0.33, blue: 0.86, alpha: 1),
                        NSColor(srgbRed: 0.62, green: 0.42, blue: 0.92, alpha: 1)])!
        .draw(in: rect, angle: -55)
    // 顶部玻璃反光
    let sheen = NSBezierPath(ovalIn: NSRect(x: rect.minX - rect.width * 0.2, y: rect.midY + rect.height * 0.05,
                                            width: rect.width * 1.4, height: rect.height * 0.9))
    NSGradient(starting: NSColor.white.withAlphaComponent(0.32), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: sheen, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 边缘高光
    NSColor.white.withAlphaComponent(0.45).setStroke()
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.008)
    rim.stroke()

    // 白色符号
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "translate", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let sz = symbol.size
        symbol.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "已生成 Resources/AppIcon.icns" : "iconutil 失败")
