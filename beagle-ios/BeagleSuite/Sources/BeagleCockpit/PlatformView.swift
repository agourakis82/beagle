//
//  PlatformView.swift
//  BeagleCockpit
//
//  The operational tab — cluster health, project list, agent activity.
//  Oriented around: "Is my platform healthy? What's running?"
//

import SwiftUI
import BeagleCore

struct PlatformView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                clusterSummary
                projectsSection
                agentActivitySection
                jobsSection
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
            .padding(.bottom, BeagleSpacing.jumbo)
        }
        .background { PostureGradientBackground(counts: catalog.postureCounts) }
        .navigationTitle("Platform")
        .refreshable {
            await catalog.refresh()
            await cognitive.refresh()
        }
    }

    // MARK: - Cluster Summary

    private var clusterSummary: some View {
        GlassPanel(elevation: .raised, truth: catalog.executive.mode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Cluster")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    TruthBadge(catalog.executive.mode, compact: true)
                }

                let counts = catalog.postureCounts
                HStack(spacing: BeagleSpacing.lg) {
                    postureStat(count: counts.alwaysOn, label: "alive", color: BeagleTheme.postureOn)
                    postureStat(count: counts.warm, label: "warm", color: BeagleTheme.postureWarm)
                    postureStat(count: counts.cold, label: "resting", color: BeagleTheme.postureCold)
                }

                Text("\(counts.totalProjects) sovereign surfaces")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func postureStat(count: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(BeagleFont.title3.font)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionLabel("Projects")

            // Always-on first
            ForEach(catalog.alwaysOnProjects) { project in
                NavigationLink(value: project) {
                    projectRow(project)
                }
                .buttonStyle(.plain)
            }

            // Warm
            ForEach(catalog.warmProjects) { project in
                NavigationLink(value: project) {
                    projectRow(project)
                }
                .buttonStyle(.plain)
            }

            // Cold (collapsed)
            if !catalog.coldProjects.isEmpty {
                DisclosureGroup {
                    ForEach(catalog.coldProjects) { project in
                        NavigationLink(value: project) {
                            projectRow(project)
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    Text("\(catalog.coldProjects.count) resting")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .tint(BeagleTheme.textTertiary)
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            PostureIndicator(project.posture, size: 10, showLabel: false)

            Text(project.projectSlug)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)

            Spacer()

            if let branch = project.branch {
                Text(branch.components(separatedBy: "/").last ?? branch)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.4))
        )
    }

    // MARK: - Agent Activity

    private var agentActivitySection: some View {
        NavigationLink {
            AgentActivityView()
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.truthRemembered)
                Text("Agent Activity")
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Jobs

    @ViewBuilder
    private var jobsSection: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Running Jobs")
                ForEach(running) { job in
                    HStack(spacing: BeagleSpacing.sm) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(BeagleTheme.postureWarm)
                            .symbolEffect(.pulse)
                        Text(job.kind ?? "unknown")
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer()
                        Text(job.status ?? "running")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.postureWarm)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .fontWeight(.medium)
            .foregroundStyle(BeagleTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
