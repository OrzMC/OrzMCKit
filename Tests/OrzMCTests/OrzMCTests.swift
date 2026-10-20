import CacheKit
import ConsoleKit
// Apple 平台用 CryptoKit；其它平台用 swift-crypto（决策 D14：跨平台）。
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif
import Fabric
import Foundation
import MojangAPI
import Testing

@testable import Game
@testable import OrzMC

/// 命令面暴露（对齐 docs/spec/cli-surface.md §2）。
@Suite struct CommandGroupTests {
    @Test func exposesSpecCommands() {
        let names = Set(CommandGroup(options: GlobalOptions()).commands.keys)
        for expected in ["client", "server", "plugin", "list", "remove", "backup", "version", "completion", "capabilities", "update", "uninstall", "app", "mcp"] {
            #expect(names.contains(expected))
        }
    }

    @Test func fabricIsHiddenAlias() {
        // `fabric` 仍可用，但不列入 commands（因此不出现在帮助/补全/capabilities）。
        #expect(!CommandGroup(options: GlobalOptions()).commands.keys.contains("fabric"))
    }

    @Test func capabilitiesReflectSignatures() {
        let capabilities = CommandGroup(options: GlobalOptions()).capabilityList()
        let client = capabilities.first { $0.name == "client" }
        #expect(client != nil)
        let names = client?.values.flatMap(\.names) ?? []
        #expect(names.contains("--version"))
        #expect(names.contains("--root-dir"))
        #expect(client?.values.contains { $0.kind == "flag" } == true)
    }

    @Test func completionNativeShells() {
        // ConsoleKit 原生只渲染 bash/zsh；fish/powershell 由 `CompletionScripts` 生成。
        #expect(Shell(rawValue: "bash") != nil)
        #expect(Shell(rawValue: "zsh") != nil)
        #expect(Shell(rawValue: "fish") == nil)
        #expect(Shell(rawValue: "powershell") == nil)
    }
}

@Suite struct OrzMCVersionTests {
    @Test func isSemanticVersion() {
        let parts = OrzMCVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { Int($0) != nil })
    }
}

/// 安装记录读取/回写（规范 install-update.md §3）。
@Suite struct StatePathsTests {
    /// 规范 `docs/spec/state-paths.json`：Unix 与 Windows 两套形状。
    @Test func unixStateDir() {
        let env = ["HOME": "/home/u"]
        #expect(StatePaths.stateDir(environment: env, isWindows: false) == "/home/u/.local/state/orzmc")
        let xdg = ["HOME": "/home/u", "XDG_STATE_HOME": "/xdg/state"]
        #expect(StatePaths.stateDir(environment: xdg, isWindows: false) == "/xdg/state/orzmc")
    }

