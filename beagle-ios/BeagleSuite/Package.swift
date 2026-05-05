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
        )
    ],
    dependencies: [
        // On-device LLM inference via Apple MLX
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        // HuggingFace Hub client for model downloads + tokenizers
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.2.0")),
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
            ],
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
