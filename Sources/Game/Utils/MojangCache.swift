import Foundation
import MojangAPI

/// 把 Mojang 元数据缓存统一指向游戏根目录的 `cache/`，与 Python `orzmc` 共享。
///
/// 共享产物：
/// - 版本清单 `<root>/cache/version_manifest.json`
/// - 版本 JSON `<root>/cache/versions/<mc>.json`（原始 Mojang JSON）
///
/// 幂等；每个会触达 Mojang 的入口在拿到 root 后调用一次即可。未调用时 `MojangAPI`
/// 退回自身的默认目录（`~/Library/Caches/MojangAPI`），行为与旧版一致。
public enum MojangCache {
    @MainActor
    public static func configure(root: String) {
        let cacheDir = URL(
            fileURLWithPath: (root as NSString).appendingPathComponent("cache"),
            isDirectory: true
        )
        Mojang.configureCache(directory: cacheDir)
        Mojang.configurePackageCache(directory: cacheDir)
    }
}
