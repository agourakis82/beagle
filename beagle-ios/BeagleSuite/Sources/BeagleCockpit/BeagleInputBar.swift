//
//  BeagleInputBar.swift
//  BeagleCockpit
//
//  Production-quality expanding input bar.
//  Two modes: .terminal (monospace, > prefix, submit on Return)
//            .chat (proportional, no prefix, Shift+Return for newlines)
//
//  Used by both Agent tab (terminal commands) and Capture tab (thought capture).
//

import SwiftUI
import BeagleCore

// MARK: - Input bar mode

public enum InputBarMode: Sendable {
    case terminal  // SF Mono, > prefix, submit on Return
    case chat      // SF Pro, no prefix, dedicated send button only
}

// MARK: - Special keys (terminal mode)

public enum SpecialKey: Sendable {
    case interrupt   // Ctrl+C → 0x03
    case eof         // Ctrl+D → 0x04
    case arrowUp     // ESC[A
    case arrowDown   // ESC[B
    case arrowRight  // ESC[C
    case arrowLeft   // ESC[D
    case tab         // 0x09

    public var escapeSequence: String {
        switch self {
        case .interrupt:  return "\u{03}"
        case .eof:        return "\u{04}"
        case .arrowUp:    return "\u{1B}[A"
        case .arrowDown:  return "\u{1B}[B"
        case .arrowRight: return "\u{1B}[C"
        case .arrowLeft:  return "\u{1B}[D"
        case .tab:        return "\t"
        }
    }
}

// MARK: - Input bar view

struct BeagleInputBar: View {
    @Binding var text: String
    let placeholder: String
    let mode: InputBarMode
    let isEnabled: Bool
    var focusRequest: Int = 0
    let onSubmit: (String) -> Void
    var onStop: (() -> Void)? = nil
    var onSpecialKey: ((SpecialKey) -> Void)?

    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 22
    @State private var submitCount: Int = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
            inputFieldContainer
            sendButton
        }
        .animation(BeagleMotion.fast, value: isEnabled)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
        .sensoryFeedback(.impact(weight: .medium), trigger: submitCount)
        .onChange(of: focusRequest) {
            guard isEnabled else { return }
            isFocused = true
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                keyboardToolbarContent
            }
        }
        #endif
    }

    // MARK: - Keyboard toolbar

    #if os(iOS)
    @ViewBuilder
    private var keyboardToolbarContent: some View {
        if mode == .terminal {
            terminalKeyboardAccessory
        }
        Spacer()
        Button("Done") { isFocused = false }
            .font(BeagleFont.footnote.font)
    }
    #endif

    // MARK: - Input field container (with background)

    private var inputFieldContainer: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            if mode == .terminal {
                promptPrefix
            }
            textInputArea
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, mode == .terminal ? BeagleSpacing.xs : BeagleSpacing.xxs)
        .background(inputBackground)
        .onKeyPress(characters: .init(charactersIn: "cd"), phases: .down) { press in
            guard press.modifiers.contains(.control) else { return .ignored }
            if press.characters == "c" {
                onSpecialKey?(.interrupt)
                return .handled
            } else if press.characters == "d" {
                onSpecialKey?(.eof)
                return .handled
            }
            return .ignored
        }
    }

    private var promptPrefix: some View {
        Text(">")
            .font(BeagleFont.data.font)
            .fontWeight(.bold)
            .foregroundStyle(BeagleTheme.truthObserved)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: BeagleRadius.md)
            .fill(BeagleTheme.surface0)
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .strokeBorder(
                        isFocused ? BeagleTheme.truthObserved.opacity(0.3) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Text input area (terminal or chat)

    @ViewBuilder
    private var textInputArea: some View {
        if mode == .terminal {
            terminalTextField
        } else {
            chatTextEditor
        }
    }

    private var terminalTextField: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .disabled(!isEnabled)
            .onSubmit { performSubmit() }
            .submitLabel(.send)
    }

    private var chatTextEditor: some View {
        ZStack(alignment: .topLeading) {
            heightMeasurer
            editor
        }
    }

    private var heightMeasurer: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 17, weight: .regular))
            .padding(.vertical, 2)
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { textHeight = geo.size.height }
                        .onChange(of: text) {
                            withAnimation(BeagleMotion.snappy) {
                                textHeight = geo.size.height
                            }
                        }
                }
            )
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(BeagleTheme.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .disabled(!isEnabled)
            .frame(minHeight: 40, maxHeight: max(40, min(168, textHeight)))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    placeholderLabel
                }
            }
    }

    private var placeholderLabel: some View {
        Text(placeholder)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(BeagleTheme.textTertiary)
            .padding(.leading, 5)
            .padding(.top, 8)
            .allowsHitTesting(false)
    }

    // MARK: - Send / Stop button

    @ViewBuilder
    private var sendButton: some View {
        if !isEnabled, let onStop {
            // Streaming in progress — show stop button
            Button {
                onStop()
            } label: {
                ZStack {
                    Circle()
                        .fill(BeagleTheme.stateError.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BeagleTheme.stateError)
                }
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else {
            // Ready to send
            Button {
                performSubmit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isTextEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
            .disabled(isTextEmpty || !isEnabled)
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Terminal keyboard accessory

    #if os(iOS)
    private var terminalKeyboardAccessory: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Control group
                accessoryButton("⌃C", key: .interrupt, highlight: true)
                accessoryButton("⌃D", key: .eof)
                accessoryDivider
                // Navigation
                accessoryButton("⇥", key: .tab)
                accessoryButton("↑", key: .arrowUp)
                accessoryButton("↓", key: .arrowDown)
                accessoryButton("←", key: .arrowLeft)
                accessoryButton("→", key: .arrowRight)
            }
            .padding(.horizontal, 4)
        }
    }

    private var accessoryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 20)
    }

    private func accessoryButton(_ label: String, key: SpecialKey, highlight: Bool = false) -> some View {
        Button {
            onSpecialKey?(key)
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(highlight ? BeagleTheme.stateError : BeagleTheme.textData)
                .frame(minWidth: 36, minHeight: 32)
                .padding(.horizontal, BeagleSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(highlight
                              ? BeagleTheme.stateError.opacity(0.12)
                              : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    highlight ? BeagleTheme.stateError.opacity(0.25) : Color.white.opacity(0.1),
                                    lineWidth: 0.5
                                )
                        )
                )
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Actions

    private func performSubmit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submitCount += 1
        onSubmit(trimmed)
        text = ""
    }
}
