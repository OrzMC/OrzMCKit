import Foundation
import MojangAPI
import RuntimeKit
import Utils

/// Java 托管（对齐 `docs/spec/behavior.md` B5）：运行时落在 `java/<major>`，不依赖系统 java。
///
/// 获取原语在 `OrzSwiftKit/RuntimeKit`（D-b）；本类型只负责**策略**：用哪个 major、
/// 落到 `GamePlan` 规定的 `java/<major>`，并把 JRE 根**拍平**到该目录（使 `bin/java` 直接可用）。
public enum JavaRuntime {

    /// 托管 java 可执行路径（`java/<major>/bin/java[.exe]`）。
    public static func managedExecutable(root: String, major: Int) -> String? {
        GamePlan.layout(
            root: root,
            version: "",
            javaMajor: major,
            windows: Platform.os == .windows
        ).javaExecutable
    }

    /// 该 MC 版本需要的 Java 主版本（读 version JSON 的 `javaVersion.majorVersion`，缺失默认 8）。
    public static func javaMajor(forMCVersion version: String) async -> Int {
        do {
            guard let entry = try await Mojang.manifest().versions.first(where: { $0.id == version }),
                  let gameVersion = try await entry.gameVersion
            else { return JavaRequirement.defaultMajor }
            return Int(gameVersion.javaVersion?.majorVersion ?? Double(JavaRequirement.defaultMajor))
        } catch {
            return JavaRequirement.defaultMajor
        }
    }

    /// 确保托管 JRE 就绪：已存在直接返回；否则经 `RuntimeKit` 下载安装到 `java/<major>`。
    public static func ensure(
        root: String,
        major: Int,
        installer: JavaRuntimeInstaller = JavaRuntimeInstaller()
    ) async throws -> String {
        let layout = GamePlan.layout(root: root, version: "", javaMajor: major)
        guard let executable = layout.javaExecutable, let homePath = layout.javaMajorDir else {
            throw RuntimeInstallError.runtimeHomeNotFound
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: executable) { return executable }

        guard let query = AdoptiumQuery.currentPlatform(featureVersion: major) else {
            throw RuntimeInstallError.noAssetListURL
        }

        // 先装到临时目录，再把运行时根**拍平**到 java/<major>，使 java/<major>/bin/java 成立。
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("orzmc-jre-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let installation = try await installer.install(query: query, into: staging)

        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        try? fileManager.removeItem(at: home)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(at: installation.home, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(at: item, to: home.appendingPathComponent(item.lastPathComponent))
        }
        return executable
    }
}
