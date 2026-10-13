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

    @Test func defaultTypes() {
        #expect(GameDir.defaultClientType == GameType.vanilla.rawValue)
        #expect(GameDir.defaultServerType == GameType.vanilla.rawValue)
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
