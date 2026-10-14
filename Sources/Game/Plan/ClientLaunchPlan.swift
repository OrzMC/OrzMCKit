import Foundation

/// 客户端启动的**纯计划**（对齐 `docs/spec/behavior.md` B6 / `data-model.md` §8）。
///
/// 与 Python `orzmc/domain/launch.py` 对齐：`jvmArgs` **不含** `-cp`/`${classpath}`，
/// 类路径单独由 `classpath` 承载；`memory` 默认 `512M/2G`。
public struct ClientLaunchPlan: Sendable, Equatable {
    public struct Memory: Sendable, Equatable {
        public let min: String
        public let max: String
    }

    public let executable: String
    public let cwd: String
    public let mainClass: String
    public let jvmArgs: [String]
    public let gameArgs: [String]
    public let classpath: [String]
    public let classpathString: String
    public let memory: Memory
    public let tokens: [String: String]
    public let features: [String: Bool]
}

/// 计划输入：版本 JSON 的**子集**（解耦生成 schema，便于离线一致性校验）。
public struct VersionPlan: Decodable, Sendable {
    public struct AssetIndex: Decodable, Sendable { public let id: String }
    public struct Asset: Decodable, Sendable {
        public let url: String
        public let sha1: String?
        public let size: Int?
    }
    public struct Downloads: Decodable, Sendable {
        public let client: Asset?
        public let server: Asset?
    }
    public struct JavaVersion: Decodable, Sendable { public let majorVersion: Int? }
    public struct Arguments: Decodable, Sendable {
        public let jvm: [ArgumentEntry]?
        public let game: [ArgumentEntry]?
    }

    public let id: String
    public let type: String?
    public let mainClass: String?
    public let assetIndex: AssetIndex?
    public let downloads: Downloads?
    public let libraries: [LibraryPlan]?
    public let arguments: Arguments?
    public let javaVersion: JavaVersion?
    public let minecraftArguments: String?
}

/// Mojang `arguments` 条目：纯字符串，或 `{rules, value}`。
public enum ArgumentEntry: Decodable, Equatable, Sendable {
    case plain(String)
    case conditional(rules: [Rule], value: [String])

    private enum CodingKeys: String, CodingKey {
        case rules
        case value
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self = .plain(text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        if let text = try? container.decode(String.self, forKey: .value) {
            self = .conditional(rules: rules, value: [text])
        } else {
            self = .conditional(rules: rules, value: try container.decode([String].self, forKey: .value))
        }
    }
}

/// Mojang 规则（库与 arguments 共用）。
public struct Rule: Decodable, Equatable, Sendable {
    public struct OperatingSystem: Decodable, Equatable, Sendable {
        public let name: String?
        public let arch: String?
        public let version: String?
    }

    public let action: String
    public let os: OperatingSystem?
    public let features: [String: Bool]?

    private enum CodingKeys: String, CodingKey {
        case action
        case os
        case features
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? "allow"
        os = try container.decodeIfPresent(OperatingSystem.self, forKey: .os)
        features = try container.decodeIfPresent([String: Bool].self, forKey: .features)
    }
}

/// 库条目（仅计划所需字段）。
public struct LibraryPlan: Decodable, Equatable, Sendable {
    public struct Download: Decodable, Equatable, Sendable {
        public let path: String
        public let url: String
        public let sha1: String?
        public let size: Int?
    }
    public struct Downloads: Decodable, Equatable, Sendable {
        public let artifact: Download?
        public let classifiers: [String: Download]?
    }

    public let name: String
    public let rules: [Rule]?
    public let downloads: Downloads?
    public let natives: [String: String]?
}

/// 计划平台（规范：`windows` / `osx` / `linux` × `x86_64` / `arm64` / `x86`）。
public struct PlanPlatform: Sendable, Equatable {
    public let os: String
    public let arch: String

    public init(os: String, arch: String) {
        self.os = os
        self.arch = arch
    }
}

/// 启动选项（用户可指定；其余用规范默认）。
public struct LaunchOptions: Sendable, Equatable {
    public var username: String
    public var minMem: String
    public var maxMem: String
    public var authUUID: String
    public var accessToken: String
    public var userType: String
    public var launcherName: String
    public var launcherVersion: String

