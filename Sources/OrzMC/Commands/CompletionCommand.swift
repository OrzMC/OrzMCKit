import ConsoleKit
import Foundation
import Game

/// `orzmc completion`：生成 / 安装 Shell 补全（规范 `docs/spec/cli-surface.md` §4.5 / §9、
/// `frontends.md` F6）。
///
/// bash / zsh 由 ConsoleKit 渲染；fish / PowerShell 由 `CompletionScripts` 依据同一份
/// `capabilityList()` 生成（ConsoleKit 原生不支持这两个 shell）。
///
/// 安装侧（`install`）的硬约束，两套实现一致：
/// - shell **只读 `$SHELL`**（不做进程探测 / 不执行外部命令探测）；
/// - 固定落点 + 幂等覆盖，rc 只在必要时补一行；
/// - `powershell` / `pwsh` 只生成脚本、不落盘 → `install` 明确返回 `E_UNSUPPORTED`；
/// - 落盘后把路径登记进 `install.conf` 的 `completion_file`，供 `uninstall` 清理。
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

    /// 按 `frontends.md` F6：只生成脚本、不落盘安装。
    static let scriptOnlyShells: Set<String> = ["powershell", "pwsh"]

    /// `$SHELL` / 显式目标 → 规范 shell 名（去路径、去 `.exe`、小写）；不认识返回 nil。
    static func normalizedShell(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let name = ((raw as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        return shells.contains(name) ? name : nil
    }

    func run(using context: CommandContext, signature: Signature) async throws {
        let target = signature.shell.lowercased()
        if target == "install" {
            try install(context: context)
            return
        }
        let script = try render(context: context, target: target)
        if options.json {
            // `shell` 回显**请求值**（`pwsh` 不折叠成 `powershell`），规范 §4.5。
            JSONOutput.success(
                command: "completion",
                data: ["mode": "script", "shell": target, "script": script]
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
                throw CLIError(
                    "不支持的 shell: \(target)(支持 \(Self.shells.joined(separator: "、")) )",
                    code: "E_USAGE"
                )
            }
            return renderConsoleKitScript(context: context, shell: shell)
        case "fish":
            return CompletionScripts.fish(root().capabilityList())
        case "powershell":
            return CompletionScripts.powershell(root().capabilityList())
        default:
            throw CLIError(
                "不支持的 shell: \(target)(支持 \(Self.shells.joined(separator: "、")) )",
                code: "E_USAGE"
            )
        }
    }

    /// 以 `orzmc` 为入口渲染脚本（去掉 `completion ...` 的路径偏移）。
    private func renderConsoleKitScript(context: CommandContext, shell: Shell) -> String {
        var renderContext = context
        let raw = renderContext.input.executablePath.first ?? Self.programName
        renderContext.input.executablePath = [Self.programName(from: raw)]
        return root().renderCompletionScript(using: renderContext, shell: shell)
    }

    /// 补全脚本里的函数名/命令名（规范 §4.5：**必须是 `orzmc`**）。
    ///
    /// 之前直接用 `argv[0]`，Windows 上会渲染成 `function _D:\a\...\orzmc.exe()`——
    /// 生成的脚本完全不可用（实测于 Windows 探针）。
    static let programName = "orzmc"

    /// `argv[0]` → 补全脚本用的命令名：取最后一段路径（`/` 与 `\` 都切）、去 `.exe`、空则回落 `orzmc`。
    static func programName(from raw: String) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let stripped = last.lowercased().hasSuffix(".exe") ? String(last.dropLast(4)) : last
        return stripped.isEmpty ? programName : stripped
    }

    private func install(context: CommandContext) throws {
        let environment = ProcessInfo.processInfo.environment
        // 规范 §4.5：只读环境变量；识别不出 → E_USAGE，并给出可执行退路。
        guard let shellName = Self.normalizedShell(environment["SHELL"]) else {
            throw CLIError(
                "无法从 $SHELL 判断当前 shell;请用 `orzmc completion <shell>` 生成脚本后手动安装",
                code: "E_USAGE"
            )
        }
        guard !Self.scriptOnlyShells.contains(shellName) else {
            throw CLIError(
                "\(shellName) 不支持自动安装补全(规范 F6):把 `orzmc completion \(shellName)` 的输出加入 $PROFILE",
                code: "E_UNSUPPORTED"
            )
        }
        // 用 $HOME（可被测试/沙箱覆盖）；NSHomeDirectory() 在 macOS 上会忽略 $HOME。
        let home = environment["HOME"] ?? NSHomeDirectory()
        let completionPath: String
        var hint: String?

        switch shellName {
        case "bash":
            completionPath = "\(home)/.local/share/bash-completion/completions/orzmc"
            try writeScript(render(context: context, target: "bash"), to: completionPath)
            // 落点靠 bash-completion 自动加载；没装（如 macOS 自带 bash 3.2）就必须 source。
            // 行尾标记与 Python 一致（`# added by orzmc ...`）：便于幂等识别与用户检索。
            hint = ensureLine(
                "[ -f \"\(completionPath)\" ] && . \"\(completionPath)\"  # added by orzmc completion install",
                in: "\(home)/.bashrc"
            )
        case "zsh":
            completionPath = "\(home)/.zsh/completions/_orzmc"
            try writeScript(render(context: context, target: "zsh"), to: completionPath)
            hint = ensureLine(
                "fpath+=(~/.zsh/completions); autoload -Uz compinit; compinit  # added by orzmc completion install",
                in: "\(home)/.zshrc"
            )
        case "fish":
            completionPath = "\(home)/.config/fish/completions/orzmc.fish"
            // fish 自动加载该目录，无需改 rc。
            try writeScript(render(context: context, target: "fish"), to: completionPath)
        default:
            throw CLIError(
                "不支持自动安装 \(shellName) 的补全;请用 `orzmc completion \(shellName)` 生成脚本",
                code: "E_UNSUPPORTED"
            )
        }

        // 登记到 install.conf（§4.5 / F2）：没有安装记录时跳过（开发环境），不报错。
        Self.recordCompletionFile(completionPath)

        if options.json {
            JSONOutput.success(
                command: "completion",
                data: [
                    "mode": "install",
                    "shell": shellName,
                    "path": completionPath,
                    "hint": hint.map { $0 as Any } ?? NSNull(),
                ]
            )
        } else {
            context.console.success("已安装 \(shellName) 补全: \(completionPath)")
            if let hint { context.console.print(hint) }
        }
    }

    /// 把补全路径写进安装记录（`frontends.md` F2：卸载要清掉自己装的东西）。
    static func recordCompletionFile(_ completionPath: String) {
        guard var found = InstallManifest.find(binary: InstallSupport.runningBinary()) else { return }
        found.manifest.completionFile = completionPath
        try? found.manifest.write(to: found.path)
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
