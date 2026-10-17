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
        onProgress: (@Sendable (LaunchProgress) -> Void)? = nil
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
    }
}
