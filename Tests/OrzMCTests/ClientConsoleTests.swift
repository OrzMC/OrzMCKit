import Foundation
import JokerKits
import MojangAPI
import Testing

@testable import Game

/// 客户端控制台的**引擎侧契约**（与 `ServerInfo.onServerLog` 对称）：
/// 无控制台前端通过 `ClientInfo.onClientLog` 拿运行期输出。
@Suite struct ClientConsoleTests {
    private func makeVersion() -> Version {
        Version(
            id: "1.21.5",
            _type: .release,
            url: "https://piston-meta.mojang.com/v1/packages/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/1.21.5.json"
        )
    }

    @Test func clientInfoCarriesLogObserver() throws {
        let collected = Collector()
        let clientInfo = ClientInfo(
            version: makeVersion(),
            username: "Steve",
            minMem: "512M",
            maxMem: "2G",
            onClientLog: { collected.append($0) }
        )
        clientInfo.onClientLog?("[Render thread] GL info: Apple M1")
        #expect(collected.text.contains("[Render thread] GL info"))
    }

    @Test func clientInfoDefaultsToNoLogObserver() throws {
        // CLI 侧不传：默认 nil，行为与之前完全一致。
        let clientInfo = ClientInfo(
            version: makeVersion(), username: "Steve", minMem: "512M", maxMem: "2G")
        #expect(clientInfo.onClientLog == nil)
    }

    #if !os(Windows)
    @Test func childProcessOutputReachesObserver() async throws {
        // 真实链路的最小验证：`ProcessRunner.run(onLine:)` 把子进程输出交给观察者。
        let collected = Collector()
        let process = try ProcessRunner.run(
            executable: "/bin/sh",
            args: ["-c", "echo '[Client] ready'; sleep 0.2"],
            onLine: { collected.append($0) }
        )
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !collected.text.contains("[Client] ready") {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(collected.text.contains("[Client] ready"))
        await process.stop()
    }
    #endif
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
