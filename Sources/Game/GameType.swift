import Foundation

/// 游戏类型（核心/装载器）。对齐 `docs/spec/data-model.md` §3 的能力矩阵。
public enum GameType: String, Sendable, CaseIterable {
    case vanilla
    case fabric
    case forge
    case paper

    /// 是否支持作为客户端（paper 无客户端）。
    public var isClientCapable: Bool { self != .paper }

    /// 是否支持作为服务端（全部支持）。
    public var isServerCapable: Bool { true }

    /// 服务端核心 jar 文件名（对齐 `docs/spec/data-model.md` §3）。
    public func serverJarName(version: String) -> String {
        switch self {
        case .paper: return "paper-\(version).jar"
        case .forge: return "forge-\(version).jar"
        case .fabric: return "fabric-server-launch.jar"
        case .vanilla: return "server.jar"
        }
    }
}

public enum GameError: Error {
    case noGameVersions
    case worldNotFound(String)
    case clientJarNotFound(String)
}