    public init(
        username: String = "guest",
        minMem: String = "512M",
        maxMem: String = "2G",
        authUUID: String = String(repeating: "0", count: 32),
        accessToken: String = "0",
        userType: String = "legacy",
        launcherName: String = "orzmc",
        launcherVersion: String = "0.1"
    ) {
        self.username = username
        self.minMem = minMem
        self.maxMem = maxMem
        self.authUUID = authUUID
        self.accessToken = accessToken
        self.userType = userType
        self.launcherName = launcherName
        self.launcherVersion = launcherVersion
    }
}

public extension GamePlan {
    /// 纯函数：由版本计划 + 布局计算客户端启动计划（无 IO、无文件系统扫描）。
    static func planClientLaunch(
        version: VersionPlan,
        root: String,
        type: GameType = .vanilla,
        platform: PlanPlatform,
        options: LaunchOptions = LaunchOptions()
    ) -> ClientLaunchPlan {
        let major = version.javaVersion?.majorVersion ?? 8
        let layout = layout(
            root: root,
            version: version.id,
            type: type,
            javaMajor: major,
            windows: platform.os == "windows"
        )
        let features = defaultFeatures()
        let separator = platform.os == "windows" ? ";" : ":"

        let libraries = (version.libraries ?? []).filter {
            allow($0.rules, platform: platform, features: features)
        }
        let classpath = libraries.compactMap { $0.downloads?.artifact }.map {
            "\(layout.clientLibrariesDir)/\($0.path)"
        } + [layout.clientJarPath]

        let tokens = makeTokens(
            version: version,
            layout: layout,
            options: options,
            classpath: classpath,
            separator: separator
        )

        let jvmEntries = version.arguments?.jvm ?? legacyJVMRaw.map(ArgumentEntry.plain)
        let jvmRaw = collect(jvmEntries, platform: platform, features: features)
            .filter { $0 != "-cp" && !$0.contains("${classpath}") }
        let gameRaw = version.arguments != nil
            ? collect(version.arguments?.game ?? [], platform: platform, features: features)
            : (version.minecraftArguments ?? "").split(separator: " ").map(String.init)

        return ClientLaunchPlan(
            executable: layout.javaExecutable ?? "",
            cwd: layout.clientDir,
            mainClass: version.mainClass ?? "net.minecraft.client.main.Main",
            jvmArgs: jvmRaw.map { substitute($0, tokens) },
            gameArgs: gameRaw.map { substitute($0, tokens) },
            classpath: classpath,
            classpathString: classpath.joined(separator: separator),
            memory: .init(min: options.minMem, max: options.maxMem),
            tokens: tokens,
            features: features
        )
    }
}

// MARK: - internals

private let legacyJVMRaw = ["-Djava.library.path=${natives_directory}", "-cp", "${classpath}"]

private func defaultFeatures() -> [String: Bool] {
    [
        "is_demo_user": false,
        "has_custom_resolution": false,
        "quick_play_singleplayer": false,
        "quick_play_multiplayer": false,
        "quick_play_realms": false,
    ]
}

private func matches(_ rule: Rule, platform: PlanPlatform, features: [String: Bool]) -> Bool {
    if let os = rule.os {
        if let name = os.name, name != platform.os { return false }
        if let arch = os.arch, arch != platform.arch { return false }
    }
    if let required = rule.features {
        for (key, value) in required where (features[key] ?? false) != value {
            return false
        }
    }
    return true
}

/// 无规则 → 允许；有规则时由**最后一条匹配**规则决定，都不匹配则排除。
private func allow(_ rules: [Rule]?, platform: PlanPlatform, features: [String: Bool]) -> Bool {
    guard let rules, !rules.isEmpty else { return true }
    var allowed = false
    for rule in rules where matches(rule, platform: platform, features: features) {
        allowed = rule.action == "allow"
    }
    return allowed
}

private func collect(_ entries: [ArgumentEntry], platform: PlanPlatform, features: [String: Bool]) -> [String] {
    var result: [String] = []
    for entry in entries {
        switch entry {
        case .plain(let text):
            result.append(text)
        case .conditional(let rules, let values):
            if allow(rules, platform: platform, features: features) {
                result.append(contentsOf: values)
            }
        }
    }
    return result
}

private func substitute(_ text: String, _ tokens: [String: String]) -> String {
    var result = text
    for (key, value) in tokens {
        result = result.replacingOccurrences(of: "${\(key)}", with: value)
    }
    return result
}

private func makeTokens(
    version: VersionPlan,
    layout: GamePlan.Layout,
    options: LaunchOptions,
    classpath: [String],
    separator: String
) -> [String: String] {
    [
        "natives_directory": layout.clientNativesDir,
        "launcher_name": options.launcherName,
        "launcher_version": options.launcherVersion,
        "classpath": classpath.joined(separator: separator),
        "classpath_separator": separator,
        "library_directory": layout.clientLibrariesDir,
        "auth_player_name": options.username,
        "version_name": version.id,
        "game_directory": layout.clientDir,
        "assets_root": layout.clientAssetsDir,
        "assets_index_name": version.assetIndex?.id ?? "",
        "auth_uuid": options.authUUID,
        "auth_access_token": options.accessToken,
        "user_type": options.userType,
        "version_type": version.type ?? "release",
        "clientid": "",
        "auth_xuid": "",
    ]
}
