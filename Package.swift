// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickTrans",
    platforms: [.macOS("26.0")],
    targets: [
        // 纯逻辑：模型请求、提示词、语言判断、词典发音
        .target(name: "QuickTransCore"),
        // 菜单栏 App
        .executableTarget(name: "QuickTrans", dependencies: ["QuickTransCore"]),
        // 命令行调试工具：不开 GUI 验证请求与解析
        .executableTarget(name: "qtcli", dependencies: ["QuickTransCore"]),
    ],
    swiftLanguageModes: [.v5]
)
