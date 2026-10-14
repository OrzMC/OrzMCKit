import Foundation

/// 服务端部署的**纯计划**（对齐 `docs/spec/data-model.md` §9 / `behavior.md` B7）。
public struct ServerDeployPlan: Sendable, Equatable {
    public struct CoreArtifact: Sendable, Equatable {
        public let url: String
        public let sha1: String?
        public let size: Int?
        public let filename: String
    }

    public let version: String
    public let type: String
    public let workdir: String
    public let jarName: String
    public let eula: Bool
    public let coreArtifact: CoreArtifact
}

public extension GamePlan {
    /// vanilla 服务端部署计划（离线，核心制品来自版本 JSON 的 `downloads.server`）。
    ///
    /// paper/fabric/forge 需要各自 provider 的数据（网络），此处返回 `nil`。
    static func planServerDeploy(
        version: VersionPlan,
        type: GameType,
        root: String
    ) -> ServerDeployPlan? {
        guard type == .vanilla, let server = version.downloads?.server else { return nil }
        let layout = layout(root: root, version: version.id, type: type)
        return ServerDeployPlan(
            version: version.id,
            type: type.rawValue,
            workdir: layout.serverDir,
            jarName: layout.serverJarName,
            eula: true,
            coreArtifact: .init(
                url: server.url,
                sha1: server.sha1,
                size: server.size,
                filename: layout.serverJarName
            )
        )
    }
}
