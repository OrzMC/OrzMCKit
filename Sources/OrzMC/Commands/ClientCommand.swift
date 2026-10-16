import ConsoleKit
import Foundation
import Game
import JokerKits

struct ClientCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {
        @Flag(name: "verbose", short: "d", help: Constants.DebugHelp.string)
        var debug: Bool

        @Flag(name: "auth", short: "a", help: Constants.clientAuthHelp.string)
        var authenticate: Bool

        @Option(name: "version", short: "v", help: Constants.VersionHelp.string)
        var version: String?

        @Option(name: "type", short: "t", help: Constants.clientTypeHelp.string)
        var type: String?

        @Option(name: "username", short: "u", help: Constants.clientUsernameHelp.string)
        var username: String?

        @Option(name: "min-mem", short: "m", help: Constants.clientMinMemHelp.string)
        var minMem: String?

        @Option(name: "max-mem", short: "x", help: Constants.clientMaxMemHelp.string)
        var maxMem: String?

        @Option(name: "jvm-opts", help: "附加 JVM 旗标(空格分隔)")
        var jvmOpts: String?

        @Flag(name: "refresh", help: "忽略元数据缓存(默认 24 小时内复用)")
        var refresh: Bool

        @Flag(name: "extract-music", help: "提取客户端音乐后退出")
        var extractMusic: Bool

        @Option(name: "download-threads", short: "j", help: "下载并发数(1-64；缺省用引擎默认)")
        var downloadThreads: Int?

        @Option(name: "root-dir", help: "游戏根目录(默认 ~/minecraft)")
        var rootDir: String?
    }

    var help: String = Constants.clientHelp.string

    func run(using context: CommandContext, signature: Signature) async throws {

        let console = context.console

        // 非 TTY / `--json`：不阻塞（B9 / 规范 §7）。
        let interactive = !options.json && TerminalEnvironment.isInteractive

        if let threads = signature.downloadThreads {
            Downloader.concurrency = min(max(threads, 1), 64)
        }

        let debug = signature.debug || options.verbose

        let resolvedType = try Self.resolveType(signature.type)

        // 正版授权（Microsoft 设备码流程）：结果贯穿 ClientInfo（用户名/令牌/uuid/user_type）。
        // 放在版本选择之前：缺 client_id 时快速失败，不触发网络/交互。
        var session: AuthSession?
        if signature.authenticate {
            let clientId = AuthConfig.clientId()
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

        let version = try await console.chooseGameVersion(signature.version, interactive: interactive, refresh: signature.refresh, root: options.resolveRoot(signature.rootDir))

        // 客户端附加组件（Fabric / Forge）：经对应元数据源解析（提取音乐不需要）。
        var addon: ProfileAddon?
        if !signature.extractMusic, resolvedType == .fabric || resolvedType == .forge {
            do {
                switch resolvedType {
                case .fabric:
                    addon = try await FabricMeta.resolve(
                        version: version.id,
                        root: options.resolveRoot(signature.rootDir),
                        refresh: signature.refresh
                    )
                case .forge:
                    addon = try await ForgeMeta.resolve(
                        version: version.id,
                        root: options.resolveRoot(signature.rootDir),
                        refresh: signature.refresh
                    )
                default:
                    break
                }
            } catch let error as ForgeMetaError {
                throw CLIError(error.description, code: error.code)
            } catch {
                throw CLIError("\(error)", code: "E_NETWORK")
            }
        }

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
        let jvmArgs = (signature.jvmOpts ?? "").split(separator: " ").map(String.init)

        // 参数收集完成
        let clientInfo = ClientInfo(
            version: version,
            username: resolvedUsername,
            rootDir: options.resolveRoot(signature.rootDir),
            type: resolvedType,
            debug: debug,
            authenticate: false,
            accessToken: session?.accessToken,
            authUUID: session?.uuid,
            userType: session != nil ? "msa" : "legacy",
            minMem: minMem,
            maxMem: maxMem,
            jvmArgs: jvmArgs,
            addon: addon,
            console: console
        )
        // 提取音乐：只确保客户端 jar，解压 .ogg 后退出（不启动）。
        if signature.extractMusic {
            let count = try await Launcher(clientInfo: clientInfo).extractMusic()
            if options.json {
                JSONOutput.success(
                    command: "client",
                    data: ["version": version.id, "type": resolvedType.rawValue, "mode": "extract-music", "count": count]
                )
            }
            return
        }
        // 启动 Launcher
        var laucher = Launcher(clientInfo: clientInfo)
        let code = try await laucher.run()

        if options.json {
            var data: [String: Any] = ["version": version.id, "username": resolvedUsername, "type": resolvedType.rawValue, "exitCode": code]
            if let session {
                data["authenticated"] = true
                data["uuid"] = session.uuid
                data["expiresAt"] = session.expiresAt
                data["source"] = session.source
            }
            JSONOutput.success(command: "client", data: data)
        }
    }

    /// 客户端类型：缺省 `vanilla`；`paper` 无客户端（`vanilla/fabric/forge` 均为客户端类型）。
    private static func resolveType(_ raw: String?) throws -> GameType {
        guard let type = GameType(rawValue: raw ?? GameType.vanilla.rawValue) else {
            throw CLIError("未知的客户端类型: \(raw ?? "")", code: "E_USAGE")
        }
        guard type.isClientCapable else {
            throw CLIError("类型 \(type.rawValue) 不能用于客户端", code: "E_UNSUPPORTED_TYPE")
        }
        return type
    }
}
