//
//  File.swift
//
//
//  Created by joker on 2022/1/3.
//

import JokerKits
import Utils
import Foundation
import ConsoleKit
import DownloadAPI

enum PaperServerError: Error {
    case versionRespFailed
    case convertBuildStringFailed
    case buildRespFailed
    case applicationFailed
    case downloadURLFailed
}

public struct PaperServer: Server {

    public let serverInfo: ServerInfo

    public init(serverInfo: ServerInfo) {
        self.serverInfo = serverInfo
    }
    
    /// 启动参数获取
    /// ```
    /// Option                                  Description
    /// ------                                  -----------
    /// -?, --help                              Show the help
    /// -C, --commands-settings <File: Yml      File for command settings (default:
    ///   file>                                   commands.yml)
    /// -P, --plugins <File: Plugin directory>  Plugin directory to use (default:
    ///                                           plugins)
    /// -S, --spigot-settings <File: Yml file>  File for spigot settings (default:
    ///                                           spigot.yml)
    /// -W, --universe, --world-container, --   World container (default: .)
    ///   world-dir <File: Directory
    ///   containing worlds>
    /// --add-extra-plugin-jar, --add-plugin    Specify paths to extra plugin jars to
    ///   <File: Jar file>                        be loaded in addition to those in
    ///                                           the plugins folder. This argument
    ///                                           can be specified multiple times,
    ///                                           once for each extra plugin jar path.
    /// -b, --bukkit-settings <File: Yml file>  File for bukkit settings (default:
    ///                                           bukkit.yml)
    /// -c, --config <File: Properties file>    Properties file to use (default:
    ///                                           server.properties)
    /// -d, --date-format <SimpleDateFormat:    Format of the date to display in the
    ///   Log date format>                        console (for log entries)
    /// --demo                                  Demo mode
    /// --eraseCache                            Whether to force cache erase during
    ///                                           world upgrade
    /// --forceUpgrade                          Whether to force a world upgrade
    /// -h, --host, --server-ip <String:        Host to listen on
    ///   Hostname or IP>
    /// --initSettings                          Only create configuration files and
    ///                                           then exit
    /// --jfrProfile                            Enable JFR profiling
    /// --log-append <Boolean: Log append>      Whether to append to the log file
    ///                                           (default: true)
    /// --log-count <Integer: Log count>        Specified how many log files to cycle
    ///                                           through (default: 1)
    /// --log-limit <Integer: Max log size>     Limits the maximum size of the log
    ///                                           file (0 = unlimited) (default: 0)
    /// --log-pattern <String: Log filename>    Specfies the log filename pattern
    ///                                           (default: server.log)
    /// --log-strip-color                       Strips color codes from log file
    /// --noconsole                             Disables the console
    /// --nogui                                 Disables the graphical console
    /// --nojline                               Disables jline and emulates the
    ///                                           vanilla console
    /// -o, --online-mode <Boolean:             Whether to use online authentication
    ///   Authentication>
    /// -p, --port, --server-port <Integer:     Port to listen on
    ///   Port>
    /// --paper, --paper-settings <File: Yml    File for Paper settings (default:
    ///   file>                                   paper.yml)
    /// --paper-dir, --paper-settings-          Directory for Paper settings (default:
    ///   directory <File: Config directory>      config)
    /// --pidFile <Path>                        pid File
    /// -s, --max-players, --size <Integer:     Maximum amount of players
    ///   Server size>
    /// --safeMode                              Loads level with vanilla datapack only
    /// --server-name <String: Name>            Name of the server (default: Unknown
    ///                                           Server)
    /// --serverId <String>                     Server ID
    /// -v, --version                           Show the CraftBukkit Version
    /// -w, --level-name, --world <String:      World name
    ///   World name>
    /// ```
    public func start() async throws -> ManagedProcess? {

        let version = serverInfo.version
        let console = serverInfo.console
        let loadingBar = console?.loadingBar(title: "获最最新构建版本")
        loadingBar?.start()
        guard let (build, name, _, _, _) = try await client.latestBuildInfo(
            project: .paper,
            version: version
        )
        else {
            loadingBar?.fail()
            return nil
        }
        loadingBar?.succeed()
        console?.info(name)

        let workDirectory = GamePlan.serverDir(version: serverInfo.version, type: .paper, root: serverInfo.rootDir)
        let serverJarFileDirPath = workDirectory
        let dirURL = URL(filePath: serverJarFileDirPath)
        if !FileManager.default.fileExists(atPath: dirURL.path()) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        let jarFileURL = dirURL.appending(path: name)

        if serverInfo.forceDownload || !FileManager.default.fileExists(atPath: jarFileURL.path()) {
            let progressBar = console?.progressBar(title: "正在下载服务端文件")
            progressBar?.start()
            guard let (dataStream, total) = try await client.downloadBuild(
                project: DownloadAPIClient.Project.paper,
                version: version,
                build: build,
                bufferSize: 512 * 1024)
            else {
                progressBar?.fail()
                return nil
            }

            var jarData = Data()
            for try await byteChunkResult in dataStream {
                switch byteChunkResult {
                case .success(let byteChunk):
                    jarData.append(byteChunk)
                    let progress = Double(jarData.count) / Double(total)
                    progressBar?.activity.currentProgress = progress
                case .failure(let error):
                    throw error
                }
            }
            progressBar?.succeed()

            if !FileManager.default.fileExists(atPath: dirURL.path()) {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            }
            try jarData.write(to: jarFileURL, options: .atomic)
        }
        
        let major = await JavaRuntime.javaMajor(forMCVersion: version)
        let javaExecutable = try await JavaRuntime.ensure(root: serverInfo.rootDir, major: major)
        let process = try await launchServer(
            jarFileURL.path(),
            workDirectory: workDirectory,
            javaExecutable: javaExecutable,
            jarArgs: [
                "--online-mode=\(serverInfo.onlineMode ? "true" : "false")",
                "--nojline",
                "--noconsole"
            ]
        )
        return process
    }

    private let client = DownloadAPIClient()
}
