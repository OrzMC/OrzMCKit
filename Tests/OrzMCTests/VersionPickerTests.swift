import Foundation
import Testing
import TransferKit

@testable import OrzMC

/// B8：进度模型必须区分 count / bytes，且 `total == nil` 判定为不定长。
@Suite struct ProgressModelTests {
    @Test func indefiniteWhenTotalIsNil() {
        let event = TransferProgress(kind: .bytes, total: nil, current: 1024)
        #expect(event.fraction == nil)
        #expect(event.kind == .bytes)
    }

    @Test func countAndBytesUseTheirOwnTotal() {
        #expect(TransferProgress(kind: .count, total: 100, current: 37).fraction == 0.37)
        #expect(TransferProgress(kind: .bytes, total: 2000, current: 1000).fraction == 0.5)
    }

    @Test func fractionIsClamped() {
        #expect(TransferProgress(kind: .bytes, total: 10, current: 20).fraction == 1)
        #expect(TransferProgress(kind: .bytes, total: 10, current: -5).fraction == 0)
    }

    @Test func zeroTotalIsIndefinite() {
        // 0 字节没有可用比例，按不定长处理，避免除零与「100%」错觉。
        #expect(TransferProgress(kind: .bytes, total: 0, current: 0).fraction == nil)
    }
}

/// B10：版本选择器的导航 / 搜索 / 渠道切换（纯状态，不依赖 TTY）。
@Suite struct VersionPickerTests {
    private func makeState() -> VersionPickerState {
        VersionPickerState(
            releases: ["1.21.4", "1.21.3", "1.21.2", "1.21.1", "1.21", "1.20.6", "1.20.4"],
            snapshots: ["24w14a", "23w51b", "1.21.4-pre1"],
            pageSize: 3
        )
    }

    @Test func defaultsToReleaseChannel() {
        let state = makeState()
        #expect(state.channelLabel == "release")
        #expect(state.allIDs.first == "1.21.4")
        #expect(state.pageItems == ["1.21.4", "1.21.3", "1.21.2"])
    }

    @Test func pagingIsBounded() {
        var state = makeState()
        #expect(state.pageCount == 3) // 7 项 / 每页 3
        state.nextPage()
        #expect(state.page == 1)
        state.nextPage()
        state.nextPage()
        #expect(state.page == 2) // 不越界
        state.previousPage()
        #expect(state.page == 1)
    }

    @Test func searchFiltersWithinChannelAndResetsPage() {
        var state = makeState()
        state.nextPage()
        state.setQuery("1.20")
        #expect(state.page == 0)
        #expect(state.filtered == ["1.20.6", "1.20.4"])
        // 不区分大小写（快照 id 含字母）
        state.clearQuery()
        #expect(state.filtered.count == 7)
    }

    @Test func selectUsesPageLocalIndex() {
        var state = makeState()
        #expect(state.select(1) == "1.21.4")
        state.nextPage()
        #expect(state.select(1) == "1.21.1")
        #expect(state.select(0) == nil)
        #expect(state.select(99) == nil)
    }

    @Test func switchingChannelShowsSnapshotsAndResetsFilters() {
        var state = makeState()
        state.setQuery("1.21")
        state.nextPage()
        state.switchChannel()
        #expect(state.channelLabel == "snapshot")
        #expect(state.query.isEmpty)
        #expect(state.page == 0)
        #expect(state.allIDs == ["24w14a", "23w51b", "1.21.4-pre1"])
        state.switchChannel()
        #expect(state.channelLabel == "release")
    }

    @Test func emptyChannelIsNotCrashing() {
        var state = VersionPickerState(releases: [], snapshots: [], pageSize: 10)
        #expect(state.pageCount == 1)
        #expect(state.pageItems.isEmpty)
        #expect(state.select(1) == nil)
        state.switchChannel()
        #expect(state.pageItems.isEmpty)
    }
}
