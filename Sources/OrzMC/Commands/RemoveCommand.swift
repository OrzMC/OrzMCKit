import ConsoleKit
import Foundation
import Game

/// `orzmc remove`：移除已安装的版本（客户端或某类型的服务端）。
struct RemoveCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Option(name: "version", short: "v", help: "要移除的 Minecraft 版本")
        var version: String?

        @Flag(name: "server", help: "移除服务端(默认移除客户端)")
        var server: Bool

        @Option(name: "type", short: "t", help: "服务端类型(移除服务端时必填)")
        var type: String?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?

        @Flag(name: "yes", short: "y", help: "跳过确认")
        var yes: Bool
    }

    var help: String = "移除已安装的版本(客户端或某类型的服务端)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console
        let root = options.resolveRoot(signature.rootDir)

        guard let version = signature.version else {
            throw CLIError("需要指定要移除的版本 (-v)", code: "E_USAGE")
        }

        let interactive = !options.json && TerminalEnvironment.isInteractive
        if !signature.yes, interactive,
           !console.confirm("移除 \(version)?".consoleText(.warning)) {
            throw CLIError("已取消移除", code: "E_CANCELLED")
        }

        var type: GameType?
        if signature.server {
            guard let raw = signature.type, let parsed = GameType(rawValue: raw) else {
                throw CLIError("移除服务端需要指定类型 (-t vanilla|paper|fabric|forge)", code: "E_USAGE")
            }
            type = parsed
        }

        let removed = GamePlan.removeInstalled(version: version, server: signature.server, type: type, root: root)
        guard removed else {
            throw CLIError("未找到要移除的版本: \(version)", code: "E_NOT_FOUND")
        }

        if options.json {
            JSONOutput.success(command: "remove", data: ["version": version, "removed": true])
        } else {
            console.success("已移除 \(version)")
        }
    }
}
