import ConsoleKit
import Foundation
import TransferKit

/// 结构化进度渲染（对齐 `docs/spec/behavior.md` B8）。
///
/// - **count / bytes 分开**：两者都来自 `TransferProgress`，百分比与速度语义不混用；
/// - **不定长**：`total == nil` 时不画「0%」假进度，改为输出一行状态
///   （对齐 Python `ProgressSink.status()`），慢网络不会表现为静默等待；
/// - **归属**：进度由传输层单线程喂入，这里只做渲染，不跨线程累加；
/// - **前端观察者**：`observer` 把同一条进度以 [`LaunchProgress`] 交出去，供无控制台的
///   前端（GUI 等）驱动 UI；CLI 不传，行为与之前完全一致。
public final class ProgressReporter: @unchecked Sendable {
    private let console: (any Console)?
    private let bar: ActivityIndicator<ProgressBar>?
    private let title: String
    private let observer: (@Sendable (LaunchProgress) -> Void)?
    private let lock = NSLock()
    private var announcedIndefinite = false

    public init(
        console: (any Console)?,
        title: String,
        observer: (@Sendable (LaunchProgress) -> Void)? = nil
    ) {
        self.console = console
        self.title = title
        self.observer = observer
        self.bar = console?.progressBar(title: title)
    }

    /// 起进度条（不定长时不会假装 0%，见 `update`）。
    public func begin() {
        bar?.start(refreshRate: 100)
    }

    public func update(_ event: TransferProgress) {
        // 观察者在锁外调用：前端回调可能切线程（GUI 走 MainActor），不应拖住渲染锁。
        observer?(LaunchProgress(event, label: title))
        lock.lock()
        defer { lock.unlock() }
        if let fraction = event.fraction {
            // `ActivityIndicator.updateProgress` 是 JokerKits 内部的；这里直接改进度与标题
            // （与 `Paper.swift` 同样的公开用法），并在标题里附百分比。
            bar?.activity.currentProgress = fraction
            bar?.activity.title = "\(title) \(Int((fraction * 100).rounded()))%"
            return
        }
        guard !announcedIndefinite else { return }
        announcedIndefinite = true
        let description = event.description ?? title
        console?.info("\(description)（总数未知，按已接收\(event.kind == .bytes ? "字节" : "项目")显示）")
    }

    public func finish() {
        bar?.succeed()
    }

    public func fail() {
        bar?.fail()
    }

    /// 包一段会喂进度的工作：开始起条、成功收尾、失败标红。
    public func tracking<T>(_ body: () async throws -> T) async throws -> T {
        begin()
        do {
            let value = try await body()
            finish()
            return value
        } catch {
            fail()
            throw error
        }
    }
}
