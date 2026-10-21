//
//  File.swift
//
//
//  Created by wangzhizhou on 2022/1/16.
//

import Foundation
import JokerKits

public extension Server {
    
    func launchServer(
        _ filePath: String,
        workDirectory: String,
        javaExecutable: String,
        jarArgs: [String] = []
    ) async throws -> ManagedProcess {
        
        try await Shell.stopAll()

        // 规范启动计划（与 Python `_build_server_command` 对齐，消除漂移）。
        var userServerArgs = jarArgs
        if serverInfo.demo { userServerArgs.append("--demo") }
        if serverInfo.showJarHelpInfo { userServerArgs.append("--help") }
        if let jarOpts = serverInfo.jarOptions {
            userServerArgs.append(jarOpts.replacingOccurrences(of: "a:", with: ""))
        }
        let options = ServerLaunchOptions(
            minMem: serverInfo.minMem,
            maxMem: serverInfo.maxMem,
            jvmOpts: serverInfo.jvmArgs,
            userServerArgs: userServerArgs,
            nogui: !serverInfo.gui && !serverInfo.showJarHelpInfo,
            forceUpgrade: serverInfo.forceUpgrade
        )
        let plan = GamePlan.planServerLaunch(
            executable: javaExecutable,
            cwd: workDirectory,
            jarPath: filePath,
            options: options
        )
        let args = plan.jvmArgs + ["-jar", plan.jarPath] + plan.serverArgs
        if serverInfo.debug { print(args.joined(separator: " ")) }

        // `--symlink`：启动前将 world 软链接到备份世界（对齐 Python `_maybe_symlink_world`）。
        if serverInfo.symlinkWorld { prepareSymlinkWorld(workDirectory: workDirectory) }
        
        let eulaFilePath = workDirectory + "/eula.txt"
        let propertiesFilePath = workDirectory + "/server.properties"
        if !FileManager.default.fileExists(atPath: eulaFilePath) || !FileManager.default.fileExists(atPath: propertiesFilePath) {
            await Shell.run(path: javaExecutable, args: args + ["--initSettings"], workDirectory: workDirectory)
        }
        let agreeEULA = try modifyEULA(at: eulaFilePath)
        if agreeEULA {
            self.serverInfo.console?.success("已同意EULA协议")
        } else {
            self.serverInfo.console?.error("未同意EULA协议")
        }
        let isOnlineMode = try modifyProperties(at: propertiesFilePath)
        if isOnlineMode {
            self.serverInfo.console?.success("服务器运行为在线模式")
        } else {
            self.serverInfo.console?.warning("服务器运行为离线模式")
        }
        // 受管进程（B7）：优雅停止 → SIGTERM → SIGKILL，退出码归一。
        // `onServerLog`：无控制台前端（GUI）把服务端运行期输出接走（stdout+stderr 合流）。
        return try ProcessRunner.run(
            executable: javaExecutable,
            args: args,
            workDirectory: workDirectory,
            onLine: serverInfo.onServerLog,
            inheritStandardInput: serverInfo.inheritStandardInput
        )
    }

    /// 将服务端 world 目录软链接到 `backup/worlds/<version>`（源不存在/目标已存在则跳过）。
    private func prepareSymlinkWorld(workDirectory: String) {
        let fileManager = FileManager.default
        let source = "\(serverInfo.rootDir)/backup/worlds/\(serverInfo.version)"
        let world = workDirectory + "/world"
        guard fileManager.fileExists(atPath: source) else {
            serverInfo.console?.warning("未找到备份世界 \(source)，跳过软链接")
            return
        }
        guard !fileManager.fileExists(atPath: world) else {
            serverInfo.console?.warning("服务端世界目录已存在，跳过软链接")
            return
        }
        do {
            try fileManager.createSymbolicLink(atPath: world, withDestinationPath: source)
            serverInfo.console?.success("已将 world 软链接到 \(source)")
        } catch {
            serverInfo.console?.warning("软链接失败: \(error)")
        }
    }
}
