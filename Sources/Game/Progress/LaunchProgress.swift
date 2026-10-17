import Foundation
import TransferKit

/// 跨出引擎边界的**结构化进度**（`Game` 公开面）。
///
/// 对齐 `docs/spec/behavior.md` B8：count / bytes 分开、`total == nil` 表示不定长。
/// 引擎内部的 `TransferProgress` 属于 `TransferKit`，GUI 等前端不应为拿进度多一层依赖，
/// 也不一定具备 ConsoleKit 控制台，因此统一经本类型对外。
public struct LaunchProgress: Sendable, Equatable {

    public enum Kind: String, Sendable, Equatable {
        /// 按**项目个数**计（例如 assets / libraries 文件数）。
        case items
        /// 按**字节数**计（单文件下载 / 总字节）。
        case bytes
    }

    public let kind: Kind
    /// 已完成量（`kind` 决定单位）。
    public let completed: Int64
    /// 总量；`nil` 表示不定长（不要画「0%」假进度）。
    public let total: Int64?
    /// 阶段标题（进度条标题 / 传输层描述），供前端显示"正在下载客户端文件"之类的文案。
    public let label: String?

    public init(kind: Kind, completed: Int64, total: Int64?, label: String? = nil) {
        self.kind = kind
        self.completed = completed
        self.total = total
        self.label = label
    }

    /// 由传输层事件转换（`label` 缺省时沿用传输层描述）。
    public init(_ event: TransferProgress, label: String? = nil) {
        self.init(
            kind: event.kind == .bytes ? .bytes : .items,
            completed: event.current,
            total: event.total,
            label: label ?? event.description
        )
    }

    /// 归一化 0…1；不定长（`total == nil` 或 `0`）时为 `nil`。
    public var fraction: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    /// 是否已完成（不定长视为未知）。
    public var isComplete: Bool {
        guard let total else { return false }
        return completed >= total
    }
}
