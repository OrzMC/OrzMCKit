import ConsoleKit
import Foundation
import Game

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct OrzMC {
    static func main() async {
        // 规范 §1/§3：全局选项在子命令之前预解析（ConsoleKit 之上）。
        let parsed = GlobalOptions.parse(CommandLine.arguments)

        // 全局 `--version` = 工具版本（与子命令 `-v/--version` = 游戏版本靠位置区分）。
        if parsed.versionRequested {
            if parsed.options.json {
                JSONOutput.success(command: "_root", data: JSONOutput.toolVersionData())
            } else {
                print("orzmc \(OrzMCVersion.current)")
                print()
                print(Compliance.text)
            }
            exit(0)
        }

        // `--json`：stdout 只留信封，人类可读日志/进度转 stderr（规范 §6.1）。
        let console: any Console = parsed.options.json ? StderrConsole() : Terminal()
        let input = CommandInput(arguments: parsed.remaining)
        let context = CommandContext(console: console, input: input)
        do {
            try await console.run(CommandGroup(options: parsed.options), with: context)
        } catch CommandError.missingCommand {
            // 无子命令：人类可读模式打印帮助（stdout）并退出 0（§1）；
            // `--json` 下 stdout 不能既有帮助又有信封，改为失败信封退出 1。
            if parsed.options.json {
                JSONOutput.failure(command: "_root", code: "E_USAGE", message: "缺少子命令")
                exit(1)
            }
            exit(0)
        } catch {
            // B11：归一化用户可读信息到 stderr，退出码 1（不裸抛底层异常）。
            let message = ErrorPresentation.message(for: error)
            let code = (error as? CLIError)?.code ?? "E_RUNTIME"
            if parsed.options.json {
                JSONOutput.failure(command: parsed.commandName, code: code, message: message)
            } else {
                FileHandle.standardError.write(Data("错误：\(message)\n".utf8))
            }
            // 规范 §6：用户取消退出 130，其余运行错误 1。
            exit(code == "E_CANCELLED" ? 130 : 1)
        }
    }
}
