//
//  FoundationModelsAgent.swift
//  BeagleCockpit
//
//  Apple Intelligence Foundation Models integration — tier-0 local agent.
//
//  Runs on-device (neural engine). Used for:
//   - Quick questions when cloud agents unreachable (offline fallback)
//   - Fast summaries of cluster state that don't need deep reasoning
//   - Writing Tools integration (commit messages, PR descriptions)
//
//  Agent tier hierarchy:
//    tier 0: Foundation Models (on-device, offline, free)
//    tier 1: Local SGLang (cluster GPU, fast, free compute)
//    tier 2: Claude Code pod (cluster, deep reasoning, metered)
//    tier 3: External API (Claude/GPT direct, highest capability)
//

import Foundation
import BeagleCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tier-0 local agent backed by Apple's on-device Foundation Models.
@MainActor
public final class FoundationModelsAgent {
    public static let shared = FoundationModelsAgent()

    private init() {}

    /// Whether Apple Intelligence / Foundation Models are available on this device.
    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Quick on-device summary of a piece of text.
    /// Returns nil if unavailable (caller should fall back to cloud agent).
    public func summarize(_ input: String, instructions: String? = nil) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, visionOS 26, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        do {
            let session = LanguageModelSession(
                instructions: instructions ?? """
                You are a concise assistant for a supercomputing control surface.
                Summarize technical state in 1-2 sentences with precise terminology.
                """
            )
            let response = try await session.respond(to: input)
            return response.content
        } catch {
            print("[FoundationModels] failed: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Polish a commit message or PR description via Writing Tools semantics.
    public func polishCommitMessage(_ draft: String) async -> String? {
        await summarize(draft, instructions: """
        Rewrite this git commit message to be clear, present-tense, and concise.
        Use conventional commits format if appropriate. Return only the polished message.
        """)
    }

    /// Classify a cluster status message by urgency (quick local routing).
    public func classifyUrgency(_ message: String) async -> String? {
        await summarize(message, instructions: """
        Classify this cluster event as one of: NOMINAL, DEGRADED, CRITICAL.
        Respond with only the single word.
        """)
    }
}
