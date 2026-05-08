// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeCounter",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ClaudeCounter", targets: ["ClaudeCounter"]),
    ],
    targets: [
        .executableTarget(name: "ClaudeCounter"),
    ]
)
