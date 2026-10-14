import Foundation
import ConsoleKit
import Fabric
import Game
import TransferKit

struct FabricCommand: AsyncCommand {
    
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
        
        if let installer = signature.installer, let version = signature.version, let installerURL = URL(string: installer), version.count > 0 {
            let installType = signature.server ? Fabric.InstallType.server : Fabric.InstallType.client
            let installDir = signature.server ? GameDir.server(version: version) : GameDir.client(version: version)
            if installerURL.isFileURL {
                try await Fabric.installFabric(
                    installType,
                    installerFileURL: installerURL,
                    installDir: installDir.dirPath,
                    version: version)
            }
            else {
                // 统一走 TransferKit 下载安装器
                let localFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(installerURL.lastPathComponent)
                let progressBar = context.console.progressBar(title: installerURL.lastPathComponent)
                progressBar.start()
                try await Transfer().download(
                    DownloadItem(url: installerURL, destination: localFileURL)
                )
                progressBar.succeed()

                // Fabric安装器
                try await Fabric.installFabric(
                    installType,
                    installerFileURL: localFileURL,
                    installDir: installDir.dirPath,
                    version: version)
            }
        }
        else {
            var context = context
            outputHelp(using: &context)
        }
    }
}
