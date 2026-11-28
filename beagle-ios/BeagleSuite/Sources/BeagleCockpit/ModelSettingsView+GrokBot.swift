//
//  ModelSettingsView+GrokBot.swift
//  BeagleCockpit
//
//  Configuração e teste da ponte bidirecional Beagle ↔ Grok Bot 1.0:
//  - Custom MCP Connector (`https://mcp.agourakis.com/mcp`) + Skill pronta para copiar
//  - Rotinas Webhook autenticadas (`Authorization: Bearer <key>` no Keychain)
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension ModelSettingsView {
    var grokBotCard: some View {
        GrokBotSettingsCard()
    }
}

private struct GrokBotSettingsCard: View {
    @State private var routines: [GrokBotRoutineTarget] = []
    @State private var selectedRoutineId: String = GrokBotRoutineTarget.primaryId
    @State private var routineName: String = "Rotina Principal"
    @State private var webhookURL: String = ""
    @State private var bearerKey: String = ""
    @State private var notes: String = ""
    @State private var includePhysio: Bool = true

    @State private var isTesting = false
    @State private var testStatusMessage: String?
    @State private var testSucceeded = false
    @State private var copiedPromptBanner = false
    @State private var recentDispatches: [GrokBotDispatchRecord] = []

    private var hasConfigured: Bool {
        GrokBotCredentials.hasConfiguredRoutine
    }

    var body: some View {
        GlassPanel(elevation: .flush, truth: hasConfigured ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                headerRow

                Text("Conecte o Grok Bot Desktop (xAI / SpaceXSI) ao Beagle nos dois sentidos: Webhook autenticado para delegar rotinas e conector MCP remoto (`mcp.agourakis.com/mcp`) para o Grok Bot ler seu Exocórtex.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineSpacing(1)

                if routines.count > 1 {
                    routinePickerRow
                }

                routineFormFields
                actionButtonsRow

                if let testStatusMessage {
                    HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(testSucceeded ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                        Text(testStatusMessage)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(testSucceeded ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }

                if let latest = recentDispatches.first {
                    Divider().opacity(0.25)
                    HStack(spacing: BeagleSpacing.xs) {
                        Circle()
                            .fill(latest.ok ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                            .frame(width: 6, height: 6)
                        Text("Último envio (\(latest.routineName)): \(latest.summary)")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityIdentifier("settings.grokBotCard")
        .onAppear {
            loadStateFromStore()
        }
    }

    private var headerRow: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(hasConfigured ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
            Text("Grok Bot (Webhook Routines & MCP)")
                .font(BeagleFont.footnote.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Spacer()
            Text(hasConfigured ? "\(routines.count) rotina\(routines.count == 1 ? "" : "s")" : "Opcional")
                .font(BeagleFont.caption2.font.monospaced())
                .foregroundStyle(hasConfigured ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
        }
    }

    private var routinePickerRow: some View {
        HStack {
            Text("Rotina ativa")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Picker("Rotina Grok Bot", selection: $selectedRoutineId) {
                ForEach(routines) { item in
                    Text(item.name).tag(item.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedRoutineId) { _, newId in
                selectRoutine(id: newId)
            }
        }
    }

    private var routineFormFields: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs + 2) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nome da Routine")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                TextField("Rotina Principal", text: $routineName)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .padding(BeagleSpacing.xs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.5))
                    )
                    .onChange(of: routineName) { _, _ in persistCurrentRoutine() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Webhook URL (`POST to` do Grok Bot)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                TextField("https://.../webhooks/routines/...", text: $webhookURL)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .autocorrectionDisabled(true)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .padding(BeagleSpacing.xs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.5))
                    )
                    .onChange(of: webhookURL) { _, _ in persistCurrentRoutine() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bearer Key (`Authorization: Bearer <key>`, salvo no Keychain)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                SecureField("grok_webhook_key_...", text: $bearerKey)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .padding(BeagleSpacing.xs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.5))
                    )
                    .onChange(of: bearerKey) { _, _ in persistCurrentRoutine() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Quando acionar esta rotina (opcional)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                TextField("Ex: triagem diária, pesquisa web contínua, agenda", text: $notes)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .padding(BeagleSpacing.xs + 2)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.4))
                    )
                    .onChange(of: notes) { _, _ in persistCurrentRoutine() }
            }

            Toggle(isOn: $includePhysio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anexar pulso Fisioma & Clima Espacial (Kp)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Envia prontidão/HRV resumida quando disparado pela Síntese Matinal.")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .tint(BeagleTheme.truthObserved)
            .onChange(of: includePhysio) { _, _ in persistCurrentRoutine() }
        }
    }

    private var actionButtonsRow: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.sm) {
                Button {
                    Task { await runWebhookPing() }
                } label: {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isTesting ? "Testando…" : "Testar Webhook")
                            .font(BeagleFont.caption.font.weight(.medium))
                    }
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule().fill(BeagleTheme.surface1.opacity(0.65))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTesting)

