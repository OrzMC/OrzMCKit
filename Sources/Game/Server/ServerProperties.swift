import Foundation

/// `server.properties` 的**只读**解析（我们只关心 UI 要展示/跳转的那几个值）。
///
/// 现在只用 `level-name`：世界存档目录名由它决定（默认 `world`），
/// 写死 `serverDir/world` 在玩家改过名字后会指到一个不存在的目录。
public enum ServerProperties {

    public static let defaultLevelName = "world"

    /// 解析 `.properties` 文本里的 `level-name`。
    ///
    /// - 忽略 `#` / `!` 注释行与空行；
    /// - 值两端空白去掉；空值 → `nil`（调用方回退默认值）；
    /// - 文件里有多个同名键时取**第一个**（Minecraft 自己也只看第一个）。
    public static func levelName(contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!") else { continue }
            guard let separator = trimmed.firstIndex(where: { $0 == "=" || $0 == ":" }) else { continue }
            let key = trimmed[trimmed.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            guard key == "level-name" else { continue }
            let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    /// 读某个服务端目录下的 `server.properties`；读不到 / 没写 → 默认 `world`。
    public static func levelName(atServerDir serverDir: String) -> String {
        let path = serverDir + "/server.properties"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return defaultLevelName
        }
        return levelName(contents: contents) ?? defaultLevelName
    }
}
