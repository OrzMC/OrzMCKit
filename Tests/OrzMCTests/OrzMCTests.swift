import ConsoleKit
import Foundation
import Testing

@testable import Game
@testable import OrzMC

/// 命令面暴露（对齐 docs/spec/cli-surface.md §2）。
@Suite struct CommandGroupTests {
    @Test func exposesSpecCommands() {
        let names = Set(CommandGroup(options: GlobalOptions()).commands.keys)
        for expected in ["client", "server", "plugin", "fabric", "list", "remove", "backup", "version", "completion"] {
            #expect(names.contains(expected))
        }
    }

    @Test func completionNativeShells() {
        // ConsoleKit 原生只支持 bash/zsh（fish/powershell 显式不支持）。
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
        #expect(GamePlan.defaultRoot.hasSuffix("/minecraft"))
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
    @Test func zipsWorldDir() throws {
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
