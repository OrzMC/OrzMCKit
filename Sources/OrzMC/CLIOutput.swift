import ConsoleKit
import Foundation
import Game

/// 命令执行错误（规范 `docs/spec/cli-surface.md` §6）：
/// 用户可读信息写 stderr，退出码 1；`--json` 时改为信封里的 `error`。
struct CLIError: Error {
    let code: String
    let message: String

    init(_ message: String, code: String = "E_RUNTIME") {
        self.code = code
        self.message = message
    }
}

/// `--json` 机器可读信封（规范 §6.1）：单条命令 stdout **恰好一个** JSON 对象。
enum JSONOutput {
    static func write(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let line = String(data: data, encoding: .utf8)
        else { return }
        print(line)
    }

    /// 成功：`{ok:true, command, data, error:null}`。
    static func success(command: String, data: [String: Any] = [:]) {
        write(["ok": true, "command": command, "data": data, "error": NSNull()])
    }

    /// 失败：`{ok:false, command, data:null, error:{code, message}}`。
    static func failure(command: String, code: String, message: String) {
        write(["ok": false, "command": command, "data": NSNull(), "error": ["code": code, "message": message]])
    }

    /// 工具版本数据（`--version` / `version`）。
    static func toolVersionData() -> [String: Any] {
        ["tool": OrzMCVersion.current, "disclaimer": Compliance.text]
    }
}

/// `--json` 模式下的控制台：人类可读日志 / 进度 / 错误一律转 **stderr**，
/// 保证 stdout 只承载最终信封（规范 §6.1）。
final class StderrConsole: Console {
    private let terminal = Terminal()

    var size: (width: Int, height: Int) { terminal.size }

    func input(isSecure: Bool) -> String { terminal.input(isSecure: isSecure) }

    func output(_ text: ConsoleText, newLine: Bool) {
        terminal.report(error: text.description + (newLine ? "\n" : ""), newLine: false)
    }

    func clear(_ type: ConsoleClear) { terminal.clear(type) }

    func report(error: String, newLine: Bool) { terminal.report(error: error, newLine: newLine) }

    var userInfo: [AnySendableHashable: any Sendable] {
        get { terminal.userInfo }
        set { terminal.userInfo = newValue }
    }

    var supportsANSICommands: Bool { false }
}
