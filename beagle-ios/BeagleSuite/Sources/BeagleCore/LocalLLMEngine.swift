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

/// Available on-device models, ordered by capability.
public enum OnDeviceModel: String, CaseIterable, Identifiable, Sendable {
    case qwen3_8B     = "qwen3-8b-4bit"
    case qwen2_5_7B   = "qwen2.5-7b"
    case deepseekR1   = "deepseek-r1-7b-4bit"
    case llama3_1_8B  = "llama3.1-8b-4bit"
    case gemma2_9B    = "gemma2-9b-4bit"
    case qwen3_4B     = "qwen3-4b-4bit"
    case llama3_2_3B  = "llama3.2-3b-4bit"
    case gemma2_2B    = "gemma2-2b-4bit"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .qwen3_8B:    return "Qwen 3 8B"
        case .qwen2_5_7B:  return "Qwen 2.5 7B"
        case .deepseekR1:  return "DeepSeek-R1 7B"
        case .llama3_1_8B: return "Llama 3.1 8B"
        case .gemma2_9B:   return "Gemma 2 9B"
        case .qwen3_4B:    return "Qwen 3 4B"
        case .llama3_2_3B: return "Llama 3.2 3B"
        case .gemma2_2B:   return "Gemma 2 2B"
        }
    }

    public var sizeDescription: String {
        switch self {
        case .qwen3_8B:    return "~5 GB"
        case .qwen2_5_7B:  return "~4.5 GB"
        case .deepseekR1:  return "~5 GB"
        case .llama3_1_8B: return "~4.8 GB"
        case .gemma2_9B:   return "~5.5 GB"
        case .qwen3_4B:    return "~2.5 GB"
        case .llama3_2_3B: return "~2 GB"
        case .gemma2_2B:   return "~1.5 GB"
        }
    }

    public var parameterCount: String {
        switch self {
        case .qwen3_8B, .llama3_1_8B: return "8B"
        case .qwen2_5_7B, .deepseekR1: return "7B"
        case .gemma2_9B:   return "9B"
        case .qwen3_4B:    return "4B"
        case .llama3_2_3B: return "3B"
        case .gemma2_2B:   return "2B"
        }
    }

    public var bestFor: String {
        switch self {
        case .qwen3_8B:    return "Math, science, code, reasoning"
        case .qwen2_5_7B:  return "STEM reasoning, technical analysis"
        case .deepseekR1:  return "Chain-of-thought, step-by-step derivations"
        case .llama3_1_8B: return "General + biomedical knowledge"
        case .gemma2_9B:   return "Reasoning, safety, instruction following"
        case .qwen3_4B:    return "Fast reasoning, balanced quality/speed"
        case .llama3_2_3B: return "Fast general purpose"
        case .gemma2_2B:   return "Ultra-fast fallback"
        }
    }

    /// Minimum device RAM in GB to run this model.
    public var minimumRAMGB: UInt64 {
        switch self {
        case .qwen3_8B, .deepseekR1, .llama3_1_8B, .gemma2_9B, .qwen2_5_7B: return 8
        case .qwen3_4B:    return 6
        case .llama3_2_3B: return 4
        case .gemma2_2B:   return 4
        }
    }

    /// Whether this device can run this model.
    public var fitsOnThisDevice: Bool {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        return ramGB >= minimumRAMGB
    }

    #if canImport(MLXLLM)
    var mlxConfiguration: ModelConfiguration {
        switch self {
        case .qwen3_8B:    return LLMRegistry.qwen3_8b_4bit
        case .qwen2_5_7B:  return LLMRegistry.qwen2_5_7b
        case .deepseekR1:  return LLMRegistry.deepSeekR1_7B_4bit
        case .llama3_1_8B: return LLMRegistry.llama3_1_8B_4bit
        case .gemma2_9B:   return LLMRegistry.gemma_2_9b_it_4bit
        case .qwen3_4B:    return LLMRegistry.qwen3_4b_4bit
        case .llama3_2_3B: return LLMRegistry.llama3_2_3B_4bit
        case .gemma2_2B:   return LLMRegistry.gemma_2_2b_it_4bit
        }
    }
    #endif

    /// Recommended model for this device.
    public static var recommended: OnDeviceModel {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        if ramGB >= 12 { return .qwen3_8B }
        if ramGB >= 8  { return .qwen3_4B }
        return .gemma2_2B
    }
}

// MARK: - Engine

@Observable
@MainActor
public final class LocalLLMEngine {

    public static let shared = LocalLLMEngine()

    public private(set) var loadState: LoadState = .idle
    public private(set) var currentModel: OnDeviceModel?
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
