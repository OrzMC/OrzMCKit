import Foundation
import Game
import Testing

@testable import OrzMC

/// 假 runner：记录 argv、回放预设 stdout（完全离线）。
private final class FakeRunner: MCPRunning {
    var received: [[String]] = []
    var stdout: String
    var stderr: String
    var exitCode: Int32

    init(stdout: String = "", stderr: String = "", exitCode: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    func run(arguments: [String]) throws -> MCPProcessResult {
        received.append(arguments)
        return MCPProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

private let capabilities = CommandGroup(options: GlobalOptions()).capabilityList()

private func request(_ method: String, _ params: [String: Any]? = nil, id: Int = 1) -> [String: Any] {
    var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
    if let params { message["params"] = params }
    return message
}

private func call(_ message: [String: Any], runner: FakeRunner) -> [String: Any]? {
    MCPServer.handleMessage(message, capabilities: capabilities, runner: runner)
}

/// `orzmc mcp`（规范 cli-surface.md §8.2）。
@Suite struct MCPServerTests {
    @Test func initializeEchoesProtocolVersion() {
        let runner = FakeRunner()
        let response = call(request("initialize", ["protocolVersion": "2024-11-05"]), runner: runner)
        let result = response?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
        let serverInfo = result?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "orzmc")
        #expect(serverInfo?["version"] as? String == OrzMCVersion.current)
        #expect((result?["capabilities"] as? [String: Any])?["tools"] != nil)
    }

    @Test func initializeDefaultsProtocolVersion() {
        let response = call(request("initialize"), runner: FakeRunner())
        let result = response?["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == MCPServer.defaultProtocolVersion)
    }

    @Test func toolsListExcludesMetaCommands() {
        let response = call(request("tools/list"), runner: FakeRunner())
        let tools = (response?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        for expected in ["client", "server", "list", "app", "remove"] {
            #expect(names.contains(expected))
        }
        for excluded in ["capabilities", "completion", "mcp", "self-uninstall"] {
            #expect(!names.contains(excluded))
        }
    }

    @Test func toolsListSchemaShapes() {
        let response = call(request("tools/list"), runner: FakeRunner())
        let tools = (response?["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        let byName = Dictionary(uniqueKeysWithValues: tools.compactMap { tool -> (String, [String: Any])? in
            guard let name = tool["name"] as? String else { return nil }
            return (name, tool)
        })

        let appSchema = byName["app"]?["inputSchema"] as? [String: Any]
        let appProperties = appSchema?["properties"] as? [String: Any]
        #expect((appProperties?["action"] as? [String: Any])?["type"] as? String == "string")
        #expect(appSchema?["required"] as? [String] == ["action"])
        #expect((appProperties?["yes"] as? [String: Any])?["type"] as? String == "boolean")

        let clientSchema = byName["client"]?["inputSchema"] as? [String: Any]
        let clientProperties = clientSchema?["properties"] as? [String: Any]
        #expect((clientProperties?["min-mem"] as? [String: Any])?["type"] as? String == "string")
        #expect(clientSchema?["additionalProperties"] as? Bool == false)
    }

    @Test func toolsCallSuccessWrapsEnvelope() throws {
        let runner = FakeRunner(stdout: #"{"ok":true,"command":"list","data":{"versions":[]},"error":null}"#)
        let response = call(
            request("tools/call", ["name": "list", "arguments": ["root-dir": "/tmp/mc"]]),
            runner: runner
        )
        let result = response?["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == false)
        let content = result?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        let envelope = try JSONSerialization.jsonObject(with: Data((text ?? "").utf8)) as? [String: Any]
        #expect(envelope?["ok"] as? Bool == true)
        #expect(envelope?["command"] as? String == "list")
        // argv：全局 `--json` 在子命令之前，选项用长名。
        #expect(runner.received == [["--json", "list", "--root-dir", "/tmp/mc"]])
    }

    @Test func toolsCallBusinessErrorIsToolError() {
        let runner = FakeRunner(
            stdout: #"{"ok":false,"command":"list","data":null,"error":{"code":"E_RUNTIME","message":"x"}}"#
        )
        let response = call(request("tools/call", ["name": "list", "arguments": [:]]), runner: runner)
        let result = response?["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == true)
    }

    @Test func toolsCallPositionalArgument() {
        let runner = FakeRunner(stdout: #"{"ok":true,"command":"app","data":{},"error":null}"#)
        _ = call(request("tools/call", ["name": "app", "arguments": ["action": "status"]]), runner: runner)
        #expect(runner.received == [["--json", "app", "status"]])
    }

    @Test func toolsCallInvalidParams() {
        let runner = FakeRunner()
        let unknown = call(request("tools/call", ["name": "nope", "arguments": [:]]), runner: runner)
        #expect((unknown?["error"] as? [String: Any])?["code"] as? Int == -32602)

        let unknownArgument = call(request("tools/call", ["name": "list", "arguments": ["bogus": 1]]), runner: runner)
        #expect((unknownArgument?["error"] as? [String: Any])?["code"] as? Int == -32602)

        let missing = call(request("tools/call", ["name": "app", "arguments": [:]]), runner: runner)
        #expect((missing?["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test func unknownMethod() {
        let response = call(request("tools/frobnicate"), runner: FakeRunner())
        #expect((response?["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func notificationHasNoResponse() {
        let response = MCPServer.handleMessage(
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            capabilities: capabilities,
            runner: FakeRunner()
        )
        #expect(response == nil)
    }

    @Test func processLineParseError() {
        let response = MCPServer.processLine("{not json}", capabilities: capabilities, runner: FakeRunner())
        #expect((response?["error"] as? [String: Any])?["code"] as? Int == -32700)
        #expect(response?["id"] is NSNull)
    }
}
