// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BeagleAssistant",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "BeagleAssistant",
            targets: ["BeagleAssistant"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "BeagleAssistant",
            dependencies: []
        ),
    ]
)

