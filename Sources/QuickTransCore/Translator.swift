import Foundation

public struct Translator: Sendable {
    public var client: LLMClient

    public init(config: LLMConfig) {
        client = LLMClient(config: config)
    }

    /// 单词卡片：模型和词典录音并行请求，录音拿不到不影响结果
    public func lookUp(_ word: String) async throws -> WordEntry {
        async let audio = DictionaryAudio.lookup(word)
        let raw = try await client.complete(system: Prompts.word, user: word, json: true)
        var entry = try Self.decodeWord(raw)
        if entry.word.isEmpty { entry.word = word }
        // 模型可能把变形还原成原形，录音按原形查
        let (us, uk) = await (entry.word.lowercased() == word.lowercased() ? audio : DictionaryAudio.lookup(entry.word))
        entry.usAudio = us
        entry.ukAudio = uk
        return entry
    }

    public func translate(_ text: String, direction: Direction) -> AsyncThrowingStream<String, Error> {
        client.stream(system: Prompts.text(direction), user: text)
    }

    static func decodeWord(_ raw: String) throws -> WordEntry {
        // 个别模型会包一层 ```json 代码块
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: #"^```(json)?\s*|\s*```$"#, with: "", options: .regularExpression)
        }
        guard let data = s.data(using: .utf8) else { throw LLMError.badResponse("空内容") }
        do {
            return try JSONDecoder().decode(WordEntry.self, from: data)
        } catch {
            throw LLMError.badResponse(String(s.prefix(120)))
        }
    }
}
