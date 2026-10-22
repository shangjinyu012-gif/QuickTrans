import Foundation

public enum InputKind: Sendable, Equatable {
    /// 单个英文单词：出词典卡片
    case word(String)
    /// 其它文本：整段翻译
    case text(String, Direction)
}

public enum Direction: Sendable, Equatable {
    case toChinese
    case toEnglish

    public var label: String {
        switch self {
        case .toChinese: return "译成中文"
        case .toEnglish: return "中译英"
        }
    }
}

public enum InputClassifier {
    /// 中文字符占非空白字符的比例超过这个值，就认为是中文
    static let chineseRatio = 0.3

    public static func classify(_ raw: String) -> InputKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let word = singleWord(text) { return .word(word) }
        return .text(text, isChinese(text) ? .toEnglish : .toChinese)
    }

    /// 划词常带上标点或首尾引号，这里先剥掉再判断
    static func singleWord(_ text: String) -> String? {
        let stripped = text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces))
        guard (1...40).contains(stripped.count),
              stripped.range(of: #"^[A-Za-z][A-Za-z'’\-]*$"#, options: .regularExpression) != nil
        else { return nil }
        return stripped
    }

    public static func isChinese(_ text: String) -> Bool {
        let chars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !chars.isEmpty else { return false }
        let han = chars.filter { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
        return Double(han.count) / Double(chars.count) > chineseRatio
    }
}
