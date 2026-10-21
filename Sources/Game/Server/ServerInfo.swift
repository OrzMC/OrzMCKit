//
//  File.swift
//  
//
//  Created by wangzhizhou on 2022/1/13.
//

import Foundation
import ConsoleKit

public struct ServerInfo: Sendable {
    public let version: String
    /// 游戏根目录（规范 §3 全局 `--root-dir`；默认 `~/minecraft`）。
    public var rootDir: String
    let gui: Bool
    let debug: Bool
    let forceUpgrade: Bool
    let demo: Bool
    /// 启动前将 `world` 软链接到 `backup/worlds/<version>`（规范 `server --symlink`）。
    var symlinkWorld: Bool
    /// 强制重新下载服务端核心 jar（规范 `server --force-download`）。
    var forceDownload: Bool
    /// 忽略元数据缓存（规范 `server --refresh`；Fabric/Forge 解析安装器与 loader 时生效）。
    var refresh: Bool

    // JVM启动内存占用参数
    var minMem: String
    var maxMem: String
    var jvmArgs: [String]
    
    // 服务端参数
    public var onlineMode: Bool // 是否以online模式运行服务端
    var showJarHelpInfo: Bool // 显示服务端Jar包帮助信息
    
    // Jar包对应的参数
    var jarOptions: String?
    
    // Console
    let console: (any Console)?

    /// 前端进度观察者：无 ConsoleKit 控制台的前端（GUI）用它接收结构化进度；
    /// CLI 为 `nil`，行为与此前一致。
    public var onProgress: (@Sendable (LaunchProgress) -> Void)?

    /// 让服务端进程**继承前端自己的 stdin**（终端场景）。
    ///
    /// - CLI（`orzmc server`）设 `true`：用户在终端里打字，输入直达服务端控制台
    ///   （与 Python 侧 `subprocess.Popen` 不传 `stdin=` 的语义一致）；
    /// - GUI 设 `false`：GUI 用 `ManagedProcess.send(_:)` 显式往管道写命令。
    public var inheritStandardInput: Bool

    /// 服务端**运行期日志**观察者（stdout + stderr 合流，按块回调）。
    ///
    /// 无控制台的前端（GUI）用它显示服务端控制台；CLI 为 `nil`（终端自己就是控制台）。
    /// 与 `onProgress` 分工：`onProgress` 是**下载/安装**阶段的结构化进度，
    /// 这里是**进程跑起来之后**的原始输出（含用户命令的回应）。
    public var onServerLog: (@Sendable (String) -> Void)?

    public init(
        version: String,
        rootDir: String = GamePlan.defaultRoot,
        gui: Bool,
        debug: Bool,
        forceUpgrade: Bool,
        demo: Bool,
        symlinkWorld: Bool = false,
        forceDownload: Bool = false,
        refresh: Bool = false,
        minMem: String,
        maxMem: String,
        jvmArgs: [String] = [],
        onlineMode: Bool,
        showJarHelpInfo: Bool,
        jarOptions: String? = nil,
        console: (any Console)? = nil,
        onProgress: (@Sendable (LaunchProgress) -> Void)? = nil,
        onServerLog: (@Sendable (String) -> Void)? = nil,
        inheritStandardInput: Bool = false
    ) {
        self.version = version
        self.rootDir = rootDir
        self.gui = gui
        self.debug = debug
        self.forceUpgrade = forceUpgrade
        self.demo = demo
        self.symlinkWorld = symlinkWorld
        self.forceDownload = forceDownload
        self.refresh = refresh
        self.minMem = minMem
        self.maxMem = maxMem
        self.jvmArgs = jvmArgs
        self.onlineMode = onlineMode
        self.showJarHelpInfo = showJarHelpInfo
        self.jarOptions = jarOptions
        self.console = console
        self.onProgress = onProgress
        self.onServerLog = onServerLog
        self.inheritStandardInput = inheritStandardInput
    }
}
