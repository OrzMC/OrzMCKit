import Foundation

// Linux/Windows 把 URLSession/URLRequest 放在 FoundationNetworking（决策 D8：跨平台）。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GUI 应用（`OrzMCApp`）的跨面安装（规范 `docs/spec/install-update.md` §8）。
///
/// 渠道：`release`（GitHub Release 的 `.zip` 产物，解压到 `~/Applications`）。
/// App Store 渠道在上架前显式不支持。
///
/// 平台：`.app` / `ditto` / `open` 是 macOS 概念，本文件整体只在 macOS 编译（D8 跨平台）。
/// 非 macOS 上 `orzmc app` 由 `AppCommand` 直接给 `E_UNSUPPORTED`。
#if os(macOS)
enum AppInstaller {
    static let repo = "OrzMC/OrzMCApp"
    static let appName = "OrzMC.app"
    static let appStoreURL = "macappstore://apps.apple.com/app/id0000000000"  // 上架后填写

    static var apiLatest: String { "https://api.github.com/repos/\(repo)/releases/latest" }
    static func apiTag(_ tag: String) -> String { "https://api.github.com/repos/\(repo)/releases/tags/\(tag)" }

    static func applicationsDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        (environment["HOME"] ?? NSHomeDirectory()) + "/Applications"
    }

    static var installedAppPath: String { applicationsDir() + "/" + appName }

    struct Release: Sendable {
        let tag: String
        let zipURL: String
    }

    /// 应用是否已安装。
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedAppPath)
    }

    /// 已安装应用的版本（读 `Info.plist` 的 `CFBundleShortVersionString`）。
    static func installedVersion() -> String? {
        let plistPath = installedAppPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    /// 解析发布：指定 tag 或最新；取其中的 `.zip` 资产。
    static func resolve(version: String?) async throws -> Release {
        let urlString = version.map(apiTag) ?? apiLatest
        let (data, _) = try await get(urlString)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let assets = object["assets"] as? [[String: Any]]
        else { throw CLIError("无法解析应用发布信息", code: "E_NETWORK") }
        let urls = assets.compactMap { $0["browser_download_url"] as? String }
        // 同一 release 可能有多个带时间戳的产物：按名称取最新的 .zip。
        guard let zip = urls.filter({ $0.lowercased().hasSuffix(".zip") }).sorted().last else {
            throw CLIError("发布 \(tag) 没有 .zip 产物", code: "E_NOT_FOUND")
        }
        return Release(tag: tag, zipURL: zip)
    }

    /// 下载 → 解压 → 安装到 `~/Applications/OrzMC.app`，返回安装路径。
    static func install(release: Release) async throws -> String {
        let fileManager = FileManager.default
        let workspace = fileManager.temporaryDirectory.appendingPathComponent("orzmc-app-\(UUID().uuidString)")
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspace) }

        let zipPath = workspace.appendingPathComponent("app.zip")
        let (data, _) = try await get(release.zipURL)
        try data.write(to: zipPath)

        let extractDir = workspace.appendingPathComponent("extract")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", ["-x", "-k", zipPath.path, extractDir.path])

        guard let appURL = (try? fileManager.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" })
        else { throw CLIError("解压后未找到 .app", code: "E_VERIFY") }

        try fileManager.createDirectory(atPath: applicationsDir(), withIntermediateDirectories: true)
        let destination = URL(fileURLWithPath: installedAppPath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: appURL, to: destination)
        return destination.path
    }

    static func open() throws {
        guard isInstalled() else {
            throw CLIError("未安装 OrzMC 应用;先运行 orzmc app install", code: "E_NOT_FOUND")
        }
        try runTool("/usr/bin/open", [installedAppPath])
    }

    static func uninstall() throws -> Bool {
        let path = installedAppPath
        guard FileManager.default.fileExists(atPath: path) else { return false }
        try FileManager.default.removeItem(atPath: path)
        return true
    }

    // MARK: 私有

    private static func runTool(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CLIError("无法执行 \(executable): \(error)", code: "E_RUNTIME")
        }
        guard process.terminationStatus == 0 else {
            throw CLIError("\(executable) 退出码 \(process.terminationStatus)", code: "E_RUNTIME")
        }
    }

    private static func get(_ urlString: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            throw CLIError("无效的地址: \(urlString)", code: "E_RUNTIME")
        }
        var request = URLRequest(url: url)
        request.setValue("orzmc-app", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let environment = ProcessInfo.processInfo.environment
        if let token = environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"] {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await URLSession.shared.data(for: request)
    }
}
#endif
