import Foundation
import JokerKits

/// 客户端文件下载的**共用编排**（Phase 4）：CLI 与 GUI 走同一份逻辑，
/// 避免各自重复「生成清单 → 下载 → 进度」。
public extension Client {
    /// 生成客户端下载清单并统一走 `Downloader`（哈希跳过 / 4 路 Range / 续传）。
    ///
    /// - Parameter onProgress: 0…1 进度回调（可选）。GUI 用于驱动进度 UI；
    ///   CLI 传 `nil`，进度由 `clientInfo.console` 的进度条呈现。
    /// - Parameter onEvent: 结构化进度回调（可选，count/bytes 分开）。无控制台的前端
    ///   （GUI）用它拿到阶段标题与已下载量；与 `onProgress` 可同时使用。
    func downloadClient(
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onEvent: (@Sendable (LaunchProgress) -> Void)? = nil
    ) async throws {
        let items = try await generateDownloadItemInfos()
        let console = clientInfo.console
        console?.pushEphemeral()
        // 结构化进度（B8）：count/bytes 分开，不定长走状态行。
        let progress = ProgressReporter(console: console, title: "正在下载客户端文件", observer: onEvent)
        try await progress.tracking {
            try await Downloader.download(items, onProgress: onProgress, onEvent: progress.update)
        }
        console?.popEphemeral()
        console?.success("下载客户端文件完成")
    }
}
