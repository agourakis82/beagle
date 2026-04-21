//
//  ControlRoomView.swift
//  BeagleCockpit
//
//  /projects/:slug — private control room per project.
//  5 operational lanes with truth badges, mirrors web cockpit ControlRoom.
//

import SwiftUI
import BeagleCore

struct ControlRoomView: View {
    let slug: String
    @State private var store: ProjectStore

    init(slug: String) {
        self.slug = slug
        self._store = State(initialValue: ProjectStore(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                missionLane
                clusterLane
                researchLane
                inferenceLane
                agentLane
                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .navigationTitle(slug)
        .task {
            await store.refresh()
        }
        .refreshable {
            await store.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Text(slug.uppercased())
                    .font(BeagleTheme.displayFont(size: 28, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(BeagleTheme.textPrimary)
                PostureIndicator(store.posture)
            }
            Spacer()
            HStack(spacing: 8) {
                TruthBadge(store.mission.mode)
                if let age = store.mission.observedAt {
                    Text(store.mission.ageLabel)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
        }
    }

    // MARK: - Lane 1: Mission Control

    private var missionLane: some View {
        Lane(title: "Mission Control", truth: store.mission.mode) {
            if let project = store.project {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatItem(label: "habitat",
                             value: project.workspacePod != nil ? "live" : "standby",
                             color: store.posture == .alwaysOn ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    StatItem(label: "branch", value: project.preferredPrBase ?? project.branch ?? "—")
                    StatItem(label: "namespace", value: project.namespace ?? "—")
                    if let tmux = project.tmuxSession {
                        StatItem(label: "tmux", value: tmux)
                    }
                    if let pg = project.playgroundClass {
                        StatItem(label: "playground", value: pg)
                    }
                }
                if let count = store.mission.value?.packetCount {
                    Text("execution packets: \(count)")
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .padding(.top, 4)
                }
            } else {
                LaneSkeleton()
            }
        }
    }

    // MARK: - Lane 2: Cluster Truth

    private var clusterLane: some View {
        Lane(title: "Cluster Truth", truth: store.clusterTruth.mode) {
            if store.clusterTruth.value != nil {
                HStack(spacing: 14) {
                    NodeIndicator(name: "r770", healthy: true)
                    NodeIndicator(name: "r740", healthy: true)
                    NodeIndicator(name: "t560", role: "ctrl")
                }
            } else {
                LaneSkeleton()
            }
        }
    }

    // MARK: - Lane 3: Research Operations

    private var researchLane: some View {
        Lane(title: "Research Operations", truth: store.research.mode) {
            if store.research.value != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ABIDE campaigns + job tracking")
                        .font(BeagleTheme.dataFont(size: 12))
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            } else {
                LaneSkeleton()
            }
        }
    }

    // MARK: - Lane 4: Inference Fabric

    private var inferenceLane: some View {
        Lane(title: "Inference Fabric", truth: store.inference.mode) {
            if let runtime = store.inference.value {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        InferenceStatusRow(
                            name: "Dynamo",
                            status: runtime.controlPlane?.status ?? "—",
                            healthy: runtime.controlPlane?.status == "ready"
                        )
                        InferenceStatusRow(
                            name: "SGLang",
                            status: runtime.engine?.status ?? "—",
                            healthy: runtime.engine?.status?.contains("published") ?? false
                        )
                    }
                    if let models = runtime.models, !models.isEmpty {
                        Text("\(models.count) model\(models.count > 1 ? "s" : "") serving")
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            } else {
                LaneSkeleton()
            }
        }
    }

    // MARK: - Lane 5: Agent (Claude Code / Codex / local)

    private var agentLane: some View {
        Lane(title: "Agent Session", truth: .declared, defaultExpanded: false) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Persistent cloud agents — Claude Code, Codex, local. Start a session that resumes from any device.")
                    .font(BeagleTheme.uiFont(size: 12))
                    .foregroundStyle(BeagleTheme.textSecondary)

                NavigationLink(value: AgentSessionDestination(slug: slug)) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Open Agent Session")
                            .font(BeagleTheme.dataFont(size: 12))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(BeagleTheme.truthObserved.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: AgentSessionDestination.self) { dest in
            AgentSessionView(slug: dest.slug)
        }
    }
}

// MARK: - Supporting views

struct LaneSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 12)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NodeIndicator: View {
    let name: String
    var healthy: Bool = false
    var role: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthy ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                .frame(width: 6, height: 6)
            Text(name)
                .font(BeagleTheme.dataFont(size: 11))
                .foregroundStyle(BeagleTheme.textData)
            if let role {
                Text(role)
                    .font(BeagleTheme.dataFont(size: 10))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }
}

struct InferenceStatusRow: View {
    let name: String
    let status: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(healthy ? BeagleTheme.truthObserved : BeagleTheme.truthStale)
                .frame(width: 6, height: 6)
            Text("\(name):")
                .foregroundStyle(BeagleTheme.textData)
            Text(status)
                .foregroundStyle(healthy ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
        }
        .font(BeagleTheme.dataFont(size: 11))
    }
}

struct AgentSessionDestination: Hashable {
    let slug: String
}
