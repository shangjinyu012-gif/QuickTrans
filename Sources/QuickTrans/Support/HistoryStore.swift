import Combine
import Foundation
import QuickTransCore

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var input: String
    var date = Date()
    var word: WordEntry?
    var translation: String?

    var summary: String {
        if let word { return word.meanings.map(\.zh).joined(separator: "；") }
        return translation ?? ""
    }
}

/// 最近 500 条查询，存在 ~/Library/Application Support/QuickTrans/history.json。
/// 同时充当缓存：同一个词、同一段话再查时直接用历史结果，点「重新翻译」才会重新请求。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let limit = 500

    @Published private(set) var items: [HistoryItem] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = saved
        }
    }

    func add(_ item: HistoryItem) {
        items.removeAll { $0.input.caseInsensitiveCompare(item.input) == .orderedSame }
        items.insert(item, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        save()
    }

    func remove(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func cachedWord(_ word: String) -> WordEntry? {
        items.first { $0.word != nil && $0.input.caseInsensitiveCompare(word) == .orderedSame }?.word
    }

    func cachedTranslation(_ text: String) -> String? {
        items.first { $0.translation != nil && $0.input == text }?.translation
    }

    private func save() {
        let snapshot = items
        let url = fileURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}
