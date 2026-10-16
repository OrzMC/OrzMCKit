import Foundation
import JokerKits

// MARK: 客户端 Fabric 附加组件
//
// 解析结果由 `FabricMeta.resolve(version:root:refresh:)` 产出并存入 `ClientInfo.addon`，
// 库下载到客户端 `libraries/`（与 vanilla 库同目录，classpath 扫描自然包含）。
extension Client {
    /// Fabric 附加 JVM 参数（loader profile 的 `arguments.jvm`）。
    func fabricClientJVMOptions() -> [String]? {
        guard let addon = clientInfo.addon, !addon.jvmArgs.isEmpty else { return nil }
        return addon.jvmArgs
    }

    /// Fabric 主类（覆盖 vanilla 主类）。
    func fabricClientMainClass() -> String? {
        clientInfo.addon?.mainClass
    }

    /// Fabric 附加游戏参数（loader profile 的 `arguments.game`）。
    func fabricClientGameArgs() -> [String] {
        clientInfo.addon?.gameArgs ?? []
    }

    /// Fabric 库下载项；无附加组件时返回 nil。
    public func fabricDownloadItems() -> [DownloadItemInfo]? {
        guard let addon = clientInfo.addon, !addon.libraries.isEmpty else { return nil }
        let items = GamePlan.planProfileAddonDownload(
            addon: addon,
            root: clientInfo.rootDir,
            version: clientInfo.version.id
        ).compactMap { item -> DownloadItemInfo? in
            guard let url = URL(string: item.url) else { return nil }
            return DownloadItemInfo(
                sourceURL: url,
                dstFileURL: URL(fileURLWithPath: item.path),
                hash: item.sha1,
                hashType: item.sha1 == nil ? nil : .sha1
            )
        }
        return items.isEmpty ? nil : items
    }
}
