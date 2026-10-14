import Foundation
import Game

/// CLI 全局选项（规范 `docs/spec/cli-surface.md` §3）：
/// `--verbose` / `--root-dir` / `--json` / `--version`。
///
/// ConsoleKit 只在 `console.run` 阶段解析旗标，且各命令各自声明选项；而
/// `--version` 与子命令的 `-v/--version`（游戏版本）语义不同、`--json` 又要求
/// stdout 只剩信封。为消除歧义，`OrzMC.main` 在构造 `CommandInput` **之前**
/// 预解析 argv：只消费**子命令之前**的全局选项，其余原样交给 ConsoleKit。
/// 因此全局选项必须出现在子命令之前（规范 §1）。
struct GlobalOptions: Sendable {
    var verbose = false
    var json = false
    var rootDir: String?

    /// 预解析结果。
    struct Parsed: Sendable {
        var options: GlobalOptions
        /// 去掉已消费的全局选项后，交给 ConsoleKit 的 argv（含可执行名）。
        var remaining: [String]
        /// 请求工具版本（全局 `--version`）。
        var versionRequested: Bool

        /// 当前命令名（用于 `--json` 错误信封）；无子命令时为 `_root`。
        var commandName: String {
            remaining.dropFirst().first { !$0.hasPrefix("-") } ?? "_root"
        }
    }

    static func parse(_ arguments: [String]) -> Parsed {
        var options = GlobalOptions()
        var remaining: [String] = []
        var versionRequested = false

        guard let executable = arguments.first else {
            return Parsed(options: options, remaining: [], versionRequested: false)
        }
        remaining.append(executable)

        var index = 1
        loop: while index < arguments.count {
            switch arguments[index] {
            case "--verbose", "-d":
                options.verbose = true
            case "--json":
                options.json = true
            case "--version":
                versionRequested = true
            case "--root-dir":
                if index + 1 < arguments.count {
                    options.rootDir = arguments[index + 1]
                    index += 1
                }
            default:
                // 第一个非全局选项（即子命令）起，全部原样交给 ConsoleKit，
                // 交由子命令自己的签名解析（脚本 / 覆盖全局）。
                remaining.append(contentsOf: arguments[index...])
                break loop
            }
            index += 1
        }
        return Parsed(options: options, remaining: remaining, versionRequested: versionRequested)
    }

    /// 游戏根目录：命令级 `--root-dir` 优先，其次全局，最后默认 `~/minecraft`。
    func resolveRoot(_ commandLevel: String?) -> String {
        commandLevel ?? rootDir ?? GamePlan.defaultRoot
    }
}
