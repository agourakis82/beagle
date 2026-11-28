//
//  ModelSettingsView.swift
//  BeagleCockpit
//
//  On-device model management — download, select, load, unload.
//
//  Premium patterns:
//   - GlassPanel cards instead of system List
//   - Living background reacts to model state (loading=warm, ready=teal)
//   - Styled download progress with percentage
//   - Rotating thinking messages during model load
//   - Haptic on model ready
//   - Error panels with retry
//

import SwiftUI
import BeagleCore

struct ModelSettingsView: View {
    @State var llm = LocalLLMEngine.shared
    @State var selectedModel: OnDeviceModel = .recommended
    @State var loadPhase = ""
    @State var loadPhaseIndex = 0
    @AppStorage("hfToken") var hfToken = ""
    @State private var showTokenInput = false
    @State private var openAIKey = DirectBrainCredentials.openAIKey
    @AppStorage("beagle.direct.openai.model") private var openAIModel = OpenAIModelCatalog.defaultFlagshipModel
    @AppStorage("beagle.direct.openai.reasoningEffort") private var openAIReasoningEffort = OpenAIReasoningEffort.auto.rawValue
    @AppStorage("beagle.direct.openai.nativeWebSearch") private var enableNativeWebSearch = true
    @AppStorage("beagle.direct.openai.toolSearch") private var enableToolSearch = true
    @State private var anthropicKey = DirectBrainCredentials.anthropicKey
    @AppStorage("beagle.moe.keepLocalLoaded") private var keepLocalLoaded = true
    @AppStorage(CompanionVoice.enginePreferenceKey) private var voiceEngineRaw = CompanionVoiceEnginePreference.auto.rawValue
    @AppStorage(CompanionLiveSessionTransportMode.storageKey) private var liveTransportRaw = CompanionLiveSessionTransportMode.auto.rawValue
    @AppStorage(CompanionVoice.openAIVoiceKey) private var openAIVoice = "marin"
    @AppStorage(CompanionVoice.autoSpeakModeKey) private var autoSpeakRaw = CompanionAutoSpeakMode.whenSpoken.rawValue
    @State private var previewVoice = CompanionVoice()
    @State private var mcpToolsCount = 0
    @State private var mcpChecking = false

    static let loadMessages = [
        String(localized: "Initializing neural engine..."),
        String(localized: "Loading model weights..."),
        String(localized: "Compiling inference graph..."),
        String(localized: "Warming token pipeline..."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                directBrainAndMCPCard
                voiceSettingsCard
                deviceCard
                hfTokenCard
                statusCard
                diagnosticsLink
                catalogSection
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
            .padding(.bottom, BeagleSpacing.jumbo)
        }
        .accessibilityIdentifier("settings.scrollView")
        .background { ModelGradient(loadState: llm.loadState) }
        .navigationTitle("Cérebro · MoE · Voz")
        .onChange(of: openAIKey) { _, newValue in
            DirectBrainCredentials.openAIKey = newValue
        }
        .onChange(of: anthropicKey) { _, newValue in
            DirectBrainCredentials.anthropicKey = newValue
        }
        .onDisappear {
            previewVoice.parar()
        }
        .task {
            openAIKey = DirectBrainCredentials.openAIKey
            openAIModel = DirectBrainCredentials.openAIModel
            anthropicKey = DirectBrainCredentials.anthropicKey
            mcpChecking = true
            let tools = await BeagleMCPClient.shared.availableTools()
            mcpToolsCount = tools.count
            mcpChecking = false
        }
    }

    // MARK: - Direct Brain (OpenAI GPT-6.2 / Claude) + MoE + Beagle MCP Card

