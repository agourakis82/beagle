//
//  LocalLLMEngine.swift
//  BeagleCore
//
//  On-device LLM inference engine backed by MLX Swift.
//  Downloads models from HuggingFace, runs inference on Neural Engine / GPU.
//
//  Tier 0.5 in the agent hierarchy:
//    Tier 0:   Foundation Models (Apple, quick, sub-second)
//    Tier 0.5: MLX (on-device, deep reasoning, 8-30 tok/s) ← THIS
//    Tier 1:   Local SGLang (cluster GPU)
//    Tier 2-3: Cloud (Claude, Grok)
//

import Foundation
import Observation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon
import Hub
import Tokenizers
#endif

// MARK: - Model catalog

/// Model category for grouping in the UI.
public enum ModelCategory: String, CaseIterable, Sendable {
    case reasoning    = "Reasoning"
    case code         = "Code"
    case medical      = "Medical & Bio"
    case ssm          = "SSM (State Space)"
    case multilingual = "Multilingual"
    case fast         = "Fast & Light"
}

/// Available on-device models — grouped by what they're genuinely best at.
public enum OnDeviceModel: String, CaseIterable, Identifiable, Sendable {

    // Reasoning
    case qwen3_8B        = "qwen3-8b-4bit"
    case deepseekR1      = "deepseek-r1-7b-4bit"
    case aceReason7B     = "acereason-nemotron-7b-4bit"
    case gemma2_9B       = "gemma2-9b-4bit"
    case gemma4_4B       = "gemma4-e4b-4bit"
    case qwen3_4B        = "qwen3-4b-4bit"

    // Code
    case mimo7B          = "mimo-7b-sft-4bit"
    case phi35Mini       = "phi-3.5-mini-4bit"
    case qwen2_5_7B      = "qwen2.5-7b"
    case codeQwen7B      = "codeqwen-7b-4bit"

    // Medical & Bio (PBPK, pharmacokinetics, biomedical literature)
    case bioMistral7B    = "biomistral-7b-4bit"
    case openBioLLM7B    = "openbiollm-7b-4bit"
    case meditron7B      = "meditron-7b-4bit"

    // SSM / Hybrid (linear complexity, long context)
    case falconH1_7B     = "falcon-h1r-7b-4bit"
    case lfm2MoE         = "lfm2-8b-a1b-3bit"
    case lfm2_1B         = "lfm2-1.2b-4bit"
    case jamba3B         = "jamba-reasoning-3b-4bit"
    case graniteHybrid   = "granite-4.0-h-tiny-4bit"

    // Multilingual (strong Portuguese)
    case mistral7B       = "mistral-7b-v0.3-4bit"
    case qwen3_1_7B      = "qwen3-1.7b-4bit"

