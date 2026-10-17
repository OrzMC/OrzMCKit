import Foundation
import Game

/// 自升级（规范 `docs/spec/install-update.md` §6）。
///
/// 与 Python `SelfUpdater` 同语义：解析最新 release → 下载对应架构资产 →
/// 校验是 Mach-O → 用**分离助手在父进程退出后**替换（运行中自替换不安全）。
enum SelfUpdate {
    static let repo = "OrzMC/OrzMCKit"
    static let stagingName = ".orzmc-update.tmp"
    /// 升级助手日志（一行 `DONE` / `FAILED`；对齐 Python `UPDATE_LOG_NAME`）。
    static let updateLogName = ".orzmc-update.log"
    static var apiLatest: String { "https://api.github.com/repos/\(repo)/releases/latest" }
    static var apiReleases: String { "https://api.github.com/repos/\(repo)/releases?per_page=10" }
    static var downloadBase: String { "https://github.com/\(repo)/releases/download" }
    static var redirectLatest: String { "https://github.com/\(repo)/releases/latest" }

    struct Target: Sendable {
        let current: String
        let latest: String
        let asset: String
        let url: String?
        let available: Bool
    }

    /// 当前进程架构对应的资产名（与 `release.yml` / Python `asset_for` 一致）。
    static func asset() -> String {
        #if arch(arm64)
        return "orzmc-macos-arm64"
        #else
        return "orzmc-macos-x86_64"
        #endif
    }

    /// 安装记录里的 `platform` 字段（对齐 Python `platform_tag`）。
    static func platformTag() -> String {
        #if arch(arm64)
        return "macos-arm64"
        #else
        return "macos-x86_64"
        #endif
    }

    static func current() -> String { "v\(OrzMCVersion.current)" }

    static func normalize(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("v") ? trimmed : "v\(trimmed)"
    }

