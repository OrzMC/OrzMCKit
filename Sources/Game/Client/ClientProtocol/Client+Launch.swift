import Foundation
import JokerKits

/// 客户端启动的**共用编排**（CLI 与 GUI 共用，避免各自重复实现）。
public extension Client {
    /// 统一客户端启动流程：解析启动参数 → 托管 JRE（B5）→ 受管进程（B7）。
    ///
    /// 返回时进程已启动（**不等待退出**）：CLI 可前台 `waitForExit()`；GUI 后台运行。
    mutating func launchClient() async throws -> ManagedProcess? {
        guard let args = try await parseBootArgs() else { return nil }
        let version = clientInfo.version.id
        let major = await JavaRuntime.javaMajor(forMCVersion: version, root: clientInfo.rootDir)
        let javaExecutable = try await JavaRuntime.ensure(root: clientInfo.rootDir, major: major)
        let gameDir = GamePlan.clientDir(version: version, root: clientInfo.rootDir)
        return try ProcessRunner.run(
            executable: javaExecutable,
            args: args,
            workDirectory: gameDir
        )
    }
}
