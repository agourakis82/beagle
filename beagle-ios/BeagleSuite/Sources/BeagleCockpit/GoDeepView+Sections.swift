//
//  GoDeepView+Sections.swift
//  BeagleCockpit
//
//  Rich card sections for GoDeepView: quick-take, quantum hypotheses,
//  executive synthesis, agentic quantitative simulation, and round-table debate.
//

import SwiftUI
import BeagleCore

extension GoDeepView {

    // MARK: - Agentic Quantitative Simulation Card (`OpenAIAgentsSessionClient`)

    var simulationSandboxCard: some View {
        GlassPanel(elevation: .raised, truth: store.isSimulating ? nil : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthObserved)

                    Text("Simulação & Execução Agêntica")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Spacer()

                    if store.isSimulating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.truthObserved)
                    } else {
                        TruthBadge(.observed, compact: true)
                    }
                }

                if let status = store.simulationStatusLine, !status.isEmpty {
                    Text(status)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                if let simOut = store.simulationOutput, !simOut.isEmpty {
                    Text(LocalizedStringKey(simOut))
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if store.isSimulating {
                    Text("Executando verificação quantitativa (PBPK / EDO / sensibilidade paramétrica) no sandbox agêntico…")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                }

                if !store.isSimulating {
                    HStack(spacing: BeagleSpacing.xs) {
                        TextField("Ajustar parâmetros ou testar cenário (ex.: ClCr 30 mL/min)…", text: $simulationSteerText)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                    .fill(Color.white.opacity(0.05))
                            )

                        Button {
                            let steer = simulationSteerText.trimmingCharacters(in: .whitespacesAndNewlines)
                            simulationSteerText = ""
                            Task {
                                await store.runSimulation(
                                    prompt: prompt,
                                    steeringInstruction: steer.isEmpty ? nil : steer
                                )
                            }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .frame(width: 32, height: 32)
                                .background(BeagleTheme.truthObserved.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Synthesis Card

    var synthesisCard: some View {
        GlassPanel(elevation: .raised, truth: store.synthesis != nil ? .observed : nil) {
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

                    Text("Síntese Executiva")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Spacer()

                    if store.isSynthesizing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.truthObserved)
                    } else {
                        TruthBadge(.observed, compact: true)
                    }
                }

                if let synthesis = store.synthesis, !synthesis.isEmpty {
                    Text(LocalizedStringKey(synthesis))
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .tint(BeagleTheme.truthObserved)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !store.isSynthesizing {
                        HStack(spacing: BeagleSpacing.sm) {
                            Button {
                                Task {
                                    savedToExocortex = true
                                    _ = await cognitive.captureThought(
                                        text: synthesis,
                                        source: "go-deeper"
                                    )
                                }
                            } label: {
                                HStack(spacing: BeagleSpacing.xxs + 1) {
                                    Image(systemName: savedToExocortex ? "checkmark.circle.fill" : "brain")
                                        .font(.system(size: 12))
                                    Text(savedToExocortex ? "Salvo no Exocórtex" : "Salvar no Exocórtex")
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

                            Menu {
                                Button {
                                    exportPDFDossier()
                                } label: {
                                    Label("PDF Científico (.pdf)", systemImage: "doc.richtext.fill")
                                }
                                Button {
                                    exportMarkdownDossier()
                                } label: {
                                    Label("Dossiê Markdown (.md)", systemImage: "doc.text.fill")
                                }
                                Button {
                                    Task { await exportBibTeXDossier() }
                                } label: {
                                    Label("BibTeX Verificado (.bib)", systemImage: "books.vertical.fill")
                                }
                                Divider()
                                Button {
                                    Task { await copyBibTeXToClipboard() }
                                } label: {
                                    Label("Copiar BibTeX", systemImage: "doc.on.doc")
                                }
                            } label: {
                                HStack(spacing: BeagleSpacing.xxs + 1) {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 12))
                                    Text("Exportar (.pdf / .md / .bib)")
                                        .font(BeagleFont.caption.font)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .padding(.horizontal, BeagleSpacing.sm + 2)
                                .padding(.vertical, BeagleSpacing.xs)
                                .background(
                                    Capsule()
                                        .fill(BeagleTheme.truthObserved.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if store.isSynthesizing {
                    Text("Integrando evidências das \(store.completedCount) lentes em paralelo...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                }
            }
        }
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .sensoryFeedback(.success, trigger: store.synthesis != nil)
    }

    // MARK: - Mesa-Redonda Section (RoundTableStore)

    var roundTableSection: some View {
        GlassPanel(elevation: .raised, truth: roundTable.result != nil ? .observed : nil) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(BeagleTheme.postureWarm)

                    Text("Mesa-Redonda Epistêmica")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Spacer()

                    if let pci = roundTable.result?.pciScore {
                        Text(String(format: "Φ %.2f", pci))
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.postureWarm)
                            .padding(.horizontal, BeagleSpacing.xs + 2)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(BeagleTheme.postureWarm.opacity(0.12)))
                    }

                    if roundTable.isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.postureWarm)
                    }
                }

                // Voice selector pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BeagleSpacing.xs) {
                        ForEach(RoundTableVoiceId.allCases) { voice in
                            let selected = roundTable.selectedVoices.contains(voice)
                            Button {
                                guard !roundTable.isRunning else { return }
                                if selected && roundTable.selectedVoices.count > 1 {
                                    roundTable.selectedVoices.remove(voice)
                                } else {
                                    roundTable.selectedVoices.insert(voice)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: voice.icon)
                                        .font(.system(size: 10))
                                    Text(voice.displayName)
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
                                .padding(.horizontal, BeagleSpacing.sm)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(selected ? BeagleTheme.postureWarm.opacity(0.18) : Color.white.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if roundTable.isRunning {
                    Text("Deliberando em paralelo entre \(roundTable.selectedVoices.count) vozes (Astra · Rosalind · Sol · Opus)...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                } else if let error = roundTable.error {
                    HStack {
                        Text(error)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.stateError)
                        Spacer()
                        Button("Repetir") {
                            Task { await roundTable.debate(prompt: prompt) }
                        }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.truthObserved)
                    }
                } else if let result = roundTable.result {
                    if let voices = result.voices {
                        ForEach(voices) { voice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.postureWarm)
                                Text(LocalizedStringKey(voice.content))
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .textSelection(.enabled)
                                    .lineSpacing(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    if let synthesis = result.synthesis, !synthesis.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)

                        Text("Síntese de Interferência")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .textCase(.uppercase)

                        Text(LocalizedStringKey(synthesis))
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }

                    HStack {
                        Button {
                            Task { await roundTable.debate(prompt: prompt) }
                        } label: {
                            Label("Debater novamente", systemImage: "arrow.clockwise")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.postureWarm)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Quick Take (on-device, instant)

    func quickTakeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 13))
                .foregroundStyle(BeagleTheme.truthObserved.opacity(0.7))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Leitura Inicial (On-Device)")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(text)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)
                    .italic()
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.truthObserved.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.truthObserved.opacity(0.06), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Quantum Hypotheses Visualization

    @ViewBuilder
    var quantumHypothesesView: some View {
        if store.quantumMode && !store.hypotheses.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                // Section header with wave icon
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("Superposição de Hipóteses")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                }

                // Amplitude bars — each hypothesis shown as a bar with height = amplitude
                ForEach(store.hypotheses) { hyp in
                    GlassPanel(elevation: hyp.isCollapsed ? .raised : .flush) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                            // Perspective label + probability badge
                            HStack {
                                Text(hyp.perspective)
                                    .font(BeagleFont.footnote.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Spacer()
                                Text("\(Int(hyp.probability * 100))%")
                                    .font(BeagleFont.data.font)
                                    .foregroundStyle(amplitudeColor(hyp.amplitude))
                            }

                            // Amplitude bar
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(amplitudeColor(hyp.amplitude).gradient)
                                    .frame(width: geo.size.width * hyp.amplitude)
                            }
                            .frame(height: 6)

                            // Hypothesis text (collapsed or full)
                            if !hyp.text.contains("[awaiting") && !hyp.text.contains("[aguardando") {
                                Text(hyp.text)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .lineLimit(hyp.isCollapsed ? 4 : 2)
                            }
                        }
                    }
                    .opacity(hyp.isCollapsed && hyp.amplitude < 0.2 ? 0.4 : 1.0)
                }

                // Interference results
                if let interference = store.interferenceResult {
                    if !interference.novelEmergent.isEmpty {
                        GlassPanel(elevation: .raised, truth: .observed) {
                            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                                HStack(spacing: BeagleSpacing.xs) {
                                    Image(systemName: "sparkles")
                                    Text("Insights Emergentes")
                                        .font(BeagleFont.footnote.font)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(BeagleTheme.truthObserved)

                                ForEach(interference.novelEmergent, id: \.self) { insight in
                                    Text("\u{2022} \(insight)")
                                        .font(BeagleFont.caption.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(BeagleMotion.slow, value: store.hypotheses.count)
        }
    }

    private func amplitudeColor(_ amplitude: Double) -> Color {
        if amplitude > 0.7 { return BeagleTheme.truthObserved }
        if amplitude > 0.3 { return BeagleTheme.postureWarm }
        return BeagleTheme.textTertiary
    }
}
