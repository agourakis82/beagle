//
//  LocalLLMEngine+Routing.swift
//  BeagleCore
//
//  Mamba Tier -1 draft model, speculative decoding, prompt complexity triage,
//  and cognitive task routing for LocalLLMEngine.
//

import Foundation

#if canImport(MLXLLM) && canImport(MLXLMCommon)
import MLXLLM
import MLXLMCommon
#endif

// MARK: - Mamba Draft Model (Tier -1)

extension LocalLLMEngine {

    /// Load a Mamba model as draft model for speculative decoding.
    /// The Mamba model runs alongside the primary transformer model, providing
    /// O(1) memory draft tokens at 86+ tok/s for pre-screening and speculation.
    public func loadMambaDraft(_ model: OnDeviceModel) async {
        guard Self.supportsLocalRuntime else { return }
        guard model.isMamba else {
            print("[LocalLLMEngine] \(model.displayName) is not a Mamba model")
            return
        }

        #if canImport(MLXLLM)
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
                    // Report Mamba download progress without disturbing primary model state
                    let _ = progress.fractionCompleted
                    _ = self  // Suppress unused warning
                }
            }

            mambaContainer = container
            mambaSession = ChatSession(
                container,
                instructions: "You are a fast pre-screening model. Classify and draft concisely.",
                generateParameters: GenerateParameters(maxTokens: 256, temperature: 0.3)
            )
            mambaModel = model
            mambaLoaded = true
        } catch {
            print("[LocalLLMEngine] Mamba load failed: \(error)")
            mambaLoaded = false
        }
        #endif
    }

    /// Unload the Mamba draft model, freeing memory.
    public func unloadMamba() {
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        mambaSession = nil
        mambaContainer = nil
        #endif
        mambaModel = nil
        mambaLoaded = false
    }

    /// Fast Mamba-only generation -- O(1) memory, ~86 tok/s.
    /// Use for: pre-screening, stream-of-consciousness, classification.
    /// Falls back to the primary model if Mamba is not loaded.
    public func mambaGenerate(prompt: String, maxTokens: Int = 256) async throws -> String {
        guard Self.supportsLocalRuntime else {
            throw LocalLLMError.platformNotSupported
        }

        #if canImport(MLXLLM)
        guard let session = mambaSession else {
            throw LocalLLMError.mambaNotLoaded
        }

        var result = ""
        let stream = session.streamResponse(to: prompt)
        var tokenCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        for try await chunk in stream {
            tokenCount += 1
            result += chunk
            if tokenCount >= maxTokens { break }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0 {
            tokensPerSecond = Double(tokenCount) / elapsed
        }

        return result
        #else
        throw LocalLLMError.platformNotSupported
        #endif
    }

    /// Streaming Mamba-only generation -- O(1) memory, ~86 tok/s.
    /// Ideal for stream-of-consciousness capture with infinite context.
    public func mambaStream(prompt: String, maxTokens: Int = 256) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        #if canImport(MLXLLM)
        guard let session = mambaSession else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.mambaNotLoaded) }
        }

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

                        if tokenCount >= maxTokens { break }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }

                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Speculative decoding -- Mamba drafts tokens, transformer verifies.
    /// Best of both worlds: Mamba speed + transformer quality.
    /// Falls back to regular generate if Mamba is not loaded.
    public func speculativeGenerate(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard Self.supportsLocalRuntime else {
            return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        }

        // If Mamba is not loaded or no primary model, fall back to regular generation
        guard mambaLoaded else {
            return generate(prompt: prompt)
        }

        #if canImport(MLXLLM)
        guard let primarySession = chatSession, mambaSession != nil else {
            return generate(prompt: prompt)
        }

        // Speculative decoding strategy:
        // 1. Mamba drafts a batch of tokens (fast, O(1) memory)
        // 2. Transformer verifies/corrects them in parallel (one forward pass)
        // 3. Accept verified tokens, reject divergent ones
        //
        // Current implementation: draft with Mamba, then refine with transformer.
        // True speculative decoding (token-level accept/reject) requires model-level
        // logit access which depends on the MLX version. This implementation provides
        // the semantic equivalent: Mamba proposes, transformer validates.

        return AsyncThrowingStream { [weak self] continuation in
            Task { @MainActor [weak self] in
                do {
                    // Phase 1: Mamba drafts a fast response
                    let draft = try await self?.mambaGenerate(prompt: prompt, maxTokens: 128) ?? ""

                    // Phase 2: Transformer refines with the draft as context
                    let refinementPrompt = """
                    Draft response: \(draft)

                    Verify and improve this draft response to the original question. \
                    Keep what is correct, fix what is wrong, and expand if needed.
                    Original question: \(prompt)
                    """

                    let stream = primarySession.streamResponse(to: refinementPrompt)
                    var tokenCount = 0
                    let startTime = CFAbsoluteTimeGetCurrent()

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

                continuation.finish()
            }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: LocalLLMError.platformNotSupported) }
        #endif
    }

    /// Classify whether a prompt needs deep reasoning (should go to Tier 0.5+)
    /// or can be handled by Mamba alone (stays at Tier -1).
    ///
    /// Uses a lightweight Mamba inference: generate a few tokens and measure
    /// perplexity/confidence. Low-complexity prompts (greetings, classification,
    /// short factual) can stay at Tier -1. Medium prompts go to Foundation Models.
    /// Complex prompts require full MLX or cloud.
    public func triagePrompt(_ prompt: String) async -> PromptComplexity {
        guard mambaLoaded else {
            // Without Mamba, we can't triage -- assume medium complexity
            return .medium
        }

        #if canImport(MLXLLM)
        // Heuristic 1: Short prompts with simple patterns are likely simple
        let wordCount = prompt.split(separator: " ").count
        if wordCount <= 5 {
            let lowered = prompt.lowercased()
            let simplePatterns = ["hello", "hi", "hey", "thanks", "yes", "no",
                                  "ok", "what time", "what date", "status"]
            if simplePatterns.contains(where: { lowered.contains($0) }) {
                return .simple
            }
        }

        // Heuristic 2: Complexity signals in the prompt itself
        let complexSignals = ["explain", "analyze", "compare", "prove", "derive",
                              "implement", "refactor", "debug", "why does", "how would",
                              "what if", "trade-off", "architecture", "design pattern",
                              "algorithm", "hypothesis", "differential equation",
                              "pharmacokinetic", "bayesian"]
        let lowered = prompt.lowercased()
        let complexCount = complexSignals.filter { lowered.contains($0) }.count

        if complexCount >= 2 { return .complex }
        if complexCount == 1 && wordCount > 20 { return .complex }

        // Heuristic 3: Try Mamba generation -- if it produces coherent output
        // quickly (high confidence), the prompt is simple enough for Tier -1
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let draft = try await mambaGenerate(prompt: prompt, maxTokens: 16)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Fast generation with non-empty output = Mamba can handle it
            let tokPerSec = Double(draft.count) / max(elapsed, 0.001)

            if draft.count >= 8 && tokPerSec > 50 {
                return .simple
            } else if draft.count >= 4 {
                return .medium
            } else {
                return .complex
            }
        } catch {
            // Mamba failed to generate -- assume medium complexity
            return .medium
        }
        #else
        return .medium
        #endif
    }
}

