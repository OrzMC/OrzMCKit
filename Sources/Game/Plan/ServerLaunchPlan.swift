import Foundation

/// 服务端启动的**纯计划**（对齐 `docs/spec/behavior.md` B7 / `data-model.md` §10）。
///
/// 参数规范（与 Python `ServerService._build_server_command` 对齐，消除两语言漂移）：
/// `java <userJvm…> -Xms<min> -Xmx<max> -jar <jar> [nogui] <userServerArgs…> [--forceUpgrade]`
public struct ServerLaunchPlan: Sendable, Equatable {
    public let executable: String
    public let cwd: String
    public let jarPath: String
    public let jvmArgs: [String]
    public let serverArgs: [String]
}

/// 服务端启动选项（用户可指定；其余用规范默认）。
public struct ServerLaunchOptions: Sendable, Equatable {
    public var minMem: String
    public var maxMem: String
    public var jvmOpts: [String]
    public var userServerArgs: [String]
    public var nogui: Bool
    public var forceUpgrade: Bool

    public init(
        minMem: String = "512M",
        maxMem: String = "2G",
        jvmOpts: [String] = [],
        userServerArgs: [String] = [],
        nogui: Bool = false,
        forceUpgrade: Bool = false
    ) {
        self.minMem = minMem
        self.maxMem = maxMem
        self.jvmOpts = jvmOpts
        self.userServerArgs = userServerArgs
        self.nogui = nogui
        self.forceUpgrade = forceUpgrade
    }
}

public extension GamePlan {
    /// 纯函数：由（可执行/工作目录/jar 路径 + 选项）计算规范服务端启动计划。
    ///
    /// `jarPath` 由调用方给出（Paper 的 jar 名随构建而变，不等于规范 `serverJarName`）。
    static func planServerLaunch(
        executable: String,
        cwd: String,
        jarPath: String,
        options: ServerLaunchOptions
    ) -> ServerLaunchPlan {
        var jvmArgs = options.jvmOpts
        jvmArgs += ["-Xms\(options.minMem)", "-Xmx\(options.maxMem)"]

        var serverArgs: [String] = []
        if options.nogui && !options.userServerArgs.contains("nogui") {
            serverArgs.append("nogui")
        }
        serverArgs += options.userServerArgs
        if options.forceUpgrade && !serverArgs.contains("--forceUpgrade") {
            serverArgs.append("--forceUpgrade")
        }

        return ServerLaunchPlan(
            executable: executable,
            cwd: cwd,
            jarPath: jarPath,
            jvmArgs: jvmArgs,
            serverArgs: serverArgs
        )
    }
}