    @Test func windowsStateDir() {
        let env = ["USERPROFILE": "C:\\Users\\u", "LOCALAPPDATA": "C:\\Users\\u\\AppData\\Local"]
        #expect(
            StatePaths.stateDir(environment: env, isWindows: true)
                == "C:\\Users\\u\\AppData\\Local\\orzmc"
        )
        // 缺 `LOCALAPPDATA` 时退回 `%USERPROFILE%\\AppData\\Local`。
        let noLocal = ["USERPROFILE": "C:\\Users\\u"]
        #expect(
            StatePaths.stateDir(environment: noLocal, isWindows: true) == "C:\\Users\\u\\AppData\\Local\\orzmc"
        )
    }

    /// 共享落点：安装记录 / 认证文件 / 补全落点都必须从 `StatePaths` 派生（单一事实源）。
    /// 一致性用例 `state-paths/*` 从适配器侧兜住，这里兜住「有人又手写一遍路径」。
    @Test func sharedPathsDeriveFromStateDir() {
        let env = ["HOME": "/home/u", "XDG_STATE_HOME": "/xdg/state"]
        #expect(StatePaths.installRecord(environment: env, isWindows: false) == "/xdg/state/orzmc/install.conf")
        #expect(StatePaths.authSession(environment: env, isWindows: false) == "/xdg/state/orzmc/auth.json")

        let win = ["USERPROFILE": "C:\\Users\\u", "LOCALAPPDATA": "C:\\Users\\u\\AppData\\Local"]
        #expect(
            StatePaths.installRecord(environment: win, isWindows: true)
                == "C:\\Users\\u\\AppData\\Local\\orzmc\\install.conf"
        )

        #expect(StatePaths.completionPath(shell: "bash", home: "/home/u", isWindows: false)
            == "/home/u/.local/share/bash-completion/completions/orzmc")
        #expect(StatePaths.completionPath(shell: "zsh", home: "/home/u", isWindows: false)
            == "/home/u/.zsh/completions/_orzmc")
        #expect(StatePaths.completionPath(shell: "fish", home: "/home/u", isWindows: false)
            == "/home/u/.config/fish/completions/orzmc.fish")
        #expect(StatePaths.completionPath(shell: "powershell", home: "/home/u", isWindows: false) == nil)
    }

    @Test func gameRootFollowsPlatform() {
        #expect(StatePaths.defaultGameRoot(environment: ["HOME": "/home/u"], isWindows: false) == "/home/u/minecraft")
        #expect(
            StatePaths.defaultGameRoot(environment: ["USERPROFILE": "C:\\Users\\u"], isWindows: true)
                == "C:\\Users\\u\\minecraft"
        )
    }
}

@Suite struct InstallManifestTests {
    @Test func parsesKeyValues() {
        let text = "tool=orzmc\nschema=1\nversion=v0.1.0\nplatform=macos-arm64\ninstall_dir=/tmp/bin\nbinary=/tmp/bin/orzmc\npath_file=/tmp/.zshrc\npath_line=export PATH=\"/tmp/bin:$PATH\"\nroot_dir=/tmp/mc\ncompletion_file=/tmp/_orzmc\n"
        let manifest = InstallManifest(lines: text.split(separator: "\n").map(String.init))
        #expect(manifest.tool == "orzmc")
        #expect(manifest.version == "v0.1.0")
        #expect(manifest.platform == "macos-arm64")
        #expect(manifest.installDir == "/tmp/bin")
        #expect(manifest.pathFile == "/tmp/.zshrc")
        #expect(manifest.pathLine == "export PATH=\"/tmp/bin:$PATH\"")
        #expect(manifest.rootDir == "/tmp/mc")
        #expect(manifest.completionFile == "/tmp/_orzmc")
    }

    @Test func roundTrips() {
        var manifest = InstallManifest(rootDir: "/tmp/mc")
        manifest.version = "v0.1.0"
        manifest.installDir = "/tmp/bin"
        manifest.binary = "/tmp/bin/orzmc"
        manifest.pathLine = "export PATH=\"/tmp/bin:$PATH\""
        let reparsed = InstallManifest(lines: manifest.serialized.split(separator: "\n").map(String.init))
        #expect(reparsed.version == "v0.1.0")
        #expect(reparsed.pathLine == manifest.pathLine)
        #expect(reparsed.rootDir == "/tmp/mc")
    }

    /// `surface`（spec §3.1）：标明哪个前端装了 CLI；缺失 = 旧记录。
    @Test func surfaceIsOptionalAndRoundTrips() {
        let legacy = InstallManifest(lines: ["tool=orzmc", "schema=1", "root_dir=/tmp/mc"])
        #expect(legacy.surface == nil)
        #expect(!legacy.serialized.contains("surface="))

        var manifest = InstallManifest(rootDir: "/tmp/mc")
        manifest.surface = "gui"
        #expect(manifest.serialized.contains("surface=gui"))
        #expect(InstallManifest(lines: manifest.serialized.split(separator: "\n").map(String.init)).surface == "gui")
    }

