import Foundation
import Fabric

/// 可选客户端附加组件（Fabric / Forge 等）解析结果。
///
/// 对齐 Python `orzmc.core.profiles.ProfileAddon`：
/// `libraries` 是额外 classpath jar；`jvmArgs` / `gameArgs` 追加到启动命令；
/// `mainClass` 覆盖 vanilla 主类（Fabric → `KnotClient`）。
public struct ProfileAddon: Sendable, Equatable {
    public struct Library: Sendable, Equatable {
        public let name: String
        /// Maven 相对路径（相对客户端 `libraries/` 目录）。
        public let path: String
        /// 完整下载 URL。
        public let url: String
        public let sha1: String?
        public let size: Int?

        public init(name: String, path: String, url: String, sha1: String?, size: Int?) {
            self.name = name
            self.path = path
            self.url = url
            self.sha1 = sha1
            self.size = size
        }
    }

    public var libraries: [Library]
    public var jvmArgs: [String]
    public var gameArgs: [String]
    public var mainClass: String?
    /// Forge 自带打过补丁的游戏 jar：置真时 vanilla jar 不进 classpath。
    public var usesOwnClientJar: Bool

    public init(
        libraries: [Library] = [],
        jvmArgs: [String] = [],
        gameArgs: [String] = [],
        mainClass: String? = nil,
        usesOwnClientJar: Bool = false
    ) {
        self.libraries = libraries
        self.jvmArgs = jvmArgs
        self.gameArgs = gameArgs
        self.mainClass = mainClass
        self.usesOwnClientJar = usesOwnClientJar
    }
}

extension FabricModel {
    /// 把 fabric-meta profile 映射为引擎的 `ProfileAddon`。
    public var profileAddon: ProfileAddon {
        ProfileAddon(
            libraries: libraries.map { library in
                ProfileAddon.Library(
                    name: library.name,
                    path: library.path,
                    url: library.downloadURL.absoluteString,
                    sha1: library.sha1,
                    size: library.size
                )
            },
            jvmArgs: arguments.jvm,
            gameArgs: arguments.game,
            mainClass: mainClass,
            usesOwnClientJar: false
        )
    }
}
