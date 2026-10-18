import ConsoleKit
import Foundation
import Game

/// `orzmc app`：跨面安装 / 打开 / 卸载 GUI 应用（规范 `docs/spec/install-update.md` §8）。
struct AppCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Argument(name: "action", help: "install|open|uninstall|status")
        var action: String

        @Option(name: "channel", help: "release(默认)|appstore")
        var channel: String?

        @Option(name: "version", short: "v", help: "指定应用版本(tag;缺省用最新发布)")
        var version: String?

        @Flag(name: "yes", short: "y", help: "跳过确认")
        var yes: Bool
    }

    var help: String = "跨面:安装 / 打开 / 卸载 GUI 应用"

    func run(using context: CommandContext, signature: Signature) async throws {
        #if os(macOS)
        let action = signature.action.lowercased()
        let channel = (signature.channel ?? "release").lowercased()
        guard channel == "release" || channel == "appstore" else {
            throw CLIError("未知渠道: \(channel)(可选 release、appstore)", code: "E_USAGE")
        }
        switch action {
        case "status":
            try status(context)
        case "open":
            try AppInstaller.open()
            emit(context, data: ["mode": "open", "path": AppInstaller.installedAppPath])
        case "install":
            try await install(context, channel: channel, version: signature.version, skipConfirm: signature.yes)
        case "uninstall":
            try uninstall(context, skipConfirm: signature.yes)
        default:
            throw CLIError("未知操作: \(action)(可选 install|open|uninstall|status)", code: "E_USAGE")
        }
        #else
        // 规范 §8：跨面安装的是 macOS `.app`；其它平台显式不支持（D8 跨平台时的诚实边界）。
        _ = signature
        throw CLIError("当前平台不支持 orzmc app(仅 macOS);请直接从 Release 下载", code: "E_UNSUPPORTED")
        #endif
    }

    #if os(macOS)
    private func status(_ context: CommandContext) throws {
        let installed = AppInstaller.isInstalled()
        let data: [String: Any] = [
            "installed": installed,
            "path": AppInstaller.installedAppPath,
            "version": installed ? (AppInstaller.installedVersion() ?? NSNull()) : NSNull(),
        ]
        if options.json {
            JSONOutput.success(command: "app", data: data)
            return
        }
        if installed {
            context.console.success("已安装: \(AppInstaller.installedAppPath)\(AppInstaller.installedVersion().map { "(\($0))" } ?? "")")
        } else {
            context.console.print("未安装 OrzMC 应用")
        }
    }

    private func install(
        _ context: CommandContext,
        channel: String,
        version: String?,
        skipConfirm: Bool
    ) async throws {
        if channel == "appstore" {
            // 上架前显式不支持（规范 §8/§10：能力不支持须显式报错）。
            throw CLIError("App Store 渠道尚未上架;请用 --channel release", code: "E_UNSUPPORTED")
        }
        let release = try await AppInstaller.resolve(version: version)
        let interactive = !options.json && TerminalEnvironment.isInteractive
        if !skipConfirm, interactive,
           !context.console.confirm("安装 OrzMC \(release.tag) 到 \(AppInstaller.applicationsDir())?".consoleText(.warning)) {
            throw CLIError("已取消安装", code: "E_CANCELLED")
        }
        let path = try await AppInstaller.install(release: release)
        if options.json {
            JSONOutput.success(command: "app", data: ["mode": "install", "version": release.tag, "path": path])
        } else {
            context.console.success("已安装 OrzMC \(release.tag): \(path)")
        }
    }

    private func uninstall(_ context: CommandContext, skipConfirm: Bool) throws {
        // 规范 §7：卸载是破坏性操作，非 TTY 必须显式 `--yes`。
        let interactive = !options.json && TerminalEnvironment.isInteractive
        let consented = skipConfirm || context.console.confirmOverride == true
        if !interactive, !consented {
            throw CLIError("非交互环境卸载需要显式 --yes", code: "E_CANCELLED")
        }
        if interactive, !consented,
           !context.console.confirm("卸载 OrzMC 应用 \(AppInstaller.installedAppPath)?".consoleText(.error)) {
            throw CLIError("已取消卸载", code: "E_CANCELLED")
        }
        let removed = try AppInstaller.uninstall()
        if options.json {
            JSONOutput.success(command: "app", data: ["mode": "uninstall", "removed": removed])
        } else if removed {
            context.console.success("已卸载 OrzMC 应用")
        } else {
            context.console.print("未安装 OrzMC 应用")
        }
    }

    private func emit(_ context: CommandContext, data: [String: Any]) {
        if options.json { JSONOutput.success(command: "app", data: data) }
    }
    #endif
}