    /// `update` 只回写版本等字段，`surface` 必须保留（升级不改变"谁装的"）。
    @Test func updatingFieldsKeepsSurface() {
        var manifest = InstallManifest(rootDir: "/tmp/mc")
        manifest.surface = "gui"
        manifest.version = "v9.9.9"
        manifest.platform = "macos-arm64"
        let reparsed = InstallManifest(lines: manifest.serialized.split(separator: "\n").map(String.init))
        #expect(reparsed.surface == "gui" && reparsed.version == "v9.9.9")
    }
}

/// 版本比较（自升级判定）。
@Suite struct SelfUpdateTests {
    @Test func versionCompare() {
        #expect(SelfUpdate.isNewer("v0.1.0", than: "v0.0.6"))
        #expect(!SelfUpdate.isNewer("v0.0.6", than: "v0.0.6"))
        #expect(!SelfUpdate.isNewer("v0.0.5", than: "v0.0.6"))
        #expect(SelfUpdate.isNewer("v1.0", than: "v0.9.9"))
    }

    @Test func normalize() {
        #expect(SelfUpdate.normalize("0.1.0") == "v0.1.0")
        #expect(SelfUpdate.normalize("v0.1.0") == "v0.1.0")
    }

    /// 资产名必须与 `release.yml` / Python `asset_for` 一致（三平台形状）。
    @Test func assetNames() {
        #expect(SelfUpdate.asset(osName: "macos", arch: "arm64") == "orzmc-macos-arm64")
        #expect(SelfUpdate.asset(osName: "linux", arch: "x86_64") == "orzmc-linux-x86_64")
        #expect(SelfUpdate.asset(osName: "windows", arch: "x86_64") == "orzmc-windows-x86_64.zip")
    }

    @Test func platformTags() {
        #expect(SelfUpdate.platformTag(osName: "linux", arch: "arm64") == "linux-arm64")
        #expect(SelfUpdate.platformTag(osName: "windows", arch: "x86_64") == "windows-x86_64")
    }

    /// 可执行文件魔数按平台区分（Mach-O / ELF / PE）。
    @Test func allowedMagicsPerPlatform() {
        let elf = Data([0x7F, 0x45, 0x4C, 0x46])
        let pe = Data([0x4D, 0x5A])
        let machO = Data([0xCF, 0xFA, 0xED, 0xFE])
        #expect(SelfUpdate.allowedMagics(osName: "linux").contains(elf))
        #expect(!SelfUpdate.allowedMagics(osName: "linux").contains(pe))
        #expect(SelfUpdate.allowedMagics(osName: "windows").contains(pe))
        #expect(!SelfUpdate.allowedMagics(osName: "windows").contains(machO))
        #expect(SelfUpdate.allowedMagics(osName: "macos").contains(machO))
    }
}

/// 全局选项预解析（规范 §3）：只消费子命令之前的全局选项。
@Suite struct GlobalOptionsTests {
    @Test func parsesLeadingGlobals() {
        let parsed = GlobalOptions.parse(["orzmc", "--verbose", "--json", "--root-dir", "/tmp/mc", "list"])
        #expect(parsed.options.verbose)
        #expect(parsed.options.json)
        #expect(parsed.options.rootDir == "/tmp/mc")
        #expect(!parsed.versionRequested)
        #expect(parsed.remaining == ["orzmc", "list"])
        #expect(parsed.commandName == "list")
    }

    @Test func stopsAtSubcommand() {
        // 子命令之后的 `--root-dir` / `--verbose` 交给子命令自己的签名。
        let parsed = GlobalOptions.parse(["orzmc", "list", "--root-dir", "/tmp/mc"])
        #expect(parsed.options.rootDir == nil)
        #expect(parsed.remaining == ["orzmc", "list", "--root-dir", "/tmp/mc"])
    }

    @Test func versionRequested() {
        let parsed = GlobalOptions.parse(["orzmc", "--version"])
        #expect(parsed.versionRequested)
        #expect(parsed.remaining == ["orzmc"])
        #expect(parsed.commandName == "_root")
    }

