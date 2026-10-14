import Foundation
import JokerKits

public extension GamePlan {
    /// 备份服务端世界：`versions/<v>/server/<type>/world` → `backup/worlds/<v>-<type>-<stamp>.zip`。
    ///
    /// 对齐 Python `Backup.backup_world`（用系统 `zip` 打包，macOS/Linux 均有）。
    static func backupWorld(
        version: String,
        type: GameType,
        root: String = defaultRoot,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> String {
        let layout = layout(root: root, version: version, type: type)
        let world = layout.serverWorldDir
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: world, isDirectory: &isDir), isDir.boolValue else {
            throw GameError.worldNotFound(world)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let worldsDir = "\(layout.backupDir)/worlds"
        let dest = "\(worldsDir)/\(version)-\(type.rawValue)-\(formatter.string(from: now)).zip"
        try fileManager.createDirectory(atPath: worldsDir, withIntermediateDirectories: true)
        _ = try Shell.runCommand(with: ["zip", "-r", dest, "."], workDirectory: world)
        return dest
    }
}
