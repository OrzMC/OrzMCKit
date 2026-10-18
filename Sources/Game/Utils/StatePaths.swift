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

    /// 默认游戏根目录：`<home>/minecraft`。
    public static func defaultGameRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isWindows: Bool = StatePaths.isWindows
    ) -> String {
        home(environment: environment, isWindows: isWindows) + separator(isWindows: isWindows) + "minecraft"
    }
}