    @Test func resolveRootPrecedence() {
        var options = GlobalOptions()
        options.rootDir = "/global"
        #expect(options.resolveRoot("/command") == "/command")
        #expect(options.resolveRoot(nil) == "/global")
        #expect(GlobalOptions().resolveRoot(nil) == GamePlan.defaultRoot)
    }
}

/// 引擎基础契约的离线单测（确定性、不联网）。
@Suite struct GameTypeTests {
    @Test func rawValues() {
        #expect(GameType.vanilla.rawValue == "vanilla")
        #expect(GameType.fabric.rawValue == "fabric")
        #expect(GameType.forge.rawValue == "forge")
        #expect(GameType.paper.rawValue == "paper")
    }

    @Test func defaultRoot() {
        // 平台相关分隔符：Windows 是 `\\`，其余是 `/`（规范 state-paths.json）。
        #expect(GamePlan.defaultRoot.hasSuffix("/minecraft") || GamePlan.defaultRoot.hasSuffix("\\minecraft"))
    }

    @Test func clientCapabilityMatrix() {
        #expect(GameType.vanilla.isClientCapable)
        #expect(GameType.fabric.isClientCapable)
        #expect(GameType.forge.isClientCapable)
        #expect(!GameType.paper.isClientCapable)
    }

    @Test func serverJarNames() {
        #expect(GameType.vanilla.serverJarName(version: "1.20.4") == "server.jar")
        #expect(GameType.paper.serverJarName(version: "1.20.4") == "paper-1.20.4.jar")
        #expect(GameType.forge.serverJarName(version: "1.20.4") == "forge-1.20.4.jar")
        #expect(GameType.fabric.serverJarName(version: "1.20.4") == "fabric-server-launch.jar")
    }
}

/// Fabric 附加组件：fabric-meta profile → `ProfileAddon` 映射（离线、确定性）。
@Suite struct FabricMetaTests {
    private let profile = """
    {
      "id": "fabric-loader-0.15.11-1.20.4",
      "inheritsFrom": "1.20.4",
      "releaseTime": "2026-10-15T04:57:17+0000",
      "time": "2026-10-15T04:57:17+0000",
      "type": "release",
      "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
      "arguments": { "game": [], "jvm": ["-DFabricMcEmu= net.minecraft.client.main.Main "] },
      "libraries": [
        { "name": "org.ow2.asm:asm:9.6", "url": "https://maven.fabricmc.net/", "sha1": "aa20", "size": 123598 },
        { "name": "net.fabricmc:intermediary:1.20.4", "url": "https://maven.fabricmc.net/" }
      ]
    }
    """

    @Test func mapsToProfileAddon() throws {
        let model = try Fabric.launcherConfig(Data(profile.utf8))
        let addon = model.profileAddon
        #expect(addon.mainClass == "net.fabricmc.loader.impl.launch.knot.KnotClient")
        #expect(addon.jvmArgs == ["-DFabricMcEmu= net.minecraft.client.main.Main "])
        #expect(addon.gameArgs.isEmpty)
        #expect(addon.libraries.count == 2)
        #expect(addon.libraries[0].path == "org/ow2/asm/asm/9.6/asm-9.6.jar")
        #expect(addon.libraries[0].url == "https://maven.fabricmc.net/org/ow2/asm/asm/9.6/asm-9.6.jar")
        #expect(addon.libraries[0].sha1 == "aa20")
        // 无 sha1 的库也能映射（下载时跳过校验）。
        #expect(addon.libraries[1].path == "net/fabricmc/intermediary/1.20.4/intermediary-1.20.4.jar")
        #expect(addon.libraries[1].sha1 == nil)
    }

