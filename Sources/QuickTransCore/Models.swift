import Foundation

/// 单词卡片。字段与提示词里约定的 JSON 一一对应（snake_case），缺字段时按空处理，避免模型偶尔漏字段导致整体解析失败。
public struct WordEntry: Codable, Sendable, Equatable {
    public struct Meaning: Codable, Sendable, Equatable {
        public var pos: String
        public var zh: String
    }
    public struct HowTo: Codable, Sendable, Equatable {
        public var label: String
        public var text: String
    }
    public struct Pair: Codable, Sendable, Equatable {
        public var en: String
        public var zh: String
    }

    public var word: String
    public var syllables: String?
    public var level: String?
    public var usPhonetic: String?
    public var ukPhonetic: String?
    public var note: String?
    public var meanings: [Meaning]
    public var howto: [HowTo]
    public var memory: String?
    public var phrases: [Pair]
    public var examples: [Pair]

    /// 词典真人录音，不来自模型
    public var usAudio: URL?
    public var ukAudio: URL?

    enum CodingKeys: String, CodingKey {
        case word, syllables, level, note, meanings, howto, memory, phrases, examples
        case usPhonetic = "us_phonetic", ukPhonetic = "uk_phonetic"
        case usAudio = "us_audio", ukAudio = "uk_audio"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = (try? c.decode(String.self, forKey: .word)) ?? ""
        syllables = try? c.decodeIfPresent(String.self, forKey: .syllables)
        level = try? c.decodeIfPresent(String.self, forKey: .level)
        usPhonetic = try? c.decodeIfPresent(String.self, forKey: .usPhonetic)
        ukPhonetic = try? c.decodeIfPresent(String.self, forKey: .ukPhonetic)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        meanings = (try? c.decodeIfPresent([Meaning].self, forKey: .meanings)) ?? []
        howto = (try? c.decodeIfPresent([HowTo].self, forKey: .howto)) ?? []
        memory = try? c.decodeIfPresent(String.self, forKey: .memory)
        phrases = (try? c.decodeIfPresent([Pair].self, forKey: .phrases)) ?? []
        examples = (try? c.decodeIfPresent([Pair].self, forKey: .examples)) ?? []
        usAudio = try? c.decodeIfPresent(URL.self, forKey: .usAudio)
        ukAudio = try? c.decodeIfPresent(URL.self, forKey: .ukAudio)
        if note?.isEmpty == true { note = nil }
        if memory?.isEmpty == true { memory = nil }
    }

    /// 复制到剪贴板时的纯文本
    public var plainText: String {
        var lines = [word]
        let ph = [usPhonetic.map { "美 \($0)" }, ukPhonetic.map { "英 \($0)" }].compactMap { $0 }
        if !ph.isEmpty { lines.append(ph.joined(separator: "  ")) }
        lines += meanings.map { "\($0.pos) \($0.zh)" }
        return lines.joined(separator: "\n").replacingOccurrences(of: "*", with: "")
    }
}

/// 模型列表项。DeepSeek 的 /models 会返回支持的推理强度；OpenAI 不返回，按模型名推断。
public struct ModelInfo: Sendable, Hashable, Identifiable {
    public var id: String
    public var effortLevels: [String]
    public var defaultEffort: String?

    public init(id: String, effortLevels: [String], defaultEffort: String?) {
        self.id = id
        self.effortLevels = effortLevels
        self.defaultEffort = defaultEffort
    }
}

public struct LLMConfig: Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String
    /// nil 表示不传 reasoning_effort
    public var effort: String?

    public init(baseURL: String, apiKey: String, model: String, effort: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.effort = effort
    }
}

public enum LLMError: LocalizedError {
    case missingKey
    case http(Int, String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "还没有填写 API Key，请在设置里填写"
        case .http(401, _):
            return "API Key 无效，请在设置里检查"
        case .http(402, _):
            return "账户余额不足，请到服务商后台充值"
        case .http(429, let msg):
            return msg.contains("quota") || msg.contains("credit")
                ? "账户额度已用完，请到服务商后台充值"
                : "请求太频繁，稍后再试"
        case .http(let code, let msg):
            return "请求失败（HTTP \(code)）：\(msg)"
        case .badResponse(let msg):
            return "模型返回的内容无法解析：\(msg)"
        }
    }
}
