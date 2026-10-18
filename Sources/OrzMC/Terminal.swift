import Foundation

#if os(Windows)
// Windows 的 C 运行时（`_isatty`/`_fileno`）在 ucrt 里。
import ucrt
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 终端能力探测（B9）：非 TTY 时**不得阻塞等待输入**。
public enum TerminalEnvironment {
    /// stdin 是否为交互式终端。
    public static var isInteractive: Bool {
        #if os(Windows)
        return _isatty(_fileno(stdin)) == 1
        #else
        return isatty(STDIN_FILENO) == 1
        #endif
    }
}
