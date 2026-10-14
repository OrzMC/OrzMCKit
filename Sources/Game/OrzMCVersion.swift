import Foundation

/// 工具版本（唯一事实源）。
///
/// 与 Python 侧 `orzmc/version.py` 对齐：**源码常量即版本源**，发版打 tag 时同步更新。
/// `orzmc --version`、`orzmc version` 与 `--json` 信封都读取此处，避免多处硬编码漂移。
///
/// 说明：`OrzMCKit` 当前尚无 release-please 工作流，`current` 取最近一次已发布 tag；
/// 后续接入发版自动化时，让流程改写此常量即可（等价于 Python 的 `x-release-please-version` 标记）。
public enum OrzMCVersion {
    public static let current = "0.0.6"
}
