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
                    runningSection
                    completedSection
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
            }
            .background { PostureGradientBackground(counts: .empty) }
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
                            Text(job.kind ?? "unknown")
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Text(job.jobId ?? "")
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func launchJob(kind: String) async {
        selectedKind = kind
        _ = await cognitive.launchJob(kind: kind)
        try? await Task.sleep(for: .seconds(1))
        selectedKind = nil
    }
}
