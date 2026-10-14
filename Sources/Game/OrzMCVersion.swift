import Foundation

/// 工具版本（唯一事实源）。
///
/// 与 Python 侧 `orzmc/version.py` 对齐：**源码常量即版本源**，发版打 tag 时同步更新。
/// `orzmc --version`、`orzmc version` 与 `--json` 信封都读取此处，避免多处硬编码漂移。
///
/// `x-release-please-version` 标记供 release-please 的 generic updater 改写；
/// 发版流程另有护栏：GitHub tag 必须与本常量一致（见 `.github/workflows/release.yml`）。
public enum OrzMCVersion {
    public static let current = "0.1.0"  // x-release-please-version
}
