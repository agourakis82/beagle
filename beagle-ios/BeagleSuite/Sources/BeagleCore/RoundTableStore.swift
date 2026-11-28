//
//  RoundTableStore.swift
//  BeagleCore
//
//  Observable store for exotic multi-model Round Table ("Mesa-Redonda") debates.
//  Orchestrates multiple epistemic voices (Consciência, Paradoxo, Quântico, Realidade/PBPK, etc.).
//  Tries the Beagle cluster endpoint first and seamlessly falls back to parallel Nov 2026
//  Direct Brain execution (GPT-6.2 Astra, GPT-Rosalind, GPT-6.2 Sol & Claude Opus 4.8)
//  computing constructive/destructive interference, PCI score (Φ), and a pt-BR synthesis.
//

import Foundation
import Observation

// MARK: - Available voices

public enum RoundTableVoiceId: String, CaseIterable, Identifiable, Sendable {
    case consciousness = "consciousness"
    case mirror        = "mirror"
    case paradox       = "paradox"
    case void          = "void"
    case reality       = "reality"
    case noetic        = "noetic"
    case quantum       = "quantum"
    case fractal       = "fractal"
    case cosmo         = "cosmo"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .consciousness: return "Consciência"
        case .mirror:        return "Espelho"
        case .paradox:       return "Paradoxo"
        case .void:          return "Vazio"
        case .reality:       return "Realidade & PBPK"
        case .noetic:        return "Noético"
        case .quantum:       return "Quântico"
        case .fractal:       return "Fractal"
        case .cosmo:         return "Cosmo"
        }
    }

    public var icon: String {
        switch self {
        case .consciousness: return "brain"
        case .mirror:        return "eye"
        case .paradox:       return "infinity"
        case .void:          return "circle.dotted"
        case .reality:       return "cross.vial.fill"
        case .noetic:        return "network"
        case .quantum:       return "waveform"
        case .fractal:       return "leaf"
        case .cosmo:         return "globe"
        }
    }

    public var perspective: String {
        switch self {
        case .consciousness: return "Auto-observação, fenomenologia clínica, qualia e teoria da mente"
        case .mirror:        return "Metacrítica autorreflexiva, pontos cegos e pressupostos ocultos"
        case .paradox:       return "Lógica autorreferencial, incompletude de Gödel e tensões dialéticas"
        case .void:          return "Dissolução de fronteiras ontológicas, apofatismo e substrato limite"
        case .reality:       return "Protocolos clínicos/experimentais concretos, farmacologia PBPK e execução"
        case .noetic:        return "Emergência distribuída, exocórtex coletivo e acoplamento cérebro-máquina"
        case .quantum:       return "Superposição de hipóteses, interferência de fases e colapso decisório"
        case .fractal:       return "Invariância de escala, fisiologia fractal, cinética não-linear e HRV 1/f"
        case .cosmo:         return "Termodinâmica fora do equilíbrio, heliobiologia e leis físicas"
        }
    }

    /// Optimal Nov 2026 frontier engine for this epistemic lens when running on Direct Brain.
    nonisolated var preferredOpenAIModel: String {
        switch self {
        case .reality, .fractal:
            return OpenAIModelCatalog.lifeSciencesModel // gpt-rosalind
        case .mirror, .void, .noetic:
            return "gpt-6.2-sol"
        case .consciousness, .paradox, .quantum, .cosmo:
            return OpenAIModelCatalog.defaultFlagshipModel // gpt-6.2-astra
        }
    }

    nonisolated var prefersAnthropicIfAvailable: Bool {
        switch self {
        case .mirror, .void, .noetic:
            return true
        default:
            return false
        }
    }
}

// MARK: - Store

@Observable
@MainActor
public final class RoundTableStore {

    public var selectedVoices: Set<RoundTableVoiceId> = [.consciousness, .paradox, .reality, .quantum]
    public var enableLiveResearchTools = true
    public private(set) var isRunning = false
    public private(set) var result: RoundTableResult?
    public private(set) var error: String?

    private let client: BeagleClient
    private let directBrain: DirectBrainClient

