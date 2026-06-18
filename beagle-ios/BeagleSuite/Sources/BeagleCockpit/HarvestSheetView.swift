//
//  HarvestSheetView.swift
//  BeagleCockpit
//
//  Bottom sheet: send the full conversation to the cluster for analysis,
//  memory storage, or follow-up angle generation.
//

import SwiftUI
import BeagleCore

struct HarvestSheetView: View {
    @Bindable var conversation: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var harvestState: HarvestState = .idle

    enum HarvestState { case idle, loading, success(String), failure(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: BeagleSpacing.lg) {
                headerSection
                    .padding(.top, BeagleSpacing.md)

                switch harvestState {
                case .idle:
                    actionsSection
                case .loading:
                    ProgressView()
                        .tint(BeagleTheme.truthObserved)
                        .frame(maxWidth: .infinity)
                        .padding()
                case .success(let msg):
                    successView(msg)
                case .failure(let err):
                    failureView(err)
                }

                Spacer()
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .background(.ultraThinMaterial)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text("Send to Beagle")
                .font(BeagleFont.title3.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text("\(conversation.messages.count) exchanges · \(conversation.discussionProfile.label) thread")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: BeagleSpacing.sm) {
            harvestActionButton(
                icon: "brain.head.profile",
                title: "Deep Analysis",
                subtitle: "Extract insights + patterns",
                mode: "analyze"
            )
            harvestActionButton(
                icon: "square.and.arrow.down.on.square",
                title: "Save to Memory",
                subtitle: "Store as knowledge artifact",
                mode: "save"
            )
            harvestActionButton(
                icon: "arrow.triangle.branch",
                title: "Go Deeper on Thread",
                subtitle: "Generate follow-up angles",
                mode: "follow-up-angles"
            )
        }
    }

    private func harvestActionButton(icon: String, title: String, subtitle: String, mode: String) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            Task { await harvest(mode: mode) }
        } label: {
            HStack(spacing: BeagleSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BeagleFont.body.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func successView(_ message: String) -> some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(BeagleTheme.stateReady)
                .symbolEffect(.bounce, value: true)
            Text(message)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(BeagleTheme.truthObserved)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func failureView(_ error: String) -> some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(BeagleTheme.stateError)
            Text(error)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { harvestState = .idle }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    @MainActor
    private func harvest(mode: String) async {
        harvestState = .loading
        do {
            let result = try await conversation.harvestConversation(mode: mode)
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            harvestState = .success(result)
        } catch {
            harvestState = .failure(error.localizedDescription)
        }
    }
}
