import Foundation

/// JVM 内存参数（`-m/--min-mem`、`-x/--max-mem`）的校验。
///
/// 规范（`docs/spec/cli-surface.md` §5）：**参数非法 → `E_USAGE`，且不做任何 IO**。
/// 之前 Swift 把非法值一路带到下载阶段，`--json` 下会先联网再失败（实测在隔离沙箱里 90 秒超时），
/// 与 Python 的「先校验后动手」不一致。这里只做纯判定，抛错交给 CLI 层（保持 Game 不依赖 CLI 错误类型）。
public enum MemorySpec {
    /// `512M` / `2G` / `1.5G`（大小写不敏感）。
    private static let pattern = try! NSRegularExpression(pattern: "^[0-9]+(\\.[0-9]+)?[MmGg]$")

    public static func isValid(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return pattern.firstMatch(in: value, options: [], range: range) != nil
    }

    /// 返回首个非法项的说明（`-m/--min-mem=nope`），全合法时 `nil`。
    public static func firstInvalid(min minMem: String, max maxMem: String) -> String? {
        if !isValid(minMem) { return "-m/--min-mem=\(minMem)" }
        if !isValid(maxMem) { return "-x/--max-mem=\(maxMem)" }
        return nil
    }
}
