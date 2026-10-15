//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation
import Fabric
import MojangAPI
import ConsoleKit

public struct ClientInfo: Sendable {
    public var version: Version
    public var username: String
    /// 游戏根目录（规范 §3 全局 `--root-dir`；默认 `~/minecraft`）。
    public var rootDir: String
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
    
    // Fabric
    var fabricModel: FabricModel?
    
    // Console
    let console: (any Console)?
    
    public init(
        version: Version,
        username: String,
        rootDir: String = GamePlan.defaultRoot,
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
        fabricModel: FabricModel? = nil,
        console: (any Console)? = nil
    ) {
        self.version = version
        self.username = username
        self.rootDir = rootDir
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
        self.fabricModel = fabricModel
        self.console = console
    }
}
