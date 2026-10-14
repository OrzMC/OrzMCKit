import Foundation
import ConsoleKit
import Fabric
import Game
import TransferKit

/// `orzmc fabric`：Fabric 客户端 / 服务端安装（保留为 `client/server -t fabric` 之外的入口）。
struct FabricCommand: AsyncCommand {
    let options: GlobalOptions

    var help: String = Constants.fabricHelp.string

    struct Signature: CommandSignature {
        @Flag(name: "server", short: "s", help: Constants.fabricServerHelp.string)
        var server: Bool

        @Option(name: "installer", short: "i", help: Constants.fabricInstallerHelp.string)
        var installer: String?

        @Option(name: "version", short: "v", help: Constants.fabricVersionHelp.string)
        var version: String?
    }

    func run(using context: CommandContext, signature: Signature) async throws {

        guard let installer = signature.installer,
              let version = signature.version,
              let installerURL = URL(string: installer),
              version.count > 0
        else {
            if options.json {
                throw CLIError("fabric 需要 --installer 与 --version", code: "E_USAGE")
            }
            var context = context
            outputHelp(using: &context)
            return
        }

        let installType = signature.server ? Fabric.InstallType.server : Fabric.InstallType.client
        let installDir = signature.server
            ? GamePlan.serverDir(version: version, type: .fabric)
            : GamePlan.clientDir(version: version)

        if installerURL.isFileURL {
            try await Fabric.installFabric(
                installType,
                installerFileURL: installerURL,
                installDir: installDir,
                version: version)
        } else {
            // 统一走 TransferKit 下载安装器
            let localFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(installerURL.lastPathComponent)
            let progressBar = context.console.progressBar(title: installerURL.lastPathComponent)
            progressBar.start()
            try await Transfer().download(
                DownloadItem(url: installerURL, destination: localFileURL)
            )
            progressBar.succeed()

            // Fabric 安装器
            try await Fabric.installFabric(
                installType,
                installerFileURL: localFileURL,
                installDir: installDir,
                version: version)
        }

        if options.json {
            JSONOutput.success(
                command: "fabric",
                data: ["version": version, "type": installType == .server ? "server" : "client", "directory": installDir]
            )
        }
    }
}
