import ConsoleKit
import MojangAPI
import Game

extension Console {
    public func userInput(hint: String, completedHint: String? = nil) -> String {
        pushEphemeral()
        output(hint, style: .warning, newLine: false)
        let input = self.input()
        popEphemeral()
        if let completedHint = completedHint {
            output(completedHint.consoleText(.success) + input.consoleText(.info))
        }
        return input
    }
    public func chooseFromList<T>(_ list: [T], display: (T) -> ConsoleText, hint: String, completedHint: String) -> T {
        let choose = choose(hint.consoleText(.warning), from: list, display: display)
        output(completedHint.consoleText(.success) + display(choose).description.consoleText(.info))
        return choose
    }
    public func chooseGameVersion(
        _ version: String?,
        interactive: Bool = TerminalEnvironment.isInteractive,
        refresh: Bool = false,
        root: String = GamePlan.defaultRoot
    ) async throws -> Version {
        await MojangCache.configure(root: root)
        guard let releaseVersions = try? await Mojang.versions(type: .release, forceUpdate: refresh),
              !releaseVersions.isEmpty
        else {
            throw GameError.noGameVersions
        }
        // 快照只在需要时取（显式指定快照 id / 交互切渠道），走同一份清单。
        func snapshotVersions() async -> [Version] {
            (try? await Mojang.versions(type: .snapshot, forceUpdate: false)) ?? []
        }
        // 显式指定：release 与 snapshot 都找（非 release 一律算 snapshot，B10），找不到直接报错。
        if let version {
            if let matched = releaseVersions.first(where: { $0.id == version }) { return matched }
            if let matched = await snapshotVersions().first(where: { $0.id == version }) { return matched }
            throw MojangAPIError.notFound
        }
        // 非 TTY / `--json`：不阻塞，使用最新 release（B9）。
        guard interactive else {
            return releaseVersions[0]
        }
        let snapshots = await snapshotVersions()
        let state = VersionPickerState(
            releases: releaseVersions.map(\.id),
            snapshots: snapshots.map(\.id),
            pageSize: 10
        )
        guard let id = runVersionPicker(console: self, state: state) else {
            return releaseVersions[0]
        }
        return (releaseVersions + snapshots).first(where: { $0.id == id }) ?? releaseVersions[0]
    }
}
