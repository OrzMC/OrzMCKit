import CacheKit
import Foundation
import JokerKits
import MojangAPI

public enum FabricServerError: Error, CustomStringConvertible {
    case missingVanillaServer(String)
    case installerFailed(Int32)
    case missingLauncher(String)

    public var description: String {
        switch self {
        case .missingVanillaServer(let version):
            return "该版本没有可用的官方服务端下载: \(version)"
        case .installerFailed(let code):
            return "Fabric 服务端生成失败（安装器退出码 \(code)）"
        case .missingLauncher(let path):
            return "未找到 Fabric 服务端产物: \(path)"
        }
    }
}

/// Fabric 服务端（对齐 Python `core/server/fabric.py`）。
///
/// fabric-installer 只生成装载器包装器 `fabric-server-launch.jar`，运行时从同目录的
/// `server.jar` 加载原版服务端；安装器本身**不再下载** vanilla jar，所以这里必须先按
/// Mojang 清单把官方 `server.jar` 放到服务端目录，再运行安装器。
public struct FabricServer: Server {
    static let installerBase = "https://maven.fabricmc.net/net/fabricmc/fabric-installer"
    /// 现代 fabric-loader 要求 Java 17+。
    static let minimumJavaMajor = 17

    public let serverInfo: ServerInfo

    public init(serverInfo: ServerInfo) {
        self.serverInfo = serverInfo
    }

    public func start() async throws -> ManagedProcess? {
        await MojangCache.configure(root: serverInfo.rootDir)
        let version = serverInfo.version
        let layout = GamePlan.layout(root: serverInfo.rootDir, version: version, type: .fabric)
        let serverDir = layout.serverDir
        try FileManager.default.createDirectory(atPath: serverDir, withIntermediateDirectories: true)

        // 1) vanilla server.jar（安装器不会再下载它）
        guard let entry = try await Mojang.manifest().versions.first(where: { $0.id == version }),
              let gameVersion = try await entry.gameVersion,
              let serverURL = URL(string: gameVersion.downloads.server.url)
        else {
            throw FabricServerError.missingVanillaServer(version)
        }
        let vanillaJar = URL(fileURLWithPath: serverDir + "/server.jar")
        if serverInfo.forceDownload { try? FileManager.default.removeItem(at: vanillaJar) }
        if !FileManager.default.fileExists(atPath: vanillaJar.path()) {
            let progress = ProgressReporter(console: serverInfo.console, title: "正在下载服务端文件", observer: serverInfo.onProgress)
            try await progress.tracking {
                try await Downloader.download(
                    DownloadItemInfo(
                        sourceURL: serverURL,
                        dstFileURL: vanillaJar,
                        hash: gameVersion.downloads.server.sha1,
                        hashType: .sha1
                    ),
                    onEvent: progress.update
                )
            }
        }

        // 2) fabric-installer + loader（经统一缓存；`--refresh` 绕过）
        let cache = MetadataCache(
            directory: URL(fileURLWithPath: layout.cacheDir, isDirectory: true),
            refresh: serverInfo.refresh
        )
        let loader = try await FabricMeta.latestLoaderVersion(version: version, cache: cache)
        let installerVersion = try await FabricMeta.latestInstallerVersion(cache: cache)
        guard let installerURL = URL(
            string: "\(Self.installerBase)/\(installerVersion)/fabric-installer-\(installerVersion).jar"
        ) else {
            throw FabricServerError.installerFailed(-1)
        }
        let buildDir = layout.serverBuildDir
        try FileManager.default.createDirectory(atPath: buildDir, withIntermediateDirectories: true)
        let installerPath = "\(buildDir)/fabric-installer-\(installerVersion).jar"
        let installerProgress = ProgressReporter(console: serverInfo.console, title: "下载 fabric-installer", observer: serverInfo.onProgress)
        try await installerProgress.tracking {
            try await Downloader.download(
                DownloadItemInfo(sourceURL: installerURL, dstFileURL: URL(fileURLWithPath: installerPath)),
                onEvent: installerProgress.update
            )
        }

        // 3) 生成 fabric-server-launch.jar（安装器日志走 stderr，stdout 留给 --json）
        let mcMajor = await JavaRuntime.javaMajor(forMCVersion: version, root: serverInfo.rootDir)
        let buildJava = try await JavaRuntime.ensure(
            root: serverInfo.rootDir,
            major: max(mcMajor, Self.minimumJavaMajor)
        )
        serverInfo.console?.info("正在生成 Fabric 服务端 (loader \(loader))...")
        let process = try ProcessRunner.run(
            executable: buildJava,
            args: ["-jar", installerPath, "server", "-dir", serverDir, "-mcversion", version, "-loader", loader],
            workDirectory: serverDir,
            onLine: { text in FileHandle.standardError.write(Data(text.utf8)) }
        )
        let code = await process.waitForExit()
        guard code == 0 else {
            throw FabricServerError.installerFailed(code)
        }
        guard FileManager.default.fileExists(atPath: layout.serverJarPath) else {
            throw FabricServerError.missingLauncher(layout.serverJarPath)
        }

        let javaExecutable = try await JavaRuntime.ensure(root: serverInfo.rootDir, major: mcMajor)
        return try await launchServer(
            layout.serverJarPath,
            workDirectory: serverDir,
            javaExecutable: javaExecutable
        )
    }
}
