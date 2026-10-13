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
        .package(url: "https://github.com/OrzMC/MojangAPI.git", from: "0.1.1"),
        .package(url: "https://github.com/OrzMC/PaperMC.git", from: "0.0.8"),
        .package(url: "https://github.com/OrzGeeker/OrzSwiftKit.git", from: "0.0.17"),
    ],
    targets: [
        // MARK: Command Line executable
        .executableTarget(
            name: "OrzMC",
            dependencies: ["Game"]
        ),
        .testTarget(
            name: "OrzMCTests",
            dependencies: ["OrzMC", "Game"]
        ),
        // MARK: Game Logic Capsule
        .target(name: "Game", dependencies: [
            "MojangAPI",
            "Fabric",
            .product(name: "DownloadAPI", package: "PaperMC"),
            .product(name: "HangarAPI", package: "PaperMC"),
            .product(name: "Utils", package: "OrzSwiftKit"),
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
