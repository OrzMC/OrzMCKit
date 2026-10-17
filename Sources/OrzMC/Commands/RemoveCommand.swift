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

        var type: GameType?
        if signature.server {
            guard let raw = signature.type, let parsed = GameType(rawValue: raw) else {
                throw CLIError("移除服务端需要指定类型 (-t vanilla|paper|fabric|forge)", code: "E_USAGE")
            }
            type = parsed
        }

        // 顺序与 Python 一致：先判「目标是否存在」(E_NOT_FOUND)，再判「是否已同意」(E_CANCELLED)。
        // 反过来会让「脚本忘了 --yes、而版本本来就不存在」报成取消，信息量更差。
        guard Self.exists(version: version, server: signature.server, type: type, root: root) else {
            throw CLIError("未找到要移除的版本: \(version)", code: "E_NOT_FOUND")
        }

        // 规范 §7 / B9：破坏性操作在**非 TTY**下必须显式 `--yes`，否则取消（130）。
        // 注意 `--yes` 会被 ConsoleKit 的全局签名消费（`confirmOverride`），子命令自己
        // 也声明了一份以保持命令面（capabilities / manifest）一致 —— 两处都算同意。
        let interactive = !options.json && TerminalEnvironment.isInteractive
        let consented = signature.yes || console.confirmOverride == true
        if !interactive, !consented {
            throw CLIError("非交互环境移除需要显式 --yes", code: "E_CANCELLED")
        }
        if interactive, !consented,
           !console.confirm("移除 \(version)?".consoleText(.warning)) {
            throw CLIError("已取消移除", code: "E_CANCELLED")
        }

        guard GamePlan.removeInstalled(version: version, server: signature.server, type: type, root: root) else {
            throw CLIError("未找到要移除的版本: \(version)", code: "E_NOT_FOUND")
        }

        if options.json {
            JSONOutput.success(command: "remove", data: ["version": version, "removed": true])
        } else {
            console.success("已移除 \(version)")
        }
    }

    /// 目标是否已安装（只看存在性，不动文件）；用于在要求 `--yes` 之前先报 `E_NOT_FOUND`。
    static func exists(version: String, server: Bool, type: GameType?, root: String) -> Bool {
        GamePlan.installedVersions(root: root).contains { entry in
            guard entry.version == version else { return false }
            if server {
                guard let type else { return false }
                return entry.serverTypes.contains(type)
            }
            return entry.hasClient
        }
    }
}
