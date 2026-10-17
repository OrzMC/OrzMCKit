import ConsoleKit
import Foundation

/// `orzmc completion`：生成 / 安装 Shell 补全（规范 `docs/spec/cli-surface.md` §9）。
///
/// bash / zsh 由 ConsoleKit 渲染；fish / PowerShell 由 `CompletionScripts` 依据同一份
/// `capabilityList()` 生成（ConsoleKit 原生不支持这两个 shell）。
struct CompletionCommand: AsyncCommand {
    let options: GlobalOptions
    /// 根命令工厂：渲染补全脚本需要整棵命令树。用闭包延迟构造，避免与
    /// `CommandGroup.init` 形成构造期循环。
    let root: @Sendable () -> CommandGroup

    struct Signature: CommandSignature {
        @Argument(name: "shell", help: "bash|zsh|fish|powershell|pwsh 打印补全脚本；install 写入 shell 补全目录")
        var shell: String
    }

    var help: String = "生成 / 安装 Shell 补全(bash/zsh/fish/powershell)"

    /// 支持的补全目标（与 manifest `completion.target` 的 enum 对齐）。
    static let shells = ["bash", "zsh", "fish", "powershell", "pwsh", "install"]

    func run(using context: CommandContext, signature: Signature) async throws {
        let target = signature.shell.lowercased()
        if target == "install" {
            try install(context: context)
            return
        }
        let script = try render(context: context, target: target)
        if options.json {
            JSONOutput.success(
                command: "completion",
                data: ["mode": "script", "shell": canonical(target), "script": script]
            )
        } else {
            context.console.print(script, newLine: false)
        }
    }

    /// `pwsh` 是 `powershell` 的别名（与 manifest enum 一致，输出同名脚本）。
    private func canonical(_ target: String) -> String {
        target == "pwsh" ? "powershell" : target
    }

    private func render(context: CommandContext, target: String) throws -> String {
        switch canonical(target) {
        case "bash", "zsh":
            guard let shell = Shell(rawValue: target) else {
                throw CLIError("不支持的 shell: \(target)", code: "E_UNSUPPORTED")
            }
            return renderConsoleKitScript(context: context, shell: shell)
        case "fish":
            return CompletionScripts.fish(root().capabilityList())
        case "powershell":
            return CompletionScripts.powershell(root().capabilityList())
        default:
            throw CLIError(
                "不支持的 shell: \(target)(支持 \(Self.shells.joined(separator: "、")) )",
                code: "E_UNSUPPORTED"
            )
        }
    }

    /// 以 `orzmc` 为入口渲染脚本（去掉 `completion ...` 的路径偏移）。
    private func renderConsoleKitScript(context: CommandContext, shell: Shell) -> String {
        var renderContext = context
        renderContext.input.executablePath = [renderContext.input.executablePath.first ?? "orzmc"]
        return root().renderCompletionScript(using: renderContext, shell: shell)
    }

    private func install(context: CommandContext) throws {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        let shellName = (shellPath as NSString).lastPathComponent
        // 用 $HOME（可被测试/沙箱覆盖）；NSHomeDirectory() 在 macOS 上会忽略 $HOME。
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let fileManager = FileManager.default
        let completionPath: String
        var rcNote: String?

        switch shellName {
        case "bash":
            completionPath = "\(home)/.local/share/bash-completion/completions/orzmc"
            try writeScript(render(context: context, target: "bash"), to: completionPath)
            rcNote = ensureLine(
                "[ -f \"\(completionPath)\" ] && . \"\(completionPath)\"",
                in: "\(home)/.bashrc"
            )
        case "zsh":
            completionPath = "\(home)/.zsh/completions/_orzmc"
            try writeScript(render(context: context, target: "zsh"), to: completionPath)
            rcNote = ensureLine("fpath=(~/.zsh/completions $fpath)", in: "\(home)/.zshrc")
        case "fish":
            completionPath = "\(home)/.config/fish/completions/orzmc.fish"
            // fish 自动加载该目录，无需改 rc。
            try writeScript(render(context: context, target: "fish"), to: completionPath)
        default:
            throw CLIError(
                "无法从 $SHELL 识别支持的 shell(bash/zsh/fish)；请用 `orzmc completion <shell>` 手动生成",
                code: "E_UNSUPPORTED"
            )
        }

        if options.json {
            JSONOutput.success(
                command: "completion",
                data: ["mode": "install", "shell": shellName, "path": completionPath]
            )
        } else {
            context.console.success("已安装 \(shellName) 补全: \(completionPath)")
            if let rcNote { context.console.print(rcNote) }
        }
    }

    private func writeScript(_ script: String, to path: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try script.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// 幂等地把一行加入 rc 文件；已存在则返回 nil，否则返回给用户的提示。
    private func ensureLine(_ line: String, in path: String) -> String? {
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        if existing.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == line }) {
            return nil
        }
        let addition = existing.isEmpty || existing.hasSuffix("\n") ? "\(line)\n" : "\n\(line)\n"
        if FileManager.default.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
            handle.seekToEndOfFile()
            handle.write(Data(addition.utf8))
            try? handle.close()
        } else {
            try? addition.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return "已把补全加载行写入 \(path)；请新开终端或 source 后生效"
    }
}
