import QuickTransCore
import SwiftUI

/// 翻译面板。胶囊态（280×34）→ 出结果后展开成卡片（380 宽），都用常规玻璃，叠在杂乱背景上也看得清。
struct TranslatorView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject private var settings = AppSettings.shared
    var onSize: (CGSize) -> Void
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    @FocusState private var inputFocused: Bool
    @ViewState private var contentHeight: CGFloat = 0

    private let maxResultHeight: CGFloat = 460

    var body: some View {
        let compact = model.isCompact
        VStack(spacing: 0) {
            if model.source == .selection, !model.quote.isEmpty {
                quote
            }
            if model.source == .input {
                inputRow
            }
            if !compact {
                if model.source == .input { Divider().opacity(0.5) }
                result
                footer
            }
        }
        .frame(width: compact ? 280 : 380)
        .glassEffect(.regular,
                     in: RoundedRectangle(cornerRadius: compact ? 17 : 18, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.focusToken) { inputFocused = true }
    }

    // MARK: - 输入

    private var inputRow: some View {
        HStack(spacing: 4) {
            TextField("输入单词或句子，回车翻译", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { model.submit(model.input) }
            iconButton("gearshape", help: "设置", action: onOpenSettings)
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .padding(.vertical, 7)
        .frame(minHeight: 34)
    }

    private var quote: some View {
        Text(model.quote)
            .font(Theme.serif(13))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent).frame(width: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
    }

    // MARK: - 结果

    private var result: some View {
        ScrollView {
            resultContent
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(contentHeight, 30), maxResultHeight))
    }

    @ViewBuilder
    private var resultContent: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在翻译…").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .word(let entry):
            WordCardView(entry: entry)
        case .text(let text, let done, let direction):
            Text(text + (done ? "" : " ▍"))
                .font(direction == .toEnglish ? Theme.serif(15) : .system(size: 14.5))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .error(let message, let showSettings):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.multicolor)
                if showSettings {
                    Button("打开设置", action: onOpenSettings).buttonStyle(.glass)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .needsPermission:
            VStack(alignment: .leading, spacing: 8) {
                Text("划词翻译需要「辅助功能」权限，用来读取其它应用里选中的文字。")
                    .font(.system(size: 13))
                Text("在系统设置里勾选 QuickTrans 后，再按一次快捷键即可。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Button("打开辅助功能设置") { SelectionReader.openAccessibilitySettings() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 页脚

    @ViewBuilder
    private var footer: some View {
        if hasResult {
            HStack(spacing: 10) {
                Text(settings.model)
                if !model.metaKind.isEmpty { Text(model.metaKind) }
                if model.metaCached {
                    Text("来自历史")
                } else if let t = model.metaElapsed {
                    Text(String(format: "%.1f 秒", t))
                }
                Spacer()
                iconButton("doc.on.doc", help: "复制结果") { model.copyResult() }
                iconButton("arrow.clockwise", help: "重新翻译") { model.retry() }
                iconButton(model.pinned ? "pin.fill" : "pin", help: model.pinned ? "取消固定" : "固定：点击外部不关闭",
                           tint: model.pinned ? Theme.accent : nil) { model.pinned.toggle() }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .padding(.top, 2)
        }
    }

    private var hasResult: Bool {
        switch model.phase {
        case .word: return true
        case .text(_, let done, _): return done
        default: return false
        }
    }

    private func iconButton(_ symbol: String, help: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
