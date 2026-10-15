import ConsoleKit
import Foundation
import Game

/// MCP `tools/call` 的单次执行结果（可注入以便离线测试；规范 `cli-surface.md` §8.2）。
struct MCPProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// 执行一次 CLI 子命令。默认实现拉起**原生子进程**（即当前 `orzmc` 可执行文件），
/// 测试注入假实现即可完全离线。
protocol MCPRunning {
    func run(arguments: [String]) throws -> MCPProcessResult
}

/// 子进程 runner：`orzmc --json <command> ...`，捕获 stdout / stderr / 退出码。
///
/// stdout 用管道（父进程持续读直到 EOF）；stderr 落临时文件，避免两个管道互相
/// 塞满造成死锁。
struct SubprocessMCPRunner: MCPRunning {
    func run(arguments: [String]) throws -> MCPProcessResult {
        let process = Process()
        process.executableURL = Self.executableURL()
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("orzmc-mcp-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stderrURL)
            throw error
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? stderrHandle.close()
        let stderrData = (try? Data(contentsOf: stderrURL)) ?? Data()
        try? FileManager.default.removeItem(at: stderrURL)

        return MCPProcessResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// 当前可执行文件（PATH 调用时 `argv[0]` 可能只是名字，需搜索 PATH）。
    static func executableURL() -> URL {
        if let path = Bundle.main.executablePath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let argument = CommandLine.arguments.first ?? "orzmc"
        if argument.contains("/") {
            return URL(fileURLWithPath: argument)
        }
        let environment = ProcessInfo.processInfo.environment
        for directory in (environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin").split(separator: ":") {
            let candidate = "\(directory)/\(argument)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return URL(fileURLWithPath: argument)
    }
}

/// 工具参数不合法（未知参数 / 类型不符 / 缺必填）→ JSON-RPC `-32602`。
struct MCPInvalidParams: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// 本地 MCP server（stdio JSON-RPC 2.0；规范 §8.2）。
///
/// - `tools/list`：由 `capabilities`（`CommandGroup.capabilityList()`）反射生成；
/// - `tools/call`：转调对应命令的 `--json` 路径，信封原样作为 tool 结果；
/// - stdout **只**输出 JSON-RPC 消息；日志 / 进度由被转调命令写 stderr（子进程捕获）。
enum MCPServer {
    /// 不暴露给 AI 的元 / 自毁命令（§8.2）。
    static let excludedTools: Set<String> = ["capabilities", "completion", "mcp", "self-uninstall"]

    static let defaultProtocolVersion = "2025-06-18"

    // MARK: - 参数描述（capabilities → tool schema）

    private struct MCPParameter {
        let name: String
        let long: String?
        let help: String
        let isFlag: Bool
        let required: Bool
        let schemaType: String
    }

    private static func parameters(_ spec: CommandCapability) -> [MCPParameter] {
        spec.values.map { value in
            let long = value.names.first { $0.hasPrefix("--") }
            let name = long.map { String($0.dropFirst(2)) } ?? value.names.first ?? ""
            return MCPParameter(
                name: name,
                long: long,
                help: value.help,
                isFlag: value.flag,
                required: value.required,
                schemaType: value.schemaType
            )
        }
    }

    static func inputSchema(_ spec: CommandCapability) -> [String: Any] {
        var properties: [String: Any] = [:]
        var required: [String] = []
        for parameter in parameters(spec) {
            var property: [String: Any] = ["type": parameter.schemaType]
            if !parameter.help.isEmpty {
                property["description"] = parameter.help
            }
            properties[parameter.name] = property
            if parameter.required {
                required.append(parameter.name)
            }
        }
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return schema
    }

    static func tools(_ capabilities: [CommandCapability]) -> [[String: Any]] {
        capabilities
            .filter { !excludedTools.contains($0.name) }
            .map { spec in
                [
                    "name": spec.name,
                    "description": spec.help,
                    "inputSchema": inputSchema(spec),
                ]
            }
    }

    // MARK: - 工具参数 → CLI argv

    static func buildArguments(_ spec: CommandCapability, arguments: [String: Any]) throws -> [String] {
        let parameters = parameters(spec)
        let known = Set(parameters.map(\.name))
        let unknown = arguments.keys.filter { !known.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw MCPInvalidParams("未知参数: \(unknown.joined(separator: ", "))")
        }

        var argv: [String] = []
        for parameter in parameters {
            guard let raw = arguments[parameter.name] else {
                if parameter.required {
                    throw MCPInvalidParams("缺少必填参数: \(parameter.name)")
                }
                continue
            }
            if parameter.isFlag {
                guard let value = raw as? Bool else {
                    throw MCPInvalidParams("参数 \(parameter.name) 应为布尔值")
                }
                if value, let long = parameter.long {
                    argv.append(long)
                }
                continue
            }
            switch parameter.schemaType {
            case "integer":
                guard let number = raw as? Int else {
                    throw MCPInvalidParams("参数 \(parameter.name) 应为整数")
                }
                argv.append(contentsOf: [parameter.long ?? parameter.name, String(number)])
            case "boolean":
                guard let value = raw as? Bool else {
                    throw MCPInvalidParams("参数 \(parameter.name) 应为布尔值")
                }
                argv.append(contentsOf: [parameter.long ?? parameter.name, value ? "true" : "false"])
            default:
                guard let value = raw as? String else {
                    throw MCPInvalidParams("参数 \(parameter.name) 应为字符串")
                }
                if let long = parameter.long {
                    argv.append(contentsOf: [long, value])
                } else {
                    argv.append(value)
                }
            }
        }
        return argv
    }

    // MARK: - tools/call

    static func callTool(
        _ spec: CommandCapability,
        arguments: [String: Any],
        runner: any MCPRunning
    ) throws -> [String: Any] {
        let argv = try buildArguments(spec, arguments: arguments)
        let process = try runner.run(arguments: ["--json", spec.name] + argv)
        let envelope = parseEnvelope(process.stdout)
            ?? synthesizedFailure(command: spec.name, stderr: process.stderr, exitCode: process.exitCode)
        let ok = (envelope["ok"] as? Bool) ?? false
        return [
            "content": [["type": "text", "text": serialize(envelope)]],
            "isError": !ok,
        ]
    }

    /// stdout 应恰好一个信封；容错取最后一行合法对象。
    static func parseEnvelope(_ stdout: String) -> [String: Any]? {
        for line in stdout.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any],
                  dictionary["ok"] is Bool
            else { continue }
            return dictionary
        }
        return nil
    }

    static func synthesizedFailure(command: String, stderr: String, exitCode: Int32) -> [String: Any] {
        let lastLine = stderr.split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        let message = (lastLine?.isEmpty == false ? lastLine! : nil) ?? "命令 \(command) 失败(退出码 \(exitCode))"
        return [
            "ok": false,
            "command": command,
            "data": NSNull(),
            "error": ["code": "E_RUNTIME", "message": message],
        ]
    }

    // MARK: - JSON-RPC 消息

    static func successResponse(_ id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func errorResponse(_ id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    /// 处理一条 JSON-RPC 消息；通知（无 `id`）返回 `nil`（不回复）。
    static func handleMessage(
        _ message: Any,
        capabilities: [CommandCapability],
        runner: any MCPRunning
    ) -> [String: Any]? {
        guard let message = message as? [String: Any] else {
            return errorResponse(NSNull(), code: -32600, message: "invalid request")
        }
        let id = message["id"] ?? NSNull()
        guard let method = message["method"] as? String else {
            return message["id"] == nil ? nil : errorResponse(id, code: -32600, message: "invalid request")
        }
        if message["id"] == nil, method.hasPrefix("notifications/") {
            return nil
        }
        var params: [String: Any] = [:]
        if let raw = message["params"], !(raw is NSNull) {
            guard let dictionary = raw as? [String: Any] else {
                return errorResponse(id, code: -32602, message: "invalid params")
            }
            params = dictionary
        }

        switch method {
        case "initialize":
            let requested = (params["protocolVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return successResponse(id, result: [
                "protocolVersion": requested ?? defaultProtocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "orzmc", "version": OrzMCVersion.current],
            ])
        case "ping":
            return successResponse(id, result: [:])
        case "tools/list":
            return successResponse(id, result: ["tools": tools(capabilities)])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return errorResponse(id, code: -32602, message: "invalid params")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let spec = capabilities.first(where: { $0.name == name }), !excludedTools.contains(name) else {
                return errorResponse(id, code: -32602, message: "未知 tool: \(name)")
            }
            do {
                return successResponse(id, result: try callTool(spec, arguments: arguments, runner: runner))
            } catch let invalid as MCPInvalidParams {
                return errorResponse(id, code: -32602, message: invalid.message)
            } catch {
                return errorResponse(id, code: -32603, message: "internal error: \(error)")
            }
        default:
            return errorResponse(id, code: -32601, message: "method not found: \(method)")
        }
    }

    static func serialize(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    // MARK: - stdio 循环

    static func serve(runner: any MCPRunning = SubprocessMCPRunner()) {
        let capabilities = CommandGroup(options: GlobalOptions()).capabilityList()
        while let line = readLine(strippingNewline: true) {
            processLine(line, capabilities: capabilities, runner: runner)
        }
    }

    @discardableResult
    static func processLine(
        _ line: String,
        capabilities: [CommandCapability],
        runner: any MCPRunning
    ) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let response: [String: Any]?
        if let data = trimmed.data(using: .utf8),
           let message = try? JSONSerialization.jsonObject(with: data) {
            response = handleMessage(message, capabilities: capabilities, runner: runner)
        } else {
            response = errorResponse(NSNull(), code: -32700, message: "parse error")
        }
        if let response {
            FileHandle.standardOutput.write(Data((serialize(response) + "\n").utf8))
        }
        return response
    }
}
