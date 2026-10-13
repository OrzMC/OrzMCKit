//
//  File.swift
//  
//
//  Created by joker on 2022/1/3.
//

import Foundation
import JokerKits
import ConsoleKit

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
}

/// 兼容层：保留原 `GameDir` API，但路径**委托规范契约 `GamePlan`**（对齐 `docs/spec/data-model.md` §1）。
///
/// 这样 `OrzMC` CLI 与 `app` 无需改动即可切到规范布局（`versions/<v>/{client,server/<type>}`）；
/// 后续可逐步把调用点迁到 `GamePlan` 并退役本类型。
public enum GameDir {

    public static let defaultClientType = GameType.vanilla.rawValue
    public static let defaultServerType = GameType.vanilla.rawValue

    case home
    case minecraft
    case manifest
    case gameVersion(version: String)
    case client(version: String, type: String = defaultClientType)
    case assets(version: String, type: String = defaultClientType)
    case assetsIdx(version: String, type: String = defaultClientType)
    case assetsObj(version: String, type: String = defaultClientType, path: String)
    case libraries(version: String, type: String = defaultClientType)
    case libraryObj(version: String, type: String = defaultClientType, path: String)
    case clientVersion(version: String, type: String = defaultClientType)
    case clientVersionProfile(version: String, profile: String, type: String = defaultClientType)
    case clientVersionProfileLibraries(version: String, profile: String, type: String = defaultClientType)
    case clientVersionNative(version: String, type: String = defaultClientType)
    case clientLogConfig(version: String, type: String = defaultClientType)
    case server(version: String, type: String = defaultServerType)
    case serverPlugin(version: String, type: String = defaultServerType)
    case serverPluginUpdate(version: String, type: String = defaultServerType)

    /// 游戏根目录（`~/minecraft`）。
    public static var root: String {
        NSString.path(withComponents: [NSHomeDirectory(), "minecraft"])
    }

    /// 版本目录（`<root>/versions/<v>`）。
    public static func versionDirectory(_ version: String) -> String {
        GamePlan.layout(root: root, version: version).versionDir
    }

    /// 规范布局（内部使用）。
    static func layout(_ version: String, _ type: String) -> GamePlan.Layout {
        GamePlan.layout(root: root, version: version, type: GameType(rawValue: type) ?? .vanilla)
    }

    public var dirPath: String {
        switch self {
        case .home:
            return NSHomeDirectory()
        case .minecraft:
            return GameDir.root
        case .manifest:
            // 规范的版本根目录（旧 layout 的 `manifest/` 对应 `versions/`）。
            return GamePlan.layout(root: GameDir.root, version: "").versionsDir
        case .gameVersion(let version):
            return GameDir.versionDirectory(version)
        case .client(let version, let type):
            return GameDir.layout(version, type).clientDir
        case .assets(let version, let type):
            return GameDir.layout(version, type).clientAssetsDir
        case .assetsIdx(let version, let type):
            return GameDir.layout(version, type).clientIndexesDir
        case .assetsObj(let version, let type, let path):
            return GameDir.layout(version, type).clientObjectsDir + "/" + path
        case .libraries(let version, let type):
            return GameDir.layout(version, type).clientLibrariesDir
        case .libraryObj(let version, let type, let path):
            return GameDir.layout(version, type).clientLibrariesDir + "/" + path
        case .clientVersion(let version, let type):
            // 客户端 jar 与 version JSON 都落在 client 目录。
            return GameDir.layout(version, type).clientDir
        case .clientVersionProfile(let version, let profile, let type):
            return GameDir.layout(version, type).clientProfilesDir + "/" + profile
        case .clientVersionProfileLibraries(let version, let profile, let type):
            return GameDir.layout(version, type).clientProfilesDir + "/" + profile + "/libraries"
        case .clientVersionNative(let version, let type):
            return GameDir.layout(version, type).clientNativesDir
        case .clientLogConfig(let version, let type):
            return GameDir.layout(version, type).clientDir + "/log_configs"
        case .server(let version, let type):
            return GameDir.layout(version, type).serverDir
        case .serverPlugin(let version, let type):
            return GameDir.layout(version, type).serverDir + "/plugins"
        case .serverPluginUpdate(let version, let type):
            return GameDir.layout(version, type).serverDir + "/plugins/update"
        }
    }

    public func filePath(_ filename: String) -> String {
        return NSString.path(withComponents: [dirPath, filename])
    }
}
