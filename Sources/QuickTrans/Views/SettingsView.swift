import Combine
import QuickTransCore
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case model = "模型", hotkey = "快捷键", general = "通用"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .model: return "cpu"
            case .hotkey: return "command"
            case .general: return "gearshape"
            }
        }
    }

    @ViewState private var pane: Pane = .model

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.rawValue, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(160)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane {
                case .model: ModelPane()
                case .hotkey: HotkeyPane()
                case .general: GeneralPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.rawValue)
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}

// MARK: - 模型

private struct ModelPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewState private var models: [ModelInfo] = []
    @ViewState private var status: String?
    @ViewState private var statusOK = true
    @ViewState private var testing = false

    var body: some View {
        Form {
            Section("服务") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(Provider.allCases) { Text($0.title).tag($0) }
                }
                TextField("接口地址", text: $settings.baseURL, prompt: Text("https://…"))
                SecureField("API Key", text: $settings.apiKey, prompt: Text("sk-…"))
                LabeledContent {
                    HStack(spacing: 10) {
                        if let status {
                            Text(status).font(.callout).foregroundStyle(statusOK ? .green : .red)
                                .lineLimit(2).multilineTextAlignment(.trailing)
                        }
                        Button(testing ? "测试中…" : "测试连接") { Task { await refresh(showStatus: true) } }
                            .disabled(testing || settings.apiKey.isEmpty)
                    }
                } label: {
                    Text("API Key 只保存在本机").font(.callout).foregroundStyle(.secondary)
                }
            }

            Section {
                if models.isEmpty {
                    TextField("翻译模型", text: $settings.model, prompt: Text(settings.provider.defaultModel))
                } else {
                    Picker("翻译模型", selection: $settings.model) {
                        ForEach(modelIDs, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("推理强度", selection: $settings.effort) {
                    Text("默认").tag("")
                    ForEach(effortLevels, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(effortLevels.isEmpty)
            } header: {
                Text("模型")
            } footer: {
                Text(effortLevels.isEmpty
                     ? "这个模型不支持推理强度。"
                     : "强度越高越准、越慢。划词翻译建议 low。单词音标由模型按剑桥词典写法给出，发音优先用词典真人录音。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .task(id: settings.provider) {
            models = []
            status = nil
            if !settings.apiKey.isEmpty { await refresh(showStatus: false) }
        }
        .onChange(of: settings.model) { normalizeEffort() }
    }

    private var modelIDs: [String] {
        var ids = models.map(\.id)
        if !settings.model.isEmpty, !ids.contains(settings.model) { ids.insert(settings.model, at: 0) }
        return ids
    }

    private var effortLevels: [String] {
        models.first { $0.id == settings.model }?.effortLevels
            ?? settings.provider.fallbackEffortLevels(for: settings.model)
    }

    private func normalizeEffort() {
        if !settings.effort.isEmpty, !effortLevels.contains(settings.effort) {
            settings.effort = effortLevels.contains("low") ? "low" : ""
        }
    }

    private func refresh(showStatus: Bool) async {
        testing = true
        defer { testing = false }
        let client = LLMClient(config: settings.llmConfig)
        do {
            models = try await client.listModels()
            if showStatus {
                var text = "连接成功，\(models.count) 个可用模型"
                if let balance = await client.balance() { text += "，余额 \(balance)" }
                status = text
                statusOK = true
            }
            normalizeEffort()
        } catch {
            if showStatus {
                status = error.localizedDescription
                statusOK = false
            }
        }
    }
}

// MARK: - 快捷键

private struct HotkeyPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ViewState private var trusted = SelectionReader.isTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("全局快捷键") {
                LabeledContent {
                    ShortcutRecorder(shortcut: $settings.translateHotkey)
                } label: {
                    Text("翻译选中文本")
                    Text("在任意应用里选中文字后按下").font(.callout).foregroundStyle(.secondary)
                }
                LabeledContent {
                    ShortcutRecorder(shortcut: $settings.inputHotkey)
                } label: {
                    Text("打开输入框")
                    Text("悬浮球隐藏时也能用").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("权限") {
                LabeledContent {
                    if trusted {
                        Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("去授权") {
                            SelectionReader.requestTrust()
                            SelectionReader.openAccessibilitySettings()
                        }
                    }
                } label: {
                    Text("辅助功能")
                    Text("用来读取其它应用里选中的文字").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .onReceive(timer) { _ in trusted = SelectionReader.isTrusted }
    }
}

// MARK: - 通用

private struct GeneralPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var history = HistoryStore.shared
    @ViewState private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle("显示桌面悬浮球", isOn: $settings.showBall)
                Toggle("开机自动启动", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            }
            Section("发音") {
                Picker("默认口音", selection: $settings.defaultAccent) {
                    ForEach(Accent.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("查询单词后自动发音", isOn: $settings.autoSpeak)
            }
            Section("历史记录") {
                LabeledContent("本地保存最近 \(HistoryStore.limit) 条，相同内容再查时直接使用") {
                    Button("清空 \(history.items.count) 条") { confirmClear = true }
                        .disabled(history.items.isEmpty)
                }
            }
        }
        .confirmationDialog("清空全部历史记录？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) { history.clear() }
        }
    }
}

// MARK: - 快捷键录制

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    @ViewState private var recording = false
    @ViewState private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "请按下快捷键…" : shortcut.display)
                .frame(minWidth: 110)
                .foregroundStyle(recording ? Theme.accent : .primary)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.pauseAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            guard !mods.isEmpty else {
                NSSound.beep()
                return nil
            }
            shortcut = Shortcut(event: event)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { HotKeyCenter.shared.resumeAll() }
        recording = false
    }
}
