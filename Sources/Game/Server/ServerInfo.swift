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

    public init(
        version: String,
        rootDir: String = GamePlan.defaultRoot,
        gui: Bool,
        debug: Bool,
        forceUpgrade: Bool,
        demo: Bool,
        minMem: String,
        maxMem: String,
        jvmArgs: [String] = [],
        onlineMode: Bool,
        showJarHelpInfo: Bool,
        jarOptions: String? = nil,
        console: (any Console)? = nil
    ) {
        self.version = version
        self.rootDir = rootDir
        self.gui = gui
        self.debug = debug
        self.forceUpgrade = forceUpgrade
        self.demo = demo
        self.minMem = minMem
        self.maxMem = maxMem
        self.jvmArgs = jvmArgs
        self.onlineMode = onlineMode
        self.showJarHelpInfo = showJarHelpInfo
        self.jarOptions = jarOptions
        self.console = console
    }
}
