import Foundation

/// 跨平台路径约定（`docs/spec/state-paths.json`、`frontends.md` §2）。
///
/// 规范规定：Unix 用 `${XDG_STATE_HOME:-$HOME/.local/state}/orzmc`，
/// Windows 用 `%LOCALAPPDATA%\orzmc`。这里把「平台判定」做成**可注入参数**，
/// 这样在 macOS/Linux 上也能为 Windows 形态写单测。
public enum StatePaths {
    /// 当前进程所在平台是否为 Windows。
    public static var isWindows: Bool {
        #if os(Windows)
        return true
        #else
        return false
        #endif
    }

    /// 当前平台的路径分隔符。
    public static func separator(isWindows: Bool = StatePaths.isWindows) -> String {
        isWindows ? "\\" : "/"
    }

    /// 用户主目录（Windows 读 `%USERPROFILE%`，其余读 `$HOME`；都缺省用 `NSHomeDirectory()`）。
    public static func home(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        let key = isWindows ? "USERPROFILE" : "HOME"
        return environment[key] ?? NSHomeDirectory()
    }

    /// 状态目录：`<base>/orzmc`。
    public static func stateDir(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        let sep = separator(isWindows: isWindows)
        if isWindows {
            // 规范：`%LOCALAPPDATA%\orzmc`；`LOCALAPPDATA` 缺失时退回 `%USERPROFILE%\AppData\Local`。
            let base = environment["LOCALAPPDATA"]
                ?? home(environment: environment, isWindows: true) + sep + "AppData" + sep + "Local"
            return base + sep + "orzmc"
        }
        let base = environment["XDG_STATE_HOME"]
            ?? home(environment: environment, isWindows: false) + sep + ".local" + sep + "state"
        return base + sep + "orzmc"
    }

    /// 安装记录 `install.conf`（规范 `install-update.md` §2/§3）。
    public static func installRecord(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        stateDir(environment: environment, isWindows: isWindows) + separator(isWindows: isWindows) + "install.conf"
    }

    /// 认证令牌 `auth.json`（规范 `auth.md`；原子写 + 0600）。
    public static func authSession(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        stateDir(environment: environment, isWindows: isWindows) + separator(isWindows: isWindows) + "auth.json"
    }

    /// 补全脚本落点（规范 `frontends.md` F6）；`powershell`/`pwsh` 不落盘。
    public static func completionPath(
        shell: String,
        home: String,
        isWindows: Bool = StatePaths.isWindows
    ) -> String? {
        let sep = separator(isWindows: isWindows)
        switch shell {
        case "bash":
            return home + sep + ".local" + sep + "share" + sep + "bash-completion" + sep + "completions" + sep + "orzmc"
        case "zsh":
            return home + sep + ".zsh" + sep + "completions" + sep + "_orzmc"
        case "fish":
            return home + sep + ".config" + sep + "fish" + sep + "completions" + sep + "orzmc.fish"
        default:
            return nil
        }
    }

    /// 默认游戏根目录：`<home>/minecraft`。
    public static func defaultGameRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        home(environment: environment, isWindows: isWindows) + separator(isWindows: isWindows) + "minecraft"
    }
}