    public init(
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared
    ) {
        self.client = client
        self.directBrain = directBrain
    }

    /// Run a Round Table debate with the selected voices.
    public func debate(prompt: String) async {
        let orderedVoices = RoundTableVoiceId.allCases.filter { selectedVoices.contains($0) }
        guard !orderedVoices.isEmpty else {
            error = "Selecione ao menos uma voz para a Mesa-Redonda."
            return
        }

        isRunning = true
        error = nil
        result = nil

        let voiceIds = orderedVoices.map(\.rawValue)
        let response = await client.roundTable(prompt: prompt, voices: voiceIds)

        if let r = response.value, !(r.voices ?? []).isEmpty {
            result = r
            isRunning = false
            return
        }

        // Seamless Direct Brain parallel multi-model Mesa-Redonda fallback (5G / Wi-Fi / offline cluster)
        if DirectBrainCredentials.hasOpenAI || DirectBrainCredentials.hasAnthropic {
            do {
                let directResult = try await Self.runDirectRoundTable(
                    prompt: prompt,
                    voices: orderedVoices,
                    directBrain: directBrain,
                    useLiveTools: enableLiveResearchTools
                )
                result = directResult
            } catch {
                self.error = error.localizedDescription
            }
        } else {
            error = response.error ?? "Mesa-Redonda indisponível (cluster offline e chaves diretas ausentes)."
        }

        isRunning = false
    }

    // MARK: - Direct Brain Parallel Mesa-Redonda

    private nonisolated static func runDirectRoundTable(
        prompt: String,
        voices: [RoundTableVoiceId],
        directBrain: DirectBrainClient,
        useLiveTools: Bool
    ) async throws -> RoundTableResult {
        var groundingParts: [String] = []
        if useLiveTools {
            async let refPrefetch = ScienceAndWebBridge.shared.prefetchContextForPrompt(prompt, maxCharsPerItem: 5_000)
            async let memoryRecall = directBrain.recallRelevantMemory(for: prompt, projectSlug: nil)
            if let pref = await refPrefetch, !pref.contextBlock.isEmpty {
                groundingParts.append(pref.contextBlock)
            }
            if let mem = await memoryRecall, !mem.isEmpty {
                groundingParts.append("## Memórias do Exocórtex\n\(mem)")
            }
        }
        let sharedGrounding = groundingParts.isEmpty ? nil : groundingParts.joined(separator: "\n\n")

        var indexedVoices: [(Int, RoundTableVoice)] = []
        var firstError: Error?

        await withTaskGroup(of: (Int, Result<RoundTableVoice, Error>).self) { group in
            for (idx, voice) in voices.enumerated() {
                group.addTask { [directBrain] in
                    do {
                        let rendered = try await Self.executeSingleVoice(
                            voice,
                            prompt: prompt,
                            directBrain: directBrain,
                            sharedGrounding: sharedGrounding,
                            useLiveTools: useLiveTools
                        )
                        return (idx, .success(rendered))
                    } catch {
                        return (idx, .failure(error))
                    }
                }
            }

            for await (idx, outcome) in group {
                switch outcome {
                case .success(let v):
                    indexedVoices.append((idx, v))
                case .failure(let err):
                    if firstError == nil { firstError = err }
                }
            }
        }

        let completedVoices = indexedVoices
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        guard !completedVoices.isEmpty else {
            throw firstError ?? NSError(
                domain: "RoundTableStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Nenhuma voz da Mesa-Redonda retornou resposta."]
            )
        }

        let (interference, pciScore) = computeInterferenceAndPCI(voices: completedVoices)
        let synthesis = await generateDebateSynthesis(
            prompt: prompt,
            voices: completedVoices,
            interference: interference,
            pciScore: pciScore,
            directBrain: directBrain,
            sharedGrounding: sharedGrounding
        )

