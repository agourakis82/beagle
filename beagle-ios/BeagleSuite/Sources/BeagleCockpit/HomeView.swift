//
//  HomeView.swift
//  BeagleCockpit
//
//  The exocortex surface. Not a dashboard — a thinking companion.
//  Opens with provocations, suggestions, and an inviting input.
//  Makes you want to engage, not just monitor.
//

import SwiftUI
import BeagleCore

struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @State private var conversation = ConversationStore()
    @State private var inputText = ""
    @State private var provocations: [Provocation] = []
    @State private var greeting = ""
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    greetingSection
                    if !provocations.isEmpty {
                        provocationsSection
                    }
                    recentThoughtsSection
                    if !conversation.isEmpty {
                        conversationSection
                    }
                    statusGlance
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.xl)
                .padding(.bottom, BeagleSpacing.jumbo)
            }

            exocortexInput
        }
        .background(
            LinearGradient(
                colors: [
                    BeagleTheme.surface0,
                    Color(red: 8/255, green: 15/255, blue: 28/255),
                    Color(red: 5/255, green: 12/255, blue: 24/255)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await bootstrap()
        }
        .refreshable {
            async let c: () = catalog.refresh()
            async let g: () = cognitive.refresh()
            _ = await (c, g)
            generateProvocations()
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text(greeting)
                .font(BeagleFont.largeTitle.font)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BeagleTheme.textPrimary, BeagleTheme.truthObserved.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

            Text(contextLine)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.6).delay(0.15), value: hasAppeared)
        }
    }

    private var contextLine: String {
        let jobCount = cognitive.activeJobs.count
        let projectCount = catalog.postureCounts.totalProjects
        if jobCount > 0 {
            return "\(jobCount) job\(jobCount > 1 ? "s" : "") running across \(projectCount) surfaces."
        }
        return "\(projectCount) sovereign surfaces. What are you thinking about?"
    }

    // MARK: - Provocations (like ChatGPT Pulse)

    private var provocationsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text("Explore")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: hasAppeared)

            ForEach(Array(provocations.enumerated()), id: \.element.id) { index, provocation in
                Button {
                    inputText = provocation.prompt
                    Task { await conversation.sendMessage(provocation.prompt) }
                } label: {
                    provocationCard(provocation)
                }
                .buttonStyle(.plain)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.35 + Double(index) * 0.1), value: hasAppeared)
            }
        }
    }

    private func provocationCard(_ p: Provocation) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: p.icon)
                .font(.system(size: 16))
                .foregroundStyle(p.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(1)
                Text(p.subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(p.color.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Recent thoughts

    @ViewBuilder
    private var recentThoughtsSection: some View {
        if !cognitive.recentThoughts.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Recent thoughts")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(cognitive.recentThoughts.prefix(3)) { thought in
                    Button {
                        let text = thought.refinedText ?? thought.rawText ?? ""
                        Task { await conversation.sendMessage("Expand on this thought: \(text)") }
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            Circle()
                                .fill(BeagleTheme.truthObserved.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(thought.refinedText ?? thought.rawText ?? "—")
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Conversation (inline, not separate tab)

    @ViewBuilder
    private var conversationSection: some View {
        VStack(spacing: BeagleSpacing.xs) {
            ForEach(conversation.messages) { message in
                ChatBubbleView(
                    message: message,
                    onRegenerate: message.role == .assistant ? {
                        Task { await conversation.regenerateLastResponse() }
                    } : nil
                )
            }
        }
    }

    // MARK: - Status glance (minimal, at the bottom)

    @ViewBuilder
    private var statusGlance: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        let errors = cognitive.activeJobs.filter { $0.status == "error" }

        if !running.isEmpty || !errors.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Status")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(running) { job in
                    statusRow(job.kind ?? "job", status: "running", color: BeagleTheme.postureWarm, pulse: true)
                }
                ForEach(errors.prefix(2)) { job in
                    statusRow(job.kind ?? "job", status: "error", color: BeagleTheme.stateError, pulse: false)
                }
            }
        }
    }

    private func statusRow(_ name: String, status: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .symbolEffect(.pulse, isActive: pulse)
            Text(name)
                .font(BeagleFont.data.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Text(status)
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(color)
        }
    }

    // MARK: - Exocortex input (always visible at bottom)

    private var exocortexInput: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: "Ask the exocortex...",
            mode: .chat,
            isEnabled: !conversation.isStreaming,
            onSubmit: { text in
                Task { await conversation.sendMessage(text) }
            }
        )
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        greeting = timeGreeting()
        async let c: () = catalog.refresh()
        async let g: () = cognitive.refresh()
        _ = await (c, g)
        generateProvocations()
        withAnimation { hasAppeared = true }
    }

    private func timeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Still thinking?"
        }
    }

    // MARK: - Provocation generation (on-device LLM)

    @State private var isGeneratingProvocations = false

    private func generateProvocations() {
        guard !isGeneratingProvocations else { return }
        isGeneratingProvocations = true

        Task {
            let projects = catalog.projects.map(\.projectSlug)
            let thoughts = cognitive.recentThoughts.prefix(3).compactMap { $0.refinedText ?? $0.rawText }
            let jobs = cognitive.activeJobs.prefix(5).map { (kind: $0.kind ?? "unknown", status: $0.status ?? "unknown") }
            let counts = (on: catalog.postureCounts.alwaysOn, warm: catalog.postureCounts.warm, cold: catalog.postureCounts.cold)

            if let raw = await FoundationModelsAgent.shared.generateProvocations(
                projects: projects,
                recentThoughts: Array(thoughts),
                recentJobs: jobs,
                postureCounts: counts
            ) {
                let parsed = parseProvocations(raw)
                if !parsed.isEmpty {
                    withAnimation(BeagleMotion.slow) {
                        provocations = parsed
                    }
                } else {
                    // LLM returned something but parsing failed — use fallback
                    withAnimation(BeagleMotion.slow) {
                        provocations = fallbackProvocations()
                    }
                }
            } else {
                // LLM unavailable — use fallback
                withAnimation(BeagleMotion.slow) {
                    provocations = fallbackProvocations()
                }
            }

            isGeneratingProvocations = false
        }
    }

    private func parseProvocations(_ raw: String) -> [Provocation] {
        let icons = ["brain.head.profile", "sparkles", "lightbulb.max"]
        let colors = [BeagleTheme.truthRemembered, BeagleTheme.truthObserved, BeagleTheme.postureWarm]

        return raw
            .components(separatedBy: "\n")
            .filter { $0.contains("|") }
            .prefix(3)
            .enumerated()
            .map { index, line in
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                return Provocation(
                    title: parts.count > 0 ? parts[0] : "Explore",
                    subtitle: parts.count > 1 ? parts[1] : "",
                    icon: icons[index % icons.count],
                    color: colors[index % colors.count],
                    prompt: parts.count > 2 ? parts[2] : parts.first ?? ""
                )
            }
    }

    private func fallbackProvocations() -> [Provocation] {
        var result: [Provocation] = []

        // Job errors are always relevant
        if let lastError = cognitive.activeJobs.first(where: { $0.status == "error" }) {
            result.append(Provocation(
                title: "\(lastError.kind ?? "Job") failed",
                subtitle: "Want to investigate what went wrong?",
                icon: "exclamationmark.triangle",
                color: BeagleTheme.stateError,
                prompt: "My \(lastError.kind ?? "pipeline") job failed. Help me debug it."
            ))
        }

        // Continue last thought
        if let thought = cognitive.recentThoughts.first, let text = thought.refinedText ?? thought.rawText {
            result.append(Provocation(
                title: "Continue your last thought",
                subtitle: String(text.prefix(60)) + (text.count > 60 ? "..." : ""),
                icon: "text.bubble",
                color: BeagleTheme.truthObserved,
                prompt: "Continue developing this thought: \(text). What are the implications and next steps?"
            ))
        }

        // Generic research spark
        result.append(Provocation(
            title: "Cross-domain connections",
            subtitle: "What unexpected links exist in your research?",
            icon: "brain.head.profile",
            color: BeagleTheme.truthRemembered,
            prompt: "Look at my active projects and find unexpected cross-domain connections that could lead to novel insights."
        ))

        return Array(result.prefix(3))
    }
}

// MARK: - Provocation model

struct Provocation: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let prompt: String
}
