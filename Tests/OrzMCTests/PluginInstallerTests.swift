import Foundation
import Testing
@testable import Game

@Suite struct PluginInstallerTests {

    // MARK: 扫描

    @Test func scanOnlyTakesEnabledJars() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "plugin-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["LuckPerms-Bukkit-5.4.1.jar", "EssentialsX.jar.disabled", "WorldEdit.jar", "notes.txt"] {
            FileManager.default.createFile(atPath: dir.appending(path: name).path, contents: Data())
        }
        try FileManager.default.createDirectory(at: dir.appending(path: "update"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appending(path: "update/Vault.jar").path, contents: Data())

        let jars = PluginInstaller.scan(pluginsDir: dir.path)
        #expect(jars.map(\.fileName) == ["LuckPerms-Bukkit-5.4.1.jar", "WorldEdit.jar"],
                "只收 plugins/ 里启用的 .jar，忽略 .disabled 与 update/ 子目录")
    }

    @Test func scanMissingDirectoryIsEmpty() {
        #expect(PluginInstaller.scan(pluginsDir: "/definitely/not/here").isEmpty)
    }

    // MARK: 匹配

    @Test func jarBelongsToProjectByNormalizedPrefix() {
        #expect(PluginInstaller.belongs(jarNamed: "LuckPerms-Bukkit-5.4.1.jar", toProject: "LuckPerms"))
        #expect(PluginInstaller.belongs(jarNamed: "essentialsx.jar", toProject: "Essentials"))
        #expect(!PluginInstaller.belongs(jarNamed: "ViaBackwards-5.0.0.jar", toProject: "ViaVersion"),
                "Via 系列互不误配")
        #expect(!PluginInstaller.belongs(jarNamed: "X.jar", toProject: "LuckPerms"))
    }

    @Test func versionTokenPicksLongestNumericRun() {
        #expect(PluginInstaller.versionToken(in: "LuckPerms-Bukkit-5.4.1") == "5.4.1")
        #expect(PluginInstaller.versionToken(in: "ViaVersion-4.9.1-SNAPSHOT") == "4.9.1")
        #expect(PluginInstaller.versionToken(in: "essentialsx") == nil)
    }

    // MARK: 状态与目标目录

    @Test func notInstalledGoesToPluginsDirectory() {
        let state = PluginInstaller.state(
            project: "LuckPerms",
            latestFileName: "LuckPerms-Bukkit-5.4.1.jar",
            installed: []
        )
        #expect(state == .notInstalled)
        #expect(PluginInstaller.target(for: state) == .plugins)
    }

    @Test func sameVersionIsUpToDate() {
        let installed = [InstalledPlugin(fileName: "LuckPerms-Bukkit-5.4.1.jar", path: "/p/x.jar")]
        let state = PluginInstaller.state(
            project: "LuckPerms",
            latestFileName: "LuckPerms-Bukkit-5.4.1.jar",
            installed: installed
        )
        #expect(state == .upToDate(installed: "5.4.1"))
        #expect(PluginInstaller.target(for: state) == .update)
    }

    @Test func olderVersionIsOutdated() {
        let installed = [InstalledPlugin(fileName: "LuckPerms-Bukkit-5.3.0.jar", path: "/p/x.jar")]
        let state = PluginInstaller.state(
            project: "LuckPerms",
            latestFileName: "LuckPerms-Bukkit-5.4.1.jar",
            installed: installed
        )
        #expect(state == .outdated(installed: "5.3.0", latest: "5.4.1"))
        #expect(PluginInstaller.target(for: state) == .update, "更新必须进 plugins/update/")
    }

    @Test func renamedJarWithSameVersionCountsAsUpToDate() {
        // 玩家把 jar 改名成 `LuckPerms-5.4.1.jar`（少了平台段）——版本一致就别重复下载。
        let installed = [InstalledPlugin(fileName: "LuckPerms-5.4.1.jar", path: "/p/x.jar")]
        let state = PluginInstaller.state(
            project: "LuckPerms",
            latestFileName: "LuckPerms-Bukkit-5.4.1.jar",
            installed: installed
        )
        #expect(state == .upToDate(installed: "5.4.1"))
    }

    @Test func otherPluginsDoNotAffectState() {
        let installed = [
            InstalledPlugin(fileName: "WorldEdit-7.3.0.jar", path: "/p/we.jar"),
            InstalledPlugin(fileName: "EssentialsX-2.20.1.jar", path: "/p/e.jar"),
        ]
        let state = PluginInstaller.state(
            project: "LuckPerms",
            latestFileName: "LuckPerms-Bukkit-5.4.1.jar",
            installed: installed
        )
        #expect(state == .notInstalled)
    }

    @Test func directoryCreatesUpdateFolderOnDemand() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "plugin-dir-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let plugins = base.appending(path: "plugins").path
        let update = base.appending(path: "plugins/update").path
        let dir = try PluginInstaller.directory(for: .update, pluginsDir: plugins, updateDir: update)
        #expect(dir == update)
        #expect(FileManager.default.fileExists(atPath: update))
    }
}
