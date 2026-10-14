//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation
import MojangAPI
import JokerKits
import Utils

public extension Client {
    /// 从客户端版本清单文件中分析出要下载的资源信息
    /// - Returns: 需要下载的资源信息数组
    func generateDownloadItemInfos() async throws -> [DownloadItemInfo] {
        var downloadItems = [DownloadItemInfo]()
        guard
            let gameInfo = try await self.clientInfo.version.gameVersion,
            let objects = try await gameInfo.assetIndexObject?.objects,
            let clientURL = URL(string: gameInfo.downloads.client.url),
            let assetIndexURL = URL(string: gameInfo.assetIndex.url)
        else { return downloadItems }
        
        let client = gameInfo.downloads.client
        let assetIndex = gameInfo.assetIndex
        let libraries = gameInfo.libraries
        let clientLogCfgFile = gameInfo.logging.client.file
        
        // 游戏版本信息JSON文件
        if let sourceURL = URL(string: clientInfo.version.url)  {
            let jsonFileName = sourceURL.lastPathComponent
            let jsonFilePath = GamePlan.clientDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + jsonFileName
            let jsonFileURL = URL(fileURLWithPath: jsonFilePath)
            let jsonFileItme = DownloadItemInfo(sourceURL: sourceURL, dstFileURL: jsonFileURL)
            downloadItems.append(jsonFileItme)
        }
        
        // 游戏客户端Jar文件
        let clientJarFileName = [clientInfo.version.id, clientURL.pathExtension].joined(separator: ".")
        let clientJarFilePath = GamePlan.clientDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + clientJarFileName
        let clientJarFileURL = URL(fileURLWithPath: clientJarFilePath)
        let clientJarItem = DownloadItemInfo(sourceURL: clientURL, dstFileURL: clientJarFileURL, hash: client.sha1, hashType: .sha1)
        downloadItems.append(clientJarItem)
        
        // 游戏客户端资源索引文件
        let indexFileName = assetIndexURL.lastPathComponent
        let indexFilePath = GamePlan.clientIndexesDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + indexFileName
        let indexFileURL = URL(fileURLWithPath: indexFilePath)
        let indexFileItem = DownloadItemInfo(sourceURL: assetIndexURL, dstFileURL: indexFileURL, hash: assetIndex.sha1, hashType: .sha1)
        downloadItems.append(indexFileItem)
        
        // 游戏客户端资源对象文件
        for object in objects.additionalProperties.values {
            let assetObjURL = object.resourceURL
            let assetFilePath = GamePlan.clientObjectsDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + object.dirName + "/" + object.fileName
            let assetFileURL = URL(fileURLWithPath: assetFilePath)
            let assetFileItem = DownloadItemInfo(sourceURL: assetObjURL, dstFileURL: assetFileURL, hash: object.hash, hashType: .sha1)
            downloadItems.append(assetFileItem)
        }
        
        // 游戏客户端依赖库文件
        for lib in libraries {
            let artifact = lib.downloads.artifact
            let dirPath = NSString(string: artifact.path).deletingLastPathComponent
            let targetDir = GamePlan.clientLibraryPath(version: clientInfo.version.id, path: dirPath, root: clientInfo.rootDir)
            
            let currentOSName = Platform.os.platformName()
            
//            if let natives = lib.natives, let nativeClassifier = natives[currentOSName], let nativeArtifact = lib.downloads.classifiers?[nativeClassifier] {
//                artifact = nativeArtifact
//                targetDir = GamePlan.clientNativesDir(version: clientInfo.version.id)
//            }
            
            // 判断当前平台是否需要下载
            var allowDownload = true
            if let rules = lib.rules {
                var allowOSSet = Set<String>()
                rules.forEach { rule in
                    if rule.action == "allow" {
                        if let osname = rule.os?.name {
                            allowOSSet.insert(osname)
                        }
                        else {
                            allowOSSet.insert(currentOSName)
                        }
                    }
                    else if rule.action == "disallow", let osName = rule.os?.name {
                        allowOSSet.remove(osName)
                    }
                }
                allowDownload = allowOSSet.contains(currentOSName)
            }
            
//            if lib.rules == nil, let natives = lib.natives, !natives.keys.contains(currentOSName) {
//                allowDownload = false
//            }
            
            guard allowDownload else {
                continue
            }
            if let artifactURL = URL(string: artifact.url) {
                let libFilePath = targetDir + "/" + artifactURL.lastPathComponent
                let libFileURL = URL(fileURLWithPath: libFilePath)
                let libFileItem = DownloadItemInfo(sourceURL: artifactURL, dstFileURL: libFileURL, hash: artifact.sha1, hashType: .sha1)
                downloadItems.append(libFileItem)
            }
        }
        
        // 游戏客户端日志配置文件
        if let clientLogCfgFileURL = URL(string: clientLogCfgFile.url) {
            let clientLogCfgFilePath = GamePlan.clientLogConfigDir(version: clientInfo.version.id, root: clientInfo.rootDir) + "/" + clientLogCfgFileURL.lastPathComponent
            let clientLogCfgFilePathURL = URL(fileURLWithPath: clientLogCfgFilePath)
            let clientLogCfgFileItem = DownloadItemInfo(sourceURL: clientLogCfgFileURL, dstFileURL: clientLogCfgFilePathURL, hash: clientLogCfgFile.sha1, hashType: .sha1)
            downloadItems.append(clientLogCfgFileItem)
        }
        
        // 返回所有需要下载的项目信息
        return downloadItems
    }
}
