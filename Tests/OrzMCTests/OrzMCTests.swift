import Testing

@testable import Game

/// 引擎基础契约的离线单测（确定性、不联网）。
@Suite struct GameTypeTests {
    @Test func rawValues() {
        #expect(GameType.vanilla.rawValue == "vanilla")
        #expect(GameType.paper.rawValue == "paper")
    }

    @Test func defaultTypes() {
        #expect(GameDir.defaultClientType == GameType.vanilla.rawValue)
        #expect(GameDir.defaultServerType == GameType.vanilla.rawValue)
    }
}
