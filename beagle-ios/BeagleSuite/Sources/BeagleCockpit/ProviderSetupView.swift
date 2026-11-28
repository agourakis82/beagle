//
//  ProviderSetupView.swift
//  BeagleCockpit
//
//  In-app provider Set-up form for a single Work-tab lane/slot. Collects the
//  base URL, API key, and model, then persists them SERVER-SIDE via
//  CockpitClient.setProviderConfig. The API key never touches on-device
//  storage (no @AppStorage / UserDefaults) — it lives only in @State for the
//  duration of the sheet and is sent once to the workspace agent.
//

import SwiftUI
import BeagleCore

/// Immutable target describing which lane/slot the sheet configures, seeded
/// from the lane's AgentRole so the form can prefill base URL and model.
struct ProviderSetupTarget: Identifiable, Equatable {
    let slug: String
    let role: String
    let title: String
    let subtitle: String?
    let slots: [AgentProviderSlot]
    let setupReason: String?

    var id: String { "\(slug)/\(role)" }

    /// Slots that can actually be configured with an API key + base URL.
    /// PATH-based (cli) and pty lanes do not surface this form.
    var configurableSlots: [AgentProviderSlot] {
        slots.filter { slot in
            switch slot.runtime {
            case "pty", "cli": return false
            default: return true
            }
        }
    }
}

@MainActor
struct ProviderSetupView: View {
    let target: ProviderSetupTarget
    /// Called after a successful save so the caller can re-fetch the registry
    /// and flip the lane to Ready.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSlotId: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(target: ProviderSetupTarget, onSaved: @escaping () -> Void = {}) {
        self.target = target
        self.onSaved = onSaved
        let slots = target.configurableSlots.isEmpty ? target.slots : target.configurableSlots
        let first = slots.first
        _selectedSlotId = State(initialValue: first?.id ?? "")
        _baseURL = State(initialValue: first?.baseUrl ?? "")
        _model = State(initialValue: first?.modelId ?? "")
    }

    private var slots: [AgentProviderSlot] {
        let configurable = target.configurableSlots
        return configurable.isEmpty ? target.slots : configurable
    }

    private var selectedSlot: AgentProviderSlot? {
        slots.first(where: { $0.id == selectedSlotId }) ?? slots.first
    }

    /// A self-hosted / local provider (runtime "*_or_local") is satisfied by a
    /// base URL alone and needs no API key; an external API slot still requires one.
    private var apiKeyOptional: Bool {
        (selectedSlot?.runtime ?? "").contains("local")
    }

    private var canSave: Bool {
        !isSaving
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (apiKeyOptional || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    header

                    if slots.count > 1 {
                        modelPicker
                    }

                    field(
                        title: "Base URL",
                        hint: "The provider's OpenAI-compatible endpoint."
                    ) {
                        TextField("https://api.example.com/v1", text: $baseURL)
                            .textFieldStyle(.plain)
                            #if !os(macOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled(true)
                            .modifier(SetupFieldChrome())
                    }

                    field(
                        title: apiKeyOptional ? "API key (optional)" : "API key",
                        hint: apiKeyOptional
                            ? "Leave blank for a local endpoint. Stored only on the workspace, never on this device."
                            : "Stored only on the workspace, never on this device."
                    ) {
                        SecureField("sk-…", text: $apiKey)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled(true)
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .modifier(SetupFieldChrome())
                    }

                    if slots.count <= 1 {
                        field(
                            title: "Model",
                            hint: "Override the default model identifier if needed."
                        ) {
                            TextField(selectedSlot?.modelId ?? "model-id", text: $model)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled(true)
                                #if !os(macOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .modifier(SetupFieldChrome())
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.stateError)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                BeagleTheme.stateError.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: BeagleRadius.md)
                            )
                    }

                    saveButton
                }
                .padding(BeagleSpacing.lg)
            }
            .background(BeagleTheme.surface0.ignoresSafeArea())
            .navigationTitle("Set up provider")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(target.title)
                .font(BeagleFont.title3.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            if let subtitle = target.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            if let reason = target.setupReason, !reason.isEmpty {
                Text(reason)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.postureWarm)
            }
        }
    }

    private var modelPicker: some View {
        field(title: "Model", hint: "Pick the provider slot to configure.") {
            Picker("Model", selection: $selectedSlotId) {
                ForEach(slots) { slot in
                    Text(slot.title).tag(slot.id)
                }
            }
            .pickerStyle(.menu)
            .tint(BeagleTheme.truthObserved)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SetupFieldChrome())
            .onChange(of: selectedSlotId) { _, newValue in
                if let slot = slots.first(where: { $0.id == newValue }) {
                    baseURL = slot.baseUrl ?? baseURL
                    model = slot.modelId
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: { Task { await save() } }) {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BeagleTheme.surface0)
                } else {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isSaving ? "Saving…" : "Save & verify")
                    .font(BeagleFont.body.font)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (canSave ? BeagleTheme.truthObserved : BeagleTheme.truthObserved.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: BeagleRadius.md)
            )
            .foregroundStyle(BeagleTheme.surface0)
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    @ViewBuilder
    private func field<Content: View>(
        title: String,
        hint: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textSecondary)
            content()
            if let hint {
                Text(hint)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func save() async {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, apiKeyOptional || !trimmedKey.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        let result = await CockpitClient.shared.setProviderConfig(
            slug: target.slug,
            role: target.role,
            slot: selectedSlot?.id,
            baseURL: trimmedBase,
            apiKey: trimmedKey,
            model: trimmedModel.isEmpty ? nil : trimmedModel
        )

        isSaving = false

        if result.value != nil {
            // Drop the key from memory as soon as it has been handed off.
            apiKey = ""
            onSaved()
            dismiss()
        } else {
            errorMessage = result.error
                ?? "Could not reach the workspace to save these credentials."
        }
    }
}

/// Shared chrome for the form's input controls so every field reads the same.
private struct SetupFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(BeagleFont.body.font)
            .foregroundStyle(BeagleTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                BeagleTheme.surface1.opacity(0.7),
                in: RoundedRectangle(cornerRadius: BeagleRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .stroke(BeagleTheme.hairline, lineWidth: 1)
            )
    }
}