    // Fast & Light
    case llama3_1_8B     = "llama3.1-8b-4bit"
    case llama3_2_3B     = "llama3.2-3b-4bit"
    case smolLM3_3B      = "smollm3-3b-4bit"
    case gemma4_2B       = "gemma4-e2b-4bit"
    case gemma2_2B       = "gemma2-2b-4bit"
    case bitnet2B        = "bitnet-b1.58-2b-4bit"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .qwen3_8B:      return "Qwen 3 8B"
        case .deepseekR1:    return "DeepSeek-R1 7B"
        case .aceReason7B:   return "AceReason 7B"
        case .gemma2_9B:     return "Gemma 2 9B"
        case .gemma4_4B:     return "Gemma 4 4B"
        case .qwen3_4B:      return "Qwen 3 4B"
        case .mimo7B:        return "MiMo 7B"
        case .phi35Mini:     return "Phi 3.5 Mini"
        case .qwen2_5_7B:    return "Qwen 2.5 7B"
        case .codeQwen7B:    return "CodeQwen 7B"
        case .bioMistral7B:  return "BioMistral 7B"
        case .openBioLLM7B:  return "OpenBioLLM 7B"
        case .meditron7B:    return "Meditron 7B"
        case .falconH1_7B:   return "Falcon H1R 7B"
        case .lfm2MoE:       return "LFM2 8B-A1B"
        case .lfm2_1B:       return "LFM2 1.2B"
        case .jamba3B:       return "Jamba 3B"
        case .graniteHybrid: return "Granite Hybrid"
        case .mistral7B:     return "Mistral 7B v0.3"
        case .qwen3_1_7B:    return "Qwen 3 1.7B"
        case .llama3_1_8B:   return "Llama 3.1 8B"
        case .llama3_2_3B:   return "Llama 3.2 3B"
        case .smolLM3_3B:    return "SmolLM3 3B"
        case .gemma4_2B:     return "Gemma 4 2B"
        case .gemma2_2B:     return "Gemma 2 2B"
        case .bitnet2B:      return "BitNet 2B"
        }
    }

    public var category: ModelCategory {
        switch self {
        case .qwen3_8B, .deepseekR1, .aceReason7B, .gemma2_9B, .gemma4_4B, .qwen3_4B: return .reasoning
        case .mimo7B, .phi35Mini, .qwen2_5_7B, .codeQwen7B: return .code
        case .bioMistral7B, .openBioLLM7B, .meditron7B: return .medical
        case .falconH1_7B, .lfm2MoE, .lfm2_1B, .jamba3B, .graniteHybrid: return .ssm
        case .mistral7B, .qwen3_1_7B: return .multilingual
        case .llama3_1_8B, .llama3_2_3B, .smolLM3_3B, .gemma4_2B, .gemma2_2B, .bitnet2B: return .fast
        }
    }

    public var sizeDescription: String {
        switch self {
        case .qwen3_8B:      return "~5 GB"
        case .deepseekR1:    return "~5 GB"
        case .aceReason7B:   return "~4.5 GB"
        case .gemma2_9B:     return "~5.5 GB"
        case .gemma4_4B:     return "~2.8 GB"
        case .qwen3_4B:      return "~2.5 GB"
        case .mimo7B:        return "~4.5 GB"
        case .phi35Mini:     return "~2.3 GB"
        case .qwen2_5_7B:    return "~4.5 GB"
        case .codeQwen7B:    return "~4.5 GB"
        case .bioMistral7B:  return "~4.5 GB"
        case .openBioLLM7B:  return "~4.5 GB"
        case .meditron7B:    return "~4.5 GB"
        case .falconH1_7B:   return "~4.5 GB"
        case .lfm2MoE:       return "~3 GB"
        case .lfm2_1B:       return "~0.8 GB"
        case .jamba3B:       return "~2 GB"
        case .graniteHybrid: return "~1.5 GB"
        case .mistral7B:     return "~4.5 GB"
        case .qwen3_1_7B:    return "~1.2 GB"
        case .llama3_1_8B:   return "~4.8 GB"
        case .llama3_2_3B:   return "~2 GB"
        case .smolLM3_3B:    return "~2 GB"
        case .gemma4_2B:     return "~1.5 GB"
        case .gemma2_2B:     return "~1.5 GB"
        case .bitnet2B:      return "~1 GB"
        }
    }

    public var parameterCount: String {
        switch self {
        case .qwen3_8B, .llama3_1_8B: return "8B"
        case .deepseekR1, .aceReason7B, .falconH1_7B, .mimo7B, .qwen2_5_7B, .mistral7B, .codeQwen7B, .bioMistral7B, .openBioLLM7B, .meditron7B: return "7B"
        case .gemma2_9B: return "9B"
        case .lfm2MoE: return "8B (1B active)"
        case .gemma4_4B, .qwen3_4B: return "4B"
        case .phi35Mini: return "3.8B"
        case .jamba3B, .llama3_2_3B, .smolLM3_3B: return "3B"
        case .gemma4_2B, .gemma2_2B, .bitnet2B: return "2B"
        case .qwen3_1_7B: return "1.7B"
        case .lfm2_1B: return "1.2B"
        case .graniteHybrid: return "~1B"
        }
    }

    public var bestFor: String {
        switch self {
        case .qwen3_8B:      return "Top-tier reasoning: math proofs, scientific analysis, multi-step logic. Best overall quality on-device."
        case .deepseekR1:    return "Chain-of-thought specialist. Shows its work step-by-step. Strongest at formal derivations."
        case .aceReason7B:   return "NVIDIA’s math champion. Outperforms larger models on MATH/GSM8K benchmarks."
        case .gemma2_9B:     return "Google’s most careful model. Strong instruction following with safety guardrails."
        case .gemma4_4B:     return "Latest Google architecture. Balanced reasoning + multimodal-ready. Great quality-to-size."
        case .qwen3_4B:      return "Fast reasoning with thinking mode. Sweet spot: quality close to 7B at half the memory."
        case .mimo7B:        return "Xiaomi’s code specialist. Trained on code + math. Better functions than general models."
        case .phi35Mini:     return "Microsoft’s STEM optimizer. Excels at code generation and scientific text."
        case .qwen2_5_7B:    return "Strong coder and technical writer. Good at structured output (JSON, YAML)."
        case .codeQwen7B:    return "Alibaba’s dedicated code model. Trained on 3T code tokens. Superior at completion, refactoring, and explanation."
        case .bioMistral7B:  return "Fine-tuned on PubMed + medical literature. Understands pharmacokinetics, drug interactions, clinical terminology."
        case .openBioLLM7B:  return "Biomedical knowledge extraction specialist. Strong on PBPK modeling terminology and research paper analysis."
        case .meditron7B:    return "Adapted from Llama on medical guidelines + PubMed. Clinical reasoning and evidence-based answers."
        case .falconH1_7B:   return "Mamba2 SSM hybrid — O(n) complexity. Long context without degrading. Future architecture."
        case .lfm2MoE:       return "Liquid SSM + MoE: only 1B params active but 8B total knowledge. Extremely fast."
        case .lfm2_1B:       return "Pure SSM from Liquid AI. Tiny but supports native tool-calling. Fastest in catalog."
        case .jamba3B:       return "AI21’s SSM+Transformer hybrid. Linear complexity for long exocortex conversations."
        case .graniteHybrid: return "IBM’s triple hybrid: SSM + Transformer + MoE. Experimental frontier architecture."
        case .mistral7B:     return "Mistral’s multilingual flagship. Strong Portuguese, French, Spanish. 128k context."
        case .qwen3_1_7B:    return "Alibaba’s fast multilingual. Good Portuguese from massive training. Quick draft model."
        case .llama3_1_8B:   return "Meta’s reliable generalist. Broad biomedical knowledge. Predictable behavior."
        case .llama3_2_3B:   return "Fast general purpose. Good enough for most tasks, small enough for quick loading."
        case .smolLM3_3B:    return "HuggingFace’s efficiency champion. Optimized for mobile. Good all-rounder."
        case .gemma4_2B:     return "Smallest Google model with latest architecture. Ultra-fast for quick questions."
        case .gemma2_2B:     return "Mature small model. Well-tested, predictable. Good emergency fallback."
        case .bitnet2B:      return "Microsoft’s 1.58-bit architecture. Radically efficient — future of inference."
        }
    }

    public var tagline: String {
        switch self {
        case .qwen3_8B:      return "Best overall"
        case .deepseekR1:    return "Shows its work"
        case .aceReason7B:   return "Math champion"
        case .gemma2_9B:     return "Most careful"
        case .gemma4_4B:     return "Balanced"
        case .qwen3_4B:      return "Fast thinker"
        case .mimo7B:        return "Code specialist"
        case .phi35Mini:     return "STEM focused"
        case .qwen2_5_7B:    return "Structured output"
        case .codeQwen7B:    return "3T code tokens"
        case .bioMistral7B:  return "PubMed trained"
        case .openBioLLM7B:  return "Bio extraction"
        case .meditron7B:    return "Clinical reasoning"
        case .falconH1_7B:   return "Long context SSM"
        case .lfm2MoE:       return "Fastest 8B"
        case .lfm2_1B:       return "Tiny + tools"
        case .jamba3B:       return "Reasoning SSM"
        case .graniteHybrid: return "Triple hybrid"
        case .mistral7B:     return "Multilingual"
        case .qwen3_1_7B:    return "Quick draft"
        case .llama3_1_8B:   return "Reliable generalist"
        case .llama3_2_3B:   return "Quick & capable"
        case .smolLM3_3B:    return "Efficiency king"
        case .gemma4_2B:     return "Ultra-fast"
        case .gemma2_2B:     return "Proven fallback"
        case .bitnet2B:      return "1-bit pioneer"
        }
    }

    public var minimumRAMGB: UInt64 {
        switch self {
        case .qwen3_8B, .deepseekR1, .aceReason7B, .llama3_1_8B, .gemma2_9B,
             .qwen2_5_7B, .falconH1_7B, .mimo7B, .mistral7B,
             .codeQwen7B, .bioMistral7B, .openBioLLM7B, .meditron7B:
            return 8
        case .gemma4_4B, .qwen3_4B, .phi35Mini, .lfm2MoE:
            return 6
        case .jamba3B, .llama3_2_3B, .smolLM3_3B, .gemma4_2B, .gemma2_2B,
             .bitnet2B, .qwen3_1_7B, .lfm2_1B, .graniteHybrid:
            return 4
        }
    }

    public var fitsOnThisDevice: Bool {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return ramGB >= minimumRAMGB
    }

    #if canImport(MLXLLM)
    var mlxConfiguration: ModelConfiguration {
        switch self {
        case .qwen3_8B:      return LLMRegistry.qwen3_8b_4bit
        case .deepseekR1:    return LLMRegistry.deepSeekR1_7B_4bit
        case .aceReason7B:   return ModelConfiguration(id: "mlx-community/AceReason-Nemotron-7B-4bit")
        case .gemma2_9B:     return LLMRegistry.gemma_2_9b_it_4bit
        case .gemma4_4B:     return LLMRegistry.gemma4_e4b_it_4bit
        case .qwen3_4B:      return LLMRegistry.qwen3_4b_4bit
        case .mimo7B:        return ModelConfiguration(id: "mlx-community/MiMo-7B-SFT-4bit")
        case .phi35Mini:     return ModelConfiguration(id: "mlx-community/Phi-3.5-mini-instruct-4bit")
        case .qwen2_5_7B:    return LLMRegistry.qwen2_5_7b
        case .codeQwen7B:    return ModelConfiguration(id: "mlx-community/CodeQwen1.5-7B-Chat-4bit")
        case .bioMistral7B:  return ModelConfiguration(id: "mlx-community/BioMistral-7B-DARE-4bit")
        case .openBioLLM7B:  return ModelConfiguration(id: "mlx-community/OpenBioLLM-Llama3-8B-4bit")
        case .meditron7B:    return ModelConfiguration(id: "mlx-community/meditron-7b-chat-4bit")
        case .falconH1_7B:   return ModelConfiguration(id: "mlx-community/Falcon-H1R-7B-4bit")
        case .lfm2MoE:       return ModelConfiguration(id: "mlx-community/LFM2-8B-A1B-3bit-MLX")
        case .lfm2_1B:       return ModelConfiguration(id: "mlx-community/LFM2-1.2B-4bit")
        case .jamba3B:       return ModelConfiguration(id: "mlx-community/AI21-Jamba-Reasoning-3B-4bit")
        case .graniteHybrid: return ModelConfiguration(id: "mlx-community/Granite-4.0-H-Tiny-4bit-DWQ")
        case .mistral7B:     return ModelConfiguration(id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit")
        case .qwen3_1_7B:    return ModelConfiguration(id: "mlx-community/Qwen3-1.7B-4bit")
        case .llama3_1_8B:   return LLMRegistry.llama3_1_8B_4bit
        case .llama3_2_3B:   return LLMRegistry.llama3_2_3B_4bit
        case .smolLM3_3B:    return ModelConfiguration(id: "mlx-community/SmolLM3-3B-4bit")
        case .gemma4_2B:     return LLMRegistry.gemma4_e2b_it_4bit
        case .gemma2_2B:     return LLMRegistry.gemma_2_2b_it_4bit
        case .bitnet2B:      return ModelConfiguration(id: "mlx-community/bitnet-b1.58-2B-4T-4bit")
        }
    }
    #endif

    public static var recommended: OnDeviceModel {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 12 { return .qwen3_8B }
        if ramGB >= 8  { return .qwen3_4B }
        return .gemma4_2B
    }

    public static func models(in category: ModelCategory) -> [OnDeviceModel] {
        allCases.filter { $0.category == category }
    }
}

