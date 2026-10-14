import Foundation
import Game

/// 安装 / 卸载 / 升级的共用文件系统原语（规范 `docs/spec/install-update.md`）。
enum InstallSupport {
    /// 运行中的二进制路径（解析符号链接）。
    static func runningBinary() -> String {
        let arg0 = CommandLine.arguments.first ?? "orzmc"
        return URL(fileURLWithPath: arg0).resolvingSymlinksInPath().path
    }

    /// 疑似开发环境安装（拒绝自升级/自卸载，除非 `--force`）。
    static func looksLikeDev(_ binary: String) -> Bool {
        let parts = binary.split(separator: "/").map(String.init)
        return parts.contains(".build") || parts.contains(".swiftpm") || parts.contains("DerivedData")
    }

    /// 目录为空则删除（不递归，只 `rmdir` 空目录；规范 §9「只删自登记内容」）。
    static func pruneEmpty(_ directory: String, fileManager: FileManager = .default) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory), contents.isEmpty else { return }
        try? fileManager.removeItem(atPath: directory)
    }

    /// 从 rc 文件删除**精确的一行**；返回是否确有删除（绝不正则，规范 §4）。
    static func removeLine(_ line: String, from path: String) -> Bool {
        guard let existing = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let index = lines.firstIndex(of: line) else { return false }
        lines.remove(at: index)
        var joined = lines.joined(separator: "\n")
        if existing.hasSuffix("\n") { joined += "\n" }
        return (try? joined.write(toFile: path, atomically: true, encoding: .utf8)) != nil
    }
}
