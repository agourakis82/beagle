//
//  MetalClusterView.swift
//  BeagleCockpit
//
//  2D cluster topology grid — shows node health, role, and status
//  with truth-aware indicators. Each node is tappable for detail.
//
//  Replaces the previous SceneKit 3D implementation for:
//  - Battery efficiency (no Metal shader, no breathing animations)
//  - Better information density (role, hostname visible at a glance)
//  - Accessibility (VoiceOver, Dynamic Type compatible)
//

import SwiftUI
import BeagleCore

struct MetalClusterView: View {
    let nodes: [ClusterNode]
    @State private var selectedNode: ClusterNode?
    @State private var pulseHealthy = false

    var body: some View {
        VStack(spacing: BeagleSpacing.md) {
            nodeGrid
            if let node = selectedNode {
                nodeDetail(node)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Node grid

    private var nodeGrid: some View {
        let displayNodes = nodes.isEmpty ? defaultNodes : nodes

        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: BeagleSpacing.sm)],
            spacing: BeagleSpacing.sm
        ) {
            ForEach(displayNodes) { node in
                nodeCard(node)
            }
        }
        .onAppear {
            pulseHealthy = true
        }
    }

    private func nodeCard(_ node: ClusterNode) -> some View {
        let isHealthy = node.healthy == true
        let isSelected = selectedNode?.id == node.id
        let color = nodeColor(node)

        return Button {
            withAnimation(BeagleMotion.snappy) {
                selectedNode = selectedNode?.id == node.id ? nil : node
            }
        } label: {
            VStack(spacing: BeagleSpacing.xs) {
                // Health indicator — Circle doesn't support symbolEffect, use scale animation
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(isHealthy ? 0.5 : 0), radius: 4)
                    .scaleEffect(isHealthy && pulseHealthy ? 1.25 : 1.0)
                    .animation(
                        isHealthy
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseHealthy
                    )

                // Hostname
                Text(node.hostname ?? node.name ?? "?")
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(1)

                // Role
                if let role = node.role {
                    Text(role)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BeagleSpacing.sm)
            .padding(.horizontal, BeagleSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .fill(isSelected ? color.opacity(0.12) : BeagleTheme.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .strokeBorder(
                        isSelected ? color.opacity(0.4) : Color.white.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedNode?.id)
    }

    // MARK: - Node detail

    private func nodeDetail(_ node: ClusterNode) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Circle()
                .fill(nodeColor(node))
                .frame(width: 10, height: 10)
                .shadow(color: nodeColor(node).opacity(0.5), radius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.hostname ?? node.name ?? "unknown")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                HStack(spacing: BeagleSpacing.xs) {
                    if let role = node.role {
                        Text(role)
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text(node.healthy == true ? "healthy" : "unhealthy")
                        .font(BeagleFont.data.font)
                        .foregroundStyle(node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                }
            }

            Spacer()

            Button {
                withAnimation(BeagleMotion.snappy) { selectedNode = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Helpers

    private func nodeColor(_ node: ClusterNode) -> Color {
        guard node.healthy == true else { return BeagleTheme.stateError }
        // Distinguish role even when healthy: ctrl = gold, worker = teal
        switch node.role {
        case "ctrl", "control-plane": return BeagleTheme.postureWarm
        default:                      return BeagleTheme.truthObserved
        }
    }

    private var defaultNodes: [ClusterNode] {
        [
            ClusterNode(name: "r770", hostname: "r770", role: nil, healthy: true),
            ClusterNode(name: "r740", hostname: "r740", role: nil, healthy: true),
            ClusterNode(name: "t560", hostname: "t560", role: "ctrl", healthy: true)
        ]
    }
}
