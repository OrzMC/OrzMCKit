import Foundation

/// 安装记录 `install.conf`（key=value 文本；规范 `docs/spec/install-update.md` §2/§3）。
///
/// 这是**跨前端的共享契约**（`docs/spec/frontends.md` §2）：CLI 的 `uninstall` / `update`
/// 据它还原 PATH、清理补全、定位二进制；GUI 读它显示「CLI 是否已安装 / 由谁安装」。
/// 因此它属于 `Game` 公共面，而不是某个可执行目标内部实现。
///
/// 与 Python `InstallManifest` 同格式；读取容忍 UTF-8 BOM（PS 5.1 写 BOM）。
public struct InstallManifest: Sendable {
    public static let fileName = "install.conf"
    /// 记录兜底位置：二进制同目录（规范 §3）。
    public static let fallbackName = ".orzmc-manifest"

    public var tool: String
    public var schema: Int
    public var version: String
    public var platform: String
    public var installDir: String
    public var binary: String
    public var source: String?
    public var pathFile: String?
    public var pathLine: String?
    public var rootDir: String
    public var completionFile: String?
    /// 装出这条记录的前端（`cli` / `gui`）；`nil` = 旧记录（未知）。规范 §3.1。
    public var surface: String?

    public init(rootDir: String = GamePlan.defaultRoot) {
        self.tool = "orzmc"
        self.schema = 1
        self.version = ""
        self.platform = ""
        self.installDir = ""
        self.binary = ""
        self.rootDir = rootDir
    }

    public init(lines: [String]) {
        var fields: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            fields[key] = String(line[line.index(after: separator)...])
        }
        tool = fields["tool"] ?? "orzmc"
        schema = Int(fields["schema"] ?? "") ?? 1
        version = fields["version"] ?? ""
        platform = fields["platform"] ?? ""
        installDir = fields["install_dir"] ?? ""
        binary = fields["binary"] ?? ""
        source = fields["source"]
        pathFile = fields["path_file"]
        pathLine = fields["path_line"]
        rootDir = fields["root_dir"] ?? GamePlan.defaultRoot
        completionFile = fields["completion_file"]
        surface = fields["surface"]
    }

    public var serialized: String {
        var lines = [
            "tool=\(tool)",
            "schema=\(schema)",
            "version=\(version)",
            "platform=\(platform)",
            "install_dir=\(installDir)",
            "binary=\(binary)",
        ]
        if let source { lines.append("source=\(source)") }
        if let pathFile { lines.append("path_file=\(pathFile)") }
        if let pathLine { lines.append("path_line=\(pathLine)") }
        lines.append("root_dir=\(rootDir)")
        if let completionFile { lines.append("completion_file=\(completionFile)") }
        if let surface { lines.append("surface=\(surface)") }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 位置

    /// 状态目录 `${XDG_STATE_HOME:-$HOME/.local/state}/orzmc`。
    /// 状态目录：`docs/spec/state-paths.json`（Unix `${XDG_STATE_HOME:-~/.local/state}/orzmc`，
    /// Windows `%LOCALAPPDATA%\\orzmc`）。
    public static func stateDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        StatePaths.stateDir(environment: environment)
    }

    public static func defaultPath() -> String { stateDir() + "/" + fileName }

    // MARK: 读写

    public static func read(at path: String) -> InstallManifest? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        var text = String(data: data, encoding: .utf8) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return InstallManifest(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    }

    /// 先找状态目录，再找二进制同目录兜底；都无则 nil。
    public static func find(binary: String) -> (path: String, manifest: InstallManifest)? {
        let state = defaultPath()
        if FileManager.default.fileExists(atPath: state), let manifest = read(at: state) {
            return (state, manifest)
        }
        let fallback = (binary as NSString).deletingLastPathComponent + "/" + fallbackName
        if FileManager.default.fileExists(atPath: fallback), let manifest = read(at: fallback) {
            return (fallback, manifest)
        }
        return nil
    }

    /// 只读状态目录里的记录（GUI 用：不关心兜底位置）。
    public static func current() -> (path: String, manifest: InstallManifest)? {
        let path = defaultPath()
        guard let manifest = read(at: path) else { return nil }
        return (path, manifest)
    }

    public func write(to path: String) throws {
        try serialized.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
