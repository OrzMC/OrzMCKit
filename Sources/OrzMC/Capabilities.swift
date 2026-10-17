import ConsoleKit
import Foundation
import Game

/// 签名值（`@Option` / `@Flag` / `@Argument`）的机器可读描述。
struct SignatureValueSpec: Sendable {
    let names: [String]
    /// `option` / `flag` / `argument`。
    let kind: String
    let help: String
    let flag: Bool
    /// MCP `inputSchema` 类型（`flag` → boolean；据 `Option<Value>` 反射）。
    let schemaType: String

    /// 位置参数在 ConsoleKit 中无值即为用法错误 → 视为必填（与 Python `capabilities` 对齐）。
    var required: Bool { kind == "argument" }

    var json: [String: Any] {
        // 键对齐 Python `capabilities` 的 option schema（未知字段给 null）。
        ["names": names, "type": NSNull(), "required": required, "flag": flag, "default": NSNull(), "help": help]
    }
}

/// 命令能力描述（规范 `docs/spec/cli-surface.md` §8）。
struct CommandCapability: Sendable {
    let name: String
    let help: String
    let values: [SignatureValueSpec]
}

/// 命令通过它自描述签名。`AsyncCommand` 的扩展提供反射实现，
/// 各命令只需声明 `CapabilityDescribing` 即可（避免手写清单漂移）。
protocol CapabilityDescribing: AnyAsyncCommand {
    var signatureValues: [SignatureValueSpec] { get }
}

extension AsyncCommand {
    /// 反射 `Signature()` 的 `@Option`/`@Flag`/`@Argument`，**与签名自动保持同步**。
    var signatureValues: [SignatureValueSpec] {
        Self.reflectValues(Signature())
    }

    static func reflectValues(_ signature: some CommandSignature) -> [SignatureValueSpec] {
        Mirror(reflecting: signature).children.compactMap { child in
            let mirror = Mirror(reflecting: child.value)
            guard let name = mirror.descendant("name") as? String else { return nil }
            let help = mirror.descendant("help") as? String ?? ""
            // Option 带 `completion`；Flag / Argument 的分辨：Flag 带 `short`，Argument 不带。
            let hasCompletion = mirror.descendant("completion") != nil
            let hasShort = mirror.descendant("short") != nil
            let kind: String
            if hasCompletion {
                kind = hasShort ? "option" : "argument"
            } else {
                kind = "flag"
            }
            var names: [String]
            if kind == "argument" {
                names = [name]
            } else if hasShort, let short = mirror.descendant("short") as? Character {
                names = ["-\(short)", "--\(name)"]
            } else {
                names = ["--\(name)"]
            }
            let schemaType = kind == "flag" ? "boolean" : Self.schemaType(of: child.value)
            return SignatureValueSpec(
                names: names,
                kind: kind,
                help: help,
                flag: kind == "flag",
                schemaType: schemaType
            )
        }
    }

    /// 从属性包装器实例反推 MCP `inputSchema` 类型。
    static func schemaType(of value: Any) -> String {
        if value is Option<Int> { return "integer" }
        if value is Option<Double> { return "number" }
        if value is Option<Bool> { return "boolean" }
        if value is Option<String> { return "string" }
        return "string"
    }
}

// 各命令声明可自描述（实现来自上面的 `AsyncCommand` 扩展）。
extension ClientCommand: CapabilityDescribing {}
extension ServerCommand: CapabilityDescribing {}
extension PluginCommand: CapabilityDescribing {}
extension FabricCommand: CapabilityDescribing {}
extension ListCommand: CapabilityDescribing {}
extension RemoveCommand: CapabilityDescribing {}
extension BackupCommand: CapabilityDescribing {}
extension VersionCommand: CapabilityDescribing {}
extension CompletionCommand: CapabilityDescribing {}
extension CapabilitiesCommand: CapabilityDescribing {}
extension UpdateCommand: CapabilityDescribing {}
extension UninstallCommand: CapabilityDescribing {}
extension AppCommand: CapabilityDescribing {}
extension MCPCommand: CapabilityDescribing {}
