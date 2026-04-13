//
//  HomeView.swift
//  BeagleCockpit
//
//  Single-screen operational status. Answers "what's happening now?"
//  in 2 seconds without tapping anything.
//
//  Shows only data that actually exists from the backend:
//  - Sounio status (always-on, warm, cold counts)
//  - Agent sessions (running or not)
//  - Recent jobs (with actual status)
//  - Quick actions (capture, agent, drill into project)
//

import SwiftUI
import BeagleCore

struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(HPCStore.self) private var hpc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                statusHeader
                primaryProject
                quickActions
                recentJobs
                projectList
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
        }
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0, BeagleTheme.surface1.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Beagle")
        .task {
            async let c: () = catalog.refresh()
            async let g: () = cognitive.refresh()
            _ = await (c, g)
        }
        .refreshable {
            async let c: () = catalog.refresh()
            async let g: () = cognitive.refresh()
            _ = await (c, g)
        }
    }

    // MARK: - Status header (posture counts + truth)

    private var statusHeader: some View {
        HStack(spacing: BeagleSpacing.lg) {
            postureStat(catalog.postureCounts.alwaysOn, "on", BeagleTheme.postureOn)
            postureStat(catalog.postureCounts.warm, "warm", BeagleTheme.postureWarm)
            postureStat(catalog.postureCounts.cold, "cold", BeagleTheme.postureCold)
            Spacer()
            TruthBadge(catalog.executive.mode)
        }
    }

    private func postureStat(_ n: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)")
                .font(BeagleFont.title2.font)
                .foregroundStyle(color)
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    // MARK: - Primary project (Sounio hero)

    @ViewBuilder
    private var primaryProject: some View {
        if let sounio = catalog.alwaysOnProjects.first {
            NavigationLink(value: sounio) {
                GlassPanel(elevation: .floating, truth: .observed) {
                    HStack(spacing: BeagleSpacing.md) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                            HStack(spacing: BeagleSpacing.xs) {
                                Circle()
                                    .fill(BeagleTheme.truthObserved)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: BeagleTheme.truthObserved.opacity(0.5), radius: 4)
                                Text(sounio.projectSlug)
                                    .font(BeagleFont.title3.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                            }
                            Text(sounio.workspacePod != nil ? "habitat live" : "habitat standby")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(sounio.workspacePod != nil ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: BeagleSpacing.sm) {
            // These don't navigate — they switch tabs
            // But showing them as visual anchors of what the app does
            actionCard("Capture", icon: "mic.fill", color: BeagleTheme.truthObserved, subtitle: "voice or text")
            actionCard("Agent", icon: "terminal", color: BeagleTheme.truthRemembered, subtitle: "Claude Code")
        }
    }

    private func actionCard(_ title: String, icon: String, color: Color, subtitle: String) -> some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(title)
                .font(BeagleFont.footnote.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Recent jobs

    @ViewBuilder
    private var recentJobs: some View {
        let jobs = cognitive.activeJobs.prefix(5)
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack {
                    Text("Recent jobs")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    TruthBadge(cognitive.state.mode, compact: true)
                }

                ForEach(Array(jobs)) { job in
                    HStack(spacing: BeagleSpacing.sm) {
                        Circle()
                            .fill(jobColor(job))
                            .frame(width: 8, height: 8)
                            .symbolEffect(.pulse, isActive: job.isRunning)

                        Text(job.kind ?? "job")
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.textPrimary)

                        Spacer()

                        Text(job.status ?? "—")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(jobColor(job))
                    }
                    .padding(.vertical, BeagleSpacing.xxs)
                }
            }
        }
    }

    private func jobColor(_ job: ScienceJob) -> Color {
        switch job.status {
        case "running":  return BeagleTheme.postureWarm
        case "done":     return BeagleTheme.truthObserved
        case "error":    return BeagleTheme.stateError
        default:         return BeagleTheme.textTertiary
        }
    }

    // MARK: - Project list (warm + cold as simple rows)

    @ViewBuilder
    private var projectList: some View {
        let others = catalog.projects.filter { $0.posture != .alwaysOn }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Projects")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(others) { project in
                    NavigationLink(value: project) {
                        HStack(spacing: BeagleSpacing.sm) {
                            PostureIndicator(project.posture, size: 10, showLabel: false)
                            Text(project.projectSlug)
                                .font(BeagleFont.body.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Text(project.posture.displayLabel)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        .padding(.vertical, BeagleSpacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
