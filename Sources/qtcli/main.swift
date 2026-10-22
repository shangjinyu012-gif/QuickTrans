import Foundation
import QuickTransCore

// 用法：QT_API_KEY=sk-xxx swift run qtcli [--model deepseek-flash] [--effort low] <文本>
//       QT_API_KEY=sk-xxx swift run qtcli --models

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...i + 1)
    return v
}

let env = ProcessInfo.processInfo.environment
let config = LLMConfig(
    baseURL: option("--base") ?? env["QT_BASE_URL"] ?? "https://api.deepseek.com",
    apiKey: env["QT_API_KEY"] ?? "",
    model: option("--model") ?? "deepseek-flash",
    effort: option("--effort") ?? "low"
)
let translator = Translator(config: config)

if args.first == "--models" {
    for m in try await translator.client.listModels() {
        print(m.id, m.effortLevels, m.defaultEffort ?? "-")
    }
    print("余额:", await translator.client.balance() ?? "-")
    exit(0)
}

let input = args.joined(separator: " ")
let start = Date()
switch InputClassifier.classify(input) {
case .word(let w):
    let entry = try await translator.lookUp(w)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
    print(String(data: try enc.encode(entry), encoding: .utf8)!)
case .text(let t, let dir):
    print("[\(dir.label)]")
    for try await piece in translator.translate(t, direction: dir) {
        FileHandle.standardOutput.write(piece.data(using: .utf8)!)
    }
    print()
}
print(String(format: "耗时 %.1fs", Date().timeIntervalSince(start)))
