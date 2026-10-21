import Foundation
import HangarAPI
import JokerKits

/// 本地已安装的插件（`plugins/` 里的一个 jar）。
public struct InstalledPlugin: Sendable, Hashable {
    /// jar 文件名，如 `LuckPerms-Bukkit-5.4.1.jar`。
    public let fileName: String
    /// 绝对路径。
    public let path: String
    /// 去掉 `.jar` 的文件名。
    public var baseName: String { String(fileName.dropLast(4)) }
    /// 文件名里能认出来的版本号（认不出 → `nil`）。
    public var version: String? { PluginInstaller.versionToken(in: baseName) }

    public init(fileName: String, path: String) {
        self.fileName = fileName
        self.path = path
    }
}

/// 插件该放进哪个目录 —— **对齐 Paper 官方更新机制**。
public enum PluginInstallTarget: String, Sendable, CaseIterable {
    /// 新装插件：直接进 `plugins/`，下次启动即加载。
    case plugins
    /// 已装插件的更新：进 `plugins/update/`，服务端**下次启动时**自动替换旧版本
    /// （Bukkit/Paper 的 `settings.update-folder`，默认 `update`）。
    case update
}

/// 一个插件相对本地目录的状态。
public enum PluginInstallState: Sendable, Equatable {
    /// 本地没有。
    case notInstalled
    /// 本地已有同一个文件（版本号一致）。
    case upToDate(installed: String)
    /// 本地已有，但是旧版本。
    case outdated(installed: String, latest: String)
}

public enum PluginInstaller {

    // MARK: 扫描

    /// 列出 `pluginsDir` 里**当前生效**的插件 jar。
    ///
    /// - 只看 `.jar`（忽略 `.jar.disabled` / `.jar.bak` 等被停用的）；
    /// - 不进 `update/` 子目录 —— 那里的 jar 还没被服务端应用。
    public static func scan(pluginsDir: String) -> [InstalledPlugin] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: pluginsDir) else { return [] }
        return names
            .filter { $0.lowercased().hasSuffix(".jar") }
            .sorted()
            .map { InstalledPlugin(fileName: $0, path: pluginsDir + "/" + $0) }
    }

    // MARK: 匹配

    /// jar 是否属于某个插件项目（`LuckPerms` ↔ `LuckPerms-Bukkit-5.4.1.jar`）。
    ///
    /// 归一化后做前缀匹配：Hangar 的下载文件名通常是 `<项目名>-<平台>-<版本>.jar`，
    /// 但玩家也可能重命名（`EssentialsX.jar`），所以不能要求全等。
    public static func belongs(jarNamed fileName: String, toProject project: String) -> Bool {
        let jar = normalize(fileName)
        let name = normalize(project)
        guard name.count >= 3, jar.count >= name.count else { return false }
        return jar.hasPrefix(name)
    }

    /// 归一化：小写 + 只留字母数字（`LuckPerms-Bukkit-5.4.1.jar` → `luckpermsbukkit541jar`）。
    public static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 从文件名里挑出版本号（最长的一段 `数字(.数字)+`，如 `5.4.1`）；没有 → `nil`。
    public static func versionToken(in text: String) -> String? {
        var best: String?
        var current = ""
        for character in text {
            if character.isNumber || character == "." {
                current.append(character)
            } else {
                consider(&best, current)
                current = ""
            }
        }
        consider(&best, current)
        return best
    }

    private static func consider(_ best: inout String?, _ candidate: String) {
        // 版本号至少 "1.2" 这种形状；纯数字（`26`）也算（`paper-26.3` 之外的单段版本）。
        let trimmed = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !trimmed.isEmpty, !trimmed.hasPrefix("."), !trimmed.hasSuffix(".") else { return }
        guard trimmed.contains(".") || trimmed.count >= 2 else { return }
        if let current = best {
            if trimmed.count > current.count { best = trimmed }
        } else {
            best = trimmed
        }
    }

    // MARK: 决策

    /// 本地状态：结合已装 jar 与远端最新文件名。
    public static func state(
        project: String,
        latestFileName: String,
        installed: [InstalledPlugin]
    ) -> PluginInstallState {
        let matches = installed.filter { belongs(jarNamed: $0.fileName, toProject: project) }
        guard let first = matches.first else { return .notInstalled }
        let latestVersion = versionToken(in: latestFileName)
        for jar in matches {
            if self.normalize(jar.baseName) == self.normalize(stripExtension(latestFileName)) {
                return .upToDate(installed: jar.version ?? jar.baseName)
            }
            if let latestVersion, jar.version == latestVersion {
                return .upToDate(installed: latestVersion)
            }
        }
        return .outdated(
            installed: first.version ?? first.baseName,
            latest: latestVersion ?? latestFileName
        )
    }

    /// 决定下载到哪个目录：**已装 → `update`，没装 → `plugins`**。
    public static func target(for state: PluginInstallState) -> PluginInstallTarget {
        switch state {
        case .notInstalled: return .plugins
        case .upToDate, .outdated: return .update
        }
    }

    /// 目标目录（按需创建）。
    public static func directory(
        for target: PluginInstallTarget,
        pluginsDir: String,
        updateDir: String
    ) throws -> String {
        let dir = target == .update ? updateDir : pluginsDir
        try dir.makeDirIfNeed()
        return dir
    }

    public static func stripExtension(_ fileName: String) -> String {
        fileName.lowercased().hasSuffix(".jar") ? String(fileName.dropLast(4)) : fileName
    }
}

// MARK: - 联网：查最新版本 → 下载到正确目录

public extension PaperPlugin {

    /// 为某个插件项目准备下载项（含**该去哪个目录**）。
    ///
    /// - Parameters:
    ///   - project: Hangar 项目（`search` / `allPlugin` 的结果）。
    ///   - gameVersion: 限定游戏版本（不匹配 → 返回 nil）。
    ///   - pluginsDir / updateDir: 服务端实例的 `plugins/` 与 `plugins/update/`。
    public func installPlan(
        for project: PluginProject,
        gameVersion: String? = nil,
        pluginsDir: String,
        updateDir: String
    ) async throws -> PluginInstallPlan? {
        guard let projectName = project.name,
              let latestDownload = try await latesetReleaseVersionDownload(of: project, version: gameVersion)
        else {
            return nil
        }
        let latestFileName = latestDownload.fileInfo?.name ?? "\(projectName).jar"
        let installed = PluginInstaller.scan(pluginsDir: pluginsDir)
        let state = PluginInstaller.state(
            project: projectName,
            latestFileName: latestFileName,
            installed: installed
        )
        let target = PluginInstaller.target(for: state)
        let dir = try PluginInstaller.directory(
            for: target,
            pluginsDir: pluginsDir,
            updateDir: updateDir
        )
        guard let item = try await project.downloadItem(
            outputFileDirURL: URL(fileURLWithPath: dir),
            version: gameVersion
        )
        else {
            return nil
        }
        return PluginInstallPlan(
            project: projectName,
            state: state,
            target: target,
            item: item
        )
    }
}

/// 一次插件安装/更新的全部信息（前端可拿来显示"装到哪、是新增还是更新"）。
public struct PluginInstallPlan: Sendable {
    public let project: String
    public let state: PluginInstallState
    public let target: PluginInstallTarget
    public let item: DownloadItemInfo

    public var destinationDirectory: String { item.dstFileURL.deletingLastPathComponent().path }
    public var fileName: String { item.dstFileURL.lastPathComponent }
}
