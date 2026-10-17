import CacheKit
import Foundation
import JokerKits
import TransferKit

public enum ForgeServerError: Error, CustomStringConvertible {
    case installFailed(Int32)
    case missingProduct(String)

    public var description: String {
        switch self {
        case .installFailed(let code):
            return "Forge 安装失败（安装器退出码 \(code)）"
        case .missingProduct(let dir):
            return "未找到 Forge 服务端产物: \(dir)"
        }
    }
}

/// Forge 服务端（对齐 Python `core/server/forge.py`）。
///
/// 通过 Maven `promotions_slim` 解析 `<mc>-<build>`，下载官方安装器并运行
/// `--installServer`，再按两个时代的不同产物布局落位：
///
/// - **现代（ForgeBootstrap / 1.20.4+ / 49.x）**：`forge-<full>-shim.jar` 的清单
///   `Class-Path` 以自身为基准指向 `libraries/`，两者必须一起搬进服务端目录；
/// - **旧版**：顶层单个可运行 `forge-<full>.jar`。
public struct ForgeServer: Server {
    public let serverInfo: ServerInfo

    public init(serverInfo: ServerInfo) {
        self.serverInfo = serverInfo
    }

    public func start() async throws -> ManagedProcess? {
        await MojangCache.configure(root: serverInfo.rootDir)
        let version = serverInfo.version
        let layout = GamePlan.layout(root: serverInfo.rootDir, version: version, type: .forge)
        let serverDir = layout.serverDir
        try FileManager.default.createDirectory(atPath: serverDir, withIntermediateDirectories: true)

        let cache = MetadataCache(
            directory: URL(fileURLWithPath: layout.cacheDir, isDirectory: true),
            refresh: serverInfo.refresh
        )
        let full = try await ForgeMeta.latestFullVersion(mcVersion: version, cache: cache)

        // 完整安装（jar + libraries/）不应每次重跑代价高昂的 --installServer。
        if !serverInfo.forceDownload, Self.isInstalled(layout: layout) {
            serverInfo.console?.info("Forge 服务端已安装,跳过安装器(用 --force-download 重装)")
        } else {
            try await install(full: full, layout: layout)
        }

        let major = await JavaRuntime.javaMajor(forMCVersion: version, root: serverInfo.rootDir)
        let javaExecutable = try await JavaRuntime.ensure(root: serverInfo.rootDir, major: major)
        return try await launchServer(
            layout.serverJarPath,
            workDirectory: serverDir,
            javaExecutable: javaExecutable
        )
    }

    // MARK: - internals

    /// 服务端 jar 存在，且（shim 时代）其 `libraries/` 就在旁边——半搬运不算已安装。
    static func isInstalled(layout: GamePlan.Layout) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: layout.serverJarPath) else { return false }
        return fileManager.fileExists(atPath: layout.serverDir + "/libraries")
    }

    private func install(full: String, layout: GamePlan.Layout) async throws {
        let buildDir = layout.serverBuildDir
        try FileManager.default.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
        let installerPath = "\(buildDir)/forge-\(full)-installer.jar"
        let installerProgress = ProgressReporter(
            console: serverInfo.console,
            title: "正在下载 Forge 安装器",
            observer: serverInfo.onProgress
        )
        try await installerProgress.tracking {
            try await ForgeMeta.downloadInstaller(
                url: ForgeMeta.installerURL(full),
                to: installerPath,
                onEvent: installerProgress.update
            )
        }

        let mcMajor = await JavaRuntime.javaMajor(forMCVersion: serverInfo.version, root: serverInfo.rootDir)
        let buildJava = try await JavaRuntime.ensure(
            root: serverInfo.rootDir,
            major: max(mcMajor, ForgeMeta.minimumJavaMajor)
        )
        serverInfo.console?.info("正在安装 Forge \(full)...")
        let process = try ProcessRunner.run(
            executable: buildJava,
            args: ["-jar", installerPath, "--installServer"],
            workDirectory: buildDir,
            // 安装器日志走 stderr：stdout 必须留给 `--json` 信封。
            onLine: { text in FileHandle.standardError.write(Data(text.utf8)) }
        )
        let code = await process.waitForExit()
        guard code == 0 else {
            throw ForgeServerError.installFailed(code)
        }
        try Self.moveProducts(full: full, version: serverInfo.version, buildDir: buildDir, layout: layout)
    }

    /// 把安装器在 `build/` 生成的产物搬进服务端目录。
    static func moveProducts(full: String, version: String, buildDir: String, layout: GamePlan.Layout) throws {
        let fileManager = FileManager.default
        let serverDir = layout.serverDir

        // 现代：shim + 它的 libraries/ 树一起搬（Class-Path 相对 shim 自身）。
        let shim = buildDir + "/forge-\(full)-shim.jar"
        if fileManager.fileExists(atPath: shim) {
            try? fileManager.removeItem(atPath: layout.serverJarPath)
            try fileManager.moveItem(atPath: shim, toPath: layout.serverJarPath)
            let librarySource = buildDir + "/libraries"
            let libraryTarget = serverDir + "/libraries"
            if fileManager.fileExists(atPath: librarySource),
               !fileManager.fileExists(atPath: libraryTarget) {
                try fileManager.moveItem(atPath: librarySource, toPath: libraryTarget)
            }
            return
        }

        // 旧版：顶层单个可运行 universal jar。
        let candidates = [
            buildDir + "/forge-\(full).jar",
            buildDir + "/\(version)-forge.jar",
            buildDir + "/\(version)-forge-universal.jar",
        ]
        guard let product = candidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            throw ForgeServerError.missingProduct(buildDir)
        }
        try? fileManager.removeItem(atPath: layout.serverJarPath)
        try fileManager.moveItem(atPath: product, toPath: layout.serverJarPath)
    }
}
