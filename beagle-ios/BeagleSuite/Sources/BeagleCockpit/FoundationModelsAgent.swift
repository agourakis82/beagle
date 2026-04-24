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

    /// Configure tool context with the app's cognitive and physio stores.
    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, visionOS 26, *)
    public func configure(cognitive: CognitiveStore, physio: PhysioStore) {
        ExocortexToolContext.shared.cognitive = cognitive
        ExocortexToolContext.shared.physio = physio
    }
    #endif

    /// Respond to a prompt using Foundation Models with exocortex tool access.
    /// Returns nil if unavailable (caller should fall back to cloud agent).
    ///
    /// Before invoking Foundation Models, checks if the Mamba draft model (Tier -1)
    /// can handle the prompt directly. Simple prompts (greetings, classification,
    /// short factual) are answered at Tier -1 for sub-10ms latency.
    public func respond(to prompt: String) async -> String? {
        // Tier -1 pre-screening: if Mamba is loaded, check prompt complexity
        if LocalLLMEngine.shared.mambaLoaded {
            let complexity = await LocalLLMEngine.shared.triagePrompt(prompt)
            if complexity == .simple {
                if let mambaResult = try? await LocalLLMEngine.shared.mambaGenerate(prompt: prompt) {
                    return mambaResult
                }
            }
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, visionOS 26, *) else { return nil }
        guard isAvailable else { return nil }
        do {
            let session = LanguageModelSession(
                model: .default,
                tools: [SearchMemoryTool(), CaptureThoughtTool(), QueryPhysioTool(), SearchBySomaticStateTool(), SuggestExplorationTool()],
                instructions: """
                You are Beagle, a personal scientific exocortex. You assist a researcher \
                with thought capture, deep exploration, and cognitive awareness. You have \
                access to their recent thoughts, physiological state, and can save new \
                insights. Adapt your depth and tone to their cognitive readiness. Be warm, \
                insightful, and concise.
                """
            )
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            print("[FoundationModelsAgent] respond error: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Warm the neural engine by creating a throwaway session.
    /// Call once at app launch — reduces latency on first real query.
    public func prewarm() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, visionOS 26, *) else { return }
        guard SystemLanguageModel.default.isAvailable else { return }
        _ = LanguageModelSession()
        #endif
    }

    /// Generate exocortex provocations — thought starters based on current context.
    /// Returns a JSON array of objects with title, subtitle, and prompt fields.
    public func generateProvocations(
        projects: [String],
        recentThoughts: [String],
        recentJobs: [(kind: String, status: String)],
        postureCounts: (on: Int, warm: Int, cold: Int)
    ) async -> String? {
        var context = "Current state of my sovereign computing platform:\n"
        context += "- \(postureCounts.on) always-on, \(postureCounts.warm) warm, \(postureCounts.cold) cold projects\n"
        context += "- Projects: \(projects.joined(separator: ", "))\n"

        if !recentJobs.isEmpty {
            let jobLines = recentJobs.prefix(5).map { "\($0.kind): \($0.status)" }
            context += "- Recent jobs: \(jobLines.joined(separator: "; "))\n"
        }

        if !recentThoughts.isEmpty {
            context += "- Recent thoughts:\n"
            for thought in recentThoughts.prefix(3) {
                context += "  - \(thought)\n"
            }
        }

        context += "\nGenerate 3 thought provocations. Each should be a genuine intellectual provocation — a surprising connection, a contrarian hypothesis, or a deep question that would make a researcher stop and think. Not operational tasks. Intellectual sparks.\n"
        context += "\nFormat: Return exactly 3 lines, each with format: TITLE | SUBTITLE | PROMPT\n"
        context += "TITLE: 3-6 words, intriguing\nSUBTITLE: 1 sentence expanding\nPROMPT: the full question to explore"

        return await summarize(context, instructions: """
        You are an intellectual provocateur embedded in a researcher's exocortex.
        Your job is to generate surprising, cross-domain, deep questions that
        provoke genuine insight. Think like a brilliant colleague who reads widely
        and makes unexpected connections. Never suggest tasks or operational work.
        Generate intellectual sparks only. Be specific to the researcher's context.
        """)
    }

    /// One-line operational triage of the current project state.
    public func triageLaneStatus(
        slug: String,
        posture: String,
        habitat: String,
        clusterNodes: Int,
        healthyNodes: Int,
        inferenceStatus: String?,
        modelCount: Int
    ) async -> String? {
        let prompt = """
        Project \(slug) (\(posture)):
        - Habitat: \(habitat)
        - Cluster: \(healthyNodes)/\(clusterNodes) nodes healthy
        - Inference: \(inferenceStatus ?? "unknown"), \(modelCount) models serving
        Provide a one-line operational triage.
        """
        return await summarize(prompt, instructions: """
        You are a sovereign supercomputing operator.
        Give a one-line operational status assessment.
        Be precise and actionable. Use technical language.
        """)
    }
}
