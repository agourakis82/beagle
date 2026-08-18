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
            name: "BeagleLocalLLM",
            targets: ["BeagleLocalLLM"]
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
        // WhisperKit REMOVIDO em 15-ago-2026: declarado no BeagleCore e importado por
        // ZERO arquivos. Toda a fala do app passa por SpeechAnalyzer/SFSpeechRecognizer
        // (ver SpeechRecognizer.swift). Ele so engordava o alvo — e como o WIDGET linka
        // BeagleCore, engordava o widget junto.
        // VT100/xterm terminal emulator for the native fleet terminal (iOS/macOS only)
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
    ],
    targets: [
        // Shared core: API client, truth system, models, Tailnet resolver,
        // Observation-framework data stores, on-device LLM engine.
        // No UI. Platform-agnostic (except watchOS excludes MLX).
        // Ponte Objective-C: converte NSException de áudio em NSError.
        //
        // O AVAudioEngine sinaliza erro de programação com NSException, e Swift NÃO
        // captura NSException: do/catch não vê, try? não vê. O processo recebe SIGABRT
        // e o app simplesmente FECHA — sem chance de degradar. Foi o que aconteceu
        // quatro vezes com o microfone.
        //
        // Este ramo já conserta as causas conhecidas (permissão antes de começar,
        // isolamento de ator, graph-init). A ponte cobre a classe INTEIRA, inclusive
        // a próxima causa que ninguém previu — e diz QUAL chamada lançou, em vez de
        // obrigar a deduzir pelo fluxo.
        //
        // Alvo separado porque SPM não mistura Swift e Objective-C no mesmo alvo.
        .target(
            name: "BeagleAudioGuard",
            path: "Sources/BeagleAudioGuard",
            publicHeadersPath: "include"
        ),
        .target(
            name: "BeagleCore",
            // NUCLEO MAGRO. MLX/Hub/Tokenizers saíram para BeagleLocalLLM em
            // 15-ago-2026. O alvo dos WIDGETS linka este aqui: tudo que entra
            // neste array entra no widget junto — e era assim que um widget de
            // três linhas de texto carregava 80 MB de runtime de LLM e três
            // bundles aninhados que faziam a instalação no aparelho ser recusada.
            // Ver Sources/BeagleCore/MotorLocal.swift.
            dependencies: [
                "BeagleAudioGuard",
            ],
            path: "Sources/BeagleCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .swiftLanguageMode(.v6)
            ]
        ),
        // O runtime de LLM local, ISOLADO do núcleo. Só o app linka isto; o widget
        // e o relógio ficam de fora, e é essa separação que devolve o tamanho.
        //
        // macOS fica de fora de propósito: swift-transformers não compila para
        // macOS com o toolchain atual (Hub/Config.swift, ObjectKey), e era isso
        // que impedia `swift test` de rodar — os testes do pacote existiam e
        // NUNCA eram executados por ninguém.
        .target(
            name: "BeagleLocalLLM",
            dependencies: [
                "BeagleCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .visionOS])),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm", condition: .when(platforms: [.iOS, .visionOS])),
                .product(name: "Hub", package: "swift-transformers", condition: .when(platforms: [.iOS, .visionOS])),
                .product(name: "Tokenizers", package: "swift-transformers", condition: .when(platforms: [.iOS, .visionOS])),
            ],
            path: "Sources/BeagleLocalLLM",
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
