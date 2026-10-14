import ConsoleKit

enum Feature: String, CaseIterable {
    case client
    case server
    case plugin
    case fabric
    case list
    case remove
    case backup
    case version
    case completion
}

struct CommandGroup: AsyncCommandGroup {
    let options: GlobalOptions
    private let features: [Feature: any AnyAsyncCommand]

    init(options: GlobalOptions = GlobalOptions()) {
        self.options = options
        self.features = [
            .client: ClientCommand(options: options),
            .server: ServerCommand(options: options),
            .plugin: PluginCommand(options: options),
            .fabric: FabricCommand(options: options),
            .list: ListCommand(options: options),
            .remove: RemoveCommand(options: options),
            .backup: BackupCommand(options: options),
            .version: VersionCommand(options: options),
            .completion: CompletionCommand(options: options, root: { CommandGroup(options: options) }),
        ]
    }

    var help: String { Constants.commandGroupHelp.string }

    var commands: [String: any AnyAsyncCommand] {
        .init(uniqueKeysWithValues: features.map { ($0.key.rawValue, $0.value) })
    }
}
