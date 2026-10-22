import AppKit
import Combine
import QuickTransCore
import ServiceManagement

enum Provider: String, CaseIterable, Identifiable {
    case deepseek, openai, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .openai: return "OpenAI"
        case .custom: return "自定义（兼容 OpenAI 接口）"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .openai: return "gpt-5.4-mini"
        case .custom: return ""
        }
    }

    /// 拉不到模型列表时的推理强度候选
    func fallbackEffortLevels(for model: String) -> [String] {
        switch self {
        case .deepseek: return ["low", "high", "max"]
        case .openai, .custom: return LLMClient.guessEffortLevels(model)
        }
    }
}

enum Accent: String, CaseIterable, Identifiable {
    case us, uk
    var id: String { rawValue }
    var title: String { self == .us ? "美式" : "英式" }
    var short: String { self == .us ? "美" : "英" }
    var language: String { self == .us ? "en-US" : "en-GB" }
}

/// 所有设置。普通项存 UserDefaults，API Key 存本机文件（见 SecretStore）；服务地址、模型、推理强度按服务商分别保存，切换服务商时互不覆盖。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard
    private var loading = false

    @Published var provider: Provider {
        didSet {
            guard !loading, provider != oldValue else { return }
            defaults.set(provider.rawValue, forKey: "provider")
            loadProviderScoped()
        }
    }
    @Published var baseURL: String = "" { didSet { saveScoped("baseURL", baseURL) } }
    @Published var model: String = "" { didSet { saveScoped("model", model) } }
    /// 空字符串表示不传 reasoning_effort，由服务端用默认值
    @Published var effort: String = "" { didSet { saveScoped("effort", effort) } }
    @Published var apiKey: String = "" {
        didSet { if !loading { SecretStore.set(apiKey, account: "apiKey.\(provider.rawValue)") } }
    }

    @Published var translateHotkey: Shortcut { didSet { save(translateHotkey, "translateHotkey") } }
    @Published var inputHotkey: Shortcut { didSet { save(inputHotkey, "inputHotkey") } }
    @Published var showBall: Bool { didSet { defaults.set(showBall, forKey: "showBall") } }
    @Published var autoSpeak: Bool { didSet { defaults.set(autoSpeak, forKey: "autoSpeak") } }
    @Published var defaultAccent: Accent { didSet { defaults.set(defaultAccent.rawValue, forKey: "defaultAccent") } }

    var ballOrigin: NSPoint? {
        get {
            guard let a = defaults.array(forKey: "ballOrigin") as? [Double], a.count == 2 else { return nil }
            return NSPoint(x: a[0], y: a[1])
        }
        set { defaults.set(newValue.map { [$0.x, $0.y] }, forKey: "ballOrigin") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    var llmConfig: LLMConfig {
        LLMConfig(baseURL: baseURL, apiKey: apiKey, model: model, effort: effort.isEmpty ? nil : effort)
    }

    private init() {
        provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .deepseek
        translateHotkey = Self.load("translateHotkey") ?? .defaultTranslate
        inputHotkey = Self.load("inputHotkey") ?? .defaultInput
        showBall = defaults.object(forKey: "showBall") as? Bool ?? true
        autoSpeak = defaults.bool(forKey: "autoSpeak")
        defaultAccent = Accent(rawValue: defaults.string(forKey: "defaultAccent") ?? "") ?? .us
        loadProviderScoped()
    }

    private func loadProviderScoped() {
        loading = true
        defer { loading = false }
        let p = provider.rawValue
        baseURL = defaults.string(forKey: "baseURL.\(p)") ?? provider.defaultBaseURL
        model = defaults.string(forKey: "model.\(p)") ?? provider.defaultModel
        effort = defaults.string(forKey: "effort.\(p)") ?? (provider == .deepseek ? "low" : "")
        apiKey = SecretStore.get(account: "apiKey.\(p)") ?? ""
    }

    private func saveScoped(_ key: String, _ value: String) {
        guard !loading else { return }
        defaults.set(value, forKey: "\(key).\(provider.rawValue)")
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
