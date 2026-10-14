import Foundation

/// 已安装版本（扫描 `<root>/versions/*`，规范 `data-model.md` §1 布局）。
public struct InstalledVersion: Sendable, Equatable {
    public let version: String
    public let hasClient: Bool
    public let serverTypes: [GameType]

    public init(version: String, hasClient: Bool, serverTypes: [GameType]) {
        self.version = version
        self.hasClient = hasClient
        self.serverTypes = serverTypes
    }
}

public extension GamePlan {
    /// 扫描 `<root>/versions/*`，列出已安装的客户端 / 服务端版本（按版本号降序）。
    static func installedVersions(root: String = defaultRoot, fileManager: FileManager = .default) -> [InstalledVersion] {
        let versionsDir = layout(root: root, version: "x").versionsDir
        guard let entries = try? fileManager.contentsOfDirectory(atPath: versionsDir) else { return [] }
        var result: [InstalledVersion] = []
        for name in entries {
            let versionDir = "\(versionsDir)/\(name)"
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: versionDir, isDirectory: &isDir), isDir.boolValue else { continue }
            let hasClient = fileManager.fileExists(atPath: "\(versionDir)/client")
            let servers = GameType.allCases.filter { fileManager.fileExists(atPath: "\(versionDir)/server/\($0.rawValue)") }
            if hasClient || !servers.isEmpty {
                result.append(InstalledVersion(version: name, hasClient: hasClient, serverTypes: servers))
            }
        }
        return result.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    /// 移除某版本的客户端或某个服务端类型；随后清理空目录。返回是否确有删除。
    @discardableResult
    static func removeInstalled(
        version: String,
        server: Bool,
        type: GameType?,
        root: String = defaultRoot,
        fileManager: FileManager = .default
    ) -> Bool {
        let versionDir = layout(root: root, version: version).versionDir
        let target = server
            ? (type.map { "\(versionDir)/server/\($0.rawValue)" })
            : "\(versionDir)/client"
        guard let target, fileManager.fileExists(atPath: target) else { return false }
        try? fileManager.removeItem(atPath: target)
        // 清理可能变空的 server/ 与 version/ 目录（只删空目录）。
        pruneIfEmpty("\(versionDir)/server", fileManager)
        pruneIfEmpty(versionDir, fileManager)
        return true
    }

    private static func pruneIfEmpty(_ path: String, _ fileManager: FileManager) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path), contents.isEmpty else { return }
        try? fileManager.removeItem(atPath: path)
    }
}
