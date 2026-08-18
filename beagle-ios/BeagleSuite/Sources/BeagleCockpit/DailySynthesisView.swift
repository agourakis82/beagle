//
//  DailySynthesisView.swift
//  BeagleCockpit
//
//  "Sintetizar hoje" — one tap gathers everything captured since local midnight
//  and cross-references it against the ORC/HSN/Sounio corpus via the same
//  grounded deep-think path Go Deeper uses. Pure client-side: builds the
//  prompt from local SwiftData captures, streams the cluster's answer, and
//  optionally saves the synthesis back into the exocortex.
//
//  Style mirrors GoDeepView's synthesis card: GlassPanel, PresencePill,
//  TruthBadge, streaming text with a save affordance once it lands.
//

import SwiftUI
import BeagleCore

struct DailySynthesisView: View {
    let captureLines: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(CognitiveStore.self) private var cognitive

    @State private var streamedText = ""
    @State private var isStreaming = false
    @State private var hasStarted = false
    @State private var streamError: String?
    @State private var savedToExocortex = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    header
                    synthesisPanel
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.sm)
                .padding(.bottom, BeagleSpacing.jumbo)
            }
            .background { BeagleTheme.surface0.ignoresSafeArea() }
            .navigationTitle("Sintetizar hoje")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: closePlacement) {
                    Button("Fechar") { dismiss() }
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            await runSynthesis()
        }
    }

    private var closePlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarLeading
        #endif
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthRemembered)
                Text("Hoje")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                PresencePill(
                    label: "\(captureLines.count) captura\(captureLines.count == 1 ? "" : "s")",
                    systemImage: "tray.full",
                    tint: BeagleTheme.truthDeclared
                )
            }

            Text("Cruzando suas capturas de hoje contra ORC/HSN/Sounio.")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Synthesis panel

    private var synthesisPanel: some View {
        GlassPanel(elevation: .raised, truth: isStreaming ? nil : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BeagleTheme.truthObserved, BeagleTheme.truthRemembered],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Text("Síntese")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if isStreaming {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.truthObserved)
                    } else if !streamedText.isEmpty {
                        TruthBadge(.observed, compact: true)
                    }
                }

                if isStreaming && streamedText.isEmpty {
                    Text("Pensando fundo — cruzando com ORC/HSN/Sounio...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                }

                if !streamedText.isEmpty {
                    Text(streamedText)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let streamError, streamedText.isEmpty {
                    Text(streamError)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }

                if !isStreaming && !streamedText.isEmpty {
                    HStack(spacing: BeagleSpacing.sm) {
                        Button {
                            Task {
                                savedToExocortex = true
                                _ = await cognitive.captureThought(
                                    text: streamedText,
                                    source: "daily-synthesis"
                                )
                            }
                        } label: {
                            HStack(spacing: BeagleSpacing.xxs + 1) {
                                Image(systemName: savedToExocortex ? "checkmark.circle.fill" : "brain")
                                    .font(.system(size: 12))
                                Text(savedToExocortex ? "Salvo" : "Salvar na memória")
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered)
                            .padding(.horizontal, BeagleSpacing.sm + 2)
                            .padding(.vertical, BeagleSpacing.xs)
                            .background(
                                Capsule()
                                    .fill((savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered).opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(savedToExocortex)
                        .sensoryFeedback(.success, trigger: savedToExocortex)

                        Spacer()
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: !isStreaming && !streamedText.isEmpty)
    }

    // MARK: - Prompt + streaming

    private func buildPrompt() -> String {
        let lines = captureLines
            .map { "- \($0)" }
            .joined(separator: "\n")
        return """
        Aqui estão minhas capturas de hoje:
        \(lines)

        Sintetize contra ORC/HSN/Sounio: (1) o que conecta; (2) o que é novo; \
        (3) o que contradiz meu trabalho anterior; (4) 2-3 follow-ups concretos. \
        Se não houver material para algum ponto, diga explicitamente em vez de inventar.
        """
    }

    private func runSynthesis() async {
        guard !captureLines.isEmpty else {
            streamError = "Nenhuma captura hoje ainda."
            return
        }
        isStreaming = true
        streamedText = ""
        streamError = nil

        let stream = BeagleClient.shared.chatStream(
            prompt: buildPrompt(),
            projectSlug: cognitive.activeProjectSlug ?? "sounio",
            discussionProfile: .cluster,
            flowState: cognitive.flowState,
            deepThink: true
        )

        do {
            for try await token in stream {
                streamedText += token
            }
        } catch {
            if streamedText.isEmpty {
                streamError = error.localizedDescription
            }
        }
        isStreaming = false
    }
}
