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
        guard let releaseVersions = try? await Mojang.versions(type: .release, forceUpdate: refresh), !releaseVersions.isEmpty
        else {
            throw GameError.noGameVersions
        }
        // 显式指定：命中即用，找不到直接报错（不弹交互）。
        if let version {
            guard let matched = releaseVersions.first(where: { $0.id == version }) else {
                throw MojangAPIError.notFound
            }
            return matched
        }
        // 非 TTY / `--json`：不阻塞，使用最新 release（B9）。
        guard interactive else {
            return releaseVersions[0]
        }
        let versions = Array(releaseVersions[releaseVersions.startIndex..<releaseVersions.startIndex + 10])
        return chooseFromList(versions, display: { $0.id.consoleText() }, hint: Constants.chooseAGameVersion.string, completedHint: Constants.choosedGameVersionHint.string)
    }
}