    static func versionKey(_ version: String) -> [Int] {
        var numbers: [Int] = []
        for part in normalize(version).dropFirst().split(separator: ".") {
            var digits = ""
            for character in part {
                guard character.isNumber else { break }
                digits.append(character)
            }
            guard !digits.isEmpty, let number = Int(digits) else { break }
            numbers.append(number)
        }
        return numbers
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        if candidate == current { return false }
        let left = versionKey(candidate)
        let right = versionKey(current)
        if left.isEmpty || right.isEmpty { return candidate != current }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: 解析

    static func resolve(version: String?, channel: String) async throws -> Target {
        let current = current()
        let latest: String
        if let version {
            latest = normalize(version)
        } else {
            latest = try await latestTag(channel: channel)
        }
        let available = isNewer(latest, than: current)
        let url = (version != nil || available) ? "\(downloadBase)/\(latest)/\(asset())" : nil
        return Target(current: current, latest: latest, asset: asset(), url: url, available: available)
    }

    static func latestTag(channel: String) async throws -> String {
        if channel == "beta", let tag = try? await firstReleaseTag() { return tag }
        if let tag = try? await apiLatestTag() { return tag }
        if let tag = try? await redirectLatestTag() { return tag }
        throw CLIError(
            "无法获取最新版本信息(网络问题或 GitHub API 限流)。请指定版本重试: orzmc update -v vX.Y.Z",
            code: "E_NETWORK"
        )
    }

    static func apiLatestTag() async throws -> String {
        let (data, _) = try await get(apiLatest, api: true)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, !tag.isEmpty
        else { throw CLIError("无法解析最新版本", code: "E_NETWORK") }
        return normalize(tag)
    }

    static func firstReleaseTag() async throws -> String {
        let (data, _) = try await get(apiReleases, api: true)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first, let tag = first["tag_name"] as? String, !tag.isEmpty
        else { throw CLIError("无法解析版本列表", code: "E_NETWORK") }
        return normalize(tag)
    }

    static func redirectLatestTag() async throws -> String {
        let (_, response) = try await get(redirectLatest)
        let final = response.url?.absoluteString ?? ""
        guard let range = final.range(of: "/releases/tag/") else {
            throw CLIError("无法解析最新版本(重定向)", code: "E_NETWORK")
        }
        let tag = final[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard !tag.isEmpty else { throw CLIError("无法解析最新版本(重定向)", code: "E_NETWORK") }
        return normalize(tag)
    }

    // MARK: 下载 / 落盘

    /// 把目标产物放入与旧二进制同卷的暂存文件（`mv` 原子）。
    static func stage(target: Target, file: String?, binary: String) async throws -> String {
        let installDir = (binary as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: installDir, withIntermediateDirectories: true)
        let staging = installDir + "/" + stagingName
        try? FileManager.default.removeItem(atPath: staging)

        do {
            if let file {
                let local = URL(fileURLWithPath: file).standardizedFileURL.path
                guard FileManager.default.fileExists(atPath: local) else {
                    throw CLIError("本地文件不存在: \(local)", code: "E_USAGE")
                }
                try FileManager.default.copyItem(atPath: local, toPath: staging)
            } else {
                guard let urlString = target.url else {
                    throw CLIError("没有可下载的版本", code: "E_RUNTIME")
                }
                let (data, _) = try await get(urlString)
                try data.write(to: URL(fileURLWithPath: staging))
            }

            try verifyExecutable(staging)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging)
        } catch {
            // 失败的升级绝不能留下半成品（成功交接时才保留给助手重命名）。
            try? FileManager.default.removeItem(atPath: staging)
            throw error
        }
        return staging
    }

    private static let machOMagics: [Data] = [
        Data([0xCF, 0xFA, 0xED, 0xFE]), Data([0xCE, 0xFA, 0xED, 0xFE]),
        Data([0xFE, 0xED, 0xFA, 0xCE]), Data([0xFE, 0xED, 0xFA, 0xCF]),
        Data([0xCA, 0xFE, 0xBA, 0xBE]), Data([0xBE, 0xBA, 0xFE, 0xCA]),
    ]

    /// 拒绝空 / HTML / JSON 错误页：必须是 Mach-O 可执行文件（规范 §6「magic 校验」）。
    static func verifyExecutable(_ path: String) throws {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CLIError("无法读取下载的二进制", code: "E_RUNTIME")
        }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 4)
        guard !head.isEmpty else { throw CLIError("下载的二进制为空,已中止升级", code: "E_VERIFY") }
        guard machOMagics.contains(head) else {
            throw CLIError("下载内容不是有效的 Mach-O 可执行文件(可能是错误页),已中止升级", code: "E_VERIFY")
        }
    }

    /// 分离助手：等本进程退出后再 `mv` 覆盖（运行中替换自身不安全）。
    ///
    /// 助手把结果写入 `.orzmc-update.log`（`DONE` / `FAILED`）：重定向的 stdout 会被缓冲，
    /// 没有日志时分不清“助手挂了”与“助手已死”。返回日志路径供调用方提示用户。
    @discardableResult
    static func handoff(staged: String, binary: String) throws -> String {
        let pid = ProcessInfo.processInfo.processIdentifier
        let log = (binary as NSString).deletingLastPathComponent + "/" + updateLogName
        // 每次升级都从空日志开始：上一次的 DONE 不能被误认为这一次的结果。
        try? FileManager.default.removeItem(atPath: log)
        let script = "i=0; while kill -0 \"$1\" 2>/dev/null && [ \"$i\" -lt 300 ]; do sleep 0.2; i=$((i+1)); done; "
            + "if mv -f \"$2\" \"$3\"; then echo DONE >> \"$4\"; else echo FAILED >> \"$4\"; exit 1; fi"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "orzmc-update", String(pid), staged, binary, log]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(atPath: staged)
            throw CLIError("无法启动升级助手,已保留旧版本: \(error)", code: "E_RUNTIME")
        }
        return log
    }

    /// 升级后回写安装记录（`version` / `platform` / `source`）。
    ///
    /// **只在「安装记录指向的二进制 == 本次替换目标」时才改写**：否则升级一份拷贝
    /// 会把全局记录改成新版本，而真正安装的二进制仍是旧版（实测过的坑）。
    static func record(target: Target, binary: String, fromFile: Bool) {
        guard let (path, manifest) = InstallManifest.find(binary: binary) else { return }
        if !manifest.binary.isEmpty {
            let recorded = URL(fileURLWithPath: manifest.binary).resolvingSymlinksInPath().path
            let replaced = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
            guard recorded == replaced else { return }
        }
        var updated = manifest
        updated.version = target.latest
        updated.platform = platformTag()
        updated.source = fromFile ? nil : target.url
        try? updated.write(to: path)
    }

    // MARK: HTTP

    private static func get(_ urlString: String, api: Bool = false) async throws -> (Data, URLResponse) {
        guard let url = URL(string: urlString) else {
            throw CLIError("无效的地址: \(urlString)", code: "E_RUNTIME")
        }
        var request = URLRequest(url: url)
        request.setValue("orzmc-selfupdate", forHTTPHeaderField: "User-Agent")
        if api {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let environment = ProcessInfo.processInfo.environment
            if let token = environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"] {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return try await URLSession.shared.data(for: request)
    }
}
