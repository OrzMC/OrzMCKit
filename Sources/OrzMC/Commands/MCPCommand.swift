import ConsoleKit

/// `orzmc mcp`：stdio JSON-RPC 2.0 本地 MCP server（规范 `docs/spec/cli-surface.md` §8.2）。
///
/// 把 CLI 命令暴露为 MCP tools：`tools/list` 由 `capabilities` 生成，`tools/call`
/// 拉起 `orzmc --json <command>` 子进程并回传信封。无参数；stdout 只写 JSON-RPC。
struct MCPCommand: AsyncCommand {
    let options: GlobalOptions

    struct Signature: CommandSignature {}

    var help: String = "本地 MCP server(stdio JSON-RPC 2.0)"

    func run(using context: CommandContext, signature: Signature) async throws {
        MCPServer.serve()
    }
}
