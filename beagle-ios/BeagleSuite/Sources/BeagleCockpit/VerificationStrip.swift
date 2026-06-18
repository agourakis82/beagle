//
//  VerificationStrip.swift
//  BeagleCockpit
//
//  iOS: inline collapsible below the assistant bubble (activated by long-press context menu).
//  macOS: shown in the sidebar panel when the user taps an assistant bubble.
//
import SwiftUI
import BeagleCore

struct VerificationStrip: View {
    let result: VerificationResult
    let profileHue: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: BeagleSpacing.xs) {
                    Circle()
                        .fill(conflictColor)
                        .frame(width: 7, height: 7)
                    Text(summaryLabel)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, BeagleSpacing.sm)
                expandedContent
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.bottom, BeagleSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.sm)
                .fill(BeagleTheme.surface1.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.sm)
                        .strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
                )
        )
        .onAppear {
            if result.temporalConflict != nil { isExpanded = true }
        }
    }

    private var summaryLabel: String {
        let n = result.sources.count
        let src = n == 1 ? "1 source" : "\(n) sources"
        if result.temporalConflict != nil {
            return "\(src) · ⚠ Memory conflict"
        }
        let unverified = result.sources.filter { $0.confidence == .unverified }.count
        if unverified > 0 {
            return "\(src) · \(unverified) unverified"
        }
        return src
    }

    private var conflictColor: Color {
        if result.temporalConflict != nil { return BeagleTheme.stateError }
        if result.sources.contains(where: { $0.confidence == .unverified }) { return BeagleTheme.textTertiary }
        return BeagleTheme.stateReady
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sources")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                FlowLayout(spacing: 4) {
                    ForEach(result.sources) { item in
                        EvidenceTag(item: item)
                    }
                }
            }

            if let conflict = result.temporalConflict {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("Memory conflict · \(conflict.daysAgo)d ago", systemImage: "exclamationmark.triangle.fill")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.stateError)
                    Text(conflict.summary)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, BeagleSpacing.xs)
    }
}

