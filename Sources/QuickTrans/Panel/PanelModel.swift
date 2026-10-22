import AppKit
import Combine
import QuickTransCore

/// 翻译面板的状态。悬浮球输入和划词共用一份。
@MainActor
final class PanelModel: ObservableObject {
    enum Source { case input, selection }

    enum Phase: Equatable {
        case idle
        case loading
        case word(WordEntry)
        case text(String, done: Bool, direction: Direction)
        case error(String, openSettings: Bool)
        case needsPermission
    }

    @Published var source: Source = .input
    @Published var input = ""
    @Published var quote = ""
    @Published var phase: Phase = .idle
    @Published var pinned = false
    @Published var metaKind = ""
    @Published var metaElapsed: Double?
    @Published var metaCached = false
    /// 每次打开输入框时 +1，用来让输入框重新获得焦点
    @Published var focusToken = 0

    private(set) var lastText = ""
    private var task: Task<Void, Never>?

    /// 胶囊态：悬浮球入口、还没出结果
    var isCompact: Bool { source == .input && phase == .idle }

    func reset() {
        task?.cancel()
        Speaker.shared.stop()
        phase = .idle
        input = ""
        quote = ""
        metaKind = ""
        metaElapsed = nil
        metaCached = false
    }

    func submit(_ raw: String, useCache: Bool = true) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastText = text
        task?.cancel()
        Speaker.shared.stop()
        metaElapsed = nil
        metaCached = false

        let settings = AppSettings.shared
        guard !settings.apiKey.isEmpty else {
            phase = .error(LLMError.missingKey.localizedDescription, openSettings: true)
            return
        }
        let translator = Translator(config: settings.llmConfig)
        let start = Date()

        switch InputClassifier.classify(text) {
        case .word(let word):
            metaKind = "单词"
            if useCache, let cached = HistoryStore.shared.cachedWord(word) {
                show(cached, cached: true)
                return
            }
            phase = .loading
            task = Task {
                do {
                    let entry = try await translator.lookUp(word)
                    guard !Task.isCancelled else { return }
                    metaElapsed = Date().timeIntervalSince(start)
                    show(entry, cached: false)
                    HistoryStore.shared.add(HistoryItem(input: word, word: entry))
                } catch {
                    fail(error)
                }
            }

        case .text(let body, let direction):
            metaKind = direction.label
            if useCache, let cached = HistoryStore.shared.cachedTranslation(body) {
                metaCached = true
                phase = .text(cached, done: true, direction: direction)
                return
            }
            phase = .loading
            task = Task {
                var output = ""
                do {
                    for try await piece in translator.translate(body, direction: direction) {
                        guard !Task.isCancelled else { return }
                        output += piece
                        phase = .text(output, done: false, direction: direction)
                    }
                    guard !Task.isCancelled else { return }
                    metaElapsed = Date().timeIntervalSince(start)
                    phase = .text(output, done: true, direction: direction)
                    if !output.isEmpty { HistoryStore.shared.add(HistoryItem(input: body, translation: output)) }
                } catch {
                    fail(error)
                }
            }
        }
    }

    func show(_ item: HistoryItem) {
        reset()
        source = .selection
        quote = item.input
        lastText = item.input
        metaCached = true
        if let word = item.word {
            metaKind = "单词"
            phase = .word(word)
        } else if let translation = item.translation {
            let direction: Direction = InputClassifier.isChinese(item.input) ? .toEnglish : .toChinese
            metaKind = direction.label
            phase = .text(translation, done: true, direction: direction)
        }
    }

    func retry() { submit(lastText, useCache: false) }

    func copyResult() {
        let text: String
        switch phase {
        case .word(let entry): text = entry.plainText
        case .text(let s, _, _): text = s
        default: return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func show(_ entry: WordEntry, cached: Bool) {
        metaCached = cached
        phase = .word(entry)
        let settings = AppSettings.shared
        if settings.autoSpeak {
            let accent = settings.defaultAccent
            Speaker.shared.speak(entry.word, accent: accent, audio: accent == .us ? entry.usAudio : entry.ukAudio)
        }
    }

    private func fail(_ error: Error) {
        guard !Task.isCancelled, !(error is CancellationError) else { return }
        if (error as? URLError)?.code == .cancelled { return }
        var openSettings = false
        if case .missingKey = error as? LLMError { openSettings = true }
        if case .http(let code, _) = error as? LLMError, code == 401 || code == 404 { openSettings = true }
        phase = .error(error.localizedDescription, openSettings: openSettings)
    }
}
