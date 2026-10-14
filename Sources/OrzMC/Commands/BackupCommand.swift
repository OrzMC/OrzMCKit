import ConsoleKit
import Foundation
import Game

/// `orzmc backup`：备份服务端世界到 `backup/worlds/`。
struct BackupCommand: AsyncCommand {

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
        let root = signature.rootDir ?? GamePlan.defaultRoot
        let type = signature.type.flatMap { GameType(rawValue: $0) } ?? .vanilla

        guard let version = signature.version ?? Self.inferVersion(root: root) else {
            console.error("没有已安装的服务端,请用 -v 指定版本")
            return
        }

        do {
            let dest = try GamePlan.backupWorld(version: version, type: type, root: root)
            console.success("备份完成: \(dest)")
        } catch {
            console.error("备份失败: \(error)")
        }
    }

    /// 缺省版本：取第一个已安装服务端的版本。
    private static func inferVersion(root: String) -> String? {
        GamePlan.installedVersions(root: root).first { !$0.serverTypes.isEmpty }?.version
    }
}
