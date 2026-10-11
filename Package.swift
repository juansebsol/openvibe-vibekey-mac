// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "vibekey-mac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "vibekey-cli", targets: ["vibekey-cli"]),
        .executable(name: "VibeKey", targets: ["VibeKey"]),
    ],
    targets: [
        .target(name: "VibeKeyCore"),
        .executableTarget(name: "vibekey-cli", dependencies: ["VibeKeyCore"]),
        .executableTarget(name: "VibeKey", dependencies: ["VibeKeyCore"]),
    ]
)
