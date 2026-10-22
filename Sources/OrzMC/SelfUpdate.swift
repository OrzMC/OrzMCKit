import Foundation

// Linux/Windows 把 URLSession/URLRequest 放在 FoundationNetworking（决策 D8：跨平台）。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Game
import JokerKits

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

    /// 当前进程所在平台名（`macos` / `linux` / `windows`）。
    static var osName: String {
        #if os(Windows)
        return "windows"
        #elseif os(Linux)
        return "linux"
        #else
        return "macos"
        #endif
    }

    /// 当前进程架构名（与发布资产一致：`arm64` / `x86_64`）。
    static var archName: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// 资产名（与 `release.yml` 一致）：\`orzmc-<os>-<arch>\`，**Windows 是 \`.zip\`**。
    ///
    /// Windows 的 Swift 程序运行时要一堆 DLL（\`swiftCore.dll\`/\`Foundation.dll\`/\`swiftCRT.dll\`…）。
    /// \`--static-swift-stdlib\` **并不能**把它们静态链进去（实测 \`dumpbin /dependents\` 仍列出它们，
    /// 干净机器上直接 \`0xC0000135 = DLL not found\`），所以 Windows 资产 = exe + DLL 的压缩包。
    ///
    /// 平台/架构做成参数是为了能在任意平台上单测三种形状。
    static func asset(osName: String = Self.osName, arch: String = Self.archName) -> String {
        let suffix = osName == "windows" ? ".zip" : ""
        return "orzmc-\(osName)-\(arch)\(suffix)"
    }

    /// Windows 的资产是压缩包：下载后要先解出 exe。
    static var assetIsArchive: Bool { osName == "windows" }

    /// 安装记录里的 `platform` 字段（对齐 Python `platform_tag`）：`<os>-<arch>`。
    static func platformTag(osName: String = Self.osName, arch: String = Self.archName) -> String {
        "\(osName)-\(arch)"
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
        // 仓库**只有预发布**时 `/releases/latest` 恒为 404（本仓库的 Swift CLI 就是这种发布
        // 口径，见 docs/two-cli-strategy.md §6），退一步取「最新一个 release」（含预发布），
        // 与 scripts/install.sh 的选择保持一致。
        if let tag = try? await firstReleaseTag() { return tag }
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
            } else if Self.assetIsArchive {
                guard let urlString = target.url else {
                    throw CLIError("没有可下载的版本", code: "E_RUNTIME")
                }
                let (data, _) = try await get(urlString)
                let archive = installDir + "/" + stagingName + ".zip"
                try? FileManager.default.removeItem(atPath: archive)
                try data.write(to: URL(fileURLWithPath: archive))
                defer { try? FileManager.default.removeItem(atPath: archive) }
                // 从压缩包里取出 exe 到暂存位置（Windows 用内置 tar）。
                let extractDir = installDir + "/" + stagingName + ".dir"
                try? FileManager.default.removeItem(atPath: extractDir)
                try FileManager.default.createDirectory(atPath: extractDir, withIntermediateDirectories: true)
                guard let unzip = PlatformTools.unzipCommand(
                    archive: archive,
                    patterns: ["orzmc.exe"],
                    destination: extractDir
                ) else {
                    throw CLIError("系统缺少解压工具(Windows 自带 tar)", code: "E_UNSUPPORTED")
                }
                // 显式标注类型：`run` 有 `-> String` / `-> Process` / async `-> Bool` 三个重载，
                // 在 async 上下文里 `try run(...)` 会选中 Bool 那个。
                let extractOutput: String = try Shell.run(path: unzip.path, args: unzip.args)
                _ = extractOutput
                let extracted = extractDir + "/orzmc.exe"
                guard FileManager.default.fileExists(atPath: extracted) else {
                    throw CLIError("压缩包里没有 orzmc.exe,已中止升级", code: "E_VERIFY")
                }
                try FileManager.default.copyItem(atPath: extracted, toPath: staging)
                try? FileManager.default.removeItem(atPath: extractDir)
            } else {
                guard let urlString = target.url else {
                    throw CLIError("没有可下载的版本", code: "E_RUNTIME")
                }
                let (data, _) = try await get(urlString)
                try data.write(to: URL(fileURLWithPath: staging))
            }

            try verifyExecutable(staging)
            #if !os(Windows)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging)
            #endif
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

    /// Linux ELF 头部。
    private static let elfMagics: [Data] = [Data([0x7F, 0x45, 0x4C, 0x46])]
    /// Windows PE（`MZ`）。
    private static let peMagics: [Data] = [Data([0x4D, 0x5A])]

    /// 该平台允许的可执行文件魔数。
    static func allowedMagics(osName: String = Self.osName) -> [Data] {
        switch osName {
        case "windows": return peMagics
        case "linux": return elfMagics
        default: return machOMagics
        }
    }

    /// 拒绝空 / HTML / JSON 错误页：必须是对应平台的可执行文件（规范 §6「magic 校验」）。
    static func verifyExecutable(_ path: String, osName: String = Self.osName) throws {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw CLIError("无法读取下载的二进制", code: "E_RUNTIME")
        }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 4)
        guard !head.isEmpty else { throw CLIError("下载的二进制为空,已中止升级", code: "E_VERIFY") }
        guard allowedMagics(osName: osName).contains(head) else {
            throw CLIError(
                "下载内容不是有效的可执行文件(\(osName);可能是错误页),已中止升级",
                code: "E_VERIFY"
            )
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

        #if os(Windows)
        // Windows 不能替换正在运行的 exe，但**可以给它改名**：
        // 当前 exe → `<exe>.old`，再把新二进制放到原位置，下次启动即生效。
        return try handoffOnWindows(staged: staged, binary: binary, log: log)
        #else
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
        #endif
    }

    #if os(Windows)
    /// Windows 的自替换：改名旧 exe → 放入新 exe → 写日志（语义与 POSIX 助手一致）。
    private static func handoffOnWindows(staged: String, binary: String, log: String) throws -> String {
        let retired = binary + ".old"
        let fm = FileManager.default
        // 上一次留下的 `.old` 先清掉（此时不会再有进程占用它）。
        try? fm.removeItem(atPath: retired)
        do {
            if fm.fileExists(atPath: binary) {
                try fm.moveItem(atPath: binary, toPath: retired)
            }
            try fm.moveItem(atPath: staged, toPath: binary)
            try? "DONE\n".write(toFile: log, atomically: true, encoding: .utf8)
        } catch {
            // 回滚：把旧 exe 放回去，别让用户既没新版也没旧版。
            if !fm.fileExists(atPath: binary), fm.fileExists(atPath: retired) {
                try? fm.moveItem(atPath: retired, toPath: binary)
            }
            try? fm.removeItem(atPath: staged)
            try? "FAILED\n".write(toFile: log, atomically: true, encoding: .utf8)
            throw CLIError("替换二进制失败,已回滚到旧版本: \(error)", code: "E_RUNTIME")
        }
        return log
    }
    #endif

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
