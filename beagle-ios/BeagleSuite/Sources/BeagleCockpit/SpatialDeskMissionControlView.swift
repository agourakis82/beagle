//
//  SpatialDeskMissionControlView.swift
//  BeagleCockpit
//
//  iPad-first Mission Control for the v3.7 Spatial Desk Mind Palace.
//  SwiftData remains cache/outbox only; the cluster owns canonical memory.
//

import SwiftUI
import BeagleCore

struct SpatialDeskMissionControlView: View {
    @State private var exocortex = ExocortexStore()
    @State private var commandText = ""
    @State private var selectedRoomId: String?

    private var snapshot: MindPalaceSnapshot? { exocortex.mindPalace?.value }
    private var selectedRoom: MindPalaceRoom? {
        guard let selectedRoomId else { return snapshot?.rooms.first }
        return snapshot?.rooms.first(where: { $0.id == selectedRoomId }) ?? snapshot?.rooms.first
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    commandBar
                    if let snapshot {
                        nextBestPlace(snapshot.nextBestPlace)
                        if proxy.size.width >= 900 {
                            HStack(alignment: .top, spacing: 16) {
                                roomsColumn(snapshot.rooms)
                                    .frame(width: 270)
                                deskColumn(snapshot)
                                rightColumn(snapshot)
                                    .frame(width: 280)
                            }
                        } else {
                            roomsColumn(snapshot.rooms)
                            deskColumn(snapshot)
                            rightColumn(snapshot)
                        }
                    } else {
                        loadingPanel
                    }
                }
                .padding(22)
            }
            .background(Color(red: 0.02, green: 0.03, blue: 0.06))
        }
        .navigationTitle("Mind Palace")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var header: some View {
        GlassPanel(elevated: true, truth: exocortex.mindPalace?.mode ?? .declared) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "rectangle.3.group.bubble.left")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 42, height: 42)
                    .background(BeagleTheme.truthObserved.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Spatial Desk")
                        .font(BeagleFont.title2.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Mission Control for parallel projects, agents, portals, memory proof, and focus.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TruthBadge(exocortex.mindPalace?.mode ?? .declared, compact: true)
                        chip(snapshot?.schemaVersion ?? "mind-palace v3.7")
                        chip(snapshot?.focusCoach.mode ?? "focus coach")
                    }
                }
                Spacer(minLength: 10)
            }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .foregroundStyle(BeagleTheme.truthRemembered)
            TextField("Open a room, promote a portal, ask what is happening in parallel...", text: $commandText)
                .textFieldStyle(.plain)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)
            Button {
                commandText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BeagleTheme.truthObserved)
            .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .background(BeagleTheme.surface1.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BeagleTheme.hairline, lineWidth: 1)
        )
    }

    private func nextBestPlace(_ decision: NextBestPlaceDecision) -> some View {
        GlassPanel(truth: .observed) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT BEST PLACE")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.title)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(decision.reason)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(Int(decision.confidence * 100))%")
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }
        }
        .onTapGesture {
            selectedRoomId = decision.roomId
        }
    }

    private func roomsColumn(_ rooms: [MindPalaceRoom]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Rooms")
            ForEach(rooms) { room in
                Button {
                    selectedRoomId = room.id
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: roomIcon(room.roomType))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(room.id == selectedRoom?.id ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.title)
                                .font(BeagleFont.body.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(1)
                            Text(room.tension)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 6)
                    }
                    .padding(10)
                    .background(
                        (room.id == selectedRoom?.id ? BeagleTheme.truthObserved.opacity(0.12) : BeagleTheme.surface1.opacity(0.58)),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deskColumn(_ snapshot: MindPalaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Spatial Desk")
            if let selectedRoom {
                GlassPanel(truth: selectedRoom.truthMode == "observed" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedRoom.title)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(selectedRoom.nextAction)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            chip(selectedRoom.sourceFamily)
                            chip(selectedRoom.freshness)
                            chip(selectedRoom.truthMode)
                        }
                    }
                }
            }

            ForEach(snapshot.desk.activeItems.prefix(8)) { item in
                GlassPanel(truth: .remembered) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(item.title, systemImage: itemIcon(item.kind))
                                .font(BeagleFont.body.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(item.state)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                        }
                        Text(item.detail)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private func rightColumn(_ snapshot: MindPalaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Action Menu")
            ForEach(snapshot.actionMenu.actions) { action in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: actionIcon(action.kind))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(action.enabled ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(action.reason)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(BeagleTheme.surface1.opacity(action.enabled ? 0.56 : 0.32), in: RoundedRectangle(cornerRadius: 8))
            }

            sectionLabel("Focus Coach")
            FocusCoachPanel(state: snapshot.focusCoach) { intervention in
                Task {
                    _ = await exocortex.recordFocusCoachEvent(
                        FocusCoachEventRequest(
                            eventKind: "snooze",
                            interventionId: intervention.id,
                            projectSlug: selectedRoom?.projectSlug,
                            notes: "Snoozed from Spatial Desk Mission Control.",
                            snoozedMinutes: 15
                        )
                    )
                    await refresh()
                }
            }

            if !snapshot.desk.portals.isEmpty {
                sectionLabel("Portals")
                ForEach(snapshot.desk.portals.prefix(3)) { portal in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(portal.title)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("\(portal.provider) · \(portal.status)")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                    .padding(9)
                    .background(BeagleTheme.surface1.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var loadingPanel: some View {
        GlassPanel(truth: .declared) {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading cluster Mind Palace...")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
        }
    }

    private func refresh() async {
        await exocortex.refreshMindPalace()
        if selectedRoomId == nil {
            selectedRoomId = snapshot?.nextBestPlace.roomId ?? snapshot?.rooms.first?.id
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.textTertiary)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption2.font)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface2.opacity(0.7), in: Capsule())
            .foregroundStyle(BeagleTheme.textSecondary)
    }

    private func roomIcon(_ type: String) -> String {
        switch type {
        case "workspace": return "apple.terminal"
        case "conversation", "portal": return "bubble.left.and.bubble.right"
        case "spatial": return "cube.transparent"
        case "paper": return "doc.text.magnifyingglass"
        default: return "folder"
        }
    }

    private func itemIcon(_ kind: String) -> String {
        switch kind {
        case "conversation_portal": return "macwindow"
        case "workspace": return "apple.terminal"
        case "spatial": return "cube.transparent"
        default: return "square.stack.3d.up"
        }
    }

    private func actionIcon(_ kind: String) -> String {
        switch kind {
        case "open_workbench": return "apple.terminal"
        case "open_memory_lens": return "sparkle.magnifyingglass"
        case "promote_conversation_clip": return "arrow.up.doc"
        case "spatial_generation_draft": return "wand.and.stars"
        case "focus_intervention": return "timer"
        default: return "arrow.forward.circle"
        }
    }
}

private struct FocusCoachPanel: View {
    let state: FocusCoachState
    let onSnooze: (FocusIntervention) -> Void

    var body: some View {
        GlassPanel(truth: .observed) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(state.mode)
                        .font(BeagleFont.body.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    Text("\(state.sessionMinutes)m")
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.truthRemembered)
                }
                ForEach(state.interventions.prefix(3)) { intervention in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: intervention.kind == "hydration" ? "drop" : "clock")
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(intervention.title)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(intervention.reason)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                        Button("Snooze") {
                            onSnooze(intervention)
                        }
                        .font(BeagleFont.caption2.font)
                        .buttonStyle(.plain)
                        .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
            }
        }
    }
}
