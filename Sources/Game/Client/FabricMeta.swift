import CacheKit
import Fabric
import Foundation

// Linux/Windows 把 URLSession/URLRequest 放在 FoundationNetworking（决策 D8：跨平台）。
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fabric 客户端附加组件解析（fabric-meta API）。
///
/// 对齐 Python `orzmc.core.fabric.Fabric`：先取该 MC 版本的最新**稳定** loader，
/// 再取 loader profile JSON，映射为 `ProfileAddon`。所有响应经统一 `MetadataCache`
/// （落盘 TTL 24h，`--refresh` 绕过；失败回退旧副本），缓存目录为 `<root>/cache`。
public enum FabricMeta {
    static let base = "https://meta.fabricmc.net/v2"

    /// 解析指定 MC 版本的 Fabric 客户端附加组件。
    public static func resolve(
        version: String,
        root: String,
        refresh: Bool = false
    ) async throws -> ProfileAddon {
        let cacheDir = URL(
            fileURLWithPath: GamePlan.layout(root: root, version: version).cacheDir,
            isDirectory: true
        )
        let cache = MetadataCache(directory: cacheDir, refresh: refresh)
        let loader = try await latestLoaderVersion(version: version, cache: cache)

        // fabric-meta 不再接受 installer 版本；仅 loader 版本即可解析 profile。
        let profileURL = cache.metaURL("fabric-profile", version, loader)
        let model: FabricModel = try await cache.get(at: profileURL) {
            let data = try await get("\(base)/versions/loader/\(version)/\(loader)/profile/json")
            return try Fabric.launcherConfig(data)
        }
        return model.profileAddon
    }

    /// 该 MC 版本的最新稳定 loader 版本（无稳定项时回退列表首项）。
    static func latestLoaderVersion(version: String, cache: MetadataCache) async throws -> String {
        struct Entry: Codable {
            struct Loader: Codable {
                let version: String
                let stable: Bool?
            }
            let loader: Loader
        }

        let url = cache.metaURL("fabric-loader", version)
        let entries: [Entry] = try await cache.get(at: url) {
            let data = try await get("\(base)/versions/loader/\(version)")
            return try JSONDecoder().decode([Entry].self, from: data)
        }
        if let stable = entries.first(where: { $0.loader.stable == true }) {
            return stable.loader.version
        }
        guard let first = entries.first else {
            throw FabricMetaError.noLoader(version)
        }
        return first.loader.version
    }

    /// 最新稳定的 fabric-installer 版本（对齐 Python `Fabric.latest_installer_version`）。
    static func latestInstallerVersion(cache: MetadataCache) async throws -> String {
        struct Entry: Codable {
            let version: String
            let stable: Bool?
        }

        let url = cache.metaURL("fabric-installer")
        let entries: [Entry] = try await cache.get(at: url) {
            let data = try await get("\(base)/versions/installer")
            return try JSONDecoder().decode([Entry].self, from: data)
        }
        if let stable = entries.first(where: { $0.stable == true }) {
            return stable.version
        }
        guard let first = entries.first else {
            throw FabricMetaError.noInstaller
        }
        return first.version
    }

    /// 拉取 URL 字节（非 2xx 视为错误，交由 `MetadataCache` 回退）。
    static func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw FabricMetaError.badURL(urlString)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FabricMetaError.http(status: http.statusCode, url: urlString)
        }
        return data
    }
}

public enum FabricMetaError: Error, CustomStringConvertible {
    case badURL(String)
    case http(status: Int, url: String)
    case noLoader(String)
    case noInstaller

    public var description: String {
        switch self {
        case .badURL(let url): return "Fabric 元数据 URL 无效: \(url)"
        case .http(let status, let url): return "Fabric 元数据请求失败（HTTP \(status)）: \(url)"
        case .noLoader(let version): return "Fabric 不支持 Minecraft \(version)"
        case .noInstaller: return "Fabric 安装器版本列表为空"
        }
    }
}
