import Foundation

/// 从 dictionaryapi.dev 取真人发音录音。
/// 只用它的录音（文件名带 -us / -uk 后缀，能分清口音）；它的音标是维基词典的窄式标音、且不标口音，不用。
public enum DictionaryAudio {
    public static func lookup(_ word: String, session: URLSession = .shared) async -> (us: URL?, uk: URL?) {
        guard let escaped = word.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(escaped)")
        else { return (nil, nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return (nil, nil) }

        var us: URL?, uk: URL?
        for entry in entries {
            for p in entry["phonetics"] as? [[String: Any]] ?? [] {
                guard let s = p["audio"] as? String, !s.isEmpty, let u = URL(string: s) else { continue }
                if us == nil, s.hasSuffix("-us.mp3") { us = u }
                if uk == nil, s.hasSuffix("-uk.mp3") { uk = u }
            }
        }
        return (us, uk)
    }
}
