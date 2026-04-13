//
//  ModelSettingsView.swift
//  BeagleCockpit
//
//  On-device model management — download, select, delete models.
//  Shows device capabilities and model recommendations.
//

import SwiftUI
import BeagleCore

struct ModelSettingsView: View {
    @State private var llm = LocalLLMEngine.shared
    @State private var selectedModel: OnDeviceModel = .recommended
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            deviceSection
            currentModelSection
            modelCatalog
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0, BeagleTheme.surface1.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("On-Device Model")
    }

    // MARK: - Device info

    private var deviceSection: some View {
        Section {
            let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
            HStack {
                Label("Device RAM", systemImage: "memorychip")
                Spacer()
                Text("\(ramGB) GB")
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textData)
            }

            HStack {
                Label("Recommended", systemImage: "sparkles")
                Spacer()
                Text(OnDeviceModel.recommended.displayName)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.truthObserved)
            }

            if !llm.isAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeagleTheme.stateError)
                    Text("MLX not available on this platform")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }
            }
        } header: {
            Text("Device")
        }
    }

    // MARK: - Current model status

    private var currentModelSection: some View {
        Section {
            switch llm.loadState {
            case .idle:
                HStack {
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text("No model loaded")
                        .foregroundStyle(BeagleTheme.textSecondary)
                }

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    HStack {
                        Text("Downloading \(selectedModel.displayName)...")
                            .font(BeagleFont.footnote.font)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    ProgressView(value: progress)
                        .tint(BeagleTheme.truthObserved)
                }

            case .loading:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading model...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.postureWarm)
                }

            case .ready:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(llm.currentModel?.displayName ?? "Model")
                            .font(BeagleFont.headline.font)
                        Text("\(llm.currentModel?.parameterCount ?? "") · \(llm.currentModel?.sizeDescription ?? "") · on-device")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Spacer()
                    if llm.isGenerating {
                        Text(String(format: "%.0f tok/s", llm.tokensPerSecond))
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }

                Button(role: .destructive) {
                    llm.unload()
                } label: {
                    Label("Unload Model", systemImage: "xmark.circle")
                }

            case .error(let msg):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeagleTheme.stateError)
                    Text(msg)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError)
                        .lineLimit(3)
                }
                Button {
                    Task { await llm.load(selectedModel) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Status")
        }
    }

    // MARK: - Model catalog

    private var modelCatalog: some View {
        Section {
            ForEach(OnDeviceModel.allCases) { model in
                Button {
                    selectedModel = model
                    Task { await llm.load(model) }
                } label: {
                    modelRow(model)
                }
                .buttonStyle(.plain)
                .disabled(!model.fitsOnThisDevice || llm.loadState == .loading || (llm.loadState != .idle && llm.loadState != .ready && llm.loadState != .error("")))
            }
        } header: {
            Text("Available Models")
        } footer: {
            Text("Models are downloaded from HuggingFace on first use. WiFi recommended for large models.")
                .font(BeagleFont.caption2.font)
        }
    }

    private func modelRow(_ model: OnDeviceModel) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BeagleSpacing.xs) {
                    Text(model.displayName)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(model.fitsOnThisDevice ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
                    Text(model.parameterCount)
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                Text(model.bestFor)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.sizeDescription)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                if !model.fitsOnThisDevice {
                    Text("too large")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.stateError)
                } else if model == .recommended {
                    Text("recommended")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
            }

            if llm.currentModel == model && llm.isReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
        .padding(.vertical, BeagleSpacing.xxs)
    }
}
