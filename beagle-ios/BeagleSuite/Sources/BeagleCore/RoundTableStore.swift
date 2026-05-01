//
//  RoundTableStore.swift
//  BeagleCore
//
//  Observable store for exotic model Round Table debates.
//  Orchestrates multiple reasoning voices (consciousness, paradox, void, quantum, etc.)
//  Each voice runs in parallel on the backend; results include interference + PCI score.
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
        case .consciousness: return "Consciousness"
        case .mirror:        return "Mirror"
        case .paradox:       return "Paradox"
        case .void:          return "Void"
        case .reality:       return "Reality"
        case .noetic:        return "Noetic"
        case .quantum:       return "Quantum"
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
        case .reality:       return "cube.transparent"
        case .noetic:        return "network"
        case .quantum:       return "waveform"
        case .fractal:       return "leaf"
        case .cosmo:         return "globe"
        }
    }

    public var perspective: String {
        switch self {
        case .consciousness: return "Self-observation, qualia, theory of own mind"
        case .mirror:        return "Auto-reflexive meta-paper generation"
        case .paradox:       return "Self-referential logic, Gödel incompleteness"
        case .void:          return "Trans-ontological navigation, boundary dissolution"
        case .reality:       return "Reality fabrication, protocol generation"
        case .noetic:        return "Collective noosphere, distributed emergence"
        case .quantum:       return "Superposition, interference, collapse"
        case .fractal:       return "Recursive self-similar patterns"
        case .cosmo:         return "Cosmological alignment, physical law validation"
        }
    }
}

// MARK: - Store

@Observable
@MainActor
public final class RoundTableStore {

    public var selectedVoices: Set<RoundTableVoiceId> = [.consciousness, .paradox, .quantum]
    public private(set) var isRunning = false
    public private(set) var result: RoundTableResult?
    public private(set) var error: String?

    private let client: BeagleClient

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    /// Run a Round Table debate with the selected voices.
    public func debate(prompt: String) async {
        guard !selectedVoices.isEmpty else {
            error = "Select at least one voice."
            return
        }

        isRunning = true
        error = nil
        result = nil

        let voiceIds = selectedVoices.map(\.rawValue)
        let response = await client.roundTable(prompt: prompt, voices: voiceIds)

        if let r = response.value {
            result = r
        } else {
            error = response.error ?? "Round Table failed."
        }
        isRunning = false
    }

    /// Convert result into ChatMessages for inline display in conversation.
    public func resultAsMessages() -> [ChatMessage] {
        guard let result else { return [] }
        var messages: [ChatMessage] = []

        // Voice responses
        for voice in result.voices ?? [] {
            messages.append(ChatMessage(
                role: .assistant,
                content: voice.content,
                source: "round-table",
                voiceName: voice.name
            ))
        }

        // Synthesis
        if let synthesis = result.synthesis {
            let pciLabel = result.pciScore.map { String(format: " (Φ %.2f)", $0) } ?? ""
            messages.append(ChatMessage(
                role: .assistant,
                content: synthesis,
                source: "round-table-synthesis",
                voiceName: "Synthesis\(pciLabel)"
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
