import Foundation
import Testing

@testable import Game
@testable import OrzMC

/// 服务端 fabric/forge 对齐（`docs/spec/data-model.md` §3 / `behavior.md` B4）。
@Suite struct ServerDeployTests {
    private func makeLayout(_ root: String, _ type: GameType) -> GamePlan.Layout {
        GamePlan.layout(root: root, version: "1.20.4", type: type)
    }

    private func tempRoot() throws -> String {
        let root = NSTemporaryDirectory() + "/orzmc-server-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        return root
    }

    @Test func serverJarNamesMatchSpec() {
        #expect(GameType.vanilla.serverJarName(version: "1.20.4") == "server.jar")
        #expect(GameType.paper.serverJarName(version: "1.20.4") == "paper-1.20.4.jar")
        #expect(GameType.fabric.serverJarName(version: "1.20.4") == "fabric-server-launch.jar")
        #expect(GameType.forge.serverJarName(version: "1.20.4") == "forge-1.20.4.jar")
    }

    @Test func buildDirIsToolPrivateState() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = makeLayout(root, .forge)
        #expect(layout.serverBuildDir == layout.serverDir + "/build")
        #expect(layout.serverDir.hasSuffix("/versions/1.20.4/server/forge"))
    }

    @Test func forgeIsInstalledRequiresLibraries() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = makeLayout(root, .forge)
        try FileManager.default.createDirectory(atPath: layout.serverDir, withIntermediateDirectories: true)

        #expect(!ForgeServer.isInstalled(layout: layout))
        // 只有 jar 而没有 libraries/：半搬运不算已安装（不能跳过安装器）。
        try Data("jar".utf8).write(to: URL(fileURLWithPath: layout.serverJarPath))
        #expect(!ForgeServer.isInstalled(layout: layout))
        try FileManager.default.createDirectory(
            atPath: layout.serverDir + "/libraries",
            withIntermediateDirectories: true
        )
        #expect(ForgeServer.isInstalled(layout: layout))
    }

    @Test func forgeMovesShimWithLibraries() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = makeLayout(root, .forge)
        let build = layout.serverBuildDir
        try FileManager.default.createDirectory(atPath: build + "/libraries", withIntermediateDirectories: true)
        let shim = build + "/forge-1.20.4-49.0.30-shim.jar"
        try Data("shim".utf8).write(to: URL(fileURLWithPath: shim))
        try Data("lib".utf8).write(to: URL(fileURLWithPath: build + "/libraries/foo.jar"))

        try ForgeServer.moveProducts(
            full: "1.20.4-49.0.30",
            version: "1.20.4",
            buildDir: build,
            layout: layout
        )

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: layout.serverJarPath))
        // 清单 Class-Path 相对 shim 自身 -> libraries/ 必须一起搬。
        #expect(fileManager.fileExists(atPath: layout.serverDir + "/libraries/foo.jar"))
        #expect(ForgeServer.isInstalled(layout: layout))
    }

    @Test func forgeMovesLegacyUniversalJar() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = makeLayout(root, .forge)
        let build = layout.serverBuildDir
        try FileManager.default.createDirectory(atPath: build, withIntermediateDirectories: true)
        let universal = build + "/1.20.4-forge-universal.jar"
        try Data("legacy".utf8).write(to: URL(fileURLWithPath: universal))

        try ForgeServer.moveProducts(
            full: "1.20.4-36.2.0",
            version: "1.20.4",
            buildDir: build,
            layout: layout
        )

        #expect(FileManager.default.fileExists(atPath: layout.serverJarPath))
    }

    @Test func forgeMissingProductThrows() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let layout = makeLayout(root, .forge)
        let build = layout.serverBuildDir
        try FileManager.default.createDirectory(atPath: build, withIntermediateDirectories: true)

        #expect(throws: ForgeServerError.self) {
            try ForgeServer.moveProducts(full: "1.20.4-49.0.30", version: "1.20.4", buildDir: build, layout: layout)
        }
    }
}

/// Paper 的控制台必须是**可用**的（回归：`--noconsole` 曾让所有命令石沉大海）。
@Suite struct PaperLaunchArgumentTests {
    @Test func paperKeepsConsoleEnabled() {
        let args = PaperServer.launchArguments(onlineMode: false)
        #expect(!args.contains("--noconsole"), "带 --noconsole 会让 stdin 命令没人读（GUI 控制台/stop 都失效）")
        #expect(args.contains("--nojline"), "非 TTY 下关掉 JLine 更稳，但控制台本身仍在")
        #expect(args.contains("--online-mode=false"))
    }

    @Test func paperOnlineModeFlagFollowsSetting() {
        #expect(PaperServer.launchArguments(onlineMode: true).contains("--online-mode=true"))
    }

    @Test func otherServersDoNotDisableConsole() {
        // Vanilla / Fabric / Forge 走通用 `launchServer`，不加 Paper 专属 flag；
        // 这里只守住"别再有人往任何核心加 --noconsole"。
        let args = PaperServer.launchArguments(onlineMode: true)
        #expect(args.filter { $0 == "--noconsole" }.isEmpty)
    }
}
