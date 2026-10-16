//
//  FabricModel.swift
//  
//
//  Created by joker on 2022/4/5.
//

import Foundation

public struct FabricModel: Codable, Sendable {
    public let id: String
    public let inheritsFrom: String
    public let releaseTime: String
    public let time: String
    public let type: String
    public let mainClass: String
    public let arguments: Argument
    public let libraries: [Library]
    public struct Argument: Codable, Sendable {
        public let game: [String]
        public let jvm: [String]
    }
    public struct Library: Codable, Sendable {
        public let name: String
        public let url: URL
        /// fabric-meta 对部分库（如 intermediary / fabric-loader）不提供 sha1/size，故可选。
        public let sha1: String?
        public let size: Int?

        /// Maven 相对路径：`group/path/artifact/version/artifact-version[-classifier].jar`。
        /// fabric-meta 的 `url` 现仅为仓库根（如 `https://maven.fabricmc.net/`），
        /// 真实落地路径必须由坐标本身推导。
        public var path: String {
            let parts = name.split(separator: ":").map(String.init)
            guard parts.count >= 3 else {
                return name.replacingOccurrences(of: ":", with: "/") + ".jar"
            }
            let group = parts[0]
            let artifact = parts[1]
            let version = parts[2]
            let classifier = parts.count >= 4 ? "-\(parts[3])" : ""
            let directory = group.replacingOccurrences(of: ".", with: "/")
            return "\(directory)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).jar"
        }

        public var downloadURL: URL {
            let base = url.absoluteString.hasSuffix("/") ? url.absoluteString : url.absoluteString + "/"
            return URL(string: base + path) ?? url
        }
    }
}
