import Foundation
import Testing

@testable import Game

/// `frontends.md` **F4.1**：`<stateDir>/auth.lock` 目录锁（算法与 Python 侧逐字一致）。
@Suite struct FileLockTests {
    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "orzmc-lock-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func acquireCreatesDirectoryAndOwner() throws {
        let dir = tempDir()
        let path = dir + "/auth.lock"
        var lock = FileLock(path: path)
        try lock.acquire()
        #expect(FileManager.default.fileExists(atPath: path), "锁用目录表示（mkdir 原子）")
        let owner = try String(contentsOfFile: path + "/owner", encoding: .utf8)
        #expect(owner.contains("pid="))
        #expect(owner.contains("since="))
        lock.release()
        #expect(!FileManager.default.fileExists(atPath: path), "释放后目录应消失")
    }

    @Test func secondHolderTimesOutWithAuthLocked() throws {
        let dir = tempDir()
        let path = dir + "/auth.lock"
        var first = FileLock(path: path)
        try first.acquire()
        defer { first.release() }

        var fakeNow = Date().timeIntervalSince1970
        var second = FileLock(
            path: path,
            timeout: 0.3,
            clock: { fakeNow },
            sleep: { fakeNow += max($0, 0.001) }
        )
        do {
            try second.acquire()
            Issue.record("第二个持有者不应拿到锁")
        } catch let FileLock.FileLockError.timeout(message) {
            #expect(message.contains("刷新令牌"))
        }
    }

    @Test func staleLockIsBroken() throws {
        let dir = tempDir()
        let path = dir + "/auth.lock"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        // 把目录 mtime 拨老 31s（陈旧判定读的是 mtime）
        let old = Date().addingTimeInterval(-31)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)

        var lock = FileLock(path: path, timeout: 1)
        try lock.acquire()
        #expect(FileManager.default.fileExists(atPath: path))
        lock.release()
    }

    @Test func freshLockIsNotBroken() throws {
        let dir = tempDir()
        let path = dir + "/auth.lock"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        var fakeNow = Date().timeIntervalSince1970
        var lock = FileLock(
            path: path,
            timeout: 0.2,
            clock: { fakeNow },
            sleep: { fakeNow += max($0, 0.001) }
        )
        do {
            try lock.acquire()
            Issue.record("未陈旧的锁不能被抢")
        } catch let FileLock.FileLockError.timeout {
            #expect(FileManager.default.fileExists(atPath: path), "别人的新鲜锁必须留着")
        }
    }

    @Test func lockPathSitsNextToAuthJson() {
        let dir = tempDir()
        let lock = FileLock.authLock(stateDir: dir)
        #expect(lock.path == dir + "/auth.lock")
        #expect(AuthStore(stateDir: dir).path == dir + "/auth.json")
    }
}
