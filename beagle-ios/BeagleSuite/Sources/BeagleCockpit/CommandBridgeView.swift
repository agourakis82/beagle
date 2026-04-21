//
//  CommandBridgeView.swift
//  BeagleCockpit
//
//  The /projects entrypoint. Native equivalent of the web command bridge.
//  Hero cards for always-on, grid for warm, chips for cold.
//

import SwiftUI
import BeagleCore

struct CommandBridgeView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                alwaysOnSection
                warmSection
                coldSection
                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .refreshable {
            await catalog.refresh()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sovereign Surfaces")
                    .font(BeagleTheme.displayFont(size: 28, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)

                let counts = catalog.postureCounts
                Text("Command bridge · \(counts.totalProjects) projects")
                    .font(BeagleTheme.uiFont(size: 13))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            Spacer()

            let counts = catalog.postureCounts
            HStack(spacing: 16) {
                postureCount(counts.alwaysOn, label: "on", color: BeagleTheme.postureOn)
                postureCount(counts.warm, label: "warm", color: BeagleTheme.postureWarm)
                postureCount(counts.cold, label: "cold", color: BeagleTheme.postureCold)
            }
        }
    }

    private func postureCount(_ n: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(n)")
                .foregroundStyle(color)
                .fontWeight(.medium)
            Text(label)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        .font(BeagleTheme.dataFont(size: 12))
    }

    @ViewBuilder
    private var alwaysOnSection: some View {
        if !catalog.alwaysOnProjects.isEmpty {
            VStack(spacing: 12) {
                ForEach(catalog.alwaysOnProjects) { project in
                    NavigationLink(value: project) {
                        ProjectHeroCard(project: project)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(for: Project.self) { project in
                ControlRoomView(slug: project.projectSlug)
            }
        }
    }

    @ViewBuilder
    private var warmSection: some View {
        if !catalog.warmProjects.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 12)],
                spacing: 12
            ) {
                ForEach(catalog.warmProjects) { project in
                    NavigationLink(value: project) {
                        ProjectMediumCard(project: project)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var coldSection: some View {
        if !catalog.coldProjects.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("COLD PROJECTS")
                    .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)

                FlowLayout(spacing: 8) {
                    ForEach(catalog.coldProjects) { project in
                        NavigationLink(value: project) {
                            ProjectColdChip(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Project cards

struct ProjectHeroCard: View {
    let project: Project

    var body: some View {
        GlassPanel(elevated: true, truth: .observed) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(project.projectSlug.uppercased())
                                .font(BeagleTheme.displayFont(size: 20, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            PostureIndicator(project.posture)
                        }
                        Text("Sovereign habitat · continuous operations")
                            .font(BeagleTheme.uiFont(size: 13))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                    Spacer()
                    TruthBadge(.observed)
                }

                HStack(spacing: 24) {
                    StatItem(label: "workspace", value: "live", color: BeagleTheme.truthObserved)
                    StatItem(label: "branch", value: project.preferredPrBase ?? project.branch ?? "main")
                    if let ns = project.namespace {
                        StatItem(label: "ns", value: ns)
                    }
                }

                HStack(spacing: 8) {
                    Label("enter control room", systemImage: "arrow.right")
                        .font(BeagleTheme.dataFont(size: 12))
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(BeagleTheme.truthObserved.opacity(0.15))
                        )
                    Spacer()
                }
            }
        }
    }
}

struct ProjectMediumCard: View {
    let project: Project

    var body: some View {
        GlassPanel(truth: .declared) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.projectSlug)
                        .font(BeagleTheme.uiFont(size: 15, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    PostureIndicator(project.posture, size: 11, showLabel: false)
                }
                Text("standby · \(project.namespace ?? "beagle")")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }
}

struct ProjectColdChip: View {
    let project: Project

    var body: some View {
        HStack(spacing: 4) {
            PostureIndicator(project.posture, size: 10, showLabel: false)
            Text(project.projectSlug)
                .font(BeagleTheme.dataFont(size: 11))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.03))
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    BeagleTheme.truthDeclared,
                    style: StrokeStyle(lineWidth: 1, dash: [1, 3])
                )
        )
    }
}

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
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .foregroundStyle(color)
        }
        .font(BeagleTheme.dataFont(size: 11))
    }
}

// MARK: - FlowLayout (simple wrapping HStack)

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