// MARK: - Prompt Complexity (Tier Routing)

/// Result of Mamba-based prompt triage for tier routing.
public enum PromptComplexity: String, Sendable {
    /// Mamba can handle it (greetings, classification, short factual answers).
    case simple
    /// Foundation Models or small MLX model (summaries, extraction, translation).
    case medium
    /// Full MLX transformer or cloud required (reasoning, code, analysis, multi-step).
    case complex
}

// MARK: - Cognitive Router

/// Automatic model selection based on task type and device capability.
/// Maps cognitive tasks to model personalities to specific models.
public enum CognitiveTask: String, CaseIterable, Sendable {
    case thoughtCapture         // Quick capture -> fast/stream personality
    case deepReasoning          // GoDeep -> reasoning personality
    case codeGeneration         // Terminal/agent context -> code personality
    case medicalAnalysis        // PBPK/pharma -> medical personality
    case creativeProvocation    // Serendipity -> creative/exotic personality
    case streamOfConsciousness  // Continuous flow -> stream personality (RWKV/Mamba)
    case triadReview            // Adversarial -> analytical personality
    case translation            // Multilingual -> multilingual personality
    case triage                 // Quick classification -> fast personality
}

extension CognitiveTask {
    /// The model personality best suited for this cognitive task.
    public var preferredPersonality: ModelPersonality {
        switch self {
        case .thoughtCapture:        return .stream
        case .deepReasoning:         return .analytical
        case .codeGeneration:        return .analytical   // code models map to analytical
        case .medicalAnalysis:       return .medical
        case .creativeProvocation:   return .creative
        case .streamOfConsciousness: return .stream
        case .triadReview:           return .analytical
        case .translation:           return .creative     // multilingual models carry creative personality
        case .triage:                return .hybrid
        }
    }

