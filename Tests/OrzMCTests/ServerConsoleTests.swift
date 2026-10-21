import Foundation
import JokerKits
import Testing

@testable import Game

/// 服务端控制台的**引擎侧契约**：无控制台前端通过 `ServerInfo.onServerLog` 拿运行期输出，
/// 通过 `ManagedProcess.send` 送命令。
@Suite struct ServerConsoleTests {
    @Test func serverInfoCarriesLogObserver() {
        let collected = Collector()
        let info = ServerInfo(
            version: "1.21.5",
            gui: false,
            debug: false,
            forceUpgrade: false,
            demo: false,
            minMem: "512M",
            maxMem: "2G",
            onlineMode: false,
            showJarHelpInfo: false,
            jarOptions: nil,
            console: nil,
            onProgress: nil,
            onServerLog: { collected.append($0) }
        )
        info.onServerLog?("[Server] Done (1.2s)!")
        #expect(collected.text.contains("[Server] Done"))
    }

    @Test func serverInfoDefaultsToNoLogObserver() {
        // CLI 侧不传：默认 nil，行为与之前完全一致（终端自己就是控制台）。
        let info = ServerInfo(
            version: "1.21.5",
            gui: false,
            debug: false,
            forceUpgrade: false,
            demo: false,
            minMem: "512M",
            maxMem: "2G",
            onlineMode: false,
            showJarHelpInfo: false,
            jarOptions: nil,
            console: nil
        )
        #expect(info.onServerLog == nil)
    }

    #if !os(Windows)
    @Test func childProcessAcceptsCommands() async throws {
        // 模拟"服务端"：读一行命令、回一行日志。
        let collector = Collector()
        let process = try ProcessRunner.run(
            executable: "/bin/sh",
            args: ["-c", "while IFS= read -r line; do echo \"[Server] $line\"; done"],
            onLine: { collector.append($0) }
        )
        #expect(process.send("say hi"))

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !collector.text.contains("[Server] say hi") {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(collector.text.contains("[Server] say hi"))
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
