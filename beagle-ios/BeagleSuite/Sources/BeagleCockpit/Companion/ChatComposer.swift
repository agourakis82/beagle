//
//  ChatComposer.swift
//  BeagleCockpit — Companion chat
//
//  The floating input bar — the ONLY Liquid Glass element in the chat (chrome floats
//  above flat content). The "+" attaches a photo (PhotosPicker); a removable chip shows
//  the attachment. Sending the image to the model (iOS 27 Foundation Models multimodal)
//  is the next step. Mic = voice, arrow = send.
//

import SwiftUI
import PhotosUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

struct ChatComposer: View {
    @Binding var text: String
    var isStreaming: Bool
    var onSend: () -> Void
    var onVoice: () -> Void

    @State private var pickedItem: PhotosPickerItem?
    @State private var attachedData: Data?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { (!trimmed.isEmpty || attachedData != nil) && !isStreaming }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if attachedData != nil { attachmentChip }

            HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anexar foto")

                TextField("Fala comigo…", text: $text, axis: .vertical)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.companionInk)
                    .tint(BeagleTheme.truthObserved)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.vertical, 4)

                Group {
                    if canSend {
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        .accessibilityLabel("Enviar")
                    } else {
                        Button(action: onVoice) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .frame(width: 30, height: 30)
                        }
                        .accessibilityLabel("Voz")
                    }
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.2), value: canSend)
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .padding(.horizontal, BeagleSpacing.sm)
        .glassEffect(.regular, in: Capsule())
        .onChange(of: pickedItem) { _, item in
            Task { attachedData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    private func send() {
        onSend()
        attachedData = nil
        pickedItem = nil
    }

    private var attachmentChip: some View {
        HStack(spacing: BeagleSpacing.xs) {
            thumbnail
            Text("foto anexada")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Button {
                attachedData = nil
                pickedItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.xs)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let data = attachedData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.sm))
        } else {
            Image(systemName: "photo").foregroundStyle(BeagleTheme.textSecondary)
        }
        #else
        Image(systemName: "photo").foregroundStyle(BeagleTheme.textSecondary)
        #endif
    }
}
