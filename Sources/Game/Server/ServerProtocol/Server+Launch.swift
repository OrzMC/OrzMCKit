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
        workDirectory: GameDir,
        javaExecutable: String,
        jarArgs: [String] = []
    ) async throws -> Process {
        
        var args = [
            "-server",
            "-Xms" + serverInfo.minMem,
            "-Xmx" + serverInfo.maxMem,
        ]
        
        if !serverInfo.jvmArgs.isEmpty {
            args += serverInfo.jvmArgs
        }

        args += [
            "-jar",
            filePath,
        ]
        
        if serverInfo.showJarHelpInfo {
            args.append("--help")
        } else {
            try await Shell.stopAll()
            let pidFilePath = workDirectory.filePath("run.pid")
            args.append("--pidFile=\(pidFilePath)")
            
            if serverInfo.forceUpgrade {
                args.append("--forceUpgrade")
            }
            
            if serverInfo.demo {
                args.append("--demo")
            }
            
            if !jarArgs.isEmpty {
                args += jarArgs
            }
            
            if let jarOpts = serverInfo.jarOptions {
                args.append(jarOpts.replacingOccurrences(of: "a:", with: ""))
            }
            
            if !serverInfo.gui {
                args.append("--nogui")
            }
        }
        if serverInfo.debug { print(args.joined(separator: " ")) }
        
        let eulaFilePath = workDirectory.filePath("eula.txt")
        let propertiesFilePath = workDirectory.filePath("server.properties")
        if !FileManager.default.fileExists(atPath: eulaFilePath) || !FileManager.default.fileExists(atPath: propertiesFilePath) {
            await Shell.run(path: javaExecutable, args: args + ["--initSettings"], workDirectory: workDirectory.dirPath)
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
        let process = try Shell.run(path: javaExecutable, args: args, workDirectory: workDirectory.dirPath, terminationHandler: nil)
        return process
    }
}