    @Test func planProfileAddonDownload() throws {
        let model = try Fabric.launcherConfig(Data(profile.utf8))
        let items = GamePlan.planProfileAddonDownload(
            addon: model.profileAddon,
            root: "/tmp/orzmc",
            version: "1.20.4"
        )
        #expect(items.count == 2)
        #expect(
            items[0].path
                == "/tmp/orzmc/versions/1.20.4/client/libraries/org/ow2/asm/asm/9.6/asm-9.6.jar"
        )
    }

    /// 真实 fabric-meta 解析（默认跳过；`ORZMC_NETWORK_SMOKE=1` 开启）。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORZMC_NETWORK_SMOKE"] == "1"))
    func resolvesLiveFabricMeta() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-fabric-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let addon = try await FabricMeta.resolve(version: "1.20.4", root: root.path)
        #expect(addon.mainClass == "net.fabricmc.loader.impl.launch.knot.KnotClient")
        #expect(addon.libraries.contains { $0.name.contains("fabric-loader") })
        #expect(addon.libraries.allSatisfy { !$0.path.isEmpty && !$0.url.isEmpty })
    }
}

/// Forge 附加组件：promotions 解析与参数提取（离线、确定性）。
@Suite struct ForgeMetaTests {
    @Test func resolvesLatestFromPromotions() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-forge-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MetadataCache(directory: dir)
        try cache.write(
            ["promos": ["1.20.4-latest": "49.2.8", "1.20.4-recommended": "49.2.0"]],
            to: cache.metaURL("forge-promotions")
        )
        let full = try await ForgeMeta.latestFullVersion(mcVersion: "1.20.4", cache: cache)
        #expect(full == "1.20.4-49.2.8")
    }

    @Test func extractsPlainArguments() {
        let entries: [ArgumentEntry] = [
            .plain("--launchTarget"),
            .plain("forge_client"),
            .conditional(rules: [], value: ["ignored"]),
        ]
        #expect(ForgeMeta.plainStrings(entries) == ["--launchTarget", "forge_client"])
    }

    @Test func installerURLShape() {
        #expect(
            "\(ForgeMeta.mavenBase)/1.20.4-49.2.8/forge-1.20.4-49.2.8-installer.jar"
                == "https://maven.minecraftforge.net/net/minecraftforge/forge/1.20.4-49.2.8/forge-1.20.4-49.2.8-installer.jar"
        )
    }

    /// 真实 Forge 解析（下载安装器 + 托管 JRE17 + 运行 --installClient，较慢，默认跳过）。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORZMC_NETWORK_SMOKE"] == "1"))
    func resolvesLiveForge() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-forge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let addon = try await ForgeMeta.resolve(version: "1.20.4", root: root.path)
        #expect(addon.usesOwnClientJar)
        #expect(addon.mainClass?.contains("ForgeBootstrap") == true)
        #expect(addon.libraries.contains { $0.path.hasSuffix("-client.jar") })
        #expect(addon.gameArgs.contains("--launchTarget"))
    }
}

/// `GamePlan` 规范布局（对齐 docs/spec/fixtures/layout/*）。
@Suite struct GamePlanLayoutTests {
    @Test func vanillaLinux() {
        let layout = GamePlan.layout(
            root: "/tmp/orzmc",
            version: "1.20.4",
            type: .vanilla,
            javaMajor: 17,
            objectSha1: "abcdef0123456789abcdef0123456789abcdef01"
        )
        #expect(layout.clientDir == "/tmp/orzmc/versions/1.20.4/client")
        #expect(layout.clientAssetsDir == "/tmp/orzmc/versions/1.20.4/client/assets")
        #expect(layout.clientObjectsDir == "/tmp/orzmc/versions/1.20.4/client/assets/objects")
        #expect(layout.clientJarPath == "/tmp/orzmc/versions/1.20.4/client/1.20.4.jar")
        #expect(layout.serverDir == "/tmp/orzmc/versions/1.20.4/server/vanilla")
        #expect(layout.serverJarName == "server.jar")
        #expect(layout.serverJarPath == "/tmp/orzmc/versions/1.20.4/server/vanilla/server.jar")
        #expect(layout.javaExecutable == "/tmp/orzmc/java/17/bin/java")
        #expect(
            layout.clientObjectPath
                == "/tmp/orzmc/versions/1.20.4/client/assets/objects/ab/abcdef0123456789abcdef0123456789abcdef01"
        )
        #expect(layout.versionManifestPath == "/tmp/orzmc/cache/version_manifest.json")
        #expect(layout.backupDir == "/tmp/orzmc/backup")
    }

    @Test func paperWindows() {
        let layout = GamePlan.layout(
            root: "/tmp/orzmc",
            version: "1.20.4",
            type: .paper,
            javaMajor: 17,
            windows: true
        )
        #expect(layout.serverDir == "/tmp/orzmc/versions/1.20.4/server/paper")
        #expect(layout.serverJarName == "paper-1.20.4.jar")
        #expect(layout.javaExecutable == "/tmp/orzmc/java/17/bin/java.exe")
        #expect(layout.clientObjectPath == nil)
        #expect(layout.javaMajorDir == "/tmp/orzmc/java/17")
    }
}

