//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation
import MojangAPI
import ConsoleKit

public struct ClientInfo: Sendable {
    public var version: Version
    public var username: String
    /// 游戏根目录（规范 §3 全局 `--root-dir`；默认 `~/minecraft`）。
    public var rootDir: String
    /// 客户端类型（`vanilla` / `fabric`；`forge` 待实现）。
    public var type: GameType
    var debug: Bool
    var authenticate: Bool
    var launcherProfile: LauncherProfile?
    
    // 正版授权
    var accountName: String?
    var accountPassword: String?
    var accessToken: String?
    var clientToken: String?

    /// 正版授权结果（`--auth`）：档案 UUID 与登录类型；离线时 nil / `legacy`。
    var authUUID: String?
    var userType: String
    
    // JVM启动内存占用参数
    var minMem: String
    var maxMem: String
    /// 用户附加 JVM 旗标（`--jvm-opts`，空格分隔已拆分为数组）。
    var jvmArgs: [String]
    
    /// 可选客户端附加组件（Fabric 等）：额外库 / 启动参数 / 主类覆盖。
    var addon: ProfileAddon?
    
    // Console
    let console: (any Console)?

    /// 客户端**运行期日志**观察者（stdout + stderr 合流，按块回调）。
    ///
    /// 无控制台的前端（GUI）用它显示客户端控制台；CLI 为 `nil`（终端自己就是控制台）。
    /// 与 `ServerInfo.onServerLog` 对称。
    public var onClientLog: (@Sendable (String) -> Void)?
    
    public init(
        version: Version,
        username: String,
        rootDir: String = GamePlan.defaultRoot,
        type: GameType = .vanilla,
        debug: Bool = false,
        authenticate: Bool = false,
        launcherProfile: LauncherProfile? = nil,
        accountName: String? = nil,
        accountPassword: String? = nil,
        accessToken: String? = nil,
        clientToken: String? = nil,
        authUUID: String? = nil,
        userType: String = "legacy",
        minMem: String,
        maxMem: String,
        jvmArgs: [String] = [],
        addon: ProfileAddon? = nil,
        console: (any Console)? = nil,
        onClientLog: (@Sendable (String) -> Void)? = nil
    ) {
        self.version = version
        self.username = username
        self.rootDir = rootDir
        self.type = type
        self.debug = debug
        self.authenticate = authenticate
        self.launcherProfile = launcherProfile
        self.accountName = accountName
        self.accountPassword = accountPassword
        self.accessToken = accessToken
        self.clientToken = clientToken
        self.authUUID = authUUID
        self.userType = userType
        self.minMem = minMem
        self.maxMem = maxMem
        self.jvmArgs = jvmArgs
        self.addon = addon
        self.console = console
        self.onClientLog = onClientLog
    }
}
