import Foundation

/// 认证令牌持久化：`<状态目录>/auth.json`（原子写 + 0600）。
/// 契约见 `docs/spec/auth.md` §5 —— 放在 OrzMC 状态目录、不进游戏根目录、不记录 token。
public final class AuthStore: @unchecked Sendable {
    public static let fileName = "auth.json"
    public let path: String

    public init(stateDir: String? = nil) {
        self.path = (stateDir ?? Self.stateDir()) + "/" + Self.fileName
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
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        // 令牌文件仅本人可读（POSIX；Windows 无此语义则由 ACL 决定）。
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    public func clear() {
        try? FileManager.default.removeItem(atPath: path)
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