        return RoundTableResult(
            voices: completedVoices,
            interference: interference,
            pciScore: pciScore,
            synthesis: synthesis
        )
    }

    private nonisolated static func executeSingleVoice(
        _ voice: RoundTableVoiceId,
        prompt: String,
        directBrain: DirectBrainClient,
        sharedGrounding: String?,
        useLiveTools: Bool
    ) async throws -> RoundTableVoice {
        let devPrompt = """
        Você é a voz **\(voice.displayName)** na Mesa-Redonda epistêmica do Beagle com Demetrios Chiuratto Agourakis.
        Sua lente exclusiva: \(voice.perspective).
        Responda SEMPRE em português brasileiro denso, autoral e sem clichês (1 parágrafo incisivo de 4 a 6 frases), defendendo radicalmente o que apenas a sua lente enxerga neste problema — incluindo mecanismos formais/empíricos concretos e onde as leituras convencionais falham.
        """

        if voice.prefersAnthropicIfAvailable && DirectBrainCredentials.hasAnthropic {
            let fullSys = [devPrompt, sharedGrounding].compactMap { $0 }.joined(separator: "\n\n")
            let res = try await directBrain.streamAnthropic(
                model: "claude-opus-4-8",
                systemPrompt: fullSys,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onToken: { _ in }
            )
            return RoundTableVoice(
                name: "\(voice.displayName) · \(res.model)",
                perspective: voice.perspective,
                content: res.content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard DirectBrainCredentials.hasOpenAI else {
            let fullSys = [devPrompt, sharedGrounding].compactMap { $0 }.joined(separator: "\n\n")
            let res = try await directBrain.streamAnthropic(
                model: "claude-opus-4-8",
                systemPrompt: fullSys,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onToken: { _ in }
            )
            return RoundTableVoice(
                name: "\(voice.displayName) · \(res.model)",
                perspective: voice.perspective,
                content: res.content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let preferredModel = voice.preferredOpenAIModel
        let attachTools = useLiveTools && (voice == .reality || voice == .cosmo)
        do {
            let res = try await directBrain.streamOpenAI(
                model: preferredModel,
                systemPrompt: devPrompt,
                developerPrefix: devPrompt,
                turnInstructions: sharedGrounding,
                reasoningEffort: "high",
                enableNativeWebSearch: attachTools,
                enableToolSearch: attachTools,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { _ in }
            )
            return RoundTableVoice(
                name: "\(voice.displayName) · \(res.model)",
                perspective: voice.perspective,
                content: res.content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch let nsError as NSError where preferredModel == OpenAIModelCatalog.lifeSciencesModel && (nsError.code == 403 || nsError.code == 404) {
            let fallback = try await directBrain.streamOpenAI(
                model: OpenAIModelCatalog.defaultFlagshipModel,
                systemPrompt: devPrompt,
                developerPrefix: devPrompt,
                turnInstructions: sharedGrounding,
                reasoningEffort: "high",
                enableNativeWebSearch: attachTools,
                enableToolSearch: attachTools,
                turns: [DirectBrainTurn(role: "user", content: prompt)],
                projectSlug: nil,
                onStatus: { _ in },
                onToken: { _ in }
            )
            return RoundTableVoice(
                name: "\(voice.displayName) · \(fallback.model)",
                perspective: voice.perspective,
                content: fallback.content.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private nonisolated static func computeInterferenceAndPCI(
        voices: [RoundTableVoice]
    ) -> (RoundTableInterference, Double) {
        guard voices.count >= 2 else {
            return (RoundTableInterference(constructive: [], destructive: [], emergentInsights: []), 0.52)
        }

        var constructive: [String] = []
        var destructive: [String] = []
        var emergent: [String] = []
        var pairSimilarities: [Double] = []

        for i in 0..<voices.count {
            for j in (i + 1)..<voices.count {
                let sim = lexicalOverlap(voices[i].content, voices[j].content)
                pairSimilarities.append(sim)
                let shortA = voices[i].name.components(separatedBy: " · ").first ?? voices[i].name
                let shortB = voices[j].name.components(separatedBy: " · ").first ?? voices[j].name
                if sim >= 0.16 {
                    constructive.append("Ressonância estrutural entre \(shortA) e \(shortB)")
                } else {
                    destructive.append("Ortogonalidade produtiva entre \(shortA) e \(shortB)")
                    emergent.append("Síntese de fronteira exigida no eixo \(shortA) ↔ \(shortB)")
                }
            }
        }

        // Perturbational Complexity Index proxy (Φ): peaks when voices combine integration (non-zero overlap)
        // with high differentiation (not redundant copies).
        let meanSim = pairSimilarities.reduce(0, +) / Double(max(1, pairSimilarities.count))
        let differentiation = max(0.0, 1.0 - meanSim)
        let integration = min(1.0, meanSim * 3.2 + 0.35)
        let voiceBonus = min(0.14, Double(voices.count - 1) * 0.035)
        let rawPCI = (0.48 + 0.38 * differentiation * integration + voiceBonus)
        let clampedPCI = min(0.96, max(0.42, (rawPCI * 100).rounded() / 100))

        return (
            RoundTableInterference(
                constructive: constructive,
                destructive: destructive,
                emergentInsights: Array(emergent.prefix(4))
            ),
            clampedPCI
        )
    }

    private nonisolated static func lexicalOverlap(_ a: String, _ b: String) -> Double {
        let tokensA = Set(
            a.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 }
        )
        let tokensB = Set(
            b.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 4 }
        )
        let union = tokensA.union(tokensB).count
        guard union > 0 else { return 0 }
        return Double(tokensA.intersection(tokensB).count) / Double(union)
    }

    private nonisolated static func generateDebateSynthesis(
        prompt: String,
        voices: [RoundTableVoice],
        interference: RoundTableInterference,
        pciScore: Double,
        directBrain: DirectBrainClient,
        sharedGrounding: String?
    ) async -> String? {
        let transcript = voices
            .map { "[\($0.name)]: \($0.content)" }
            .joined(separator: "\n\n")

        let sysPrompt = """
        Você é o Moderador de Interferência da Mesa-Redonda do Beagle (Φ = \(String(format: "%.2f", pciScore))).
        Responda SEMPRE em português brasileiro denso, direto e autoral (1 a 2 parágrafos curtos):
        1) Identifique a convergência estrutural real entre as vozes;
        2) Explicite o conflito/paradoxo mais fértil que emergiu entre elas;
        3) Formule a síntese superior acionável para Demetrios.
        """

        let userPrompt = """
        Questão debatida: "\(prompt)"

        Vozes em paralelo:
        \(transcript)
        """

        if DirectBrainCredentials.hasOpenAI,
           let res = try? await directBrain.streamOpenAI(
               model: OpenAIModelCatalog.defaultFlagshipModel,
               systemPrompt: sysPrompt,
               developerPrefix: sysPrompt,
               turnInstructions: sharedGrounding,
               reasoningEffort: "high",
               enableNativeWebSearch: false,
               enableToolSearch: false,
               turns: [DirectBrainTurn(role: "user", content: userPrompt)],
               projectSlug: nil,
               onStatus: { _ in },
               onToken: { _ in }
           ),
           !res.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return res.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if DirectBrainCredentials.hasAnthropic,
           let res = try? await directBrain.streamAnthropic(
               model: "claude-opus-4-8",
               systemPrompt: sysPrompt,
               turns: [DirectBrainTurn(role: "user", content: userPrompt)],
               projectSlug: nil,
               onToken: { _ in }
           ),
           !res.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return res.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return voices.first?.content
    }

    /// Convert result into ChatMessages for inline display in conversation.
    public func resultAsMessages() -> [ChatMessage] {
        guard let result else { return [] }
        var messages: [ChatMessage] = []

        for voice in result.voices ?? [] {
            messages.append(ChatMessage(
                role: .assistant,
                content: voice.content,
                source: "round-table",
                voiceName: voice.name
            ))
        }

        if let synthesis = result.synthesis {
            let pciLabel = result.pciScore.map { String(format: " (Φ %.2f)", $0) } ?? ""
            messages.append(ChatMessage(
                role: .assistant,
                content: synthesis,
                source: "round-table-synthesis",
                voiceName: "Síntese\(pciLabel)"
            ))
        }

        return messages
    }

    public func reset() {
        result = nil
        error = nil
        isRunning = false
    }
}
