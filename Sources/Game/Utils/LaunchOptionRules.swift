import Foundation

/// 启动相关选项的**前置校验**（规范 `docs/spec/cli-surface.md` §5）：
/// 参数非法 → `E_USAGE`，且**不做任何 IO**（否则 `--json` 下会先联网/下载再失败）。
///
/// 与 Python 同语义：并发数 1–64、内存 `512M`/`2G` 形态（见 `MemorySpec`）。
public enum LaunchOptionRules {
    public static let downloadThreadRange = 1...64

    /// 返回首个非法项的说明（`-j/--download-threads=0`），合法时 `nil`。
    public static func firstInvalid(downloadThreads: Int?) -> String? {
        guard let threads = downloadThreads else { return nil }
        guard downloadThreadRange.contains(threads) else {
            return "下载并发数必须在 1-64 之间(当前 \(threads))"
        }
        return nil
    }
}
