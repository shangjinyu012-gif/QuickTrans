import SwiftUI

struct HistoryView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ViewState private var query = ""
    var onOpen: (HistoryItem) -> Void

    var body: some View {
        List {
            ForEach(filtered) { item in
                Button {
                    onOpen(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.input)
                                .font(item.word != nil ? Theme.serif(14, weight: .semibold) : .system(size: 13))
                                .lineLimit(1)
                            Spacer()
                            Text(item.date, format: .relative(presentation: .named))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(item.summary.replacingOccurrences(of: "*", with: ""))
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("删除", role: .destructive) { history.remove(item) }
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "还没有查询记录" : "没有匹配的记录",
                                       systemImage: "clock",
                                       description: Text(query.isEmpty ? "用悬浮球或划词快捷键翻译后，会记录在这里" : ""))
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "搜索单词或原文")
        .frame(minWidth: 420, minHeight: 480)
    }

    private var filtered: [HistoryItem] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter {
            $0.input.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query)
        }
    }
}
