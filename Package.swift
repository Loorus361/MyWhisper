// swift-tools-version: 6.3
// Defines the MyWhisper SwiftPM package and macOS target configuration.
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyWhisper",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "MyWhisperCore",
            targets: ["MyWhisperCore"]
        ),
    ],
    targets: [
        .target(
            name: "MyWhisperCore"
        ),
        .executableTarget(
            name: "MyWhisper",
            dependencies: ["MyWhisperCore"]
        ),
        .testTarget(
            name: "MyWhisperTests",
            dependencies: ["MyWhisperCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
