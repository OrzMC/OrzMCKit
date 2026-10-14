import ConsoleKit
import Foundation
import Game

/// `orzmc list`：列出已安装的版本（客户端 / 服务端类型）。
struct ListCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = "列出已安装的版本(客户端 / 服务端类型)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console
        let root = options.resolveRoot(signature.rootDir)
        let versions = GamePlan.installedVersions(root: root)

        let data: [String: Any] = [
            "versions": versions.map { item in
                [
                    "version": item.version,
                    "client": item.hasClient,
                    "servers": item.serverTypes.map(\.rawValue),
                ] as [String: Any]
            }
        ]
        if options.json {
            JSONOutput.success(command: "list", data: data)
            return
        }

        guard !versions.isEmpty else {
            console.output("尚未安装任何版本")
            return
        }
        console.output("已安装版本:")
        for item in versions {
            let client = item.hasClient ? "✓" : ""
            let servers = item.serverTypes.map(\.rawValue).joined(separator: ",")
            console.output("  \(item.version)  客户端 \(client)  服务端 \(servers)")
        }
    }
}
