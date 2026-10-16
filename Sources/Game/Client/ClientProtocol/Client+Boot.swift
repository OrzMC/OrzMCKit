//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation
import JokerKits
import Utils
import MojangAPI

extension Client {
    public mutating func parseBootArgs() async throws -> [String]? {
        guard let gameInfo = try await self.clientInfo.version.gameVersion
        else {
            return nil
        }
        
        let jarExt = "jar"
        let cpSep = Platform.os == .windows ? ";" : ":"
        
        let libraryDirs = Array([
            GamePlan.clientLibrariesDir(version: clientInfo.version.id, root: clientInfo.rootDir),
            GamePlan.clientDir(version: clientInfo.version.id, root: clientInfo.rootDir),
        ])
        
        var classPath = Array(libraryDirs.compactMap { FileManager.allFiles(in: $0, ext: jarExt) }.joined())
        // Forge 自带打过补丁的游戏 jar：排除 vanilla jar，避免未打补丁的类覆盖它。
        if clientInfo.addon?.usesOwnClientJar == true {
            let vanillaJar = GamePlan.clientJarPath(version: clientInfo.version.id, root: clientInfo.rootDir)
            classPath.removeAll { $0 == vanillaJar }
        }
        let gameDir = GamePlan.clientDir(version: clientInfo.version.id, root: clientInfo.rootDir)
        let envs = [
            "natives_directory": GamePlan.clientNativesDir(version: clientInfo.version.id, root: clientInfo.rootDir),
            "launcher_name": "OrzMC",
            "launcher_version": clientInfo.version.id,
            "auth_player_name": clientInfo.username,
            "version_name": clientInfo.version.id,
            "game_directory": gameDir,
            "assets_root": GamePlan.clientAssetsDir(version: clientInfo.version.id, root: clientInfo.rootDir),
            "assets_index_name": gameInfo.assetIndex.id,
            "auth_uuid": clientInfo.authUUID ?? UUID().uuidString,
            "auth_access_token": clientInfo.accessToken ?? "0",
            "clientid": "",
            "auth_xuid": "",
            "user_type": clientInfo.userType,
            "version_type": clientInfo.version._type.rawValue,
            "classpath": classPath.joined(separator: cpSep),
            "path": GamePlan.clientLogConfigDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + gameInfo.logging.client.file.id
        ]
        
        var javaArgsArray = [
            "-Xms" + clientInfo.minMem,
            "-Xmx" + clientInfo.maxMem,
            "-Djava.net.preferIPv4Stack=true"
        ]
        
        if clientInfo.debug {
            javaArgsArray.append(gameInfo.logging.client.argument)
        }
        
        // 处理jvm相关参数
        var jvmArgsArray = gameInfo.arguments.jvm.compactMap { (arg) -> String? in
            switch arg {
            case .case1(let value):
                return value
            case .case2(let obj):
                if let rules = obj.rules {
                    for rule in rules {
                        if rule.os?.name == Platform.os.platformName(), rule.action == "allow" {
                            switch obj.value {
                            case .case1(let value):
                                return value
                            case .case2(let values):
                                return values.joined(separator: " ")
                            case .none:
                                return nil
                            }
                        }
                    }
                }
                return nil
            }
        }
        // 添加 Fabric 客户端相关的JVM参数
        if let fabricJVMOptions = self.fabricClientJVMOptions() {
            jvmArgsArray.append(contentsOf: fabricJVMOptions)
        }
        // 用户附加 JVM 旗标（`--jvm-opts`）
        jvmArgsArray.append(contentsOf: clientInfo.jvmArgs)
        
        // 处理游戏启动器参数
        let gameArgsArray = gameInfo.arguments.game.compactMap { (arg) -> String? in
            switch arg {
            case .case1(let value):
                return value
            case .case2(_):
                return nil
            }
        }
        // Fabric loader profile 的附加游戏参数（通常在末位追加）
        let extraGameArgs = self.fabricClientGameArgs()
        
        var mainClass = gameInfo.mainClass
        if let fabricMainClass = self.fabricClientMainClass() {
            mainClass = fabricMainClass
        }
        
        //构造参数数组
        var args = [String]()
        let regex = try NSRegularExpression(pattern: "\\$\\{(\\w+)\\}", options: .caseInsensitive)
        Array([
            javaArgsArray,
            jvmArgsArray,
            [mainClass],
            gameArgsArray,
            extraGameArgs
        ].joined()).forEach { arg in
            
            let matches = regex.matches(in: arg, range: NSRange(location: 0, length: arg.count))
            var argValue = arg
            for m in matches {
                if let placeholderRange = Range(m.range(at: 0), in: arg), let envKeyRange = Range(m.range(at: 1),in: arg) {
                    let envPlaceholder = String(arg[placeholderRange])
                    let envKey = String(arg[envKeyRange])
                    if let envValue = envs[envKey] {
                        argValue = argValue.replacingOccurrences(of: envPlaceholder, with: envValue)
                    }
                    else {
                        argValue = argValue.replacingOccurrences(of: envPlaceholder, with: "")
                    }
                }
            }
            if argValue.count > 0 {
                args.append(argValue)
            }
        }
        
        if clientInfo.debug {
            for arg in args {
                print(arg)
            }
        }
        return args
    }
}
