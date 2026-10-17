import Foundation
import JokerKits

public extension Client {
    /// 从客户端 jar 提取 `.ogg` 音乐到 `backup/music/<version>`（对齐 Python `--extract-music`）。
    ///
    /// 只确保**客户端 jar** 存在（音乐提取不需要资源/库）；随后用系统 `unzip` 按 `*.ogg`
    /// 过滤解压（保留 jar 内目录结构）。
    @discardableResult
    func extractMusic() async throws -> Int {
        let root = clientInfo.rootDir
        let version = clientInfo.version.id
        let layout = GamePlan.layout(root: root, version: version)
        let jar = layout.clientJarPath
        let console = clientInfo.console

        if !FileManager.default.fileExists(atPath: jar) {
            let items = try await generateDownloadItemInfos()
            if let jarItem = items.first(where: { $0.dstFileURL.path == jar }) {
                let progress = ProgressReporter(console: console, title: "正在下载客户端 jar")
                try await progress.tracking {
                    try await Downloader.download(jarItem, onEvent: progress.update)
                }
            }
        }
        guard FileManager.default.fileExists(atPath: jar) else {
            throw GameError.clientJarNotFound(jar)
        }

        let dest = "\(layout.backupDir)/music/\(version)"
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)

        // 客户端 jar 内含 `assets/minecraft/sounds/**/*.ogg`；unzip 的 `*` 可跨 `/`。
        _ = await Shell.run(path: "/usr/bin/unzip", args: ["-o", jar, "*.ogg", "-d", dest], workDirectory: root)

        let count = countMusicFiles(at: dest)
        console?.success("已提取 \(count) 个音乐文件到 \(dest)")
        return count
    }

    private func countMusicFiles(at directory: String) -> Int {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return 0 }
        var count = 0
        for case let path as String in enumerator where path.lowercased().hasSuffix(".ogg") {
            count += 1
        }
        return count
    }
}
