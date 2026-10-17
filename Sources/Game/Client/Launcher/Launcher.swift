//
//  Launcher.swift
//  
//
//  Created by joker on 2022/1/3.
//

/// Minecraft 客户端启动器
///
/// [写启动器参考文章](https://wiki.vg/Game_files)
///
/// [启动器Wiki](https://minecraft.fandom.com/zh/wiki/教程/编写启动器)

import JokerKits
import Utils

public struct Launcher: Client {
    
    /// 客户端启动器启动参数相关
    public var clientInfo: ClientInfo
    
    public init(clientInfo: ClientInfo) {
        self.clientInfo = clientInfo
    }
        
    /// 客户端启动（协议要求，退出码丢弃；CLI 用 `run()`）。
    mutating public func start() async throws {
        _ = try await self.run()
    }

    /// 启动并前台等待退出，返回归一化退出码（CLI 用）。
    mutating public func run() async throws -> Int {
        
        // 选择启动的方式（仅 vanilla 走 launcher_profiles 机制；fabric 由 fabric-meta 解析）
        if clientInfo.type == .vanilla {
            try self.chooseProfile()
        }
        
        // 正版验证
        try await self.authenticate()
        
        // 下载启动器启动所需要的文件、资源及依赖
        try await self.download()
        
        // 下载Fabric相关的库
        try await self.downloadFabric()
        
        // 分析参数并启动客户端
        return try await self.launch()
    }
    
    /// 授权验证：CLI `--auth` 已在命令层完成（会话已注入 `accessToken`），此时跳过；
    /// 其余情况走 legacy `auth()`（当前禁用，恒返回 false）。
    mutating func authenticate() async throws {
        guard clientInfo.accessToken == nil else { return }
        guard try await auth()
        else {
            return
        }
        self.clientInfo.console?.success("验证账号密码为正版用户")
    }
    
    /// 启动客户端（前台等待退出），返回归一化退出码（B7）。
    mutating func launch() async throws -> Int {
        self.clientInfo.console?.success("客户端正在启动，请稍等......")
        guard let process = try await launchClient() else {
            return 0
        }
        let console = clientInfo.console
        let code = Int(await process.waitForExit())
        if code == 0 {
            console?.success("客户端正常")
        } else {
            console?.error("客户端异常退出（exit=\(code)）")
        }
        return code
    }
    
    /// 下载启动器启动需要的文件（共用引擎 `downloadClient`；Phase 4）。
    func download() async throws {
        try await downloadClient()
    }
    
    /// 下载Fabric客户端相关文件（库落到客户端 `libraries/`）
    mutating func downloadFabric() async throws {
        guard let downloadItemInfos = fabricDownloadItems() else {
            return
        }
        let progress = ProgressReporter(console: clientInfo.console, title: "开始下载Fabric库文件")
        try await progress.tracking {
            try await Downloader.download(downloadItemInfos, onEvent: progress.update)
        }
        self.clientInfo.console?.success("下载Fabric库文件完成")
    }
    
    /// 选择客户端启动方式
    mutating func chooseProfile() throws  {
        let menuItems = try launcherProfileItems()
        var chooseItem = menuItems.first
        if menuItems.count > 1 {
            chooseItem = self.clientInfo.console?.choose("选择启动方式：".consoleText(.success), from: menuItems)
        }
        guard let chooseItem = chooseItem else {
            return
        }
        self.clientInfo.console?.success("启动：", newLine: false)
        self.clientInfo.console?.output(chooseItem.consoleText(.info))
        try selectedProfile(chooseItem)
    }
}