// MARK: - Engine

@Observable
@MainActor
public final class LocalLLMEngine {

    public static let shared = LocalLLMEngine()

    public private(set) var loadState: LoadState = .idle
    public private(set) var currentModel: OnDeviceModel? {
        didSet {
            if let model = currentModel {
                UserDefaults.standard.set(model.rawValue, forKey: "lastSelectedModel")
            }
        }
    }

    /// Last model the user selected (persisted across restarts).
    public var lastSelectedModel: OnDeviceModel? {
        guard let raw = UserDefaults.standard.string(forKey: "lastSelectedModel") else { return nil }
        return OnDeviceModel(rawValue: raw)
    }
    public private(set) var downloadProgress: Double = 0
    public private(set) var isGenerating: Bool = false
    public private(set) var tokensPerSecond: Double = 0

    public enum LoadState: Sendable, Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case error(String)
    }

    public var isReady: Bool { loadState == .ready }
    public var isAvailable: Bool {
        #if canImport(MLXLLM)
        return true
        #else
        return false
        #endif
    }

    #if canImport(MLXLLM)
    private var modelContainer: ModelContainer?
    nonisolated(unsafe) private var chatSession: ChatSession?
    #endif

    private init() {
        #if canImport(MLXLLM)
        Memory.cacheLimit = 20 * 1024 * 1024
        #endif
    }

    // MARK: - Load

    public func load(_ model: OnDeviceModel) async {
        #if canImport(MLXLLM)
        guard loadState != .loading else { return }

        // Check if model fits on this device
        if !model.fitsOnThisDevice {
            loadState = .error("Not enough RAM for \(model.displayName). Needs \(model.minimumRAMGB)GB+.")
            return
        }

        currentModel = model
        loadState = .downloading(0)

        do {
            let config = model.mlxConfiguration
            let downloader = HubApiDownloader()
            let tokenizer = HFTokenizerLoader()

            let container = try await loadModelContainer(
                from: downloader,
                using: tokenizer,
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress.fractionCompleted
                    self?.loadState = .downloading(progress.fractionCompleted)
                }
            }

            modelContainer = container
            chatSession = ChatSession(
                container,
                instructions: """
                You are an exocortex — an extension of a researcher's mind working on \
                sovereign supercomputing, PBPK pharmacokinetics, heliobiology, and \
                computational neuroscience. Think deeply. Make cross-domain connections. \
                Challenge assumptions. Be intellectually provocative.
                """,
                generateParameters: GenerateParameters(maxTokens: 2048, temperature: 0.7)
            )
            loadState = .ready
        } catch {
            loadState = .error(error.localizedDescription)
        }
        #else
        loadState = .error("MLX not available on this platform")
        #endif
    }

    public func unload() {
        #if canImport(MLXLLM)
        chatSession = nil
        modelContainer = nil
        Memory.clearCache()
        #endif
        currentModel = nil
        loadState = .idle
        isGenerating = false
    }

    // MARK: - Generate (streaming)

    public func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        #if canImport(MLXLLM) && canImport(MLXLLM)
        guard let session = chatSession else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.modelNotLoaded) }
        }

        isGenerating = true
        let stream = session.streamResponse(to: prompt)

        return AsyncThrowingStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                var tokenCount = 0
                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    for try await chunk in stream {
                        tokenCount += 1
                        continuation.yield(chunk)

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            self?.tokensPerSecond = Double(tokenCount) / elapsed
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }

                self?.isGenerating = false
                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Non-streaming convenience.
    public func respond(to prompt: String) async throws -> String {
        var result = ""
        for try await chunk in generate(prompt: prompt) {
            result += chunk
        }
        return result
    }

    /// Clear conversation history but keep model loaded.
    public func clearHistory() async {
        #if canImport(MLXLLM)
        await chatSession?.clear()
        #endif
    }
}

