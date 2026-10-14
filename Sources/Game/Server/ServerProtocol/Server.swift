//
//  File.swift
//  
//
//  Created by joker on 2022/1/3.
//
import Foundation
import JokerKits

public protocol Server {
    var serverInfo: ServerInfo { get }
    func start() async throws -> ManagedProcess?
}
