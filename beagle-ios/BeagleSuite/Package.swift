// swift-tools-version: 6.2
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
        ),
        .library(
            name: "BeagleWorkbenchKit",
            targets: ["BeagleWorkbenchKit"]
        )
    ],
    dependencies: [
        // On-device LLM inference via Apple MLX
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        // HuggingFace Hub client for model downloads + tokenizers
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.1.0")),
        // On-device Whisper speech-to-text
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.18.0"),
        // VT100/xterm terminal emulator for the native fleet terminal (iOS/macOS only)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
    ],
    targets: [
        // Shared core: API client, truth system, models, Tailnet resolver,
        // Observation-framework data stores, on-device LLM engine.
        // No UI. Platform-agnostic (except watchOS excludes MLX).
        .target(
            name: "BeagleCore",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .macOS, .visionOS])),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .macOS, .visionOS])),
                .product(name: "Hub", package: "swift-transformers", condition: .when(platforms: [.iOS, .macOS, .visionOS])),
                .product(name: "Tokenizers", package: "swift-transformers", condition: .when(platforms: [.iOS, .macOS, .visionOS])),
                .product(name: "WhisperKit", package: "WhisperKit", condition: .when(platforms: [.iOS, .macOS, .visionOS])),
            ],
            path: "Sources/BeagleCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "BeagleWorkbenchKit",
            dependencies: [
                "BeagleCore",
                .product(name: "SwiftTerm", package: "SwiftTerm", condition: .when(platforms: [.iOS, .macOS])),
            ],
            path: "Sources/BeagleWorkbenchKit",
            exclude: ["LICENSE-AGPL-NOTICE.md"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "BeagleCoreTests",
            dependencies: ["BeagleCore"],
            path: "Tests/BeagleCoreTests"
        ),
        .testTarget(
            name: "BeagleWorkbenchKitTests",
            dependencies: ["BeagleWorkbenchKit", "BeagleCore"],
            path: "Tests/BeagleWorkbenchKitTests"
        )
    ]
)
