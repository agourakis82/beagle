//
//  ModelSettingsView+CatalogAndStatus.swift
//  BeagleCockpit
//
//  LLM load-state status card, diagnostics navigation link, grouped HuggingFace
//  on-device model catalog, and reactive MeshGradient backdrop.
//

import SwiftUI
import BeagleCore

extension ModelSettingsView {
    // MARK: - Status Card (state machine)

    var statusCard: some View {
        GlassPanel(elevation: .raised, truth: statusTruth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Status")

                switch llm.loadState {
                case .idle:
                    idleStatus

                case .downloading(let progress):
                    downloadingStatus(progress)

                case .loading:
                    loadingStatus

                case .ready:
                    readyStatus

                case .error(let msg):
                    errorStatus(msg)
                }
            }
        }
        .animation(BeagleMotion.snappy, value: llm.loadState == .ready)
    }

    private var statusTruth: TruthMode {
        switch llm.loadState {
        case .ready: return .observed
        case .error: return .stale
        default: return .declared
        }
    }

    private var idleStatus: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 14))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text("No model loaded")
                .font(BeagleFont.subheadline.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private func downloadingStatus(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.truthRemembered)
                    .symbolEffect(.pulse, isActive: true)
                Text("Downloading \(selectedModel.displayName)")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(BeagleFont.dataProminent.font)
                    .foregroundStyle(BeagleTheme.truthRemembered)
            }

            // Custom progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [BeagleTheme.truthRemembered, BeagleTheme.truthObserved],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(4, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
    }

    private var loadingStatus: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 14))
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.pulse, isActive: true)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(selectedModel.displayName)
                    .font(BeagleFont.subheadline.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text(loadPhase.isEmpty ? Self.loadMessages[0] : loadPhase)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.postureWarm)
                    .contentTransition(.numericText())
                    .animation(BeagleMotion.normal, value: loadPhase)
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
                .tint(BeagleTheme.postureWarm)
        }
        .task {
            loadPhaseIndex = 0
            while !Task.isCancelled {
                loadPhase = Self.loadMessages[loadPhaseIndex % Self.loadMessages.count]
                loadPhaseIndex += 1
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    private var readyStatus: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(BeagleTheme.truthObserved)

                VStack(alignment: .leading, spacing: 2) {
                    Text(llm.currentModel?.displayName ?? "Model")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("\(llm.currentModel?.parameterCount ?? "") · \(llm.currentModel?.sizeDescription ?? "") · on-device")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                Spacer()

                if llm.isGenerating {
                    Text(String(format: "%.0f tok/s", llm.tokensPerSecond))
                        .font(BeagleFont.dataProminent.font)
                        .fontWeight(.bold)
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }

            Button {
                llm.unload()
            } label: {
                Label("Unload Model", systemImage: "xmark.circle")
            }
            .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))
        }
        .sensoryFeedback(.success, trigger: llm.isReady)
    }

    private func errorStatus(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.stateError)
                Text(msg)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.stateError)
                    .lineLimit(3)
            }

            Button {
                Task { await llm.load(selectedModel) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
        }
    }

    // MARK: - Diagnostics link

    var diagnosticsLink: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(BeagleTheme.truthObserved.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 15))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics")
                        .font(BeagleFont.subheadline.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Run all real-device tests automatically")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .frame(minHeight: 54)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthObserved.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.diagnosticsLink")
    }

    // MARK: - Model Catalog (grouped by category)

    var catalogSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
            ForEach(ModelCategory.allCases, id: \.rawValue) { category in
                let models = OnDeviceModel.models(in: category)
                if !models.isEmpty {
                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        HStack(spacing: BeagleSpacing.xs) {
                            Image(systemName: categoryIcon(category))
                                .font(.system(size: 13))
                                .foregroundStyle(categoryColor(category))
                            Text(category.rawValue)
                                .font(BeagleFont.headline.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                        }

                        Text(categoryDescription(category))
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineSpacing(1)

                        ForEach(models) { model in
                            let isActive = llm.currentModel == model && llm.isReady
                            let isDisabled = !model.fitsOnThisDevice || llm.loadState == .loading

                            Button {
                                selectedModel = model
                                Task { await llm.load(model) }
                            } label: {
                                modelCard(model, isActive: isActive)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDisabled)
                            .opacity(isDisabled ? 0.5 : 1.0)
                            .sensoryFeedback(.impact(weight: .medium), trigger: selectedModel == model)
                        }
                    }
                }
            }

            Text("Models download from HuggingFace on first use. WiFi recommended.")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .padding(.top, BeagleSpacing.xxs)
        }
    }

    private func categoryIcon(_ cat: ModelCategory) -> String {
        switch cat {
        case .reasoning:    return "brain.head.profile"
        case .code:         return "curlybraces"
        case .medical:      return "cross.vial.fill"
        case .exotic:       return "sparkle"
        case .ssm:          return "waveform.path"
        case .multilingual: return "globe"
        case .fast:         return "hare"
        case .rnn:          return "arrow.trianglehead.2.clockwise"
        case .diffusion:    return "aqi.medium"
        case .moe:          return "square.grid.3x3"
        }
    }

    private func categoryColor(_ cat: ModelCategory) -> Color {
        switch cat {
        case .reasoning:    return BeagleTheme.truthObserved
        case .code:         return BeagleTheme.truthRemembered
        case .medical:      return BeagleTheme.stateError
        case .exotic:       return Color(hue: 300/360, saturation: 0.6, brightness: 0.9) // magenta
        case .ssm:          return BeagleTheme.postureWarm
        case .multilingual: return BeagleTheme.textData
        case .fast:         return BeagleTheme.truthDeclared
        case .rnn:          return Color(hue: 170/360, saturation: 0.7, brightness: 0.8) // teal
        case .diffusion:    return Color(hue: 260/360, saturation: 0.5, brightness: 0.9) // violet
        case .moe:          return Color(hue: 40/360, saturation: 0.8, brightness: 0.9) // amber
        }
    }

    private func categoryDescription(_ cat: ModelCategory) -> String {
        switch cat {
        case .reasoning:
            return "Mathematical proofs, scientific analysis, step-by-step derivations. Use for deep thinking."
        case .code:
            return "Function generation, structured output (JSON/YAML), technical writing. Use for building."
        case .medical:
            return "Fine-tuned on PubMed, medical guidelines, clinical literature. Understands pharmacokinetics, drug interactions, PBPK terminology."
        case .exotic:
            return "Models trained with different data, different cultures, different assumptions. When you need to think sideways, try a mind that was shaped differently."
        case .ssm:
            return "State Space Models — O(n) complexity, infinite context without memory blowup. The future of on-device LLM."
        case .multilingual:
            return "Strong Portuguese, French, Spanish alongside English. Use for multilingual drafting."
        case .fast:
            return "Quick answers, low memory, fast loading. Use as fallback or for simple questions."
        case .rnn:
            return "Recurrent architectures — RWKV, xLSTM. Infinite context, constant memory, biological memory dynamics."
        case .diffusion:
            return "Diffusion language models — generate text via denoising, not autoregression. Fundamentally different thinking."
        case .moe:
            return "Mixture of Experts — sparse activation means huge knowledge with small compute. Only a fraction of parameters fire per token."
        }
    }

    private func modelCard(_ model: OnDeviceModel, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            HStack(spacing: BeagleSpacing.xs) {
                Text(model.displayName)
                    .font(BeagleFont.body.font)
                    .fontWeight(.medium)
                    .foregroundStyle(model.fitsOnThisDevice ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)

                Text(model.parameterCount)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                Text(model.tagline)
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.medium)
                    .foregroundStyle(categoryColor(model.category))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(categoryColor(model.category).opacity(0.1)))

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }

            Text(model.bestFor)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
                .lineSpacing(1)

            HStack(spacing: BeagleSpacing.sm) {
                Text(model.sizeDescription)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textTertiary)

                if !model.fitsOnThisDevice {
                    Text("too large for this device")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.stateError)
                } else if model.requiresHFToken && hfToken.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 8))
                        Text("needs HF token")
                    }
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.postureWarm)
                } else if model == .recommended {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text("recommended")
                    }
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.truthObserved)
                }

                Text("min \(model.minimumRAMGB) GB RAM")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(isActive ? BeagleTheme.truthObserved.opacity(0.06) : BeagleTheme.surface1.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(
                    isActive ? BeagleTheme.truthObserved.opacity(0.2) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Helpers

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .fontWeight(.medium)
            .foregroundStyle(BeagleTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    func metricRow(_ label: String, value: String, color: Color = BeagleTheme.textData) -> some View {
        HStack {
            Text(label)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Text(value)
                .font(BeagleFont.data.font)
                .foregroundStyle(color)
        }
    }
}


// MARK: - Model Gradient

/// Background reacts to model load state:
/// - Loading/downloading: warm gold glow
/// - Ready: teal glow (neural engine active)
/// - Error: subtle red tint
/// - Idle: deep void
struct ModelGradient: View {
    let loadState: LocalLLMEngine.LoadState
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: loadState == .ready)
        .onAppear {
            guard !reduceMotion, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)

        let tealIntensity: Double
        let goldIntensity: Double

        switch loadState {
        case .ready:
            tealIntensity = 0.25
            goldIntensity = 0.0
        case .loading, .downloading:
            tealIntensity = 0.0
            goldIntensity = 0.20
        case .error:
            tealIntensity = 0.0
            goldIntensity = 0.0
        case .idle:
            tealIntensity = 0.0
            goldIntensity = 0.0
        }

        return [
            BeagleTheme.truthObserved.opacity(tealIntensity),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(goldIntensity),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}