    private var directBrainAndMCPCard: some View {
        GlassPanel(elevation: .flush, truth: DirectBrainCredentials.hasOpenAI ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13))
                        .foregroundStyle(DirectBrainCredentials.hasOpenAI ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    Text("Cérebro MoE · OpenAI GPT-6.2 · Beagle MCP")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    Text(mcpChecking ? "MCP…" : "MCP · \(mcpToolsCount + 16) tools")
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.truthObserved)
                }

                Text("Combina o modelo local sem censura (abliterated on-device) com a família GPT-6.2 (Prompt Caching em `developer`, `tool_search` sob demanda em namespaces, `web_search` nativa e Agents API) + GraphRAG++ do cluster.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineSpacing(1)

                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI API Key (sk-...)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    SecureField("sk-proj-...", text: $openAIKey)
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .padding(BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(BeagleTheme.surface1.opacity(0.6))
                        )
                }

                HStack {
                    Text("Modelo OpenAI Principal")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Modelo OpenAI", selection: $openAIModel) {
                        ForEach(OpenAIModelCatalog.presets) { preset in
                            Text(preset.displayName).tag(preset.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Esforço de Raciocínio")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Esforço de Raciocínio", selection: $openAIReasoningEffort) {
                        ForEach(OpenAIReasoningEffort.allCases) { effort in
                            Text(effort.displayName).tag(effort.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ou digite um Model ID customizado da OpenAI")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    TextField("gpt-6.2-astra", text: $openAIModel)
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .autocorrectionDisabled(true)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(BeagleSpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                .fill(BeagleTheme.surface1.opacity(0.45))
                        )
                }

                Toggle(isOn: $enableNativeWebSearch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pesquisa Web Nativa OpenAI (`web_search`)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("Permite busca em tempo real com citações verificadas dentro do loop de raciocínio do GPT-6.2.")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .tint(BeagleTheme.truthObserved)

                Toggle(isOn: $enableToolSearch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tool Search sob Demanda (`namespaces` + `defer_loading`)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("Mantém Bula/PCDT e memória imediatos e carrega literatura, dispositivos Apple e MCP sob demanda.")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .tint(BeagleTheme.truthObserved)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API Key (opcional · sk-ant-...)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .padding(BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(BeagleTheme.surface1.opacity(0.6))
                        )
                }

                Toggle(isOn: $keepLocalLoaded) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manter LLM Local Sem Censura ativo online (MoE)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("Evita descarregar o modelo MLX quando o Wi-Fi/5G conecta, permitindo escuta local instantânea sem filtro na Camada 1 do MoE.")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .tint(BeagleTheme.truthObserved)
            }
        }
    }

    // MARK: - Bidirectional Voice & TTS Settings Card

    private var voiceSettingsCard: some View {
        GlassPanel(elevation: .flush, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "waveform.and.mic")
                        .font(.system(size: 13))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Voz Bidirecional · TTS & Mãos-Livres")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if let backend = previewVoice.motorAtivo {
                        Text(backend.rawValue)
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }

                Text("Conversa full-duplex em português do Brasil com GPT-Live (`gpt-live-1.1` + delegação MoE/Bula/MCP) e síntese Realtime GA (`gpt-realtime-2.1-mini`) → Cluster Beagle → Voz Neural Offline no hospital.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineSpacing(1)

                HStack {
                    Text("Sessão Mãos-Livres")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Sessão Mãos-Livres", selection: $liveTransportRaw) {
                        ForEach(CompanionLiveSessionTransportMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Motor de Voz (TTS)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Motor de Voz", selection: $voiceEngineRaw) {
                        ForEach(CompanionVoiceEnginePreference.allCases) { engine in
                            Text(engine.label).tag(engine.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Timbre OpenAI (pt-BR)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Timbre OpenAI", selection: $openAIVoice) {
                        Text("Marin (Flagship Natural)").tag("marin")
                        Text("Cedar (Calmo & Profundo)").tag("cedar")
                        Text("Tempo (Português BR · Masc Natural)").tag("tempo")
                        Text("Bossa (Português BR · Fem Natural)").tag("bossa")
                        Text("Ash (Quente & Firme)").tag("ash")
                        Text("Sage (Sereno & Claro)").tag("sage")
                        Text("Coral (Expressiva)").tag("coral")
                        Text("Verse (Natural & Dinâmico)").tag("verse")
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Text("Resposta Falada no Chat")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    Picker("Resposta Falada", selection: $autoSpeakRaw) {
                        ForEach(CompanionAutoSpeakMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    Task {
                        if previewVoice.estaAtivo {
                            previewVoice.parar()
                        } else {
                            await previewVoice.falar(
                                "Tô aqui contigo, Demetrios. Seja no plantão ou na pesquisa, pode falar comigo que eu te respondo por voz mesmo quando a rede oscilar.",
                                id: "settings-preview"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: previewVoice.estaAtivo ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(previewVoice.estaAtivo ? "Parar prévia de voz" : "Ouvir prévia da voz")
                            .font(BeagleFont.caption.font.weight(.medium))
                    }
                    .foregroundStyle(previewVoice.estaAtivo ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule()
                            .fill(BeagleTheme.surface1.opacity(0.65))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - HuggingFace Token Card

    private var hfTokenCard: some View {
        GlassPanel(elevation: .flush, truth: hfToken.isEmpty ? .declared : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(hfToken.isEmpty ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                    Text("HuggingFace Token")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if !hfToken.isEmpty {
                        HStack(spacing: BeagleSpacing.xxs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text("Configured")
                                .font(BeagleFont.caption2.font)
                        }
                        .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }

                if hfToken.isEmpty {
                    Text("Some models (Medical, Llama, Mistral) are gated and require a HuggingFace access token. Get one at huggingface.co/settings/tokens.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineSpacing(1)
                }

                if showTokenInput || hfToken.isEmpty {
                    SecureField("hf_...", text: $hfToken)
                        .font(BeagleFont.data.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .padding(BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(BeagleTheme.surface1.opacity(0.6))
                        )
                        .sensoryFeedback(.success, trigger: !hfToken.isEmpty)
                } else {
                    Button {
                        showTokenInput = true
                    } label: {
                        Text("Change token")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Device Card

    private var deviceCard: some View {
        GlassPanel(elevation: .flush) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Device")

                let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
                metricRow("RAM", value: "\(ramGB) GB")
                metricRow("Recommended", value: OnDeviceModel.recommended.displayName, color: BeagleTheme.truthObserved)
                metricRow(
                    "Apple Intelligence",
                    value: FoundationModelsAgent.shared.modelTierDescription,
                    color: FoundationModelsAgent.shared.isAnyModelAvailable ? BeagleTheme.truthObserved : BeagleTheme.textTertiary
                )

                if !llm.isAvailable {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BeagleTheme.stateError)
                        Text("MLX not available on this platform")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.stateError)
                    }
                }
            }
        }
        .accessibilityIdentifier("settings.deviceCard")
    }

}
