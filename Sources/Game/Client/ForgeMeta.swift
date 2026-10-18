import CacheKit
import Foundation

// Linux/Windows 把 URLSession/URLRequest 放在 FoundationNetworking（决策 D8：跨平台）。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import JokerKits
import TransferKit

/// Forge 客户端附加组件解析（Maven `promotions_slim` + 官方安装器）。
///
/// 对齐 Python `orzmc.core.client.forge.ForgeProvider`：Forge 没有独立的客户端定义，
/// 启动 json 内嵌在安装器里，打过补丁的 `client` jar 只能由安装器的二进制补丁流程生成。
/// 流程：解析版本 → 下载安装器 → 读取内嵌 `version.json` → 无头运行 `--installClient` →
/// 收集生成/下载的库到客户端 `libraries/` → 清理临时安装目录。
///
/// 仅支持现代 ForgeBootstrap（1.20.4+ / 49.x）；旧版 `cpw.mods.bootstraplauncher`
/// 明确报错，避免产出损坏的启动配置。
public enum ForgeMeta {
    static let promotionsURL = "https://files.minecraftforge.net/maven/net/minecraftforge/forge/promotions_slim.json"
    static let mavenBase = "https://maven.minecraftforge.net/net/minecraftforge/forge"
    static let legacyLauncherClass = "cpw.mods.bootstraplauncher"
    static let minimumJavaMajor = 17

    /// 解析指定 MC 版本的 Forge 客户端附加组件（含下载安装器、运行安装器、收集库）。
    public static func resolve(
        version: String,
        root: String,
        refresh: Bool = false
    ) async throws -> ProfileAddon {
        let cache = MetadataCache(directory: cacheDirectory(root: root, version: version), refresh: refresh)
        let full = try await latestFullVersion(mcVersion: version, cache: cache)

        let forgeDir = GamePlan.clientDir(version: version, root: root) + "/forge"
        let installerPath = forgeDir + "/forge-\(full)-installer.jar"
        try await downloadInstaller(
            url: "\(mavenBase)/\(full)/forge-\(full)-installer.jar",
            to: installerPath
        )

        let forgeJSON = try extractVersionPlan(installerPath)
        if (forgeJSON.mainClass ?? "").contains(legacyLauncherClass) {
            throw ForgeMetaError.legacyLauncher(full)
        }

        let installDir = forgeDir + "/install"
        defer { try? FileManager.default.removeItem(atPath: installDir) }
        try await runClientInstall(
            installerPath: installerPath,
            installDir: installDir,
            root: root,
            mcVersion: version
        )
        let libraries = try harvestLibraries(
            plan: forgeJSON,
            installDir: installDir,
            root: root,
            version: version
        )

        return ProfileAddon(
            libraries: libraries,
            jvmArgs: plainStrings(forgeJSON.arguments?.jvm),
            gameArgs: plainStrings(forgeJSON.arguments?.game),
            mainClass: forgeJSON.mainClass,
            // 打补丁的 client jar 就是游戏 jar；vanilla jar 不能再进 classpath 覆盖它。
            usesOwnClientJar: true
        )
    }

    // MARK: - internals

    static func cacheDirectory(root: String, version: String) -> URL {
        URL(fileURLWithPath: GamePlan.layout(root: root, version: version).cacheDir, isDirectory: true)
    }

    /// 该 MC 版本的 Forge 完整版本串（`<mc>-<build>`，优先 `-latest`）。
    static func latestFullVersion(mcVersion: String, cache: MetadataCache) async throws -> String {
        struct Promotions: Codable {
            let promos: [String: String]?
        }
        let url = cache.metaURL("forge-promotions")
        let promos = try await cache.get(Promotions.self, at: url) {
            let data = try await fetch(promotionsURL)
            return try JSONDecoder().decode(Promotions.self, from: data)
        }.promos ?? [:]
        for key in ["\(mcVersion)-latest", "\(mcVersion)-recommended"] {
            if let build = promos[key] {
                return "\(mcVersion)-\(build)"
            }
        }
        throw ForgeMetaError.noVersion(mcVersion)
    }

    /// Forge 安装器下载地址（`maven/<full>/forge-<full>-installer.jar`）。
    public static func installerURL(_ full: String) -> String {
        "\(mavenBase)/\(full)/forge-\(full)-installer.jar"
    }