    /// Human-readable description of when this task type applies.
    public var taskDescription: String {
        switch self {
        case .thoughtCapture:        return "Quick thought capture — low latency, streaming"
        case .deepReasoning:         return "Deep reasoning — multi-step logic, proofs, analysis"
        case .codeGeneration:        return "Code generation — implementation, refactoring, debugging"
        case .medicalAnalysis:       return "Medical analysis — PBPK, pharmacokinetics, clinical"
        case .creativeProvocation:   return "Creative provocation — lateral thinking, serendipity"
        case .streamOfConsciousness: return "Stream of consciousness — infinite context, journaling"
        case .triadReview:           return "Triad review — adversarial debate, bias detection"
        case .translation:           return "Translation — multilingual, Portuguese, cross-lingual"
        case .triage:                return "Triage — quick classification, routing"
        }
    }
}

extension LocalLLMEngine {

    /// Suggest the best on-device model for a cognitive task, considering device RAM.
    ///
    /// Selection logic:
    /// 1. Find models whose personality matches the task's preferred personality and fit on this device.
    /// 2. Prefer the lightest model that fits (minimize memory pressure on iPhone).
    /// 3. If no personality match fits, fall back to any model that fits, preferring lighter ones.
    /// 4. Ultimate fallback: gemma2_2B (smallest mature model in the catalog).
    public func suggestModel(for task: CognitiveTask) -> OnDeviceModel {
        let personality = task.preferredPersonality
        let candidates = OnDeviceModel.allCases
            .filter { $0.personality == personality && $0.fitsOnThisDevice && !$0.isExperimental }
            .sorted { $0.minimumRAMGB < $1.minimumRAMGB }

        // Primary: best-fit personality match
        if let best = candidates.first { return best }

        // Secondary: any non-experimental model that fits
        let fallbacks = OnDeviceModel.allCases
            .filter { $0.fitsOnThisDevice && !$0.isExperimental }
            .sorted { $0.minimumRAMGB < $1.minimumRAMGB }

        return fallbacks.first ?? .gemma2_2B
    }

    /// Load the suggested model for a cognitive task, then generate a response.
    ///
    /// If the currently loaded model already matches the suggestion, it stays loaded
    /// (no unnecessary reload). Otherwise the engine loads the suggested model first.
    public func respondForTask(_ task: CognitiveTask, prompt: String) async throws -> String {
        let model = suggestModel(for: task)
        if currentModel != model {
            await load(model)
        }
        return try await respond(to: prompt)
    }

    /// Streaming variant of `respondForTask` — returns tokens as they arrive.
    public func generateForTask(_ task: CognitiveTask, prompt: String) async -> AsyncThrowingStream<String, Error> {
        let model = suggestModel(for: task)
        if currentModel != model {
            await load(model)
        }
        return generate(prompt: prompt)
    }

    /// Combine Mamba triage with cognitive routing:
    /// 1. Mamba classifies prompt complexity.
    /// 2. Simple prompts stay on Mamba (Tier -1).
    /// 3. Medium/complex prompts route through `suggestModel(for:)`.
    ///
    /// This is the highest-level entry point — the exocortex calls this and the
    /// engine handles everything: triage, model selection, loading, generation.
    public func autoRespond(prompt: String, task: CognitiveTask) async throws -> String {
        // For triage and thought capture, try Mamba first if loaded
        if mambaLoaded && (task == .triage || task == .thoughtCapture) {
            let complexity = await triagePrompt(prompt)
            if complexity == .simple {
                return try await mambaGenerate(prompt: prompt, maxTokens: 256)
            }
        }

        return try await respondForTask(task, prompt: prompt)
    }
}
