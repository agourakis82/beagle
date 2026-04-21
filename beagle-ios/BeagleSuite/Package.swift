// swift-tools-version: 6.0
// BeagleSuite — Sovereign supercomputing cockpit native Apple clients
//
// Multi-target Swift package for iOS 26, macOS 26, visionOS 26, watchOS 26.
// Apps are built via Xcode workspace; this package provides shared library targets.

import PackageDescription

let package = Package(
    name: "BeagleSuite",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26),
        .watchOS(.v26)
    ],
    products: [
        .library(
            name: "BeagleCore",
            targets: ["BeagleCore"]
        )
    ],
    targets: [
        // Shared core: API client, truth system, models, Tailnet resolver,
        // Observation-framework data stores. No UI. Platform-agnostic.
        .target(
            name: "BeagleCore",
            path: "Sources/BeagleCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "BeagleCoreTests",
            dependencies: ["BeagleCore"],
            path: "Tests/BeagleCoreTests"
        )
    ]
)
