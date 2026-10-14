//
//  File.swift
//  
//
//  Created by wangzhizhou on 2022/1/12.
//

import MojangAPI
import JokerKits
import Utils
import Foundation

enum VanillaServerError: Error {
    case getServerInfoFailed
    case launchFailed
}

/// Vanilla 服务器
///
/// 启动命令示例:
/// ```bash
/// java -Xmx1024M -Xms1024M -jar minecraft_server.1.18.1.jar nogui
/// ```
///
/// 1. [官方部署服务器文档](https://www.minecraft.net/en-us/download/server)
/// 2. [部署服务器百科文档](https://minecraft.fandom.com/wiki/Tutorials/Setting_up_a_server)
///
/// 官方服务端文件下载速度太慢, 容易超时
public struct VanillaServer: Server {
    
    public let serverInfo: ServerInfo
    
    public init(serverInfo: ServerInfo) {
        self.serverInfo = serverInfo
    }
    

    /// 启动参考获取
    /// ```
    /// Starting net.minecraft.server.Main
    /// Option               Description
    /// ------               -----------
    /// --bonusChest
    /// --demo
    /// --eraseCache
    /// --forceUpgrade
    /// --help
    /// --initSettings       Initializes 'server.properties' and 'eula.txt', then quits
    /// --jfrProfile
    /// --nogui
    /// --pidFile <Path>
    /// --port <Integer>     (default: -1)
    /// --safeMode           Loads level with vanilla datapack only
    /// --serverId <String>
    /// --universe <String>  (default: .)
    /// --world <String>
    /// ```
    public func start() async throws -> ManagedProcess? {
        
        guard let version = try await Mojang.manifest().versions.filter({ $0.id == serverInfo.version }).first,
              let gameVersion = try await version.gameVersion,
              let serverVersionURL = URL(string: gameVersion.downloads.server.url)
        else {
            throw VanillaServerError.getServerInfoFailed
        }

        let serverJarFileName = serverVersionURL.lastPathComponent
        let serverJarFileDirPath = GameDir.server(version: serverInfo.version, type: GameType.vanilla.rawValue)
        let serverJarFilePath = serverJarFileDirPath.filePath(serverJarFileName)
        let serverJarFileURL = URL(fileURLWithPath: serverJarFilePath)
        let serverJarFileItem = DownloadItemInfo(sourceURL: serverVersionURL, dstFileURL: serverJarFileURL, hash: gameVersion.downloads.server.sha1, hashType: .sha1)
        
        let progressBar = self.serverInfo.console?.progressBar(title: "正在下载服务端文件")
        try await Downloader.download(serverJarFileItem, progressBar: progressBar)

        let major = Int(gameVersion.javaVersion?.majorVersion ?? Double(JavaRequirement.defaultMajor))
        let javaExecutable = try await JavaRuntime.ensure(root: GameDir.root, major: major)
        let process = try await launchServer(
            serverJarFilePath,
            workDirectory: serverJarFileDirPath,
            javaExecutable: javaExecutable
        )
        return process
    }
}
