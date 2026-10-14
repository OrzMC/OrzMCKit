import ConsoleKit
import Foundation
import Game

/// `orzmc backup`：备份服务端世界到 `backup/worlds/`。
struct BackupCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Option(name: "version", short: "v", help: "要备份的版本(缺省自动推断)")
        var version: String?

        @Option(name: "type", short: "t", help: "服务端类型")
        var type: String?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = "备份服务端世界到 backup/worlds/"

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console
        let root = options.resolveRoot(signature.rootDir)
        let type = signature.type.flatMap { GameType(rawValue: $0) } ?? .vanilla

        guard let version = signature.version ?? Self.inferVersion(root: root) else {
            throw CLIError("没有已安装的服务端,请用 -v 指定版本", code: "E_USAGE")
        }

        let dest = try GamePlan.backupWorld(version: version, type: type, root: root)
        if options.json {
            JSONOutput.success(
                command: "backup",
                data: ["version": version, "type": type.rawValue, "destination": dest]
            )
        } else {
            console.success("备份完成: \(dest)")
        }
    }

    /// 缺省版本：取第一个已安装服务端的版本。
    private static func inferVersion(root: String) -> String? {
        GamePlan.installedVersions(root: root).first { !$0.serverTypes.isEmpty }?.version
    }
}
