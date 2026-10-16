import ConsoleKit
import JokerKits
import Game

struct ServerCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Flag(name: "verbose", short: "d", help: Constants.DebugHelp.string)
        var debug: Bool

        @Flag(name: "nogui", short: "g", help: Constants.serverGUIHelp.string)
        var nogui: Bool

        @Flag(name: "force-upgrade", short: "f", help: Constants.serverForceUpgradeHelp.string)
        var forceUpgrade: Bool

        @Option(name: "type", short: "t", help: Constants.serverTypeHelp.string)
        var type: String?

        @Option(name: "version", short: "v", help: Constants.VersionHelp.string)
        var version: String?

        @Option(name: "min-mem", short: "m", help: Constants.serverMinMemHelp.string)
        var minMem: String?

        @Option(name: "max-mem", short: "x", help: Constants.serverMaxMemHelp.string)
        var maxMem: String?

        @Option(name: "jvm-opts", help: "附加 JVM 旗标(空格分隔)")
        var jvmOpts: String?

        @Flag(name: "online-mode", short: "o", help: Constants.serverOnlineModeHelp.string)
        var onlineMode: Bool

        @Flag(name: "yes", short: "y", help: "跳过确认(服务端默认自动接受 EULA;此旗标为命令面兼容)")
        var yes: Bool

        @Flag(name: "print-jar-help", short: "j", help: Constants.serverJarHelp.string)
        var jarHelp: Bool

        @Option(name: "server-args", short: "e", help: Constants.serverJarOptionHelp.string)
        var jarOpts: String?

        @Flag(name: "demo", help: Constants.serverDemoModeHelp.string)
        var demo: Bool

        @Flag(name: "kill-all", short: "k", help: Constants.serverKillAllHelp.string)
        var killAll: Bool

        @Flag(name: "refresh", help: "忽略元数据缓存(默认 24 小时内复用)")
        var refresh: Bool

        @Flag(name: "symlink", help: "软链接到备份世界(backup/worlds/<version>)")
        var symlink: Bool

        @Flag(name: "force-download", help: "强制重新下载服务端核心")
        var forceDownload: Bool

        @Option(name: "download-threads", short: "j", help: "下载并发数(1-64；缺省用引擎默认)")
        var downloadThreads: Int?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = Constants.serverHelp.string

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console

        if signature.killAll {
            let stopped = try await Shell.stopAll()
            if options.json {
                JSONOutput.success(command: "server", data: ["mode": "kill-all", "stopped": stopped])
            }
            return
        }

        let interactive = !options.json && TerminalEnvironment.isInteractive

        if let threads = signature.downloadThreads {
            Downloader.concurrency = min(max(threads, 1), 64)
        }
        let version = try await console.chooseGameVersion(signature.version, interactive: interactive, refresh: signature.refresh, root: options.resolveRoot(signature.rootDir))

        // `--nogui` 默认 false = 弹 GUI（对齐规范/Python）；给定时 headless。
        let gui = !signature.nogui
        let debug = signature.debug || options.verbose
        let minMem = signature.minMem ?? Constants.serverMinMemDefault
        let maxMem = signature.maxMem ?? Constants.serverMaxMemDefault
        let onlineMode = signature.onlineMode
        let forceUpgrade = signature.forceUpgrade
        let demo = signature.demo
        let jarHelp = signature.jarHelp
        let jarOpts = signature.jarOpts
        let jvmArgs = (signature.jvmOpts ?? "").split(separator: " ").map(String.init)

        let resolvedType = try Self.resolveType(signature.type)
        console.success(Constants.uiOutputServerType.string + resolvedType.rawValue)

        let serverInfo = ServerInfo(
            version: version.id,
            rootDir: options.resolveRoot(signature.rootDir),
            gui: gui,
            debug: debug,
            forceUpgrade: forceUpgrade,
            demo: demo,
            symlinkWorld: signature.symlink,
            forceDownload: signature.forceDownload,
            minMem: minMem,
            maxMem: maxMem,
            jvmArgs: jvmArgs,
            onlineMode: onlineMode,
            showJarHelpInfo: jarHelp,
            jarOptions: jarOpts,
            console: console
        )

        let code: Int
        switch resolvedType {
        case .paper:
            code = try await runForeground(PaperServer(serverInfo: serverInfo), console: console)
        case .vanilla:
            code = try await runForeground(VanillaServer(serverInfo: serverInfo), console: console)
        case .fabric, .forge:
            // 显式不支持，不静默（对齐 docs/spec/behavior.md：不支持的类型须明确提示）。
            throw CLIError("暂未支持的服务端类型: \(resolvedType.rawValue)", code: "E_UNSUPPORTED")
        }

        if options.json {
            JSONOutput.success(
                command: "server",
                data: ["version": version.id, "type": resolvedType.rawValue, "exitCode": code]
            )
        }
    }

    /// 服务端类型：缺省 `vanilla`（规范 §4.2 已决，与 Python 一致）。
    private static func resolveType(_ raw: String?) throws -> GameType {
        guard let type = GameType(rawValue: raw ?? GameType.vanilla.rawValue) else {
            throw CLIError("未知的服务端类型: \(raw ?? "")", code: "E_USAGE")
        }
        return type
    }

    /// 前台运行服务端并等待退出，返回其归一化退出码（B7）。
    private func runForeground(_ server: some Server, console: any Console) async throws -> Int {
        guard let process = try await server.start() else { return 0 }
        let code = Int(await process.waitForExit())
        console.success("服务端已退出（exit=\(code)）")
        return code
    }
}
