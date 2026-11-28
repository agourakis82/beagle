//
//  LocalLLMEngine+Inference.swift
//  BeagleCore
//
//  Primary model lifecycle (load, unload, system instructions), streaming
//  generation, and HuggingFace Hub downloader / tokenizer adapters.
//

import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLX
import MLXLLM
import MLXLMCommon
import Hub
import Tokenizers
#endif

extension LocalLLMEngine {

    /// Põe o grounding onde ele pertence: no papel de SISTEMA.
    ///
    /// Antes o offline mandava o grounding inteiro dentro do turno do USUÁRIO
    /// (`streamResponse(to:)` trata tudo como fala dele). O modelo então recebia
    /// 9 KB de "Você é o Beagle, não é assistente..." como se ELE tivesse dito
    /// aquilo — e respondia continuando o documento de persona. Foi o que ele viu
    /// na tela: o companion escrevendo longamente sobre como devia se comportar,
    /// sem que nada tivesse sido perguntado.
    ///
    /// Trocar de papel custa recriar a sessão (perde o histórico interno), então
    /// só recria quando o texto realmente muda.
    public func aplicarInstrucoes(_ texto: String) {
        #if canImport(MLXLLM)
        let novo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !novo.isEmpty, novo != instrucoesAtuais, let container = modelContainer else { return }
        chatSession = makeChatSession(with: container, instructions: novo)
        instrucoesAtuais = novo
        #endif
    }

    // MARK: - Load

    public func load(_ model: OnDeviceModel) async {
        guard Self.supportsLocalRuntime else {
            loadState = .error("On-device models are unavailable in the simulator")
            return
        }

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
            chatSession = makeChatSession(with: container)
            loadState = .ready
        } catch {
            loadState = .error(error.localizedDescription)
        }
        #else
        loadState = .error("MLX not available on this platform")
        #endif
    }

    public func unload() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        chatSession = nil
        modelContainer = nil
        mambaSession = nil
        mambaContainer = nil
        Memory.clearCache()
        #endif
        currentModel = nil
        mambaModel = nil
        mambaLoaded = false
        loadState = .idle
        isGenerating = false
    }

    // MARK: - Generate (streaming)

    public func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        #if canImport(MLXLLM)
        guard let session = chatSession else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.modelNotLoaded) }
        }

        isGenerating = true
        let stream = session.streamResponse(to: prompt)

        return AsyncThrowingStream { [weak self] continuation in
            // Run generation OFF the main actor. The whole engine is @MainActor, so a
            // plain `Task {}` here inherits the main executor and the MLX prefill/decode
            // blocks the UI thread — that is the "frozen spinner, zero tokens" symptom.
            // Detach, stream tokens out, and hop back to main only to publish state.
            Task.detached { [weak self] in
                var tokenCount = 0
                let startTime = CFAbsoluteTimeGetCurrent()

                do {
                    for try await chunk in stream {
                        tokenCount += 1
                        continuation.yield(chunk)

                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        if elapsed > 0 {
                            let tps = Double(tokenCount) / elapsed
                            await MainActor.run { self?.tokensPerSecond = tps }
                        }
                    }
                } catch {
                    await MainActor.run { self?.isGenerating = false }
                    continuation.finish(throwing: error)
                    return
                }

                await MainActor.run { self?.isGenerating = false }
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
        if let container = modelContainer {
            chatSession = makeChatSession(with: container)
        }
        #endif
    }
}

// MARK: - HuggingFace Downloader + TokenizerLoader

#if canImport(MLXLLM)

/// Downloads model snapshots from HuggingFace Hub.
struct HubApiDownloader: Downloader, Sendable {
    let hub: HubApi

    init() {
        // Use stored HF token for gated models (medical, etc.)
        let token = UserDefaults.standard.string(forKey: "hfToken")
        self.hub = HubApi(
            downloadBase: LocalLLMEngine.pesosBase,
            hfToken: token
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
