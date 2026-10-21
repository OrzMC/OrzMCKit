import Foundation
import Testing
@testable import Game

@Suite struct ServerPropertiesTests {

    @Test func readsLevelName() {
        let text = """
        #Minecraft server properties
        #Mon Oct 20 12:00:00 UTC 2026
        enable-query=false
        level-name=my world
        online-mode=true
        """
        #expect(ServerProperties.levelName(contents: text) == "my world")
    }

    @Test func colonSeparatorAlsoWorks() {
        #expect(ServerProperties.levelName(contents: "level-name:skyblock") == "skyblock")
    }

    @Test func matchesFullKeyOnly() {
        let text = """
        level-name-extra=nope
        level-name=world
        """
        #expect(ServerProperties.levelName(contents: text) == "world")
    }

    @Test func emptyValueFallsBack() {
        #expect(ServerProperties.levelName(contents: "level-name=\n") == nil)
    }

    @Test func missingFileUsesDefault() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "props-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ServerProperties.levelName(atServerDir: dir.path) == "world")
    }

    @Test func readsFromServerDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "props-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "level-name=hardcore\n".write(toFile: dir.appending(path: "server.properties").path, atomically: true, encoding: .utf8)
        #expect(ServerProperties.levelName(atServerDir: dir.path) == "hardcore")
    }

    @Test func worldDirHonoursLevelName() {
        let world = GamePlan.serverWorldDir(version: "1.21.5", type: .paper, levelName: "skyblock", root: "/tmp/mc")
        #expect(world.hasSuffix("/server/paper/skyblock"), "\(world)")
        let defaultWorld = GamePlan.serverWorldDir(version: "1.21.5", type: .paper, root: "/tmp/mc")
        #expect(defaultWorld.hasSuffix("/server/paper/world"), "\(defaultWorld)")
    }

    @Test func commonServerDirectories() {
        let logs = GamePlan.serverLogsDir(version: "1.21.5", type: .vanilla, root: "/tmp/mc")
        let mods = GamePlan.serverModsDir(version: "1.21.5", type: .fabric, root: "/tmp/mc")
        let config = GamePlan.serverConfigDir(version: "1.21.5", type: .forge, root: "/tmp/mc")
        #expect(logs.hasSuffix("/server/vanilla/logs"))
        #expect(mods.hasSuffix("/server/fabric/mods"))
        #expect(config.hasSuffix("/server/forge/config"))
    }
}
