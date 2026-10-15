import ConsoleKit
import Foundation
import Game

/// `orzmc self-uninstall`：卸载工具自身（删二进制 / 还原 PATH / 删补全；
/// 游戏数据默认保留；规范 `docs/spec/install-update.md` §9）。
struct SelfUninstallCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Flag(name: "yes", short: "y", help: "跳过确认(游戏数据默认保留)")
        var yes: Bool

        @Flag(name: "remove-root", help: "连游戏数据根目录(默认 ~/minecraft)一起删除")
        var removeRoot: Bool

        @Flag(name: "force", help: "绕过开发环境护栏")
        var force: Bool

        @Option(name: "root-dir", help: "游戏根目录(默认读取安装记录，否则 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = "卸载工具自身(删除二进制/PATH/补全;游戏数据默认保留)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let binary = InstallSupport.runningBinary()
        if !signature.force, InstallSupport.looksLikeDev(binary) {
            throw CLIError(
                "检测到疑似开发环境安装(.build/.swiftpm/DerivedData),已拒绝卸载;确认无误可加 --force 继续",
                code: "E_USAGE"
            )
        }

        let found = InstallManifest.find(binary: binary)
        let manifest = found?.manifest
        let targetBinary = manifest?.binary.isEmpty == false ? manifest!.binary : binary
        let rootDir = signature.rootDir ?? manifest?.rootDir ?? GamePlan.defaultRoot

        let interactive = !options.json && TerminalEnvironment.isInteractive
        if signature.removeRoot {
            try validateRoot(rootDir)
            if !signature.yes, interactive,
               !context.console.confirm("将删除游戏数据目录 \(rootDir)，确定继续?".consoleText(.error)) {
                throw CLIError("已取消卸载", code: "E_CANCELLED")
            }
        }

        let fileManager = FileManager.default
        var removed: [String] = []

        // 1) 还原 PATH（精确删记录的那一行）
        if let manifest, let pathFile = manifest.pathFile, let pathLine = manifest.pathLine,
           InstallSupport.removeLine(pathLine, from: pathFile) {
            removed.append("path")
        }
        // 2) 删除补全
        if let completionFile = manifest?.completionFile, fileManager.fileExists(atPath: completionFile) {
            try? fileManager.removeItem(atPath: completionFile)
            InstallSupport.pruneEmpty((completionFile as NSString).deletingLastPathComponent)
            removed.append("completion")
        }
        // 3) 删除安装记录
        if let found {
            try? fileManager.removeItem(atPath: found.path)
            InstallSupport.pruneEmpty((found.path as NSString).deletingLastPathComponent)
            removed.append("manifest")
        }
        // 4) 可选删除游戏数据
        if signature.removeRoot, fileManager.fileExists(atPath: rootDir) {
            try? fileManager.removeItem(atPath: rootDir)
            removed.append("root")
        }
        // 5) 删除二进制放最后（运行中不影响的文件系统语义）
        if fileManager.fileExists(atPath: targetBinary) {
            try? fileManager.removeItem(atPath: targetBinary)
            removed.append("binary")
        }
        InstallSupport.pruneEmpty((targetBinary as NSString).deletingLastPathComponent)

        if options.json {
            JSONOutput.success(command: "self-uninstall", data: ["uninstalled": true, "removed": removed])
        } else {
            context.console.success("已卸载 orzmc")
        }
    }

    /// 拒绝明显危险的根删除目标（规范 §9「只删自登记内容」）。
    private func validateRoot(_ rootDir: String) throws {
        let standardized = URL(fileURLWithPath: rootDir).standardizedFileURL.path
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        guard standardized != "/", standardized != home, standardized.split(separator: "/").count >= 2 else {
            throw CLIError("拒绝删除危险目录: \(standardized)", code: "E_USAGE")
        }
    }
}