                Button {
                    addNewRoutine()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Nova Rotina")
                            .font(BeagleFont.caption.font.weight(.medium))
                    }
                    .foregroundStyle(BeagleTheme.truthRemembered)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule().fill(BeagleTheme.surface1.opacity(0.55))
                    )
                }
                .buttonStyle(.plain)

                if selectedRoutineId != GrokBotRoutineTarget.primaryId && routines.count > 1 {
                    Button {
                        removeSelectedRoutine()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(BeagleTheme.stateError)
                            .padding(7)
                            .background(
                                Circle().fill(BeagleTheme.surface1.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remover rotina selecionada")
                }
            }

            Button {
                copyMCPAndSkillPrompt()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedPromptBanner ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(copiedPromptBanner
                         ? "Prompt MCP & Skill copiado para a Área de Transferência!"
                         : "Copiar Prompt do Connector MCP & Skill")
                        .font(BeagleFont.caption.font.weight(.medium))
                }
                .foregroundStyle(copiedPromptBanner ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(
                    Capsule().fill(BeagleTheme.surface1.opacity(0.65))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    // MARK: - State Synchronization

    private func loadStateFromStore() {
        let saved = GrokBotCredentials.routines
        if saved.isEmpty {
            let initial = GrokBotRoutineTarget(
                id: GrokBotRoutineTarget.primaryId,
                name: "Rotina Principal",
                webhookURLString: "",
                notes: ""
            )
            routines = [initial]
            selectedRoutineId = initial.id
            selectRoutine(id: initial.id)
        } else {
            routines = saved
            let preferredId = saved.first(where: { $0.id == selectedRoutineId })?.id ?? saved[0].id
            selectedRoutineId = preferredId
            selectRoutine(id: preferredId)
        }
        recentDispatches = GrokBotCredentials.recentDispatches
    }

    private func selectRoutine(id: String) {
        guard let target = routines.first(where: { $0.id == id }) else { return }
        routineName = target.name
        webhookURL = target.webhookURLString
        notes = target.notes
        includePhysio = target.includePhysioContext
        bearerKey = GrokBotCredentials.bearerKey(forRoutineId: target.id)
        testStatusMessage = nil
    }

    private func persistCurrentRoutine() {
        let updated = GrokBotRoutineTarget(
            id: selectedRoutineId,
            name: routineName,
            webhookURLString: webhookURL,
            notes: notes,
            includePhysioContext: includePhysio
        )
        GrokBotCredentials.upsertRoutine(updated, bearerKey: bearerKey)
        routines = GrokBotCredentials.routines
    }

    private func addNewRoutine() {
        let newTarget = GrokBotRoutineTarget(
            id: "routine-\(UUID().uuidString.prefix(8).lowercased())",
            name: "Rotina \(routines.count + 1)",
            webhookURLString: "",
            notes: "",
            includePhysioContext: true
        )
        GrokBotCredentials.upsertRoutine(newTarget, bearerKey: "")
        routines = GrokBotCredentials.routines
        selectedRoutineId = newTarget.id
        selectRoutine(id: newTarget.id)
    }

    private func removeSelectedRoutine() {
        let removingId = selectedRoutineId
        GrokBotCredentials.removeRoutine(id: removingId)
        loadStateFromStore()
    }

    private func runWebhookPing() async {
        persistCurrentRoutine()
        isTesting = true
        testStatusMessage = nil
        let target = GrokBotRoutineTarget(
            id: selectedRoutineId,
            name: routineName,
            webhookURLString: webhookURL,
            notes: notes,
            includePhysioContext: includePhysio
        )
        let result = await GrokBotBridgeClient.shared.pingRoutine(target, bearerKey: bearerKey)
        isTesting = false
        testSucceeded = result.ok
        if result.ok {
            let statusStr = result.httpStatus.map { "HTTP \($0)" } ?? "OK"
            let extra = result.responsePreview.isEmpty ? "" : " · \(result.responsePreview)"
            testStatusMessage = "Conectado (\(statusStr)) à rotina '\(result.routineName)'\(extra)"
        } else {
            testStatusMessage = result.errorMessage ?? "Falha ao testar webhook."
        }
        recentDispatches = GrokBotCredentials.recentDispatches
    }

    private func copyMCPAndSkillPrompt() {
        let prompt = GrokBotCredentials.beagleMCPSetupPrompt(includeCockpitToken: false)
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = prompt
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        #endif
        copiedPromptBanner = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                copiedPromptBanner = false
            }
        }
    }
}
