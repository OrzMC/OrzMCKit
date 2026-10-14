import Foundation
import Testing

@testable import Game

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
