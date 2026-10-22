import AppKit
import SwiftUI

/// 原型里定下的视觉语言：墨水蓝做强调色，荧光笔黄标重点，英文用衬线体（New York），中文用系统字体。
enum Theme {
    /// 墨水蓝；深色模式下提亮
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.53, green: 0.64, blue: 1.0, alpha: 1)
            : NSColor(srgbRed: 0x34 / 255, green: 0x51 / 255, blue: 0xB2 / 255, alpha: 1)
    })

    static let marker = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
            : NSColor(srgbRed: 1.0, green: 0.87, blue: 0.29, alpha: 0.75)
    })

    static let memoryFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.78, blue: 0.2, alpha: 0.16)
            : NSColor(srgbRed: 1.0, green: 0.89, blue: 0.43, alpha: 0.38)
    })

    static let memoryLabel = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.8, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.54, green: 0.42, blue: 0, alpha: 1)
    })

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// 模型输出里的行内标记：*英文片段* 换成衬线体，**重点** 加粗或用荧光笔高亮
enum InlineMarkup {
    enum Emphasis { case bold, highlight }

    static func render(_ source: String, size: CGFloat, serifBase: Bool = false, emphasis: Emphasis = .bold) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var strong = false
        var serif = false
        let chars = Array(source)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            let useSerif = serif || serifBase
            var font: Font = useSerif ? Theme.serif(size) : .system(size: size)
            if strong {
                switch emphasis {
                case .bold:
                    font = useSerif ? Theme.serif(size, weight: .semibold) : .system(size: size, weight: .semibold)
                case .highlight:
                    run.backgroundColor = Theme.marker
                }
            }
            run.font = font
            result += run
            buffer = ""
        }

        while i < chars.count {
            if chars[i] == "*" {
                flush()
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    strong.toggle()
                    i += 2
                } else {
                    serif.toggle()
                    i += 1
                }
                continue
            }
            buffer.append(chars[i])
            i += 1
        }
        flush()
        return result
    }
}

/// macOS 27 SDK 把 `@State` 换成了宏，宏插件只随 Xcode 提供，仅装命令行工具时无法展开。
/// 底层的 State 属性包装器仍在，用别名直接引用它，效果与 `@State` 相同。
typealias ViewState<Value> = SwiftUI.State<Value>
