import Foundation

/// 路径便捷 API（**唯一布局契约 `GamePlan`** 的入口）。
///
/// 原先由 `GameDir` 枚举提供的路径，统一改为 `GamePlan` 的静态方法；
/// 内部一律委托 `GamePlan.layout(...)`，逻辑路径用 `/`。
public extension GamePlan {
    /// 默认游戏根目录（`~/minecraft`）。
    static var defaultRoot: String {
        StatePaths.defaultGameRoot()
    }

    // MARK: client

    static func clientDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientDir
    }

    static func clientAssetsDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientAssetsDir
    }

    static func clientIndexesDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientIndexesDir
    }

    static func clientObjectsDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientObjectsDir
    }

    static func clientLibrariesDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientLibrariesDir
    }

    static func clientNativesDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientNativesDir
    }

    static func clientJarPath(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientJarPath
    }

    static func clientLogConfigDir(version: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientDir + "/log_configs"
    }

    static func clientProfileDir(version: String, profile: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version).clientProfilesDir + "/" + profile
    }

    static func clientProfileLibrariesDir(version: String, profile: String, root: String = defaultRoot) -> String {
        clientProfileDir(version: version, profile: profile, root: root) + "/libraries"
    }

    static func clientObjectPath(version: String, sha1: String, root: String = defaultRoot) -> String {
        layout(root: root, version: version, objectSha1: sha1).clientObjectPath ?? ""
    }

    static func clientLibraryPath(version: String, path: String, root: String = defaultRoot) -> String {
        clientLibrariesDir(version: version, root: root) + "/" + path
    }

    // MARK: server

    static func serverDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        layout(root: root, version: version, type: type).serverDir
    }

    static func serverJarPath(version: String, type: GameType, root: String = defaultRoot) -> String {
        layout(root: root, version: version, type: type).serverJarPath
    }

    static func serverPluginDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        serverDir(version: version, type: type, root: root) + "/plugins"
    }

    static func serverBuildDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        layout(root: root, version: version, type: type).serverBuildDir
    }

    static func serverPluginUpdateDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        serverPluginDir(version: version, type: type, root: root) + "/update"
    }

    /// 世界存档目录（`<serverDir>/<level-name>`）。
    ///
    /// `level-name` 来自 `server.properties`（默认 `world`）；玩家改过名字时调用方应传
    /// `ServerProperties.levelName(atServerDir:)` 的结果，别假设一定是 `world`。
    static func serverWorldDir(
        version: String,
        type: GameType,
        levelName: String = ServerProperties.defaultLevelName,
        root: String = defaultRoot
    ) -> String {
        serverDir(version: version, type: type, root: root) + "/" + levelName
    }

    /// 服务端日志目录（`logs/latest.log` 在这里）。
    static func serverLogsDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        serverDir(version: version, type: type, root: root) + "/logs"
    }

    /// 服务端 mod 目录（Fabric / Forge）。
    static func serverModsDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        serverDir(version: version, type: type, root: root) + "/mods"
    }

    /// 服务端配置目录（Fabric / Forge 的 mod 配置）。
    static func serverConfigDir(version: String, type: GameType, root: String = defaultRoot) -> String {
        serverDir(version: version, type: type, root: root) + "/config"
    }

    // MARK: client 常用目录

    static func clientLogsDir(version: String, root: String = defaultRoot) -> String {
        clientDir(version: version, root: root) + "/logs"
    }

    static func clientSavesDir(version: String, root: String = defaultRoot) -> String {
        clientDir(version: version, root: root) + "/saves"
    }

    static func clientModsDir(version: String, root: String = defaultRoot) -> String {
        clientDir(version: version, root: root) + "/mods"
    }

    static func clientResourcePacksDir(version: String, root: String = defaultRoot) -> String {
        clientDir(version: version, root: root) + "/resourcepacks"
    }
}
