import ConsoleKit
import Foundation

/// Minecraft 版本选择器（对齐 `docs/spec/behavior.md` B10）。
///
/// 契约：TTY 下要能**导航 + 搜索 + 切渠道**；非 TTY 由调用方直接用最新 release。
/// 这里把「状态」与「终端 IO」分开：`VersionPickerState` 是纯逻辑（可单测），
/// `runVersionPicker` 只负责渲染与读一行输入。
///
/// 交互（与 Python `prompt_toolkit` 选择器同一套语义，输入方式按行）：
/// - 数字 = 选择本页第 N 项；
/// - 其他文字 = 在当前渠道内**搜索**（子串，不区分大小写）；
/// - `n` / `p` = 下一页 / 上一页；`t` = 切换 `release` / `snapshot`；
/// - `x` = 清除搜索；空行 = 放弃（回退最新 release）。
struct VersionPickerState {
    enum Channel: String, CaseIterable {
        case release
        case snapshot
    }

    let releases: [String]
    let snapshots: [String]
    let pageSize: Int
    private(set) var channel: Channel
    private(set) var query = ""
    private(set) var page = 0

    init(releases: [String], snapshots: [String], pageSize: Int = 10, channel: Channel = .release) {
        self.releases = releases
        self.snapshots = snapshots
        self.pageSize = max(1, pageSize)
        self.channel = channel
    }

    /// 当前渠道的全部版本（服务端给的顺序即从新到旧）。
    var allIDs: [String] {
        channel == .release ? releases : snapshots
    }

    /// 搜索后的结果（空查询 = 全部）。
    var filtered: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return allIDs }
        return allIDs.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var pageCount: Int {
        max(1, (filtered.count + pageSize - 1) / pageSize)
    }

    /// 当前页的版本（已按页截断）。
    var pageItems: [String] {
        let start = min(page * pageSize, filtered.count)
        let end = min(start + pageSize, filtered.count)
        return Array(filtered[start..<end])
    }

    var channelLabel: String { channel.rawValue }

    /// 1-based、**页内**序号 → 版本 id。
    func select(_ index: Int) -> String? {
        guard index >= 1, index <= pageItems.count else { return nil }
        return pageItems[index - 1]
    }

    mutating func switchChannel() {
        channel = channel == .release ? .snapshot : .release
        query = ""
        page = 0
    }

    mutating func nextPage() {
        page = min(page + 1, pageCount - 1)
    }

    mutating func previousPage() {
        page = max(page - 1, 0)
    }

    mutating func setQuery(_ text: String) {
        query = text
        page = 0
    }

    mutating func clearQuery() {
        query = ""
        page = 0
    }
}

/// 渲染 + 读取一行输入；返回选中的版本 id，空行/EOF 返回 nil（调用方回退最新 release）。
func runVersionPicker(console: any Console, state initialState: VersionPickerState) -> String? {
    var state = initialState
    while true {
        render(console: console, state: state)
        let answer = console.ask("> ".consoleText(.info)).trimmingCharacters(in: .whitespaces)
        if answer.isEmpty { return nil }
        if let index = Int(answer) {
            if let id = state.select(index) { return id }
            console.warning("序号超出本页范围（1-\(state.pageItems.count)）")
            continue
        }
        switch answer.lowercased() {
        case "n", "next":
            state.nextPage()
        case "p", "prev", "previous":
            state.previousPage()
        case "t", "toggle":
            state.switchChannel()
        case "x", "clear":
            state.clearQuery()
        default:
            state.setQuery(answer)
        }
    }
}

private func render(console: any Console, state: VersionPickerState) {
    let total = state.filtered.count
    var header = "Minecraft 版本（\(state.channelLabel)"
    if !state.query.isEmpty { header += "，搜索 “\(state.query)”" }
    header += "，共 \(total) 个"
    if state.pageCount > 1 { header += "，第 \(state.page + 1)/\(state.pageCount) 页" }
    header += "）"
    console.output(header.consoleText(.info))

    if state.pageItems.isEmpty {
        console.warning("没有匹配的版本；输入 x 清除搜索，或 t 切换渠道")
    }
    for (offset, id) in state.pageItems.enumerated() {
        let marker = offset == 0 ? "❯" : " "
        console.output(" \(marker) \(offset + 1). \(id)".consoleText(offset == 0 ? .success : .plain))
    }
    console.output(
        "输入序号选择 / 文字搜索 / n 下一页 / p 上一页 / t 切换渠道 / x 清除搜索 / 回车=最新 release"
            .consoleText(.warning)
    )
}
