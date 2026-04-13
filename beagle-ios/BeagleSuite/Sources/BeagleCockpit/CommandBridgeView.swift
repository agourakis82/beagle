//
//  CommandBridgeView.swift
//  BeagleCockpit
//
//  Command bridge — the sovereign supercomputing surface picker.
//  Hero cards for always-on with ambient glow, warm grid, cold chips.
//

import SwiftUI
import BeagleCore

struct CommandBridgeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Namespace private var heroNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxl) {
                headerSection
                if catalog.executive.mode == .stale {
                    catalogErrorBanner
                }
                alwaysOnSection
                warmSection
                coldSection
                if catalog.projects.isEmpty && catalog.executive.mode != .stale {
                    emptyProjectsState
                }
                Spacer(minLength: BeagleSpacing.jumbo)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
        }
        .background { PostureGradientBackground(counts: catalog.postureCounts) }
        .refreshable {
            await catalog.refresh()
        }
    }

    private var catalogErrorBanner: some View {
        GlassPanel(elevation: .raised, truth: .stale) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(BeagleTheme.stateError)
                    Text("Could not load projects")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
                if let error = catalog.executive.error {
                    Text(error)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                Button {
                    Task { await catalog.refresh() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton(color: BeagleTheme.stateError))
            }
        }
    }

    private var emptyProjectsState: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.4))
            Text("No projects found")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("Pull to refresh when cockpit is reachable")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BeagleSpacing.jumbo)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                    Text("Projects")
                        .font(BeagleFont.title1.font)
                        .tracking(-0.3)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Text("\(catalog.postureCounts.totalProjects) sovereign surfaces")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Spacer()
                TruthBadge(catalog.executive.mode)
            }

            // Posture pills
            HStack(spacing: BeagleSpacing.sm) {
                posturePill(catalog.postureCounts.alwaysOn, label: "on", color: BeagleTheme.postureOn)
                posturePill(catalog.postureCounts.warm, label: "warm", color: BeagleTheme.postureWarm)
                posturePill(catalog.postureCounts.cold, label: "cold", color: BeagleTheme.postureCold)
            }
        }
    }

    private func posturePill(_ n: Int, label: String, color: Color) -> some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Text("\(n)")
                .font(BeagleFont.data.font)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Text(label)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xxs + 2)
        .background(
            Capsule().fill(color.opacity(0.08))
        )
        .overlay(
            Capsule().strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Always-on (hero cards)

    @ViewBuilder
    private var alwaysOnSection: some View {
        if !catalog.alwaysOnProjects.isEmpty {
            VStack(spacing: BeagleSpacing.md) {
                ForEach(catalog.alwaysOnProjects) { project in
                    NavigationLink(value: project) {
                        ProjectHeroCard(project: project)
                            .matchedTransitionSource(id: project.id, in: heroNamespace)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: project.id)
                    .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1 : 0.7)
                            .scaleEffect(phase.isIdentity ? 1 : 0.97)
                    }
                }
            }
            .navigationDestination(for: Project.self) { project in
                ControlRoomView(slug: project.projectSlug)
                    #if os(iOS)
                    .navigationTransition(.zoom(sourceID: project.id, in: heroNamespace))
                    #endif
            }
        }
    }

    // MARK: - Warm projects (grid)

    @ViewBuilder
    private var warmSection: some View {
        if !catalog.warmProjects.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Warm standby")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: BeagleSpacing.md)],
                    spacing: BeagleSpacing.md
                ) {
                    ForEach(catalog.warmProjects) { project in
                        NavigationLink(value: project) {
                            ProjectMediumCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .offset(y: phase.isIdentity ? 0 : 8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cold projects (chips)

    @ViewBuilder
    private var coldSection: some View {
        if !catalog.coldProjects.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Cold catalog")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                FlowLayout(spacing: BeagleSpacing.xs) {
                    ForEach(catalog.coldProjects) { project in
                        NavigationLink(value: project) {
                            ProjectColdChip(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Hero Card (always-on projects)

struct ProjectHeroCard: View {
    let project: Project

    var body: some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                // Title row
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        HStack(spacing: BeagleSpacing.xs) {
                            Text(project.projectSlug)
                                .font(BeagleFont.title3.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            PostureIndicator(project.posture, size: 12)
                        }
                        Text(project.posture.operationalMeaning)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                    Spacer()
                    TruthBadge(.observed)
                }

                // Stats
                HStack(spacing: BeagleSpacing.xxl) {
                    StatItem(label: "habitat", value: project.workspacePod != nil ? "live" : "standby",
                             color: project.workspacePod != nil ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    StatItem(label: "branch", value: project.preferredPrBase ?? project.branch ?? "main")
                    if let ns = project.namespace {
                        StatItem(label: "ns", value: ns)
                    }
                }

                // Arrow indicator
                HStack {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BeagleTheme.truthObserved.opacity(0.5))
                }
            }
        }
    }
}

// MARK: - Medium Card (warm projects)

struct ProjectMediumCard: View {
    let project: Project

    var body: some View {
        HStack(spacing: 0) {
            // Leading color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(BeagleTheme.postureWarm)
                .frame(width: 3)
                .padding(.vertical, BeagleSpacing.xs)

            GlassPanel(elevation: .raised, truth: .declared) {
                VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Text(project.projectSlug)
                            .font(BeagleFont.body.font)
                            .fontWeight(.medium)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        PostureIndicator(project.posture, size: 10, showLabel: false)
                    }
                    Text("standby · \(project.namespace ?? "beagle")")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
        }
    }
}

// MARK: - Cold Chip

struct ProjectColdChip: View {
    let project: Project

    var body: some View {
        HStack(spacing: BeagleSpacing.xxs + 2) {
            PostureIndicator(project.posture, size: 9, showLabel: false)
            Text(project.projectSlug)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xxs + 2)
        .background(
            Capsule().fill(Color.white.opacity(0.03))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    BeagleTheme.truthDeclared.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 4])
                )
        )
    }
}

// MARK: - StatItem

struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    init(label: String, value: String, color: Color = BeagleTheme.textData) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .font(BeagleFont.data.font)
                .foregroundStyle(color)
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > width {
                height += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
