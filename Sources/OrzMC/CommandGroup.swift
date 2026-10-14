import ConsoleKit

enum Feature: String, CaseIterable {
    case client
    case server
    case plugin
    case fabric
    case list
    case remove
    case backup
}

struct CommandGroup: AsyncCommandGroup {
    let features: [Feature: any AnyAsyncCommand] = [
        .client: ClientCommand(),
        .server: ServerCommand(),
        .plugin: PluginCommand(),
        .fabric: FabricCommand(),
        .list: ListCommand(),
        .remove: RemoveCommand(),
        .backup: BackupCommand(),
    ]
    var help: String { Constants.commandGroupHelp.string }
    var commands: [String : any AnyAsyncCommand] {
        let sequence: [(String, any AnyAsyncCommand)] = features.keys.map { ($0.rawValue, features[$0]!) }
        return .init(uniqueKeysWithValues:sequence)
    }
}

