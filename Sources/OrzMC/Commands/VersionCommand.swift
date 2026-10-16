import ConsoleKit
import Game

/// `orzmc version`：打印工具版本（与全局 `--version` 同源）。
struct VersionCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {}

    var help: String = "打印工具版本"

    func run(using context: CommandContext, signature: Signature) async throws {
        if options.json {
            JSONOutput.success(command: "version", data: JSONOutput.toolVersionData())
        } else {
            context.console.output("orzmc \(OrzMCVersion.current)")
            context.console.output(Compliance.line.consoleText())
        }
    }
}