    static func downloadInstaller(
        url: String,
        to path: String,
        onEvent: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws {
        guard let source = URL(string: url) else { throw ForgeMetaError.badURL(url) }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await Downloader.download(
            DownloadItemInfo(sourceURL: source, dstFileURL: destination),
            onEvent: onEvent
        )
    }

    /// 读取安装器 jar 内嵌的 `version.json`（`unzip -p`）；`unzip` 路径由 `PlatformTools` 解析（D8）。
    static func extractVersionPlan(_ installerPath: String) throws -> VersionPlan {
        guard let unzip = PlatformTools.readEntryCommand(archive: installerPath, entry: "version.json") else {
            throw ForgeMetaError.extractFailed(installerPath)
        }
        let json = try Shell.run(path: unzip.path, args: unzip.args)
        guard let data = json.data(using: .utf8), !data.isEmpty else {
            throw ForgeMetaError.extractFailed(installerPath)
        }
        return try JSONDecoder().decode(VersionPlan.self, from: data)
    }

    /// 无头运行官方安装器 `--installClient`（需要 launcher_profiles.json 与 Java 17+）。
    static func runClientInstall(
        installerPath: String,
        installDir: String,
        root: String,
        mcVersion: String
    ) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        let profilePath = installDir + "/launcher_profiles.json"
        if !fileManager.fileExists(atPath: profilePath) {
            try minimalLauncherProfile.write(toFile: profilePath, atomically: true, encoding: .utf8)
        }

        let mcMajor = await JavaRuntime.javaMajor(forMCVersion: mcVersion, root: root)
        let java = try await JavaRuntime.ensure(root: root, major: max(mcMajor, minimumJavaMajor))
        let process = try ProcessRunner.run(
            executable: java,
            args: ["-jar", installerPath, "--installClient", installDir],
            workDirectory: installDir,
            // 安装器日志走 stderr：stdout 必须留给 `--json` 信封。
            onLine: { text in FileHandle.standardError.write(Data(text.utf8)) }
        )
        let code = await process.waitForExit()
        guard code == 0 else {
            throw ForgeMetaError.installFailed(code)
        }
    }

    /// 把安装器在临时目录生成的库（含打补丁的 `-client.jar`）移入客户端 `libraries/`。
    static func harvestLibraries(
        plan: VersionPlan,
        installDir: String,
        root: String,
        version: String
    ) throws -> [ProfileAddon.Library] {
        let fileManager = FileManager.default
        let sourceRoot = installDir + "/libraries"
        var libraries: [ProfileAddon.Library] = []
        for library in plan.libraries ?? [] {
            guard let artifact = library.downloads?.artifact else { continue }
            let source = sourceRoot + "/" + artifact.path
            guard fileManager.fileExists(atPath: source) else { continue }
            let destination = GamePlan.clientLibraryPath(version: version, path: artifact.path, root: root)
            try fileManager.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.moveItem(atPath: source, toPath: destination)
            libraries.append(
                ProfileAddon.Library(
                    name: library.name,
                    path: artifact.path,
                    url: artifact.url,
                    sha1: artifact.sha1,
                    size: artifact.size
                )
            )
        }
        guard libraries.contains(where: { $0.path.hasSuffix("-client.jar") }) else {
            throw ForgeMetaError.clientJarMissing
        }
        return libraries
    }

    /// `arguments.<key>` 里的纯字符串条目（Forge 不产出规则字典）。
    static func plainStrings(_ entries: [ArgumentEntry]?) -> [String] {
        (entries ?? []).compactMap { entry in
            if case .plain(let text) = entry { return text }
            return nil
        }
    }

    static func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw ForgeMetaError.badURL(urlString) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ForgeMetaError.http(status: http.statusCode, url: urlString)
        }
        return data
    }

    static let minimalLauncherProfile = """
    {"authenticationDatabase":{},"selectedUser":{"account":"","profile":""},"profiles":{},"settings":{"enableSnapshots":false,"keepLauncherOpen":false},"version":1}
    """
}

public enum ForgeMetaError: Error, CustomStringConvertible {
    case badURL(String)
    case http(status: Int, url: String)
    case noVersion(String)
    case legacyLauncher(String)
    case extractFailed(String)
    case installFailed(Int32)
    case clientJarMissing

    /// CLI 错误码（对齐 `docs/spec/cli-surface.md` §6.1）。
    public var code: String {
        switch self {
        case .legacyLauncher: return "E_UNSUPPORTED_TYPE"
        case .noVersion: return "E_VERSION_NOT_FOUND"
        case .badURL, .http: return "E_NETWORK"
        default: return "E_RUNTIME"
        }
    }

    public var description: String {
        switch self {
        case .badURL(let url):
            return "Forge 元数据 URL 无效: \(url)"
        case .http(let status, let url):
            return "Forge 元数据请求失败（HTTP \(status)）: \(url)"
        case .noVersion(let version):
            return "未找到 Minecraft \(version) 的 Forge 版本"
        case .legacyLauncher(let full):
            return "Forge \(full) 使用旧版启动器(BootstrapLauncher),暂不支持客户端启动(仅支持 ForgeBootstrap 系,1.20.4 及以上)"
        case .extractFailed(let path):
            return "无法从 Forge 安装器读取 version.json: \(path)"
        case .installFailed(let code):
            return "Forge 客户端安装失败 (exit=\(code))"
        case .clientJarMissing:
            return "未找到 Forge 客户端产物(client jar),安装可能不完整"
        }
    }
}
