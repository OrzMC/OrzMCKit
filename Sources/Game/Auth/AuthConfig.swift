import Foundation

/// `--auth` 的 Azure 公共客户端配置（规范 `docs/spec/auth.md` §10）。
public enum AuthConfig {
    /// 内置 Azure 公共客户端 `client_id`（组织目录 + 个人账号，Allow public client flows）。
    /// 空串 = 未内置；可用环境变量 `ORZMC_AZURE_CLIENT_ID` 覆盖。
    public static let defaultClientId = ""

    /// 解析顺序：显式 `override` → 环境变量 `ORZMC_AZURE_CLIENT_ID` → 内置默认。
    public static func clientId(override: String? = nil) -> String {
        let value = override ?? ProcessInfo.processInfo.environment["ORZMC_AZURE_CLIENT_ID"] ?? defaultClientId
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
