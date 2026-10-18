import Foundation
import Testing

@testable import OrzMC

/// `capabilities` 上报的枚举值（父仓库 `surface.py` 据此与 manifest 比对）。
@Suite struct CapabilityEnumTests {
    private func spec(_ command: String, _ option: String) -> SignatureValueSpec? {
        CommandGroup(options: GlobalOptions()).capabilityList()
            .first { $0.name == command }?
            .values.first { $0.names.contains(option) }
    }

    @Test func serverSupportsAllFourTypes() {
        #expect(spec("server", "--type")?.enumValues == ["vanilla", "paper", "fabric", "forge"])
    }

    @Test func clientSupportsThreeTypes() {
        #expect(spec("client", "--type")?.enumValues == ["vanilla", "fabric", "forge"])
    }

    @Test func updateChannels() {
        #expect(spec("update", "--channel")?.enumValues == ["release", "beta"])
    }

    @Test func completionCoversAllShells() {
        #expect(
            spec("completion", "shell")?.enumValues
                == ["bash", "zsh", "fish", "powershell", "pwsh", "install"]
        )
    }

    @Test func appStoreChannelIsNotClaimed() {
        // App Store 未上架：只声明 release（manifest 目标含 appstore，属已声明差异）。
        #expect(spec("app", "--channel")?.enumValues == ["release"])
    }

    @Test func nonEnumOptionsStayNil() {
        #expect(spec("client", "--username")?.enumValues == nil)
    }

    @Test func jsonCarriesEnum() throws {
        let value = try #require(spec("server", "--type"))
        let json = value.json
        #expect(json["enum"] as? [String] == ["vanilla", "paper", "fabric", "forge"])
    }
}

/// fish / PowerShell 补全由同一份 `capabilityList()` 渲染（ConsoleKit 不支持它们）。
/// 补全落点的 shell 判定（规范 `cli-surface.md` §4.5:只读 `$SHELL`,不做进程探测）。
@Suite struct CompletionShellResolutionTests {
    @Test func normalizesShellPath() {
        #expect(CompletionCommand.normalizedShell("/bin/zsh") == "zsh")
        #expect(CompletionCommand.normalizedShell("/usr/local/bin/fish") == "fish")
        #expect(CompletionCommand.normalizedShell("/opt/homebrew/bin/bash") == "bash")
        #expect(CompletionCommand.normalizedShell("/usr/local/bin/pwsh") == "pwsh")
    }

    @Test func rejectsUnknownAndEmpty() {
        #expect(CompletionCommand.normalizedShell("/bin/tcsh") == nil)
        #expect(CompletionCommand.normalizedShell("") == nil)
        #expect(CompletionCommand.normalizedShell(nil) == nil)
    }

    @Test func scriptOnlyShellsMatchSpec() {
        // frontends.md F6:powershell/pwsh 只生成脚本、不落盘。
        #expect(CompletionCommand.scriptOnlyShells == ["powershell", "pwsh"])
    }
}

@Suite struct CompletionScriptTests {
    /// 规范 §4.5：脚本里的命令名/函数名固定为 `orzmc`。
    @Test func programNameNormalizesArgv0() {
        #expect(CompletionCommand.programName(from: "orzmc") == "orzmc")
        #expect(CompletionCommand.programName(from: "/usr/local/bin/orzmc") == "orzmc")
        #expect(CompletionCommand.programName(from: "C:\\Users\\x\\.local\\bin\\orzmc.exe") == "orzmc")
        #expect(CompletionCommand.programName(from: "C:/tools/orzmc.EXE") == "orzmc")
        #expect(CompletionCommand.programName(from: "") == "orzmc")
    }

    @Test func fishListsCommandsAndOptions() {
        let script = CompletionScripts.fish(CommandGroup(options: GlobalOptions()).capabilityList())
        #expect(script.contains("complete -c orzmc -f"))
        #expect(script.contains("__fish_use_subcommand\" -a \"server\""))
        #expect(script.contains("__fish_seen_subcommand_from server"))
        #expect(script.contains("-l type"))
    }

    @Test func powershellRegistersCompleter() {
        let script = CompletionScripts.powershell(CommandGroup(options: GlobalOptions()).capabilityList())
        #expect(script.contains("Register-ArgumentCompleter -Native -CommandName orzmc"))
        #expect(script.contains("'server'"))
        #expect(script.contains("'capabilities'"))
    }
}
