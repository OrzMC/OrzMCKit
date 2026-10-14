//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation

public extension Client {
    static func launcherProfilePath(for version: String, root: String = GamePlan.defaultRoot) -> String {
        return GamePlan.clientDir(version: version, root: root) + "/launcher_profiles.json"
    }
    static func launcherProfile(for version: String, root: String = GamePlan.defaultRoot) throws -> LauncherProfile? {
        let dstFilePath = self.launcherProfilePath(for: version, root: root)
        guard dstFilePath.isExist() else {
            return nil
        }
        let fileURL = URL(fileURLWithPath: dstFilePath)
        let data = try Data(contentsOf: fileURL)
        return try LauncherProfile.profile(from: data)
    }
    static func launcherProfileItems(for version: String, root: String = GamePlan.defaultRoot) throws -> [String] {
        guard let launcherProfile = try self.launcherProfile(for: version, root: root) else {
            return [String]()
        }
        return Array(launcherProfile.profiles.keys.sorted())
    }
    static func saveSelectedProfile(for version: String, with chooseItem: String, root: String = GamePlan.defaultRoot) throws -> LauncherProfile?  {
        let launcherProfilePath = Self.launcherProfilePath(for: version, root: root)
        guard var launcherProfile = try Self.launcherProfile(for: version, root: root) else {
            try GamePlan.clientDir(version: version, root: root).makeDirIfNeed()
            try LauncherProfile.vanillaProfile(version: version).writeToFile(launcherProfilePath)
            return nil
        }
        launcherProfile.selectedProfile = chooseItem
        try launcherProfile.writeToFile(launcherProfilePath)
        return launcherProfile
    }
    func launcherProfileItems() throws -> [String] {
        let version = self.clientInfo.version.id
        return try Self.launcherProfileItems(for: version, root: self.clientInfo.rootDir)
    }
    mutating func selectedProfile(_ chooseItem: String) throws {
        let version = self.clientInfo.version.id
        guard let launcherProfile = try Self.saveSelectedProfile(for: version, with: chooseItem, root: self.clientInfo.rootDir) else {
            return
        }
        self.clientInfo.launcherProfile = launcherProfile
    }
}
