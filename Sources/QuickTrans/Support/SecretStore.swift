import Foundation

/// API Key 存在 ~/Library/Application Support/QuickTrans/credentials.json，文件权限 600（仅当前用户可读写）。
/// 不用钥匙串的原因：App 用没有团队 ID 的自签名证书签名，钥匙串按二进制哈希识别 App，每次重新编译都会弹授权框。
enum SecretStore {
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickTrans", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("credentials.json")
    }()

    private static var cache: [String: String] = {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }()

    static func get(account: String) -> String? {
        cache[account]
    }

    static func set(_ value: String, account: String) {
        cache[account] = value.isEmpty ? nil : value
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