/// `GamePlan.planClientLaunch` 纯计划（与 conformance `client-plan/*` 同构）。
@Suite struct GamePlanClientLaunchTests {
    private let fixture = """
    {
      "id": "1.20.4",
      "type": "release",
      "mainClass": "net.minecraft.client.main.Main",
      "javaVersion": { "majorVersion": 17 },
      "assetIndex": { "id": "5" },
      "downloads": { "client": { "url": "u", "sha1": "y", "size": 1 } },
      "libraries": [
        { "name": "com.example:always:1.0", "downloads": { "artifact": { "path": "com/example/always/1.0/always-1.0.jar", "url": "u" } } },
        { "name": "com.example:maconly:1.0", "rules": [{ "action": "allow", "os": { "name": "osx" } }], "downloads": { "artifact": { "path": "com/example/maconly/1.0/maconly-1.0.jar", "url": "u" } } },
        { "name": "com.example:notmac:1.0", "rules": [{ "action": "disallow", "os": { "name": "osx" } }], "downloads": { "artifact": { "path": "com/example/notmac/1.0/notmac-1.0.jar", "url": "u" } } }
      ],
      "arguments": {
        "jvm": [
          { "rules": [{ "action": "allow", "os": { "name": "osx" } }], "value": ["-XstartOnFirstThread"] },
          "-Djava.library.path=${natives_directory}",
          "-cp",
          "${classpath}"
        ],
        "game": [
          "--username", "${auth_player_name}",
          "--version", "${version_name}",
          "--gameDir", "${game_directory}",
          "--assetIndex", "${assets_index_name}"
        ]
      }
    }
    """

    @Test func vanillaMacOS() throws {
        let version = try JSONDecoder().decode(VersionPlan.self, from: Data(fixture.utf8))
        let plan = GamePlan.planClientLaunch(
            version: version,
            root: "/tmp/orzmc",
            platform: PlanPlatform(os: "osx", arch: "arm64")
        )

        #expect(plan.executable == "/tmp/orzmc/java/17/bin/java")
        #expect(plan.cwd == "/tmp/orzmc/versions/1.20.4/client")
        #expect(plan.mainClass == "net.minecraft.client.main.Main")
        #expect(plan.jvmArgs.contains("-XstartOnFirstThread"))
        #expect(plan.jvmArgs.contains("-Djava.library.path=/tmp/orzmc/versions/1.20.4/client/natives"))
        #expect(!plan.jvmArgs.contains("-cp"))
        #expect(plan.gameArgs.contains("guest"))
        #expect(plan.gameArgs.contains("1.20.4"))
        #expect(plan.classpath.contains { $0.hasSuffix("always-1.0.jar") })
        #expect(plan.classpath.contains { $0.hasSuffix("maconly-1.0.jar") })
        #expect(!plan.classpath.contains { $0.hasSuffix("notmac-1.0.jar") })
        #expect(plan.tokens["assets_index_name"] == "5")
        #expect(plan.tokens["version_type"] == "release")
        #expect(plan.memory.min == "512M")
        #expect(plan.memory.max == "2G")
    }
}

