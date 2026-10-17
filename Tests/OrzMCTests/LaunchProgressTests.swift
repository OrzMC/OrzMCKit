import Testing
import TransferKit

@testable import Game

/// 前端进度模型（`docs/spec/behavior.md` B8）：count/bytes 分开、不定长不假装 0%。
@Suite struct LaunchProgressTests {

    @Test func mapsCountEvent() {
        let progress = LaunchProgress(
            TransferProgress(kind: .count, total: 10, current: 4),
            label: "正在下载客户端文件"
        )
        #expect(progress.kind == .items)
        #expect(progress.completed == 4)
        #expect(progress.total == 10)
        #expect(progress.fraction == 0.4)
        #expect(progress.label == "正在下载客户端文件")
        #expect(!progress.isComplete)
    }

    @Test func mapsByteEventAndClampsFraction() {
        let progress = LaunchProgress(TransferProgress(kind: .bytes, total: 200, current: 500))
        #expect(progress.kind == .bytes)
        #expect(progress.fraction == 1)
        #expect(progress.isComplete)
    }

    @Test func indefiniteHasNoFraction() {
        let progress = LaunchProgress(TransferProgress(kind: .bytes, total: nil, current: 1234))
        #expect(progress.total == nil)
        #expect(progress.fraction == nil)
        #expect(!progress.isComplete)
    }

    @Test func zeroTotalIsIndefinite() {
        let progress = LaunchProgress(kind: .bytes, completed: 0, total: 0)
        #expect(progress.fraction == nil)
    }

    @Test func keepsTransportDescriptionWhenLabelMissing() {
        let progress = LaunchProgress(
            TransferProgress(kind: .count, description: "libraries", total: 2, current: 1)
        )
        #expect(progress.label == "libraries")
    }
}
