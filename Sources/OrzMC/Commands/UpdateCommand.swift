import ConsoleKit
import Foundation
import Game

/// `orzmc update`：升级**工具自身**（非游戏版本；规范 `docs/spec/install-update.md` §6）。
struct UpdateCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Option(name: "version", short: "v", help: "升级到指定版本(如 0.1.0 / v0.1.0);缺省用最新 release")
        var version: String?

        @Flag(name: "check", help: "只检查是否有新版本,不下载")
        var check: Bool

        @Option(name: "file", help: "用本地二进制升级(需同时 --version;离线/测试接缝)")
        var file: String?

        @Flag(name: "yes", short: "y", help: "跳过升级确认")
        var yes: Bool

        @Flag(name: "force", help: "绕过开发环境护栏")
        var force: Bool

        @Option(name: "channel", help: "release(默认)|beta")
        var channel: String?
    }

    var help: String = "升级工具自身(非游戏版本)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let binary = InstallSupport.runningBinary()
        let channel = (signature.channel ?? "release").lowercased()
        guard channel == "release" || channel == "beta" else {
            throw CLIError("未知渠道: \(channel)(可选 release、beta)", code: "E_USAGE")
        }
        if signature.file != nil && signature.version == nil {
            throw CLIError("使用本地文件升级时必须同时指定版本: orzmc update --file <路径> --version vX.Y.Z", code: "E_USAGE")
        }

        let target = try await SelfUpdate.resolve(version: signature.version, channel: channel)

        if signature.check {
            emitCheck(context, target)
            return
        }

        if signature.version == nil && signature.file == nil && !target.available {
            if options.json {
                JSONOutput.success(
                    command: "update",
                    data: ["mode": "check", "current": target.current, "latest": target.latest, "available": false]
                )
            } else {
                context.console.print("已是最新版本 \(target.current)")
            }
            return
        }

        // 只在真正升级前拦住开发环境（`--check` 无副作用，允许）。
        if !signature.force, InstallSupport.looksLikeDev(binary) {
            throw CLIError(
                "检测到疑似开发环境安装(.build/.swiftpm/DerivedData),已拒绝自升级;确认无误可加 --force 继续",
                code: "E_USAGE"
            )
        }

        let interactive = !options.json && TerminalEnvironment.isInteractive
        if !signature.yes, interactive,
           !context.console.confirm("升级 orzmc \(target.current) → \(target.latest)?".consoleText(.warning)) {
            throw CLIError("已取消升级", code: "E_CANCELLED")
        }

        let staged = try await SelfUpdate.stage(target: target, file: signature.file, binary: binary)
        let log = try SelfUpdate.handoff(staged: staged, binary: binary)
        SelfUpdate.record(target: target, binary: binary, fromFile: signature.file != nil)

        if options.json {
            JSONOutput.success(
                command: "update",
                data: [
                    "mode": "update", "current": target.current, "latest": target.latest,
                    "asset": target.asset, "applied": true,
                ]
            )
        } else {
            context.console.success("已升级到 \(target.latest)(本命令退出后生效)")
            context.console.print("升级助手日志: \(log)")
        }
    }

    private func emitCheck(_ context: CommandContext, _ target: SelfUpdate.Target) {
        if options.json {
            JSONOutput.success(
                command: "update",
                data: [
                    "mode": "check", "current": target.current, "latest": target.latest,
                    "available": target.available,
                ]
            )
        } else {
            context.console.print("当前版本: \(target.current)")
            context.console.print("最新版本: \(target.latest)")
            if target.available {
                context.console.warning("有新版本可用: orzmc update")
            } else {
                context.console.success("已是最新版本")
            }
        }
    }
}