@Suite struct InstalledVersionsTests {
    private func makeRoot() -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-versions-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        for path in ["versions/1.20.4/client", "versions/1.20.4/server/paper", "versions/1.21/server/vanilla"] {
            try? fm.createDirectory(atPath: url.appendingPathComponent(path).path, withIntermediateDirectories: true)
        }
        return url.path
    }

    @Test func scansAndSorts() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let versions = GamePlan.installedVersions(root: root)
        #expect(versions.map(\.version) == ["1.21", "1.20.4"])
        let item = versions.first { $0.version == "1.20.4" }
        #expect(item?.hasClient == true)
        #expect(item?.serverTypes == [.paper])
    }

    @Test func removesClientKeepsServer() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(GamePlan.removeInstalled(version: "1.20.4", server: false, type: nil, root: root))
        #expect(!FileManager.default.fileExists(atPath: "\(root)/versions/1.20.4/client"))
        #expect(FileManager.default.fileExists(atPath: "\(root)/versions/1.20.4/server/paper"))
    }

    @Test func removesLastServerAndPrunesVersionDir() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(GamePlan.removeInstalled(version: "1.21", server: true, type: .vanilla, root: root))
        #expect(!FileManager.default.fileExists(atPath: "\(root)/versions/1.21"))
    }

    @Test func removeMissingReturnsFalse() {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        #expect(!GamePlan.removeInstalled(version: "9.9.9", server: false, type: nil, root: root))
    }
}

@Suite struct BackupTests {
    // 备份依赖系统 `zip`；极简 Linux 镜像可能没有（CI 已装），缺失则跳过而不是假失败。
    @Test(.enabled(if: PlatformTools.zip() != nil))
    func zipsWorldDir() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-backup-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let world = root.appendingPathComponent("versions/1.20.4/server/vanilla/world")
        try fm.createDirectory(at: world, withIntermediateDirectories: true)
        try "level".write(to: world.appendingPathComponent("level.dat"), atomically: true, encoding: .utf8)

        let dest = try GamePlan.backupWorld(version: "1.20.4", type: .vanilla, root: root.path)
        #expect(dest.hasSuffix(".zip"))
        #expect(dest.contains("/backup/worlds/"))
        #expect(fm.fileExists(atPath: dest))
    }

    @Test func missingWorldThrows() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-backup-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: GameError.self) {
            _ = try GamePlan.backupWorld(version: "1.20.4", type: .vanilla, root: root.path)
        }
    }
}

/// 与 Python 共享 Mojang 元数据缓存（`ORZMC_NETWORK_SMOKE=1` 开启）。
@Suite(.serialized) struct MojangCacheTests {
    /// 清单 / 版本 JSON 落到 `<root>/cache`；版本 JSON 保持**原始字节**（sha1 与清单一致）——
    /// 这是 Python `orzmc` 按 sha1 校验并复用缓存的前提。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORZMC_NETWORK_SMOKE"] == "1"))
    func writesSharedCacheUnderGameRoot() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("orzmc-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        await MojangCache.configure(root: root.path)
        let manifest = try await Mojang.manifest(forceUpdate: true)
        let entry = try #require(manifest.versions.first { $0.id == "1.20.4" })
        _ = try await entry.gameVersion

        let fm = FileManager.default
        let manifestPath = root.appendingPathComponent("cache/version_manifest.json").path
        let versionPath = root.appendingPathComponent("cache/versions/1.20.4.json").path
        #expect(fm.fileExists(atPath: manifestPath))
        #expect(fm.fileExists(atPath: versionPath))

        // 原始字节的 sha1 必须等于清单 URL 里的包哈希（Python 按此校验并复用）。
        let expected = try #require(
            URL(string: entry.url)?.pathComponents
                .first { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        ).lowercased()
        let data = try Data(contentsOf: URL(fileURLWithPath: versionPath))
        let actual = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(actual == expected)

        // 还原全局，避免影响其它测试。
        let defaultCache = (
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        ).appendingPathComponent("MojangAPI", isDirectory: true)
        await Mojang.configureCache(directory: defaultCache)
        await Mojang.configurePackageCache(directory: nil)
    }
}
