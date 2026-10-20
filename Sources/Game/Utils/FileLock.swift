import Foundation

/// 跨进程文件锁（`docs/spec/frontends.md` **F4.1**）：`<stateDir>/auth.lock` **目录锁**。
///
/// **算法必须与 Python 侧逐字一致**，否则两边互不加锁：
///
/// 1. 获取：`mkdir(lock)` —— 在 POSIX 与 Windows 上都是原子的；
/// 2. 陈旧：目录 `mtime` 超过 `staleAfter`（30s）视为持锁进程已崩，删掉重试；
/// 3. 超时：最多等 `timeout`（10s），拿不到抛 `FileLockError.timeout`（规范错误码 `E_AUTH_LOCKED`）——
///    **绝不**在没拿到锁的情况下刷新令牌（刷新期间要持锁跨网络）。
///
/// 为什么不用 `flock`：`flock` 与 `fcntl` 锁在 Linux/macOS 属于**不同命名空间**，跨语言极易
/// "看起来加了锁、其实互不可见"；Windows 又没有 `flock`。`mkdir` 三平台语义一致，
/// 代价是崩溃后要靠陈旧检测兜底。
public struct FileLock {
    public enum FileLockError: Error, CustomStringConvertible {
        case timeout(String)
        case unavailable(String)

        public var code: String { "E_AUTH_LOCKED" }

        public var description: String {
            switch self {
            case let .timeout(message), let .unavailable(message): return message
            }
        }
    }

    public static let staleAfter: TimeInterval = 30
    public static let defaultTimeout: TimeInterval = 10
    public static let pollInterval: TimeInterval = 0.05

    public let path: String
    private let timeout: TimeInterval
    private let staleAfter: TimeInterval
    private let clock: () -> Double
    private let sleep: (TimeInterval) -> Void
    private var held = false

    public init(
        path: String,
        timeout: TimeInterval = FileLock.defaultTimeout,
        staleAfter: TimeInterval = FileLock.staleAfter,
        clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.path = path
        self.timeout = timeout
        self.staleAfter = staleAfter
        self.clock = clock
        self.sleep = sleep
    }

    /// `auth.json` 旁边的那把锁（与 Python 侧同一个路径）。
    public static func authLock(stateDir: String? = nil) -> FileLock {
        FileLock(path: (stateDir ?? StatePaths.stateDir()) + "/auth.lock")
    }

    // MARK: 获取 / 释放

    public mutating func acquire() throws {
        let deadline = clock() + timeout
        while true {
            do {
                try FileManager.default.createDirectory(
                    atPath: path, withIntermediateDirectories: false)
            } catch {
                // 已存在（或创建失败）：先看是不是陈旧锁，再看超时。
                if isStale() {
                    breakStale()
                    continue
                }
                if clock() >= deadline {
                    throw FileLockError.timeout(
                        "拿不到认证锁 \(path)（另一进程正在刷新令牌）；稍后重试，或确认没有卡住的 orzmc 进程")
                }
                sleep(Self.pollInterval)
                continue
            }
            writeOwner()
            held = true
            return
        }
    }

    public mutating func release() {
        guard held else { return }
        held = false
        try? FileManager.default.removeItem(atPath: path + "/owner")
        // 释放失败不抛：陈旧检测会在 30s 后兜底。
        try? FileManager.default.removeItem(atPath: path)
    }

    /// `withLock` 风格：`try FileLock.authLock().withLock { ... }`
    public func withLock<T>(_ body: () throws -> T) throws -> T {
        var lock = self
        try lock.acquire()
        defer { lock.release() }
        return try body()
    }

    public func withLock<T>(_ body: () async throws -> T) async throws -> T {
        var lock = self
        try lock.acquire()
        defer { lock.release() }
        return try await body()
    }

    // MARK: 陈旧检测

    private func age() -> TimeInterval {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else { return 0 }
        return clock() - modified.timeIntervalSince1970
    }

    private func isStale() -> Bool { age() > staleAfter }

    private func breakStale() {
        try? FileManager.default.removeItem(atPath: path + "/owner")
        try? FileManager.default.removeItem(atPath: path)
    }

    /// 持有者信息（pid + 起始时间）——**仅供排查**，不参与判定。
    private func writeOwner() {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let body = "pid=\(ProcessInfo.processInfo.processIdentifier)\nsince=\(stamp)\n"
        try? body.write(toFile: path + "/owner", atomically: true, encoding: .utf8)
    }
}
