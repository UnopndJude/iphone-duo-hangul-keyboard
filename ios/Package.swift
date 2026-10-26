// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreePadCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ThreePadCore", targets: ["ThreePadCore"]),
        .library(name: "ThreePadDocument", targets: ["ThreePadDocument"])
    ],
    targets: [
        .target(name: "ThreePadCore", path: "Core"),
        .target(name: "ThreePadDocument", dependencies: ["ThreePadCore"], path: "DocumentBridge"),
        .testTarget(name: "ThreePadCoreTests", dependencies: ["ThreePadCore"], path: "Tests/CoreTests"),
        .testTarget(name: "DocumentTests", dependencies: ["ThreePadDocument", "ThreePadCore"], path: "Tests/DocumentTests")
    ],
    swiftLanguageVersions: [.v5]
)
