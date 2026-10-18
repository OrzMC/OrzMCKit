// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "OrzMCKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "orzmc", targets: ["OrzMC"]),
        .library(name: "Game", targets: ["Game"]),
        .library(name: "Fabric", targets: ["Fabric"]),
    ],
    dependencies: [
        .package(url: "https://github.com/OrzMC/MojangAPI.git", branch: "main"),
        .package(url: "https://github.com/OrzMC/PaperMC.git", branch: "main"),
        .package(url: "https://github.com/OrzGeeker/OrzSwiftKit.git", branch: "main"),
        // 一致性适配器要算 SHA-1：Apple 用 CryptoKit，其它平台用 swift-crypto（决策 D14）。
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
    ],
    targets: [
        // MARK: Command Line executable
        .executableTarget(
            name: "OrzMC",
            dependencies: ["Game"]
        ),
        .testTarget(
            name: "OrzMCTests",
            dependencies: [
                "OrzMC",
                "Game",
                "Fabric",
                .product(name: "CacheKit", package: "OrzSwiftKit"),
                .product(name: "TransferKit", package: "OrzSwiftKit"),
                .product(name: "Crypto",
                         package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ]
        ),
        // MARK: Conformance adapter (drives parent docs/spec fixtures)
        .executableTarget(
            name: "ConformanceAdapter",
            dependencies: [
                "Game",
                "MojangAPI",
                .product(name: "CacheKit", package: "OrzSwiftKit"),
                .product(name: "TransferKit", package: "OrzSwiftKit"),
                .product(name: "Crypto",
                         package: "swift-crypto",
                         condition: .when(platforms: [.linux])),
            ]
        ),
        // MARK: Game Logic Capsule
        .target(name: "Game", dependencies: [
            "MojangAPI",
            "Fabric",
            .product(name: "DownloadAPI", package: "PaperMC"),
            .product(name: "HangarAPI", package: "PaperMC"),
            .product(name: "CacheKit", package: "OrzSwiftKit"),
            .product(name: "Utils", package: "OrzSwiftKit"),
            .product(name: "RuntimeKit", package: "OrzSwiftKit"),
            .product(name: "TransferKit", package: "OrzSwiftKit"),
        ]),
        // MARK: Fabric
        .target(
            name: "Fabric",
            dependencies: [.product(name: "JokerKits", package: "OrzSwiftKit")]
        ),
        .testTarget(
            name: "FabricTests",
            dependencies: ["Fabric"]
        ),
    ]
)
