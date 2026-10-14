import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 终端能力探测（B9）：非 TTY 时**不得阻塞等待输入**。
enum Terminal {
    /// stdin 是否为交互式终端。
    static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1
    }
}
