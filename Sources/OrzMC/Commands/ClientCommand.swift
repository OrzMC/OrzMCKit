import ConsoleKit
import Foundation
import Game

struct ClientCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Flag(name: "verbose", short: "d", help: Constants.DebugHelp.string)
        var debug: Bool

        @Flag(name: "auth", short: "a", help: Constants.clientAuthHelp.string)
        var authenticate: Bool

        @Option(name: "version", short: "v", help: Constants.VersionHelp.string)
        var version: String?

        @Option(name: "username", short: "u", help: Constants.clientUsernameHelp.string)
        var username: String?

        @Option(name: "min-mem", short: "m", help: Constants.clientMinMemHelp.string)
        var minMem: String?

        @Option(name: "max-mem", short: "x", help: Constants.clientMaxMemHelp.string)
        var maxMem: String?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = Constants.clientHelp.string

    func run(using context: CommandContext, signature: Signature) async throws {

        let console = context.console

        // 非 TTY / `--json`：不阻塞（B9 / 规范 §7）。
        let interactive = !options.json && TerminalEnvironment.isInteractive

        let debug = signature.debug || options.verbose

        // 正版授权（Microsoft 设备码流程）：结果贯穿 ClientInfo（用户名/令牌/uuid/user_type）。
        // 放在版本选择之前：缺 client_id 时快速失败，不触发网络/交互。
        var session: AuthSession?
        if signature.authenticate {
            let environment = ProcessInfo.processInfo.environment
            let clientId = (environment["ORZMC_AZURE_CLIENT_ID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clientId.isEmpty else {
                throw CLIError(
                    "未配置 Azure 应用 client_id(设置 ORZMC_AZURE_CLIENT_ID);见 docs/spec/auth.md",
                    code: "E_AUTH_NOT_CONFIGURED"
                )
            }
            do {
                session = try await authenticate(clientId: clientId) { device in
                    FileHandle.standardError.write(
                        Data("请在浏览器打开 \(device.verificationUri) 并输入代码 \(device.userCode)\n".utf8)
                    )
                }
            } catch let error as AuthError {
                throw CLIError(error.message, code: error.code)
            }
        }

        let version = try await console.chooseGameVersion(signature.version, interactive: interactive)

        // 非 TTY：用户名默认 guest，不阻塞（B9）。`--auth` 时不提示（认证后以档案用户名为准）。
        let username: String
        if signature.authenticate {
            username = signature.username ?? "guest"
        } else {
            username = signature.username ?? (interactive
                ? console.userInput(
                    hint: Constants.uiInputUsername.string,
                    completedHint: Constants.uiOutputUsername.string
                )
                : "guest")
        }
        let resolvedUsername = session?.name ?? username

        let minMem = signature.minMem ?? Constants.clientMinMemDefault
        let maxMem = signature.maxMem ?? Constants.clientMaxMemDefault

        // 参数收集完成
        let clientInfo = ClientInfo(
            version: version,
            username: resolvedUsername,
            rootDir: options.resolveRoot(signature.rootDir),
            debug: debug,
            authenticate: false,
            accessToken: session?.accessToken,
            authUUID: session?.uuid,
            userType: session != nil ? "msa" : "legacy",
            minMem: minMem,
            maxMem: maxMem,
            console: console
        )
        // 启动 Launcher
        var laucher = Launcher(clientInfo: clientInfo)
        let code = try await laucher.run()

        if options.json {
            var data: [String: Any] = ["version": version.id, "username": resolvedUsername, "exitCode": code]
            if let session {
                data["authenticated"] = true
                data["uuid"] = session.uuid
                data["expiresAt"] = session.expiresAt
                data["source"] = session.source
            }
            JSONOutput.success(command: "client", data: data)
        }
    }
}
