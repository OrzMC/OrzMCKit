import ConsoleKit
import Game

enum Feature: String, CaseIterable {
    case client
    case server
    case plugin
    case list
    case remove
    case backup
    case version
    case completion
    case capabilities
    case update
    case uninstall
    case app
    case mcp

    /// CLI 中的命令名（枚举名即命令名）。
    var commandName: String { rawValue }
}

struct CommandGroup: AsyncCommandGroup {
    let options: GlobalOptions
    /// `fabric` 是**隐藏别名**：仍可用，但不出现在帮助 / 补全 / `capabilities`（规范 §2）。
    private let hiddenFabric: FabricCommand
    private let features: [Feature: any AnyAsyncCommand]

    init(options: GlobalOptions = GlobalOptions()) {
        self.options = options
        self.hiddenFabric = FabricCommand(options: options)
        self.features = [
            .client: ClientCommand(options: options),
            .server: ServerCommand(options: options),
            .plugin: PluginCommand(options: options),
            .list: ListCommand(options: options),
            .remove: RemoveCommand(options: options),
            .backup: BackupCommand(options: options),
            .version: VersionCommand(options: options),
            .completion: CompletionCommand(options: options, root: { CommandGroup(options: options) }),
            .capabilities: CapabilitiesCommand(options: options),
            .update: UpdateCommand(options: options),
            .uninstall: UninstallCommand(options: options),
            .app: AppCommand(options: options),
            .mcp: MCPCommand(options: options),
        ]
    }

    var help: String { Constants.commandGroupHelp.string }

    var commands: [String: any AnyAsyncCommand] {
        .init(uniqueKeysWithValues: features.map { ($0.key.commandName, $0.value) })
    }

    /// 能力清单（命令 / 选项），供 `capabilities` 使用；`fabric` 隐藏，不列入。
    func capabilityList() -> [CommandCapability] {
        commands.keys.sorted().map { name in
            let command = commands[name]!
            let values = (command as? any CapabilityDescribing)?.signatureValues ?? []
            return CommandCapability(name: name, help: command.help, values: values)
        }
    }

    /// 自定义 `run`：支持隐藏别名 `fabric`（未列入 `commands`）；其余与默认行为一致。
    func run(using context: inout CommandContext) async throws {
        if context.input.arguments.first == "fabric" {
            context.input.arguments.removeFirst()
            context.input.executablePath.append("fabric")
            try await hiddenFabric.run(using: &context)
            return
        }
        if let name = context.input.arguments.first {
            guard let command = commands[name] else {
                throw CommandError.unknownCommand(name, available: Array(commands.keys))
            }
            context.input.arguments.removeFirst()
            context.input.executablePath.append(name)
            try await command.run(using: &context)
            return
        }
        try outputHelp(using: &context)
        throw CommandError.missingCommand
    }
}
