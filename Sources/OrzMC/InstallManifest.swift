import Foundation
import Game

/// 安装记录 `install.conf`（key=value 文本；规范 `docs/spec/install-update.md` §2/§3）。
///
/// 与 Python `InstallManifest` 同格式：`uninstall` 据它还原 PATH / 清理补全 /
/// 定位二进制；`update` 升级后回写 `version`。读取容忍 UTF-8 BOM。
struct InstallManifest: Sendable {
    static let fileName = "install.conf"
    /// 记录兜底位置：二进制同目录（规范 §3）。
    static let fallbackName = ".orzmc-manifest"

    var tool = "orzmc"
    var schema = 1
    var version = ""
    var platform = ""
    var installDir = ""
    var binary = ""
    var source: String?
    var pathFile: String?
    var pathLine: String?
    var rootDir: String
    var completionFile: String?

    init(rootDir: String = GamePlan.defaultRoot) {
        self.rootDir = rootDir
    }

    init(lines: [String]) {
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
    }

    var serialized: String {
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
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: 位置

    /// 状态目录 `${XDG_STATE_HOME:-$HOME/.local/state}/orzmc`。
    static func stateDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let base = environment["XDG_STATE_HOME"] ?? ((environment["HOME"] ?? NSHomeDirectory()) + "/.local/state")
        return base + "/orzmc"
    }

    static func defaultPath() -> String { stateDir() + "/" + fileName }

    // MARK: 读写

    static func read(at path: String) -> InstallManifest? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        var text = String(data: data, encoding: .utf8) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return InstallManifest(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    }

    /// 先找状态目录，再找二进制同目录兜底；都无则 nil。
    static func find(binary: String) -> (path: String, manifest: InstallManifest)? {
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

    func write(to path: String) throws {
        try serialized.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
