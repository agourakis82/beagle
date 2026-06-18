//
//  AgentPlanCard.swift
//  BeagleCockpit
//
//  Sheet that appears when ConversationStore.pendingPlan != nil.
//  User can adjust per-step depth sliders before confirming execution.
//
import SwiftUI
import BeagleCore

struct AgentPlanCard: View {
    @Bindable var conversation: ConversationStore
    @Environment(\.dismiss) private var dismiss

    @State private var depths: [String: Double] = [:]
    @State private var isConfirming = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = conversation.pendingPlan {
                    planContent(plan)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        conversation.pendingPlan = nil
                        dismiss()
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .onAppear { initDepths() }
    }

    private func planContent(_ plan: AgentPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(plan.title)
                .font(BeagleFont.subheadline.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.md)
                .padding(.bottom, BeagleSpacing.sm)

            ScrollView {
                VStack(spacing: BeagleSpacing.sm) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { idx, step in
                        stepRow(step: step, index: idx)
                    }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.bottom, BeagleSpacing.lg)
            }

            Divider()
                .padding(.horizontal, BeagleSpacing.lg)

            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                Task { await confirmAndDismiss() }
            } label: {
                HStack {
                    if isConfirming {
                        ProgressView().tint(.white)
                    } else {
                        Text("Run Plan").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BeagleTheme.truthObserved, in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isConfirming)
            .padding(BeagleSpacing.lg)
        }
    }

    private func stepRow(step: PlanStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Text("\(index + 1)")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .frame(width: 18)
                Text(step.label)
                    .font(BeagleFont.body.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            ToolDepthSlider(
                labelMin: step.depthLabelMin,
                labelMax: step.depthLabelMax,
                value: Binding(
                    get: { depths[step.id] ?? Double(step.depthDefault) },
                    set: { depths[step.id] = $0 }
                )
            )
            .padding(.leading, 26)
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.surface1.opacity(0.5))
        )
    }

    private func initDepths() {
        guard let plan = conversation.pendingPlan else { return }
        depths = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.id, Double($0.depthDefault)) })
    }

    private func confirmAndDismiss() async {
        isConfirming = true
        let intDepths = depths.mapValues { Int($0) }
        await conversation.confirmPlan(depths: intDepths)
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        isConfirming = false
        dismiss()
    }
}
