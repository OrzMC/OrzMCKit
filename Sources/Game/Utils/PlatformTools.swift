import Foundation

/// 平台外部工具的可执行路径解析（决策 D8：Swift CLI 跨平台）。
///
/// 现状：只收拢「系统 `unzip`」这一处平台假设。
/// - macOS：`/usr/bin/unzip`（系统自带）。
/// - Linux：`/usr/bin/unzip` / `/bin/unzip`，再退化到 `PATH` 查找（发行版可能需要自行安装 `unzip`）。
/// - 其它（Windows 等）：返回 `nil`，由调用方按规范给出 `E_UNSUPPORTED` / 降级行为。
public enum PlatformTools {
    /// 系统 `unzip` 路径；找不到返回 `nil`（**不抛错**，让调用方决定降级或报错）。
    public static func unzip(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        #if os(Windows)
        return nil
        #else
        let fixed = ["/usr/bin/unzip", "/bin/unzip", "/usr/local/bin/unzip"]
        if let hit = fixed.first(where: fileExists) { return hit }
        // 退化到 PATH（有些发行版把 unzip 装进 /usr/local 之外的前缀）。
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = String(dir) + "/unzip"
            if fileExists(candidate) { return candidate }
        }
        return nil
        #endif
    }
}
