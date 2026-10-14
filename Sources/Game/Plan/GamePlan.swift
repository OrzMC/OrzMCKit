import Foundation

/// 规范对齐的**纯计划契约**（dev 决策 D-a：strangler-fig）。
///
/// 布局对齐 `docs/spec/data-model.md` §1；逻辑路径统一用 `/`（各实现按平台转换）。
/// 旧 `GameDir` 已退役：路径统一由本契约与 `GamePlan+Paths` 提供。
public enum GamePlan {

    public struct Layout: Sendable, Equatable {
        public let root: String
        public let versionsDir: String
        public let versionDir: String
        public let clientDir: String
        public let clientAssetsDir: String
        public let clientIndexesDir: String
        public let clientObjectsDir: String
        public let clientLibrariesDir: String
        public let clientNativesDir: String
        public let clientJarPath: String
        public let clientProfilesDir: String
        public let serverDir: String
        public let serverJarName: String
        public let serverJarPath: String
        public let serverEulaPath: String
        public let serverPropertiesPath: String
        public let serverPluginsDir: String
        public let serverWorldDir: String
        public let javaDir: String
        public let javaMajorDir: String?
        public let javaExecutable: String?
        public let cacheDir: String
        public let versionManifestPath: String
        public let versionJsonsDir: String
        public let downloadTmpDir: String
        public let backupDir: String
        public let clientObjectPath: String?
    }

    /// 计算规范布局（纯函数，不建目录、不 IO）。
    ///
    /// - Parameters:
    ///   - root: 游戏根目录（默认 `~/minecraft` 由调用方给出）。
    ///   - version: MC 版本。
    ///   - type: 核心/装载器类型（只影响 `server/<type>`）。
    ///   - javaMajor: 托管 JRE 主版本（给出时才计算 `java/<major>` 与可执行路径）。
    ///   - objectSha1: 资源对象 sha1（给出时才计算 `clientObjectPath`）。
    ///   - windows: 决定 `java` / `java.exe`。
    public static func layout(
        root: String,
        version: String,
        type: GameType = .vanilla,
        javaMajor: Int? = nil,
        objectSha1: String? = nil,
        windows: Bool = false
    ) -> Layout {
        let root = root.hasSuffix("/") ? String(root.dropLast()) : root
        let versionsDir = "\(root)/versions"
        let versionDir = "\(versionsDir)/\(version)"
        let clientDir = "\(versionDir)/client"
        let assets = "\(clientDir)/assets"
        let serverDir = "\(versionDir)/server/\(type.rawValue)"
        let serverJarName = type.serverJarName(version: version)
        let javaDir = "\(root)/java"
        let javaMajorDir = javaMajor.map { "\(javaDir)/\($0)" }
        let javaExecutable = javaMajor.map { "\(javaDir)/\($0)/bin/java\(windows ? ".exe" : "")" }
        let cacheDir = "\(root)/cache"

        return Layout(
            root: root,
            versionsDir: versionsDir,
            versionDir: versionDir,
            clientDir: clientDir,
            clientAssetsDir: assets,
            clientIndexesDir: "\(assets)/indexes",
            clientObjectsDir: "\(assets)/objects",
            clientLibrariesDir: "\(clientDir)/libraries",
            clientNativesDir: "\(clientDir)/natives",
            clientJarPath: "\(clientDir)/\(version).jar",
            clientProfilesDir: "\(clientDir)/profiles",
            serverDir: serverDir,
            serverJarName: serverJarName,
            serverJarPath: "\(serverDir)/\(serverJarName)",
            serverEulaPath: "\(serverDir)/eula.txt",
            serverPropertiesPath: "\(serverDir)/server.properties",
            serverPluginsDir: "\(serverDir)/plugins",
            serverWorldDir: "\(serverDir)/world",
            javaDir: javaDir,
            javaMajorDir: javaMajorDir,
            javaExecutable: javaExecutable,
            cacheDir: cacheDir,
            versionManifestPath: "\(cacheDir)/version_manifest.json",
            versionJsonsDir: "\(cacheDir)/versions",
            downloadTmpDir: "\(cacheDir)/download_tmp",
            backupDir: "\(root)/backup",
            clientObjectPath: objectSha1.map { "\(assets)/objects/\($0.prefix(2))/\($0)" }
        )
    }
}
