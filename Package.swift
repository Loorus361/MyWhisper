// swift-tools-version: 6.3
// Defines the MyWhisper SwiftPM package and macOS target configuration.
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyWhisper",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "MyWhisper"
        ),
        .testTarget(
            name: "MyWhisperTests",
            dependencies: ["MyWhisper"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
