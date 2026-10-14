import ConsoleKit
import Game

/// `orzmc capabilities`：机器可读的能力清单（命令 / 选项 / 退出码；规范 §8）。
///
/// 供 AI / 脚本发现 CLI 能力（D9）；签名由 `CommandCapability` 反射生成，不手写。
struct CapabilitiesCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {}

    var help: String = "打印机器可读的能力清单(命令 / 选项 / 退出码)"

    func run(using context: CommandContext, signature: Signature) async throws {
        let capabilities = CommandGroup(options: options).capabilityList()
        let data: [String: Any] = [
            "tool": "orzmc",
            "version": OrzMCVersion.current,
            "exitCodes": [
                ["code": 0, "meaning": "成功"],
                ["code": 1, "meaning": "运行错误(错误信息写 stderr)"],
                ["code": 130, "meaning": "用户取消(Ctrl-C / 拒绝确认)"],
            ],
            "envelope": ["ok": "bool", "command": "string", "data": "object|null", "error": "{code,message}|null"],
            "commands": capabilities.map { capability in
                [
                    "name": capability.name,
                    "help": capability.help,
                    "options": capability.values.map(\.json),
                ] as [String: Any]
            },
        ]
        if options.json {
            JSONOutput.success(command: "capabilities", data: data)
            return
        }
        for capability in capabilities {
            context.console.print("\(capability.name) — \(capability.help)")
            for value in capability.values {
                context.console.print("    \(value.names.joined(separator: ", "))  \(value.help)")
            }
        }
    }
}
