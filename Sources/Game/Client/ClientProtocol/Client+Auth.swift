import Foundation
import MojangAPI

extension Client {
    /// Legacy Mojang 账密认证**已废弃**。
    ///
    /// 正版授权改用 Microsoft 设备码流程（`Game/Auth/Authenticator.swift`），
    /// 由 CLI `--auth` 在命令层完成并把会话注入 `ClientInfo`（`accessToken`/`authUUID`/`userType`）。
    /// 保留本方法以兼容 `Launcher.authenticate()` 的调用点，恒返回 `false`（不做任何认证）。
    public mutating func auth() async throws -> Bool {
        return false
    }
}
