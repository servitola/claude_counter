// swift-tools-version: 6.2

import PackageDescription

/// Strict concurrency + warnings-as-errors apply to every target.
/// Upcoming features keep us close to Swift 7 semantics so we don't
/// accumulate migration debt.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableExperimentalFeature("StrictConcurrency"),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "ClaudeCounter",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ClaudeCounter", targets: ["ClaudeCounter"]),
        .executable(name: "ClaudeCounterWidget", targets: ["ClaudeCounterWidget"]),
    ],
    targets: [
        .target(
            name: "CounterShared",
            path: "Sources/CounterShared",
            swiftSettings: strict
        ),
        .executableTarget(
            name: "ClaudeCounter",
            dependencies: ["CounterShared"],
            path: "Sources/ClaudeCounter",
            swiftSettings: strict
        ),
        // Packaged by scripts/build-app.sh as PlugIns/ClaudeCounterWidget.appex;
        // SwiftPM has no app-extension product. An extension starts in
        // ExtensionKit's _NSExtensionMain, not a plain main.
        .executableTarget(
            name: "ClaudeCounterWidget",
            dependencies: ["CounterShared"],
            path: "Sources/ClaudeCounterWidget",
            swiftSettings: strict,
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(
            name: "ClaudeCounterTests",
            dependencies: ["ClaudeCounter", "CounterShared"],
            path: "Tests/ClaudeCounterTests",
            resources: [
                .copy("Fixtures/usage.json"),
                .copy("Fixtures/organizations.json"),
                .copy("Fixtures/codex_usage_both_windows.json"),
                .copy("Fixtures/codex_usage_weekly_only.json"),
            ],
            swiftSettings: strict
        ),
    ]
)
