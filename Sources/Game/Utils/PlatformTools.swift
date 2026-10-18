import Foundation

/// 平台外部工具的可执行路径解析（决策 D8：Swift CLI 跨平台）。
///
/// 收拢「压缩/解压」这处平台假设：
/// - macOS / Linux：系统 `zip` / `unzip`（路径见 `locate`，找不到退化到 `PATH`）。
/// - Windows：系统自带 `tar.exe`（Windows 10+ 内置 bsdtar，支持 zip 的读写）。
///
/// 因此对外暴露的是**「命令 + 参数」**（而不是只有路径）：同一件事在不同平台的参数不一样，
/// 调用方不该自己拼。
public enum PlatformTools {
    /// 系统 `zip` 路径（备份打包用）；找不到返回 `nil`。
    public static func zip(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        locate("zip", environment: environment, fileExists: fileExists)
    }

    /// 系统 `unzip` 路径；找不到返回 `nil`（**不抛错**，让调用方决定降级或报错）。
    public static func unzip(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        locate("unzip", environment: environment, fileExists: fileExists)
    }

    /// 打包目录为 zip：返回 `(可执行文件, 参数)`；无可用工具时 `nil`。
    ///
    /// - POSIX：`zip -r <dest> .`（在 workDirectory 下执行）
    /// - Windows：`tar.exe -a -c -f <dest> .`
    public static func zipCommand(
        destination: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> (path: String, args: [String])? {
        #if os(Windows)
        guard locate("tar", environment: environment, fileExists: fileExists) != nil else { return nil }
        return ("tar.exe", ["-a", "-c", "-f", destination, "."])
        #else
        guard let zip = zip(environment: environment, fileExists: fileExists) else { return nil }
        return (zip, ["-r", destination, "."])
        #endif
    }

    /// 从 jar/zip 里按模式解压到目标目录。
    ///
    /// - POSIX：`unzip -o <archive> <patterns...> -d <dest>`
    /// - Windows：`tar.exe -x -f <archive> -C <dest> <patterns...>`
    public static func unzipCommand(
        archive: String,
        patterns: [String],
        destination: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> (path: String, args: [String])? {
        #if os(Windows)
        guard locate("tar", environment: environment, fileExists: fileExists) != nil else { return nil }
        return ("tar.exe", ["-x", "-f", archive, "-C", destination] + patterns)
        #else
        guard let unzip = unzip(environment: environment, fileExists: fileExists) else { return nil }
        return (unzip, ["-o", archive] + patterns + ["-d", destination])
        #endif
    }

    /// 读取压缩包内单个条目的内容（stdout）。
    ///
    /// - POSIX：`unzip -p <archive> <entry>`
    /// - Windows：`tar.exe -x -O -f <archive> <entry>`
    public static func readEntryCommand(
        archive: String,
        entry: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> (path: String, args: [String])? {
        #if os(Windows)
        guard locate("tar", environment: environment, fileExists: fileExists) != nil else { return nil }
        return ("tar.exe", ["-x", "-O", "-f", archive, entry])
        #else
        guard let unzip = unzip(environment: environment, fileExists: fileExists) else { return nil }
        return (unzip, ["-p", archive, entry])
        #endif
    }

    private static func locate(
        _ tool: String,
        environment: [String: String],
        fileExists: (String) -> Bool
    ) -> String? {
        #if os(Windows)
        return nil
        #else
        let fixed = ["/usr/bin/\(tool)", "/bin/\(tool)", "/usr/local/bin/\(tool)"]
        if let hit = fixed.first(where: fileExists) { return hit }
        // 退化到 PATH（有些发行版把工具装进非标准前缀）。
        for dir in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = String(dir) + "/\(tool)"
            if fileExists(candidate) { return candidate }
        }
        return nil
        #endif
    }
}
