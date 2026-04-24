//
//  SpatialTriadView.swift
//  BeagleVisionOS
//
//  Spatial adversarial review with embodied AI agents.
//
//  ATHENA (accuracy)  — front-left  (10 o'clock), blue
//  HERMES (clarity)   — front-right (2 o'clock),  gold
//  ARGOS  (rigor)     — front-center-up,           red
//  JUDGE              — above all three,            silver
//
//  The three agents surround the user as glass orbs in mixed-immersion
//  space, each delivering their opinion in sequence. The Judge appears
//  above once all three have spoken.
//
//  Paper reference: "Spatial adversarial review with embodied AI agents"
//

#if os(visionOS)
import SwiftUI
import RealityKit
import BeagleCore

// MARK: - SpatialTriadView (Immersive Space)

struct SpatialTriadView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var draftText = ""
    @State private var result: TriadResult?
    @State private var revealedAgents: Set<String> = []
    @State private var showJudge = false

    // Thinking-phase messages per agent, cycled during review
    private static let thinkingMessages: [String: [String]] = [
        "ATHENA": ["Verifying factual accuracy...", "Cross-referencing sources...", "Checking citations..."],
        "HERMES": ["Reviewing prose clarity...", "Analyzing structure...", "Evaluating persuasiveness..."],
        "ARGOS":  ["Scanning for bias...", "Testing logical coherence...", "Checking edge cases..."],
    ]

    var body: some View {
        ZStack {
            // --- Agent orbs positioned around the user ---

            if cognitive.isReviewingTriad || result != nil {
                // ATHENA — front-left (10 o'clock)
                agentOrb(
                    name: "ATHENA",
                    icon: "scope",
                    color: .blue,
                    offset: CGPoint(x: -320, y: -60)
                )

                // HERMES — front-right (2 o'clock)
                agentOrb(
                    name: "HERMES",
                    icon: "text.alignleft",
                    color: .yellow,
                    offset: CGPoint(x: 320, y: -60)
                )

                // ARGOS — front-center, elevated
                agentOrb(
                    name: "ARGOS",
                    icon: "shield.lefthalf.filled",
                    color: .red,
                    offset: CGPoint(x: 0, y: -220)
                )
            }

            // --- Judge verdict — appears above once all agents resolved ---
            if showJudge, let result {
                judgeVerdict(result)
                    .offset(y: -380)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // --- Input/control ornament anchored to bottom ---
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(spacing: 16) {
                if result == nil {
                    Text("Triad Spatial Debate")
                        .font(BeagleTheme.displayFont(size: 22, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Text("Submit a draft for adversarial review by three embodied agents")
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    TextField("Draft to review...", text: $draftText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...8)

                    Button {
                        Task { await submitForReview() }
                    } label: {
                        Label("Submit for Triad Review", systemImage: "sparkles")
                            .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BeagleTheme.truthObserved)
                    .disabled(
                        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || cognitive.isReviewingTriad
                    )
                }

                if cognitive.isReviewingTriad {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Agents deliberating...")
                            .font(BeagleTheme.uiFont(size: 14))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }

                if result != nil {
                    Button {
                        resetState()
                    } label: {
                        Label("New Review", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(width: 500)
            .glassBackgroundEffect()
        }

        // TODO: Add SpatialAudioExperience per agent position
        // ATHENA speaks from front-left  — azimuth ~-30deg
        // HERMES speaks from front-right — azimuth ~+30deg
        // ARGOS speaks from above        — elevation ~+30deg
        // JUDGE speaks from directly above — elevation ~+60deg
        // Requires AVFAudio SpatialAudioExperience API
        // Each agent would have an AudioSource component positioned at their
        // respective SIMD3 coordinate, with spatialBlend = 1.0 for full 3D.
    }

    // MARK: - Agent Orb

    @ViewBuilder
    private func agentOrb(
        name: String,
        icon: String,
        color: Color,
        offset: CGPoint
    ) -> some View {
        let opinion = opinionFor(name)
        let isRevealed = revealedAgents.contains(name)

        VStack(spacing: 10) {
            // Agent icon with pulse during thinking
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: cognitive.isReviewingTriad && !isRevealed)

            Text(name)
                .font(BeagleTheme.displayFont(size: 18, weight: .semibold))
                .foregroundStyle(BeagleTheme.textPrimary)

            // Opinion text or thinking phase
            if let opinion, isRevealed {
                if let text = opinion.opinion {
                    Text(text)
                        .font(BeagleTheme.uiFont(size: 13))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(8)
                        .frame(maxWidth: 280)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                if let conf = opinion.confidence {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", conf))
                            .font(BeagleTheme.displayFont(size: 28, weight: .bold))
                        Text("/ 10")
                            .font(BeagleTheme.dataFont(size: 14))
                    }
                    .foregroundStyle(color)
                }
            } else if cognitive.isReviewingTriad {
                AgentThinkingLabel(
                    messages: Self.thinkingMessages[name] ?? ["Thinking..."],
                    color: color
                )
            }
        }
        .padding(24)
        .frame(minWidth: 200)
        .glassBackgroundEffect()
        .opacity(isRevealed || cognitive.isReviewingTriad ? 1 : 0.4)
        .scaleEffect(isRevealed ? 1.0 : 0.92)
        .offset(x: offset.x, y: offset.y)
        .animation(.spring(duration: 0.6, bounce: 0.3), value: isRevealed)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Judge Verdict

    @ViewBuilder
    private func judgeVerdict(_ triad: TriadResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "scalemass")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.9))

            Text("JUDGE")
                .font(BeagleTheme.displayFont(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            if let judgeOpinion = triad.judge {
                if let text = judgeOpinion.opinion {
                    Text(text)
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(6)
                        .frame(maxWidth: 340)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                if let conf = judgeOpinion.confidence {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", conf))
                            .font(BeagleTheme.displayFont(size: 32, weight: .bold))
                        Text("/ 10")
                            .font(BeagleTheme.dataFont(size: 16))
                    }
                    .foregroundStyle(.white)
                }
            }

            if let consensus = triad.consensus {
                HStack(spacing: 6) {
                    Image(systemName: consensus.localizedCaseInsensitiveContains("consensus")
                          ? "checkmark.seal.fill"
                          : "exclamationmark.triangle.fill")
                    Text(consensus)
                        .font(BeagleTheme.uiFont(size: 14, weight: .medium))
                }
                .foregroundStyle(consensus.localizedCaseInsensitiveContains("consensus")
                                 ? BeagleTheme.truthObserved
                                 : BeagleTheme.postureWarm)
            }
        }
        .padding(28)
        .glassBackgroundEffect()
    }

    // MARK: - Helpers

    private func opinionFor(_ name: String) -> TriadAgentOpinion? {
        guard let result else { return nil }
        switch name {
        case "ATHENA": return result.athena
        case "HERMES": return result.hermes
        case "ARGOS":  return result.argos
        case "JUDGE":  return result.judge
        default:       return nil
        }
    }

    private func submitForReview() async {
        result = nil
        revealedAgents = []
        showJudge = false

        let triad = await cognitive.submitForTriadReview(draft: draftText)
        result = triad

        // Reveal agents one at a time with staggered animation
        if triad != nil {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation { revealedAgents.insert("ATHENA") }

            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { revealedAgents.insert("HERMES") }

            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { revealedAgents.insert("ARGOS") }

            // Judge appears last, above the triad
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.spring(duration: 0.8, bounce: 0.2)) {
                showJudge = true
            }
        }
    }

    private func resetState() {
        withAnimation {
            result = nil
            revealedAgents = []
            showJudge = false
            draftText = ""
        }
    }
}

// MARK: - Agent Thinking Label (cycles through messages)

private struct AgentThinkingLabel: View {
    let messages: [String]
    let color: Color
    @State private var index = 0

    var body: some View {
        Text(messages[index % messages.count])
            .font(BeagleTheme.uiFont(size: 12))
            .foregroundStyle(color.opacity(0.8))
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.3), value: index)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    index += 1
                }
            }
    }
}

// MARK: - Preview

#Preview(windowStyle: .automatic) {
    SpatialTriadView()
        .environment(CognitiveStore())
}
#endif
