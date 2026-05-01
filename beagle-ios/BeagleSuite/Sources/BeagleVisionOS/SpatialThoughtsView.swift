//
//  SpatialThoughtsView.swift
//  BeagleVisionOS
//
//  Spatial thought stream: recent thoughts floating as glass post-its
//  in a gentle arc around the user at eye level.
//
//  Designed for a volumetric WindowGroup on visionOS 26.
//

#if os(visionOS)
import SwiftUI
import RealityKit
import BeagleCore

struct SpatialThoughtsView: View {
    let thoughts: [ThoughtCapture]
    @State private var selectedId: String?
    @State private var floatPhase: Bool = false

    private let maxCards = 7
    private let arcSpreadDegrees: Double = 80
    private let cardDistance: CGFloat = 350

    var body: some View {
        let visible = Array(thoughts.prefix(maxCards))

        ZStack {
            if visible.isEmpty {
                emptyState
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, thought in
                    thoughtCard(thought, index: index, total: visible.count)
                }
            }
        }
        .onAppear { floatPhase = true }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No recent thoughts")
                .font(BeagleTheme.uiFont(size: 17, weight: .medium))
                .foregroundStyle(BeagleTheme.textSecondary)
            Text("Capture something and it will float here.")
                .font(BeagleTheme.uiFont(size: 14))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(32)
        .glassBackgroundEffect()
    }

    // MARK: - Thought Card

    @ViewBuilder
    private func thoughtCard(_ thought: ThoughtCapture, index: Int, total: Int) -> some View {
        let angle = spreadAngle(index: index, total: total)
        let isSelected = selectedId == thought.id
        let text = thought.refinedText ?? thought.rawText ?? ""
        let verticalStagger: CGFloat = index % 2 == 0 ? -12 : 12

        VStack(alignment: .leading, spacing: 10) {
            // Source + timestamp header
            HStack(spacing: 6) {
                Image(systemName: sourceIcon(thought.source ?? ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(sourceLabel(thought.source ?? ""))
                    .font(BeagleTheme.uiFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                if let ts = thought.createdAt {
                    Text(timeAgo(ts))
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }

            // Thought body
            Text(text)
                .font(BeagleTheme.uiFont(size: 14))
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(isSelected ? 20 : 3)
                .frame(maxWidth: isSelected ? 400 : 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            // Sync state indicator
            if let sync = thought.syncState {
                HStack(spacing: 4) {
                    Circle()
                        .fill(syncColor(sync))
                        .frame(width: 5, height: 5)
                    Text(sync.rawValue)
                        .font(BeagleTheme.dataFont(size: 9))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(width: isSelected ? 420 : 280)
        .glassBackgroundEffect()
        .hoverEffect()
        .rotation3DEffect(
            .degrees(angle * 0.3),
            axis: (x: 0, y: 1, z: 0)
        )
        .offset(
            x: sin(angle * .pi / 180) * cardDistance,
            y: verticalStagger
        )
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .opacity(isSelected || selectedId == nil ? 1.0 : 0.7)
        .offset(y: floatPhase ? -4 : 4)
        .animation(
            floatAnimation(index: index),
            value: floatPhase
        )
        .onTapGesture {
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                selectedId = selectedId == thought.id ? nil : thought.id
            }
        }
        .accessibilityLabel("Thought: \(text)")
        .accessibilityHint(isSelected ? "Tap to collapse" : "Tap to expand")
    }

    // MARK: - Layout

    private func spreadAngle(index: Int, total: Int) -> Double {
        guard total > 1 else { return 0 }
        let step = arcSpreadDegrees / Double(total - 1)
        return -arcSpreadDegrees / 2 + step * Double(index)
    }

    // MARK: - Animation

    private func floatAnimation(index: Int) -> Animation {
        .easeInOut(duration: 3.0 + Double(index) * 0.4)
        .repeatForever(autoreverses: true)
        .delay(Double(index) * 0.2)
    }

    // MARK: - Source Helpers

    private func sourceIcon(_ source: String) -> String {
        let s = source.lowercased()
        if s.contains("voice") || s.contains("dictation") { return "mic.fill" }
        if s.contains("keyboard") || s.contains("typed") { return "keyboard" }
        if s.contains("clipboard") || s.contains("paste") { return "doc.on.clipboard" }
        if s.contains("siri") { return "waveform" }
        if s.contains("journal") { return "sparkles" }
        if s.contains("watch") { return "applewatch" }
        if s.contains("shortcut") { return "bolt.fill" }
        return "brain.head.profile"
    }

    private func sourceLabel(_ source: String) -> String {
        guard !source.isEmpty else { return "thought" }
        return source
            .replacingOccurrences(of: "_", with: " ")
            .localizedCapitalized
    }

    private func syncColor(_ state: IdeaSyncState) -> Color {
        switch state {
        case .localOnly: return .orange
        case .queued: return .yellow
        case .synced: return .green
        case .delegated: return .blue
        }
    }

    // MARK: - Time Formatting

    private func timeAgo(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString) else {
            return isoString
        }
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(interval / 60))m ago"
        case ..<86400: return "\(Int(interval / 3600))h ago"
        default: return "\(Int(interval / 86400))d ago"
        }
    }
}
#endif
