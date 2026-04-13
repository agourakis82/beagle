//
//  TriadReviewView.swift
//  BeagleCockpit
//
//  Adversarial review: ATHENA (accuracy) + HERMES (writing) + ARGOS (rigor) + Judge.
//  Submit a draft, get scores from 4 agents, give feedback to train LoRA.
//

import SwiftUI
import BeagleCore
import Charts

struct TriadReviewView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var draftText = ""
    @State private var result: TriadResult?
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    inputSection
                    if cognitive.isReviewingTriad { progressSection }
                    if let result { resultsSection(result) }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
            }
            .background { HealthPulseGradient(truth: result != nil ? .observed : .declared) }
            .navigationTitle("Triad Review")
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        GlassPanel(elevation: .raised) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Submit draft for adversarial review")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)

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

    // MARK: - Progress

    private var progressSection: some View {
        GlassPanel(elevation: .flush) {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .symbolEffect(.variableColor.iterative, isActive: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Triad reviewing...")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("ATHENA + HERMES + ARGOS + Judge (up to 2 min)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Spacer()
                ProgressView()
            }
        }
    }

    // MARK: - Results

    private func resultsSection(_ triad: TriadResult) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            // Scores chart
            if let scores = triad.scores {
                GlassPanel(elevation: .floating, truth: .observed) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        Text("Scores")
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)

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
                                Image(systemName: verdictIcon(verdict))
                                    .foregroundStyle(verdictColor(verdict))
                                Text(verdict)
                                    .font(BeagleFont.dataProminent.font)
                                    .foregroundStyle(verdictColor(verdict))
                            }
                        }
                    }
                }
            }

            // Agent opinions
            ForEach(agentOpinions(triad), id: \.0) { name, opinion in
                if let opinion {
                    agentOpinionCard(name: name, opinion: opinion)
                }
            }

            // Feedback buttons
            feedbackButtons
        }
    }

    private func agentOpinionCard(name: String, opinion: TriadAgentOpinion) -> some View {
        GlassPanel(elevation: .flush) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack {
                    Text(name)
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if let conf = opinion.confidence {
                        Text(String(format: "%.1f", conf))
                            .font(BeagleFont.dataProminent.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
                if let text = opinion.opinion {
                    Text(text)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var feedbackButtons: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Button {
                Task { await cognitive.submitFeedback(runId: "triad-\(Date.now.timeIntervalSince1970)", clarity: 8, adequacy: 8, notes: "accepted") }
            } label: {
                Label("Accept", systemImage: "hand.thumbsup.fill")
            }
            .buttonStyle(PrimaryButton())

            Button {
                result = nil
                draftFocused = true
            } label: {
                Label("Revise", systemImage: "pencil")
            }
            .buttonStyle(SecondaryButton())
        }
    }

    // MARK: - Helpers

    private func submitForReview() async {
        draftFocused = false
        result = nil
        let triad = await cognitive.submitForTriadReview(draft: draftText)
        withAnimation(BeagleMotion.slow) { result = triad }
    }

    private func agentOpinions(_ t: TriadResult) -> [(String, TriadAgentOpinion?)] {
        [("ATHENA", t.athena), ("HERMES", t.hermes), ("ARGOS", t.argos), ("JUDGE", t.judge)]
    }

    private func verdictIcon(_ v: String) -> String {
        v.contains("consensus") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private func verdictColor(_ v: String) -> Color {
        v.contains("consensus") ? BeagleTheme.truthObserved : BeagleTheme.postureWarm
    }
}
