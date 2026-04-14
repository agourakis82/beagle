//
//  ScienceJobsView.swift
//  BeagleCockpit
//
//  Launch and monitor scientific pipelines from the iPhone.
//  Any project, any pipeline kind (PBPK, helio, scaffolds, PCS, KEC).
//

import SwiftUI
import BeagleCore

struct ScienceJobsView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var selectedKind: String?
    @State private var launchError: String?
    @State private var launchSuccess: String?

    private let jobKinds = [
        ("pbpk",     "cross.vial.fill",      "PBPK"),
        ("helio",    "sun.max.fill",          "Heliobiology"),
        ("scaffold", "cube.transparent.fill", "Scaffolds"),
        ("pcs",      "atom",                  "PCS"),
        ("kec",      "brain.head.profile",    "KEC")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    launcherSection
                    if let success = launchSuccess {
                        launchSuccessBanner(success)
                    }
                    if let error = launchError {
                        launchErrorBanner(error)
                    }
                    runningSection
                    completedSection
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
            }
            .background { ScienceJobsGradient(hasRunning: cognitive.activeJobs.contains(where: \.isRunning)) }
            .navigationTitle("Science")
            .task {
                await cognitive.pollActiveJobs()
            }
        }
    }

    // MARK: - Launcher

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Launch pipeline")
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textTertiary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: BeagleSpacing.sm)], spacing: BeagleSpacing.sm) {
                ForEach(jobKinds, id: \.0) { kind, icon, label in
                    Button {
                        Task { await launchJob(kind: kind) }
                    } label: {
                        VStack(spacing: BeagleSpacing.xs) {
                            Image(systemName: icon)
                                .font(.system(size: 24))
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .symbolEffect(.pulse, isActive: selectedKind == kind)
                            Text(label)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 72)
                        .padding(.vertical, BeagleSpacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .fill(.regularMaterial)
                                .opacity(0.5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .strokeBorder(
                                    selectedKind == kind ? BeagleTheme.truthObserved.opacity(0.3) : Color.white.opacity(0.06),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: selectedKind)
                }
            }
        }
    }

    // MARK: - Running jobs

    @ViewBuilder
    private var runningSection: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Running")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.truthObserved)

                ForEach(running) { job in
                    GlassPanel(elevation: .raised, truth: .observed) {
                        HStack(spacing: BeagleSpacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .symbolEffect(.pulse)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.kind ?? "unknown")
                                    .font(BeagleFont.headline.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Text(job.jobId ?? "—")
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Spacer()
                            Text(job.status ?? "running")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.postureWarm)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Completed jobs

    @ViewBuilder
    private var completedSection: some View {
        let completed = cognitive.activeJobs.filter(\.isCompleted)
        if !completed.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Completed")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(completed) { job in
                    GlassPanel(elevation: .flush) {
                        HStack(spacing: BeagleSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BeagleTheme.truthObserved)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.kind ?? "unknown")
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Text(job.jobId ?? "")
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Spacer()
                            GoDeepButton(prompt: "Analyze the results of my \(job.kind ?? "science") job \(job.jobId ?? "")")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func launchJob(kind: String) async {
        launchError = nil
        launchSuccess = nil
        selectedKind = kind
        let job = await cognitive.launchJob(kind: kind)
        if let job {
            withAnimation(BeagleMotion.snappy) {
                launchSuccess = "\(kind.uppercased()) submitted — \(job.jobId ?? "tracking")"
            }
        } else {
            withAnimation(BeagleMotion.snappy) {
                launchError = "Failed to submit \(kind) job. Check backend connectivity."
            }
        }
        try? await Task.sleep(for: .seconds(0.5))
        selectedKind = nil
    }

    private func launchSuccessBanner(_ message: String) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(BeagleTheme.truthObserved)
            Text(message)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.truthObserved)
            Spacer()
            Button {
                withAnimation(BeagleMotion.snappy) { launchSuccess = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.truthObserved.opacity(0.08))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .sensoryFeedback(.success, trigger: launchSuccess != nil)
    }

    private func launchErrorBanner(_ error: String) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BeagleTheme.stateError)
            Text(error)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation(BeagleMotion.snappy) { launchError = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.stateError.opacity(0.1))
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Science Jobs Gradient

/// Background pulses with gold warmth when jobs are running.
private struct ScienceJobsGradient: View {
    let hasRunning: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: hasRunning)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)
        return [
            BeagleTheme.truthObserved.opacity(hasRunning ? 0.12 : 0.0),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(hasRunning ? 0.18 : 0.0),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}
