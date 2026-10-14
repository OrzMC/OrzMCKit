import ConsoleKit
import Game

struct ClientCommand: AsyncCommand {
    
    struct Signature: CommandSignature {
        @Flag(name: "debug", short: "d", help: Constants.DebugHelp.string)
        var debug: Bool
        
        @Flag(name: "auth", short: "a", help: Constants.clientAuthHelp.string)
        var authenticate: Bool
        
        @Option(name: "version", short: "v", help: Constants.VersionHelp.string)
        var version: String?
        
        @Option(name: "username", short: "u", help: Constants.clientUsernameHelp.string)
        var username: String?
        
        @Option(name: "ms", short: "s", help: Constants.clientMinMemHelp.string)
        var minMem: String?
        
        @Option(name: "mx", short: "x", help: Constants.clientMaxMemHelp.string)
        var maxMem: String?
    }
    
    var help: String = Constants.clientHelp.string
    
    func run(using context: CommandContext, signature: Signature) async throws {
        
        let console = context.console
        
        let version = try await console.chooseGameVersion(signature.version)
        
        // 非 TTY：用户名默认 guest，不阻塞（B9）。
        let username = signature.username ?? (Terminal.isInteractive
            ? console.userInput(
                hint: Constants.uiInputUsername.string,
                completedHint: Constants.uiOutputUsername.string
            )
            : "guest")
        
        let debug = signature.debug
        
        // 显示指定是否进行正版授权
        var accountName: String? = nil
        if signature.authenticate && Terminal.isInteractive {
            accountName = console.userInput(hint: Constants.uiInputAuthAccount.string)
            if let accountName = accountName, accountName.count > 0 {
                console.output(Constants.uiOutputAuthAccount.string.consoleText(.success) + accountName.consoleText(.info))
                let accountPassword = console.userInput(hint: Constants.uiInputAuthPassword.string)
                if accountPassword.count > 0 {
                    let secureText = String(repeating: Constants.uiOutputPasswordMask.string, count: accountPassword.count)
                    console.output(Constants.uiOutputAuthPassword.string.consoleText(.success) + secureText.consoleText(.info))
                }
            }
        }
        // ---
        
        let minMem = signature.minMem ?? Constants.clientMinMemDefault
        let maxMem = signature.maxMem ?? Constants.clientMaxMemDefault
        
        // 参数收集完成
        let clientInfo = ClientInfo(
            version: version,
            username: username,
            debug: debug,
            authenticate: signature.authenticate,
            accountName: accountName,
            minMem: minMem,
            maxMem: maxMem,
            console: console
        )
        // 启动 Launcher
        var laucher = Launcher(clientInfo: clientInfo)
        try await laucher.start()
    }
}
