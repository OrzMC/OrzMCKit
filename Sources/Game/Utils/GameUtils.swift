//
//  File.swift
//  
//
//  Created by joker on 2022/10/22.
//

import Foundation
import JokerKits
import MojangAPI

public struct GameUtils {

    public static func releases() async -> [String] {
        await MojangCache.configure(root: GamePlan.defaultRoot)
        do {
            return try await Mojang.versions(type: .release).compactMap { $0.id }
        } catch {
            return []
        }
    }
    
    public static func releaseGameVersion(_ version: String) async -> [Version]? {
        await MojangCache.configure(root: GamePlan.defaultRoot)
        return try? await Mojang.versions(type: .release).filter { $0.id == version }
    }
}
