import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 认证令牌持久化：`<状态目录>/auth.json`（原子写 + 0600）。
/// 契约见 `docs/spec/auth.md` §5 —— 放在 OrzMC 状态目录、不进游戏根目录、不记录 token。
public final class AuthStore: @unchecked Sendable {
    public static let fileName = "auth.json"
    public let path: String

    public init(stateDir: String? = nil) {
        self.path = stateDir.map { $0 + "/" + Self.fileName } ?? StatePaths.authSession()
    }

    /// 状态目录（与 `InstallManifest` 同一实现，见 `StatePaths`；Windows 走 `%LOCALAPPDATA%`）。
    public static func stateDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        StatePaths.stateDir(environment: environment)
    }

    public func load() -> AuthSession? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }
        return Self.decode(root)
    }

    static func decode(_ root: [String: Any]) -> AuthSession? {
        guard let account = root["account"] as? [String: Any],
              let minecraft = root["minecraft"] as? [String: Any],
              let msa = root["msa"] as? [String: Any],
              let uuid = account["uuid"] as? String,
              let name = account["name"] as? String,
              let accessToken = minecraft["accessToken"] as? String,
              let minecraftExpires = number(minecraft["expiresAt"]),
              let msaAccess = msa["accessToken"] as? String,
              let refreshToken = msa["refreshToken"] as? String,
              let msaExpires = number(msa["expiresAt"]) else { return nil }
        return AuthSession(
            uuid: uuid,
            name: name,
            accessToken: accessToken,
            expiresAt: minecraftExpires,
            msa: MsaTokens(
                accessToken: msaAccess,
                refreshToken: refreshToken,
                expiresAt: msaExpires,
                tokenType: msa["tokenType"] as? String ?? "Bearer",
                scope: msa["scope"] as? String
            )
        )
    }

    public func save(_ session: AuthSession, clientId: String) throws {
        var msa: [String: Any] = [
            "accessToken": session.msa.accessToken,
            "refreshToken": session.msa.refreshToken,
            "expiresAt": session.msa.expiresAt,
            "tokenType": session.msa.tokenType,
        ]
        if let scope = session.msa.scope { msa["scope"] = scope }
        let payload: [String: Any] = [
            "schema": 1,
            "clientId": clientId,
            "account": ["uuid": session.uuid, "name": session.name],
            "minecraft": ["accessToken": session.accessToken, "expiresAt": session.expiresAt],
            "msa": msa,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        #if os(Windows)
        // Windows permissions are determined by the parent directory's ACL.
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        #else
        // Create the temporary file private from its first instant, then atomically replace.
        let temporaryPath = directory + "/.auth-" + UUID().uuidString
        let descriptor = open(temporaryPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { try? FileManager.default.removeItem(atPath: temporaryPath) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try file.write(contentsOf: data)
        try file.close()
        guard rename(temporaryPath, path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #endif
    }

    public func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 跨进程锁（`frontends.md` F4.1）：刷新令牌的整个「读 → 换新 → 写」要持它。
    /// 与 Python 侧算法逐字一致（`<stateDir>/auth.lock` 目录锁）。
    public static func lock(stateDir: String? = nil) -> FileLock {
        FileLock.authLock(stateDir: stateDir)
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
