import AVFoundation
import Combine

/// 发音：有词典真人录音就播录音，否则用系统 en-US / en-GB 语音
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var playing: Accent?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, accent: Accent, audio: URL?) {
        stop()
        playing = accent
        guard let audio else {
            synthesize(text, accent: accent)
            return
        }
        let item = AVPlayerItem(url: audio)
        let player = AVPlayer(playerItem: item)
        self.player = player
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = nil }
        }
        // 录音加载失败（断网等）时退回系统语音
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { self?.synthesize(text, accent: accent) }
        }
        player.play()
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObserver = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        playing = nil
    }

    private func synthesize(_ text: String, accent: Accent) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: accent.language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        playing = accent
        synthesizer.speak(utterance)
    }

    private static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playing = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synthesizer.isSpeaking { self.playing = nil } }
    }
}
