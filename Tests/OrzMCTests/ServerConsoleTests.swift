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

/// CLI 让服务端继承终端 stdin（GUI 走管道 + `send`）——两种模式不能同时生效。
@Suite struct ServerStdinModeTests {
    @Test func serverInfoDefaultsToPipeMode() {
        let info = ServerInfo(
            version: "1.21.5", gui: false, debug: false, forceUpgrade: false, demo: false,
            minMem: "512M", maxMem: "2G", onlineMode: false, showJarHelpInfo: false,
            jarOptions: nil, console: nil
        )
        #expect(info.inheritStandardInput == false, "GUI 默认用管道，由 ManagedProcess.send 写命令")
    }

    @Test func cliCanInheritTerminalStdin() {
        let info = ServerInfo(
            version: "1.21.5", gui: false, debug: false, forceUpgrade: false, demo: false,
            minMem: "512M", maxMem: "2G", onlineMode: false, showJarHelpInfo: false,
            jarOptions: nil, console: nil, inheritStandardInput: true
        )
        #expect(info.inheritStandardInput)
    }

    #if !os(Windows)
    @Test func inheritedStdinLetsChildReadCommands() async throws {
        // 模拟 CLI：子进程继承我们（测试进程）的 stdin 时，不再有我们可写的管道；
        // 反向验证"管道模式才有 send"。真正在终端里打字的验收在 air 上跑 `orzmc server`。
        let process = try ProcessRunner.run(
            executable: "/bin/sh",
            args: ["-c", "sleep 1"],
            inheritStandardInput: true
        )
        #expect(process.canSendCommands == false)
        _ = await process.waitForExit()
    }
    #endif
}