// MARK: - Errors

public enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case platformNotSupported

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "No model loaded. Download a model first."
        case .platformNotSupported: return "On-device LLM requires iOS/macOS/visionOS."
        }
    }
}

// MARK: - HuggingFace Downloader + TokenizerLoader

#if canImport(MLXLLM)
import Hub
import Tokenizers

/// Downloads model snapshots from HuggingFace Hub.
struct HubApiDownloader: Downloader, Sendable {
    let hub: HubApi

    init() {
        self.hub = HubApi(
            downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: id, type: .models)
        return try await hub.snapshot(
            from: repo,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

/// Loads tokenizers from HuggingFace swift-transformers.
struct HFTokenizerLoader: TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> MLXLMCommon.Tokenizer {
        let hfTokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerAdapter(hfTokenizer)
    }
}

/// Adapts HuggingFace Tokenizer to MLXLMCommon.Tokenizer protocol.
struct TokenizerAdapter: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: Tokenizers.Tokenizer

    init(_ upstream: Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        // Convert Sendable messages to String messages for upstream
        let stringMessages = messages.map { msg in
            msg.reduce(into: [String: String]()) { result, pair in
                result[pair.key] = "\(pair.value)"
            }
        }
        return try upstream.applyChatTemplate(messages: stringMessages)
    }
}
#endif
