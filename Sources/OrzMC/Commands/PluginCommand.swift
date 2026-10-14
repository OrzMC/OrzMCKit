import ConsoleKit
import JokerKits
import Foundation
import Game
import HangarAPI

/// `orzmc plugin`：Hangar 搜索 / 下载服务端插件。
struct PluginCommand: AsyncCommand {
    let options: GlobalOptions

    var help: String = Constants.pluginHelp.string

    struct Signature: CommandSignature {
        @Flag(name: "list", short: "l", help: Constants.pluginListHelp.string)
        var list: Bool

        @Option(name: "output", short: "o", help: Constants.pluginOutputHelp.string)
        var output: String?

        @Option(name: "search", short: "s", help: Constants.pluginSearchHelp.string)
        var searchText: String?

        @Option(name: "count", short: "c", help: Constants.pluginSearchResultCountHelp.string)
        var searchResultCountMax: Int64?

        @Option(name: "version", short: "v", help: Constants.pluginSpecifiedGameVersionHelp.string)
        var version: String?
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let console = context.console
        let plugin = PaperPlugin()
        if let searchText = signature.searchText {
            let (results, _) = try await plugin.search(
                with: searchText,
                pagination: .init(limit: signature.searchResultCountMax ?? Constants.pluginSearchResultCountMaxDefault)
            )
            guard let results, !results.isEmpty else {
                if options.json {
                    JSONOutput.success(command: "plugin", data: ["mode": "search", "count": 0, "results": []])
                } else {
                    console.error(Constants.uiOutputPluginSearchNoResult.string)
                }
                return
            }
            if options.json {
                JSONOutput.success(
                    command: "plugin",
                    data: ["mode": "search", "count": results.count, "results": results.map(Self.json)]
                )
                return
            }
            let searchResultHint = "搜索结果".consoleText(.success) + "(\(results.count))".consoleText(.warning) + "个:\n".consoleText(.success)
            console.output(searchResultHint, newLine: true)
            results.forEach { $0.output(console: console) }
        } else if signature.list {
            let loadingBar = console.loadingBar(title: "插件信息获取中")
            loadingBar.start()
            let foundPlguins = try await plugin.allPlugin()
            loadingBar.activity.title = "插件信息获取完成"
            loadingBar.succeed()

            let notFoundPlugins = PaperPlugin.all.filter { pluginName in
                !foundPlguins.contains { project in project.name == pluginName }
            }
            if options.json {
                JSONOutput.success(
                    command: "plugin",
                    data: [
                        "mode": "list",
                        "plugins": foundPlguins.compactMap(\.name),
                        "notFound": notFoundPlugins,
                    ]
                )
                return
            }
            console.success("获取到的插件如下：")
            foundPlguins.forEach { $0.output(console: console) }
            if !notFoundPlugins.isEmpty {
                console.output("未获取插件信息：".consoleText(.error) + notFoundPlugins.joined(separator: ",").consoleText(.warning) + .newLine)
            }
        } else {
            guard let outputDirFilePath = signature.output else {
                throw CLIError(Constants.uiOutputUnspecifyOutputPath.string, code: "E_USAGE")
            }
            try outputDirFilePath.makeDirIfNeed()
            let outputDirFileURL = URL(fileURLWithPath: outputDirFilePath)
            let progressBar = console.progressBar(title: Constants.uiOutputDownloading.string)
            let allPlugins = try await plugin.allPlugin()
            var downloaded: [String] = []
            for plugin in allPlugins {
                guard let downloadItem = try await plugin.downloadItem(outputFileDirURL: outputDirFileURL, version: signature.version) else {
                    continue
                }
                downloaded.append(downloadItem.dstFileURL.lastPathComponent)
                progressBar.activity.title = "\(plugin.name ?? "") \(Constants.uiOutputDownloading.string)"
                try await Downloader.download(downloadItem, progressBar: progressBar)
            }
            if options.json {
                JSONOutput.success(
                    command: "plugin",
                    data: ["mode": "download", "directory": outputDirFileURL.path, "files": downloaded]
                )
                return
            }
            console.output(Constants.uiOutputDownloadedToDir.string.consoleText(.info) + outputDirFileURL.path.consoleText(.success))
            await Shell.runCommand(with: ["open", outputDirFileURL.path])
        }
    }

    /// `PluginProject` → `--json` 可序列化子集（缺失字段省略）。
    private static func json(_ project: PluginProject) -> [String: Any] {
        var object: [String: Any] = [:]
        if let name = project.name { object["name"] = name }
        if let description = project.description { object["description"] = description }
        if let category = project.category?.rawValue { object["category"] = category }
        if let downloads = project.stats?.downloads { object["downloads"] = downloads }
        if let views = project.stats?.views { object["views"] = views }
        if let stars = project.stats?.stars { object["stars"] = stars }
        return object
    }
}
