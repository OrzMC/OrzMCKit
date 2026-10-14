import CacheKit
import CryptoKit
import Foundation
import Game
import MojangAPI
import TransferKit

// OrzMC Swift 一致性适配器（协议：docs/spec/conformance.md §6）。
// stdin 收一个请求 JSON（fixture 的 given + id/specVersion），stdout 回一个响应 JSON。
// 仅做纯计划：不联网、不写盘、无副作用。

struct ConformanceError: Error {
    let code: String
    let message: String
}

func fail(_ code: String, _ message: String) -> ConformanceError {
    ConformanceError(code: code, message: message)
}

func ok(_ data: [String: Any]) -> [String: Any] { ["ok": true, "data": data] }
func err(_ code: String, _ message: String) -> [String: Any] {
    ["ok": false, "code": code, "message": message]
}

func asDouble(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let int = value as? Int { return Double(int) }
    if let double = value as? Double { return double }
    return nil
}

func asInt(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    return nil
}

func isNull(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}

// MARK: - fixtures

func fixturesDirectory() -> URL {
    let env = ProcessInfo.processInfo.environment["ORZMC_CONFORMANCE_FIXTURES"]
    if let env, !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

func loadFixture(_ relative: String) throws -> Data {
    let url = fixturesDirectory().appendingPathComponent(relative)
    guard let data = try? Data(contentsOf: url) else {
        throw fail("E_INTERNAL", "无法读取快照: \(relative)")
    }
    return data
}

// MARK: - operations

func opPlanLayout(_ given: [String: Any]) -> [String: Any] {
    let type = GameType(rawValue: given["type"] as? String ?? "vanilla") ?? .vanilla
    let platform = given["platform"] as? [String: Any]
    let layout = GamePlan.layout(
        root: given["root"] as? String ?? "",
        version: given["version"] as? String ?? "",
        type: type,
        javaMajor: asInt(given["javaMajor"]),
        objectSha1: given["objectSha1"] as? String,
        windows: (platform?["os"] as? String) == "windows"
    )
    var out: [String: Any] = [
        "root": layout.root,
        "versionsDir": layout.versionsDir,
        "versionDir": layout.versionDir,
        "clientDir": layout.clientDir,
        "clientAssetsDir": layout.clientAssetsDir,
        "clientIndexesDir": layout.clientIndexesDir,
        "clientObjectsDir": layout.clientObjectsDir,
        "clientLibrariesDir": layout.clientLibrariesDir,
        "clientNativesDir": layout.clientNativesDir,
        "clientJarPath": layout.clientJarPath,
        "clientProfilesDir": layout.clientProfilesDir,
        "serverDir": layout.serverDir,
        "serverJarName": layout.serverJarName,
        "serverJarPath": layout.serverJarPath,
        "serverEulaPath": layout.serverEulaPath,
        "serverPropertiesPath": layout.serverPropertiesPath,
        "serverPluginsDir": layout.serverPluginsDir,
        "serverWorldDir": layout.serverWorldDir,
        "javaDir": layout.javaDir,
        "cacheDir": layout.cacheDir,
        "versionManifestPath": layout.versionManifestPath,
        "versionJsonsDir": layout.versionJsonsDir,
        "downloadTmpDir": layout.downloadTmpDir,
        "backupDir": layout.backupDir,
    ]
    if let majorDir = layout.javaMajorDir { out["javaMajorDir"] = majorDir }
    if let executable = layout.javaExecutable { out["javaExecutable"] = executable }
    if let objectPath = layout.clientObjectPath { out["clientObjectPath"] = objectPath }
    return out
}

func opPlanClientLaunch(_ given: [String: Any]) throws -> [String: Any] {
    let type = GameType(rawValue: given["type"] as? String ?? "vanilla") ?? .vanilla
    guard type.isClientCapable else {
        throw fail("E_UNSUPPORTED_TYPE", "类型 \(type.rawValue) 不支持客户端")
    }
    let data = try loadFixture(given["snapshot"] as? String ?? "")
    let version = try JSONDecoder().decode(VersionPlan.self, from: data)
    let platform = given["platform"] as? [String: Any]
    let optionsInput = given["options"] as? [String: Any]

    var options = LaunchOptions()
    if let username = optionsInput?["username"] as? String { options.username = username }
    if let minMem = optionsInput?["minMem"] as? String { options.minMem = minMem }
    if let maxMem = optionsInput?["maxMem"] as? String { options.maxMem = maxMem }

    let plan = GamePlan.planClientLaunch(
        version: version,
        root: given["root"] as? String ?? "",
        type: type,
        platform: PlanPlatform(
            os: platform?["os"] as? String ?? "linux",
            arch: platform?["arch"] as? String ?? "x86_64"
        ),
        options: options
    )
    return [
        "executable": plan.executable,
        "cwd": plan.cwd,
        "mainClass": plan.mainClass,
        "jvmArgs": plan.jvmArgs,
        "gameArgs": plan.gameArgs,
        "classpath": plan.classpath,
        "classpathString": plan.classpathString,
        "memory": ["min": plan.memory.min, "max": plan.memory.max],
        "tokens": plan.tokens,
        "features": plan.features,
    ]
}

func opResolveVersion(_ given: [String: Any]) throws -> [String: Any] {
    let summary = try JSONDecoder().decode(
        ManifestSummary.self,
        from: try loadFixture(given["snapshot"] as? String ?? "")
    )
    let channel = BuildChannel(rawValue: given["channel"] as? String ?? "release") ?? .release
    guard let info = summary.resolve(channel) else {
        throw fail("E_VERSION_NOT_FOUND", "渠道 \(channel.rawValue) 无版本")
    }
    return ["id": info.id, "channel": info.type.channel.rawValue, "type": info.type.rawValue]
}

func opRequiredJava(_ given: [String: Any]) throws -> [String: Any] {
    let requirement = try Mojang.javaRequirement(
        fromVersionJSON: try loadFixture(given["snapshot"] as? String ?? "")
    )
    return [
        "majorVersion": requirement.majorVersion,
        "distribution": requirement.distribution,
        "runtimeKind": requirement.runtimeKind,
    ]
}

func opVerifyArtifact(_ given: [String: Any]) throws -> [String: Any] {
    guard (given["hashType"] as? String ?? "sha1") == "sha1" else {
        throw fail("E_UNSUPPORTED_OP", "仅支持 sha1")
    }
    let content = Data((given["dataUtf8"] as? String ?? "").utf8)
    let digest = Insecure.SHA1.hash(data: content).map { String(format: "%02x", $0) }.joined()
    return ["valid": digest == (given["expectedSha1"] as? String ?? "").lowercased()]
}

func opCacheDecision(_ given: [String: Any]) -> [String: Any] {
    let mtime = asDouble(given["mtime"]).map { Date(timeIntervalSince1970: $0) }
    let policy = CachePolicy(ttl: asDouble(given["ttl"]) ?? CachePolicy.defaultTTL)
    let action = policy.decide(
        mtime: mtime,
        now: Date(timeIntervalSince1970: asDouble(given["now"]) ?? 0),
        refresh: given["refresh"] as? Bool ?? false,
        offline: given["offline"] as? Bool ?? false,
        hasStale: given["hasStale"] as? Bool ?? false
    )
    return ["action": action.rawValue]
}

func opPlanServerDeploy(_ given: [String: Any]) throws -> [String: Any] {
    let type = GameType(rawValue: given["type"] as? String ?? "vanilla") ?? .vanilla
    let data = try loadFixture(given["snapshot"] as? String ?? "")
    let version = try JSONDecoder().decode(VersionPlan.self, from: data)
    guard let plan = GamePlan.planServerDeploy(
        version: version,
        type: type,
        root: given["root"] as? String ?? ""
    ) else {
        throw fail("E_UNSUPPORTED_OP", "\(type.rawValue) 无离线部署计划")
    }
    return [
        "version": plan.version,
        "type": plan.type,
        "workdir": plan.workdir,
        "jarName": plan.jarName,
        "eula": plan.eula,
        "coreArtifact": [
            "url": plan.coreArtifact.url,
            "sha1": plan.coreArtifact.sha1 ?? NSNull(),
            "size": plan.coreArtifact.size ?? NSNull(),
            "filename": plan.coreArtifact.filename,
        ],
    ]
}

func opPlanDownloadConcurrency(_ given: [String: Any]) -> [String: Any] {
    let plan = TransferPolicy.plan(sizeBytes: asInt(given["sizeBytes"]) ?? 0)
    return ["mode": plan.mode.rawValue, "parts": plan.parts]
}

func opResolveConcurrency(_ given: [String: Any]) -> [String: Any] {
    ["concurrency": TransferPolicy.clampThreads(asInt(given["threads"]) ?? 0)]
}

func opNonTtyDefaults(_ given: [String: Any]) throws -> [String: Any] {
    let summary = try JSONDecoder().decode(
        ManifestSummary.self,
        from: try loadFixture(given["snapshot"] as? String ?? "")
    )
    return [
        "version": given["providedVersion"] as? String ?? summary.latestRelease,
        "username": given["providedUsername"] as? String ?? "guest",
        "interactive": false,
        "confirm": true,
    ]
}

func opNormalizeProgress(_ given: [String: Any]) -> [String: Any] {
    let input = given["input"] as? [String: Any] ?? [:]
    let total = input["total"]
    return [
        "kind": input["kind"] as? String ?? "count",
        "description": input["description"] ?? NSNull(),
        "total": isNull(total) ? NSNull() : total!,
        "current": input["current"] ?? NSNull(),
        "phase": input["phase"] ?? NSNull(),
        "indefinite": isNull(total),
    ]
}

func dispatch(_ request: [String: Any]) -> [String: Any] {
    guard let operation = request["operation"] as? String else {
        return err("E_USAGE", "缺少 operation")
    }
    do {
        switch operation {
        case "planLayout": return ok(opPlanLayout(request))
        case "planClientLaunch": return ok(try opPlanClientLaunch(request))
        case "resolveVersion": return ok(try opResolveVersion(request))
        case "requiredJava": return ok(try opRequiredJava(request))
        case "verifyArtifact": return ok(try opVerifyArtifact(request))
        case "cacheDecision": return ok(opCacheDecision(request))
        case "planServerDeploy": return ok(try opPlanServerDeploy(request))
        case "planDownloadConcurrency": return ok(opPlanDownloadConcurrency(request))
        case "resolveConcurrency": return ok(opResolveConcurrency(request))
        case "nonTtyDefaults": return ok(try opNonTtyDefaults(request))
        case "normalizeProgress": return ok(opNormalizeProgress(request))
        default: return err("E_UNSUPPORTED_OP", "未实现操作 \(operation)")
        }
    } catch let error as ConformanceError {
        return err(error.code, error.message)
    } catch {
        return err("E_INTERNAL", "\(error)")
    }
}

// MARK: - entry

let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard
    let object = try? JSONSerialization.jsonObject(with: inputData),
    let request = object as? [String: Any]
else {
    FileHandle.standardOutput.write(Data("\(err("E_USAGE", "非法请求 JSON"))\n".utf8))
    exit(2)
}

let response = dispatch(request)
let output = try JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes, .sortedKeys])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
