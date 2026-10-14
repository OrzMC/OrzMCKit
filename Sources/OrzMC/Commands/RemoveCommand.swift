import ConsoleKit
import Foundation
import Game

/// `orzmc remove`：移除已安装的版本（客户端或某类型的服务端）。
struct RemoveCommand: AsyncCommand {

    struct Signature: CommandSignature {
        @Option(name: "version", short: "v", help: "要移除的 Minecraft 版本")
        var version: String?

        @Flag(name: "server", help: "移除服务端(默认移除客户端)")
        var server: Bool

        @Option(name: "type", short: "t", help: "服务端类型(移除服务端时必填)")
        var type: String?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = "移除已安装的版本(客户端或某类型的服务端)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console
        let root = signature.rootDir ?? GamePlan.defaultRoot

        guard let version = signature.version else {
            console.error("需要指定要移除的版本 (-v)")
            return
        }

        var type: GameType?
        if signature.server {
            guard let raw = signature.type, let parsed = GameType(rawValue: raw) else {
                console.error("移除服务端需要指定类型 (-t vanilla|paper|fabric|forge)")
                return
            }
            type = parsed
        }

        let removed = GamePlan.removeInstalled(version: version, server: signature.server, type: type, root: root)
        if removed {
            console.success("已移除 \(version)")
        } else {
            console.error("未找到要移除的版本: \(version)")
        }
    }
}
