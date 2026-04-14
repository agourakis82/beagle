//
//  TriadReviewView.swift
//  BeagleCockpit
//
//  Adversarial review: ATHENA (accuracy) + HERMES (writing) + ARGOS (rigor) + Judge.
//
//  Premium patterns:
//   - 4 agent slots visible during review (each with rotating thinking messages)
//   - Agents resolve one at a time with spring animation + haptic
//   - Real feedback UI with star rating
//   - Share/export for review results
//   - Elevated opinion cards (.raised, not .flush)
//

import SwiftUI
import BeagleCore
import Charts

struct TriadReviewView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var draftText = ""
    @State private var result: TriadResult?
    @State private var reviewPhase = ""
    @State private var reviewPhaseIndex = 0
    @State private var clarityRating: Int = 0
    @State private var adequacyRating: Int = 0
    @State private var feedbackNotes = ""
    @State private var feedbackSubmitted = false
    @FocusState private var draftFocused: Bool

    private static let agentPhases: [(agent: String, messages: [String])] = [
        ("ATHENA", ["Verifying factual accuracy...", "Cross-referencing sources...", "Checking citations..."]),
        ("HERMES", ["Reviewing prose clarity...", "Analyzing structure...", "Evaluating persuasiveness..."]),
        ("ARGOS",  ["Scanning for bias...", "Testing logical coherence...", "Checking edge cases..."]),
        ("JUDGE",  ["Weighing agent scores...", "Evaluating consensus...", "Rendering verdict..."]),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    inputSection
                    if cognitive.isReviewingTriad { agentProgressSection }
                    if let result { resultsSection(result) }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
                .padding(.bottom, BeagleSpacing.jumbo)
            }
            .background { HealthPulseGradient(truth: result != nil ? .observed : .declared) }
            .navigationTitle("Triad Review")
            .toolbar {
                if result != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: exportText, subject: Text("Triad Review")) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        GlassPanel(elevation: .raised) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Submit draft for adversarial review")

                TextEditor(text: $draftText)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 300)
                    .focused($draftFocused)

                HStack {
                    Text("\(draftText.count) chars")
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    Button {
                        Task { await submitForReview() }
                    } label: {
                        Label("Review", systemImage: "sparkles")
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cognitive.isReviewingTriad)
                }
            }
        }
    }

    // MARK: - Agent Progress (per-agent thinking, not a single spinner)

    private var agentProgressSection: some View {
        VStack(spacing: BeagleSpacing.sm) {
            ForEach(Array(Self.agentPhases.enumerated()), id: \.element.agent) { index, entry in
                AgentThinkingSlot(
                    agentName: entry.agent,
                    messages: entry.messages,
                    color: agentColor(entry.agent),
                    delay: Double(index) * 0.15
                )
            }
        }
        .transition(.asymmetric(insertion: .push(from: .bottom).combined(with: .opacity), removal: .opacity))
    }

    // MARK: - Results

    private func resultsSection(_ triad: TriadResult) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            // Scores chart
            if let scores = triad.scores {
                GlassPanel(elevation: .floating, truth: .observed) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        sectionLabel("Scores")

                        Chart {
                            if let v = scores.athena {
                                BarMark(x: .value("Score", v), y: .value("Agent", "ATHENA"))
                                    .foregroundStyle(BeagleTheme.truthObserved.gradient)
                            }
                            if let v = scores.hermes {
                                BarMark(x: .value("Score", v), y: .value("Agent", "HERMES"))
                                    .foregroundStyle(BeagleTheme.truthRemembered.gradient)
                            }
                            if let v = scores.argos {
                                BarMark(x: .value("Score", v), y: .value("Agent", "ARGOS"))
                                    .foregroundStyle(BeagleTheme.postureWarm.gradient)
                            }
                            if let v = scores.judge {
                                BarMark(x: .value("Score", v), y: .value("Agent", "JUDGE"))
                                    .foregroundStyle(BeagleTheme.textData.gradient)
                            }
                        }
                        .chartXScale(domain: 0...10)
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                    .font(BeagleFont.data.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.white.opacity(0.06))
                                AxisValueLabel()
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                        .frame(height: 140)

                        if let verdict = triad.consensus {
                            HStack(spacing: BeagleSpacing.xs) {
                                Image(systemName: verdict.localizedCaseInsensitiveContains("consensus") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(verdict.localizedCaseInsensitiveContains("consensus") ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                                Text(verdict)
                                    .font(BeagleFont.dataProminent.font)
                                    .foregroundStyle(verdict.localizedCaseInsensitiveContains("consensus") ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                            }
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: result != nil)
            }

            // Agent opinions (elevated)
            ForEach(agentOpinions(triad), id: \.0) { name, opinion in
                if let opinion {
                    agentOpinionCard(name: name, opinion: opinion)
                }
            }

            // Real feedback
            feedbackSection
        }
    }

    private func agentOpinionCard(name: String, opinion: TriadAgentOpinion) -> some View {
        GlassPanel(elevation: .raised, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack {
                    Image(systemName: agentIcon(name))
                        .font(.system(size: 14))
                        .foregroundStyle(agentColor(name))
                    Text(name)
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if let conf = opinion.confidence {
                        HStack(spacing: BeagleSpacing.xxs) {
                            Text(String(format: "%.1f", conf))
                                .font(BeagleFont.dataProminent.font)
                                .fontWeight(.bold)
                            Text("/ 10")
                                .font(BeagleFont.dataSmall.font)
                        }
                        .foregroundStyle(agentColor(name))
                    }
                }
                if let text = opinion.opinion {
                    Text(text)
                        .font(BeagleFont.subheadline.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }
            }
        }
    }

    // MARK: - Feedback (real UI with ratings)

    private var feedbackSection: some View {
        GlassPanel(elevation: .raised) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Your Feedback")

                if feedbackSubmitted {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("Feedback recorded — training LoRA")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                } else {
                    // Clarity rating
                    ratingRow("Clarity", rating: $clarityRating, color: BeagleTheme.truthObserved)
                    // Adequacy rating
                    ratingRow("Adequacy", rating: $adequacyRating, color: BeagleTheme.truthRemembered)

                    HStack(spacing: BeagleSpacing.sm) {
                        Button {
                            Task {
                                feedbackSubmitted = await cognitive.submitFeedback(
                                    runId: "triad-\(Date.now.timeIntervalSince1970)",
                                    clarity: max(1, clarityRating),
                                    adequacy: max(1, adequacyRating),
                                    notes: feedbackNotes.isEmpty ? nil : feedbackNotes
                                )
                            }
                        } label: {
                            Label("Submit", systemImage: "hand.thumbsup.fill")
                        }
                        .buttonStyle(PrimaryButton())
                        .disabled(clarityRating == 0 || adequacyRating == 0)
                        .sensoryFeedback(.success, trigger: feedbackSubmitted)

                        Button {
                            result = nil
                            feedbackSubmitted = false
                            clarityRating = 0
                            adequacyRating = 0
                            draftFocused = true
                        } label: {
                            Label("Revise", systemImage: "pencil")
                        }
                        .buttonStyle(SecondaryButton())
                    }
                }
            }
        }
    }

    private func ratingRow(_ label: String, rating: Binding<Int>, color: Color) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Text(label)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .frame(width: 70, alignment: .leading)

            ForEach(1...10, id: \.self) { value in
                Button {
                    withAnimation(BeagleMotion.fast) { rating.wrappedValue = value }
                } label: {
                    Circle()
                        .fill(value <= rating.wrappedValue ? color : Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(
                                value <= rating.wrappedValue ? color.opacity(0.4) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: rating.wrappedValue)
            }

            Text("\(rating.wrappedValue)")
                .font(BeagleFont.dataProminent.font)
                .foregroundStyle(rating.wrappedValue > 0 ? color : BeagleTheme.textTertiary)
                .frame(width: 24)
        }
    }

    // MARK: - Helpers

    private func submitForReview() async {
        draftFocused = false
        result = nil
        feedbackSubmitted = false
        let triad = await cognitive.submitForTriadReview(draft: draftText)
        withAnimation(BeagleMotion.slow) { result = triad }
    }

    private func agentOpinions(_ t: TriadResult) -> [(String, TriadAgentOpinion?)] {
        [("ATHENA", t.athena), ("HERMES", t.hermes), ("ARGOS", t.argos), ("JUDGE", t.judge)]
    }

    private func agentColor(_ name: String) -> Color {
        switch name {
        case "ATHENA": return BeagleTheme.truthObserved
        case "HERMES": return BeagleTheme.truthRemembered
        case "ARGOS":  return BeagleTheme.postureWarm
        case "JUDGE":  return BeagleTheme.textData
        default:       return BeagleTheme.textSecondary
        }
    }

    private func agentIcon(_ name: String) -> String {
        switch name {
        case "ATHENA": return "scope"
        case "HERMES": return "text.alignleft"
        case "ARGOS":  return "shield.lefthalf.filled"
        case "JUDGE":  return "scalemass"
        default:       return "person"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .fontWeight(.medium)
            .foregroundStyle(BeagleTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var exportText: String {
        guard let r = result else { return "" }
        var lines = ["# Triad Review", ""]
        for (name, opinion) in agentOpinions(r) {
            if let o = opinion {
                lines.append("## \(name)")
                if let conf = o.confidence { lines.append("Score: \(String(format: "%.1f", conf))/10") }
                if let text = o.opinion { lines.append(text) }
                lines.append("")
            }
        }
        if let verdict = r.consensus { lines.append("**Verdict:** \(verdict)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Agent Thinking Slot

/// Shows one agent's thinking progress during a Triad review.
private struct AgentThinkingSlot: View {
    let agentName: String
    let messages: [String]
    let color: Color
    var delay: Double = 0
    @State private var currentMessage = ""
    @State private var messageIndex = 0
    @State private var appeared = false

    var body: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: iconForAgent)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: true)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(agentName)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text(currentMessage.isEmpty ? messages[0] : currentMessage)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(color.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(BeagleMotion.normal, value: currentMessage)
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
                .tint(color)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(color.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(color.opacity(0.1), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(BeagleMotion.bouncy.delay(delay), value: appeared)
        .onAppear { appeared = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                messageIndex += 1
                currentMessage = messages[messageIndex % messages.count]
            }
        }
    }

    private var iconForAgent: String {
        switch agentName {
        case "ATHENA": return "scope"
        case "HERMES": return "text.alignleft"
        case "ARGOS":  return "shield.lefthalf.filled"
        case "JUDGE":  return "scalemass"
        default:       return "person"
        }
    }
}
