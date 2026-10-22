import QuickTransCore
import SwiftUI

struct WordCardView: View {
    let entry: WordEntry
    @ObservedObject private var speaker = Speaker.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let note = entry.note {
                Text(InlineMarkup.render(note, size: 12))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)
            }
            phonetics.padding(.top, 6)
            meanings.padding(.top, 12)

            if !entry.howto.isEmpty {
                section("怎么用")
                howto
            }
            if let memory = entry.memory {
                memoryNote(memory).padding(.top, 14)
            }
            if !entry.phrases.isEmpty {
                section("常用搭配")
                phrases
            }
            if !entry.examples.isEmpty {
                section("例句")
                examples
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 词头：衬线体 + 词典式音节分隔点，整张卡片唯一的视觉重点
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(headword)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let level = entry.level, !level.isEmpty {
                Text(level)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
            }
        }
    }

    private var headword: AttributedString {
        let parts = (entry.syllables?.isEmpty == false ? entry.syllables! : entry.word).components(separatedBy: "·")
        var s = AttributedString()
        for (i, part) in parts.enumerated() {
            if i > 0 {
                var dot = AttributedString("·")
                dot.font = Theme.serif(27)
                dot.foregroundColor = .secondary.opacity(0.45)
                s += dot
            }
            var run = AttributedString(part)
            run.font = Theme.serif(27, weight: .semibold)
            s += run
        }
        return s
    }

    private var phonetics: some View {
        HStack(spacing: 16) {
            phonetic(.us, entry.usPhonetic, audio: entry.usAudio)
            phonetic(.uk, entry.ukPhonetic, audio: entry.ukAudio)
        }
    }

    private func phonetic(_ accent: Accent, _ text: String?, audio: URL?) -> some View {
        HStack(spacing: 5) {
            Text(accent.short).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(text ?? "—").font(Theme.serif(14))
            Button {
                if speaker.playing == accent { speaker.stop() } else { speaker.speak(entry.word, accent: accent, audio: audio) }
            } label: {
                Image(systemName: speaker.playing == accent ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: speaker.playing == accent)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(speaker.playing == accent ? Color.white : Theme.accent)
                    .background(Circle().fill(speaker.playing == accent ? Theme.accent : Theme.accent.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(audio == nil ? "\(accent.title)发音（系统语音）" : "\(accent.title)发音（真人录音）")
        }
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, m in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.pos).font(Theme.serif(13.5).italic()).foregroundStyle(Theme.accent)
                        .frame(minWidth: 22, alignment: .leading)
                    Text(InlineMarkup.render(m.zh, size: 13.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var howto: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(Array(entry.howto.enumerated()), id: \.offset) { _, h in
                GridRow {
                    Text(h.label).font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 1)
                    Text(InlineMarkup.render(h.text, size: 12.8)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func memoryNote(_ text: String) -> some View {
        var label = AttributedString("记法  ")
        label.font = .system(size: 12.8, weight: .semibold)
        label.foregroundColor = Theme.memoryLabel
        return Text(label + InlineMarkup.render(text, size: 12.8, emphasis: .highlight))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.memoryFill))
    }

    private var phrases: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 3) {
            ForEach(Array(entry.phrases.enumerated()), id: \.offset) { _, p in
                GridRow {
                    Text(p.en).font(Theme.serif(13.5))
                    Text(p.zh).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(InlineMarkup.render(e.en, size: 14, serifBase: true, emphasis: .highlight))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(e.zh).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}
