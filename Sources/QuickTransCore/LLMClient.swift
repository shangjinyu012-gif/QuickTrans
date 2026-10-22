import Foundation

/// OpenAI 兼容的 Chat Completions 客户端，DeepSeek、OpenAI 和其它兼容服务共用。
public struct LLMClient: Sendable {
    public var config: LLMConfig
    var session: URLSession

    public init(config: LLMConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - 请求

    /// 非流式请求，返回完整文本
    public func complete(system: String, user: String, json: Bool) async throws -> String {
        let request = try makeChatRequest(system: system, user: user, json: json, stream: false)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw LLMError.badResponse(String(data: data, encoding: .utf8)?.prefix(200).description ?? "") }
        return content
    }

    /// 流式请求，逐段返回增量文本（忽略推理过程 reasoning_content）
    public func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(system: system, user: user, json: false, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = Data()
                        for try await b in bytes { body.append(b) }
                        try Self.check(response, data: body)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let piece = delta["content"] as? String, !piece.isEmpty
                        else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - 模型列表与余额

    public func listModels() async throws -> [ModelInfo] {
        var request = URLRequest(url: try endpoint("models"))
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data: data)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]]
        else { throw LLMError.badResponse("模型列表格式不对") }

        return list.compactMap { item -> ModelInfo? in
            guard let id = item["id"] as? String else { return nil }
            if let effort = item["effort"] as? [String: Any], let levels = effort["supported_levels"] as? [String] {
                return ModelInfo(id: id, effortLevels: levels, defaultEffort: effort["default_level"] as? String)
            }
            let levels = Self.guessEffortLevels(id)
            return ModelInfo(id: id, effortLevels: levels, defaultEffort: levels.isEmpty ? nil : "low")
        }
        .filter { Self.isChatModel($0.id) }
        .sorted { $0.id < $1.id }
    }

    /// DeepSeek 专有的余额接口；其它服务返回 nil
    public func balance() async -> String? {
        guard config.baseURL.contains("deepseek"), let url = try? endpoint("user/balance") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        guard let (data, _) = try? await session.data(for: request),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = obj["balance_infos"] as? [[String: Any]], let first = infos.first,
              let total = first["total_balance"] as? String
        else { return nil }
        let symbol = (first["currency"] as? String) == "CNY" ? "¥" : "$"
        return "\(symbol)\(total)"
    }

    // MARK: - 内部

    func makeChatRequest(system: String, user: String, json: Bool, stream: Bool) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw LLMError.missingKey }
        var body: [String: Any] = [
            "model": config.model,
            "stream": stream,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if let effort = config.effort { body["reasoning_effort"] = effort }
        if json { body["response_format"] = ["type": "json_object"] }

        var request = URLRequest(url: try endpoint("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90
        return request
    }

    func endpoint(_ path: String) throws -> URL {
        var base = config.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/\(path)"), url.scheme?.hasPrefix("http") == true else {
            throw LLMError.badResponse("接口地址不合法：\(config.baseURL)")
        }
        return url
    }

    static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let m = err["message"] as? String {
                message = m
            }
            throw LLMError.http(http.statusCode, message)
        }
    }

    /// OpenAI 的推理模型（o 系列、gpt-5 系列）支持 reasoning_effort，其它不支持
    public static func guessEffortLevels(_ id: String) -> [String] {
        if id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") { return ["low", "medium", "high"] }
        if id.hasPrefix("gpt-5"), !id.contains("chat") { return ["minimal", "low", "medium", "high"] }
        return []
    }

    /// 过滤掉语音、图像、向量等非对话模型
    static func isChatModel(_ id: String) -> Bool {
        let excluded = ["tts", "transcribe", "whisper", "audio", "realtime", "image", "embedding",
                        "moderation", "dall-e", "search", "davinci", "babbage", "instruct", "live", "codex"]
        return !excluded.contains { id.contains($0) }
    }
}
