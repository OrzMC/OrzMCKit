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
        return try ProcessRunner.run(
            executable: javaExecutable,
            args: args,
            workDirectory: workDirectory
        )
    }
}
