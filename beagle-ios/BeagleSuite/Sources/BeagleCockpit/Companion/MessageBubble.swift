//
//  MessageBubble.swift
//  BeagleCockpit — Companion chat
//
//  A FLAT, opaque, directional message bubble (Messages-style). Per the design system:
//  glass is chrome only — bubbles never use glass. The companion's voice is warm
//  (`companionSurface`/`companionInk`); the user is cool (`userSurface`). Streaming shows
//  a breathing presence dot, not a spinner. Memory grounding shows a provenance chip.
//  See docs/design/2026-06-24-companion-design-system.md (§4 Components).
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

struct MessageBubble: View {
    let message: ChatMessage
    /// True only for the last message in the thread — gates "Regenerar" (which re-rolls the
    /// most recent response, so it only makes sense on the latest turn).
    var isLast: Bool = false
    /// Re-roll the last assistant response — provided by the chat screen (calls the store).
    var onRegenerate: (() -> Void)? = nil

    @State private var showThinking = false
    @State private var showGoDeep = false
    @State private var goDeepStore = GoDeepStore()

    /// Âmbar do desenho da presença — a mesma brasa do ancestral de luz.
    static let marcaAmbar = Color(red: 0.78, green: 0.48, blue: 0.29)

    private var isUser: Bool { message.role == .user }
    /// The text the user actually reads (the companion's note is stripped out) — what we copy,
    /// share, or send to Go-Deeper.
    private var displayedText: String { isUser ? message.content : parsed.message }

    var body: some View {
        HStack(spacing: 0) {
            // Text-first (2026-06-28): tighter side margin (md, was xxl) so long
            // Opus replies have room to breathe — user opted for max text width
            // over a "Messages-app" hard side gutter.
            if isUser { Spacer(minLength: BeagleSpacing.md) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: BeagleSpacing.xxs) {
                bubble
                    .contextMenu { if !isThinking { messageActions } }
                    .sheet(isPresented: $showGoDeep) {
                        GoDeepView(store: goDeepStore, prompt: displayedText)
                    }
                if !isUser, let thinking = parsed.thinking {
                    thinkingDisclosure(thinking)
                }
                if !isUser, let provenance = groundingLabel {
                    MemoryProvenanceChip(label: provenance)
                }
            }

            if !isUser { Spacer(minLength: BeagleSpacing.md) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // Long-press actions on a bubble — the native chat pattern (Claude/ChatGPT/Messages all use
    // a context menu here, not swipe, which fights the scroll). The Go-Deeper sheet is presented
    // from bubble state (not inside the menu) to dodge the context-menu→sheet teardown bug.
    @ViewBuilder
    private var messageActions: some View {
        Button { copyText() } label: { Label("Copiar", systemImage: "doc.on.doc") }
        Button { showGoDeep = true } label: { Label("Go Deeper", systemImage: "scope") }
        if !isUser, isLast, let onRegenerate {
            Button { onRegenerate() } label: { Label("Regenerar", systemImage: "arrow.clockwise") }
        }
        ShareLink(item: displayedText) { Label("Compartilhar", systemImage: "square.and.arrow.up") }
    }

    private func copyText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = displayedText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Split the companion's internal note (presence framing + "Nota rápida" reasoning)
    /// from the warm message it actually says. The model puts the note above a `---` rule.
    private var parsed: (message: String, thinking: String?) {
        let c = message.content
        guard let r = c.range(of: "\n---\n") ?? c.range(of: "\n---") else { return (c, nil) }
        let before = c[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = c[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeNote = ["nota", "pergunta viva", "interpretação", "próximo movimento", "abana"]
            .contains { before.range(of: $0, options: .caseInsensitive) != nil }
        return (after.isEmpty || !looksLikeNote) ? (c, nil) : (after, before)
    }

    @ViewBuilder
    private func thinkingDisclosure(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showThinking.toggle() }
            } label: {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(showThinking ? "esconder o que penso" : "ver o que penso")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .padding(BeagleSpacing.sm)
                    .background(BeagleTheme.companionSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, BeagleSpacing.xs)
    }

    // MARK: - Bubble

    /// Companion is thinking — request in flight, no text yet.
    private var isThinking: Bool { !isUser && message.isStreaming && message.content.isEmpty }

    private var bubble: some View {
        Group {
            if isThinking {
                TypingIndicator()
                    .padding(.vertical, 14)
                    .padding(.horizontal, BeagleSpacing.md)
            } else if isUser {
                // Você sabe o que escreveu. A tela serve à voz dele.
                Text(message.content)
                    .font(BeagleFont.body.font.italic())
                    .foregroundStyle(BeagleTheme.textPrimary.opacity(0.58))
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .padding(.vertical, BeagleSpacing.sm)
                    .padding(.horizontal, BeagleSpacing.md)
            } else if message.isProvisional {
                // Instant on-device presence — warm pt-BR opener, styled as a soft murmur (not a
                // final answer) until the grounded cloud reply replaces it.
                Text(message.content)
                    .font(BeagleFont.body.font.italic())
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
                    .padding(.vertical, BeagleSpacing.sm)
                    .padding(.horizontal, BeagleSpacing.md)
            } else {
                // Companion replies render real markdown — code blocks (with copy), lists,
                // tables, headings, emphasis — instead of a flat string.
                MarkdownText(
                    text: parsed.message,
                    inkColor: BeagleTheme.companionInk,
                    bodyFont: .system(.body, design: .serif),
                    lineSpacingPt: 6.5
                )
                .padding(.vertical, BeagleSpacing.sm)
                .padding(.leading, BeagleSpacing.md)
                .padding(.trailing, BeagleSpacing.sm)
            }
        }
        // Bolhas simétricas tratavam as duas falas como a mesma coisa. Não são:
        // a sua é telegráfica, a dele é parágrafo. Moldura de altura inteira
        // vira caixa; uma marca curta no início do turno é assinatura.
        .overlay(alignment: .topLeading) {
            if !isUser && !isThinking {
                Capsule()
                    .fill(Self.marcaAmbar)
                    .frame(width: 2.5, height: 20)
                    .padding(.top, BeagleSpacing.sm + 3)
                    .padding(.leading, 3)
            }
        }
        .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let r = BeagleRadius.lg
        let tail: CGFloat = 4
        return UnevenRoundedRectangle(
            topLeadingRadius: r,
            bottomLeadingRadius: isUser ? r : tail,
            bottomTrailingRadius: isUser ? tail : r,
            topTrailingRadius: r
        )
    }

    /// Quiet provenance when the companion grounded on memory/physiome (finding 7).
    private var groundingLabel: String? {
        guard let source = message.source, !source.isEmpty else { return nil }
        switch source {
        case "physiome", "physiome-digest": return "do teu corpo"
        case "exocortex", "memory", "recall": return "do que lembro de ti"
        default: return nil
        }
    }
}

// MARK: - Streaming presence (breathing dot, not a spinner)

private struct TypingIndicator: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(BeagleTheme.companionInk.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.4)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: animate)
            }
        }
        .onAppear { animate = true }
        .accessibilityLabel("pensando")
    }
}

// MARK: - Memory provenance chip

private struct MemoryProvenanceChip: View {
    let label: String

    var body: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(BeagleFont.caption2.font)
        }
        .foregroundStyle(BeagleTheme.memoryGrounded)
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 2)
        .background(BeagleTheme.memoryGrounded.opacity(0.12), in: Capsule())
        .padding(.leading, BeagleSpacing.xs)
    }
}

// MARK: - Markdown rendering (zero-dependency, themed)

/// A lightweight GitHub-flavored-markdown renderer for companion replies — fenced code blocks
/// (with copy + horizontal scroll), headings, bullet/numbered lists, blockquotes, pipe tables,
/// horizontal rules, and inline emphasis/links/inline-code. Block structure is hand-parsed;
/// inline runs go through `AttributedString(markdown:)`. Tolerant of streaming (an unclosed
/// code fence renders as a code block up to the current text).
struct MarkdownText: View {
    let text: String
    var inkColor: Color = BeagleTheme.companionInk
    /// A fala dele é para LER, não para escanear: serifa e entrelinha de leitura.
    var bodyFont: Font = BeagleFont.body.font
    var lineSpacingPt: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .font(bodyFont)
        .lineSpacing(lineSpacingPt)
        .foregroundStyle(inkColor)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let s):
            Text(mdInline(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let s):
            Text(mdInline(s))
                .font(headingFont(level)).fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(inkColor.opacity(0.55))
                        Text(mdInline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).").monospacedDigit().foregroundStyle(inkColor.opacity(0.55))
                        Text(mdInline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let s):
            HStack(spacing: BeagleSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5).fill(inkColor.opacity(0.3)).frame(width: 3)
                Text(mdInline(s)).foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let lang, let body):
            CodeBlockView(language: lang, code: body)
        case .table(let header, let rows):
            MarkdownTableView(header: header, rows: rows, ink: inkColor)
        case .rule:
            Divider().overlay(inkColor.opacity(0.15))
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return BeagleFont.title2.font
        case 2: return BeagleFont.title3.font
        default: return BeagleFont.headline.font
        }
    }
}

/// Inline markdown → AttributedString (bold/italic/`code`/links). Falls back to plain on failure.
fileprivate func mdInline(_ s: String) -> AttributedString {
    (try? AttributedString(
        markdown: s,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(s)
}

// MARK: Markdown block model + parser

fileprivate enum MarkdownBlock {
    case paragraph(String)
    case heading(Int, String)
    case bullet([String])
    case numbered([String])
    case quote(String)
    case code(String?, String)        // language, body
    case table([String], [[String]])  // header cells, rows
    case rule

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []
        func flush() {
            let joined = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            para.removeAll()
        }
        while i < lines.count {
            let raw = lines[i]
            let t = raw.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {                                   // fenced code
                flush()
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i]); i += 1
                }
                i += 1   // consume closing fence (or run past end on stream)
                blocks.append(.code(lang.isEmpty ? nil : lang, body.joined(separator: "\n")))
                continue
            }
            if t == "---" || t == "***" || t == "___" {              // horizontal rule
                flush(); blocks.append(.rule); i += 1; continue
            }
            if let h = heading(t) {                                  // # heading
                flush(); blocks.append(.heading(h.0, h.1)); i += 1; continue
            }
            if t.contains("|"), i + 1 < lines.count, isSeparator(lines[i + 1]) {   // pipe table
                flush()
                let header = cells(t)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let rt = lines[i].trimmingCharacters(in: .whitespaces)
                    if rt.isEmpty || !rt.contains("|") { break }
                    rows.append(cells(rt)); i += 1
                }
                blocks.append(.table(header, rows)); continue
            }
            if isBullet(t) {                                          // - bullet list
                flush()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(stripBullet(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                blocks.append(.bullet(items)); continue
            }
            if isNumbered(t) {                                       // 1. numbered list
                flush()
                var items: [String] = []
                while i < lines.count, isNumbered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    items.append(stripNumber(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                blocks.append(.numbered(items)); continue
            }
            if t.hasPrefix(">") {                                    // > blockquote
                flush()
                var buf: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let s = lines[i].trimmingCharacters(in: .whitespaces)
                    buf.append(String(s.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                blocks.append(.quote(buf.joined(separator: "\n"))); continue
            }
            if t.isEmpty { flush(); i += 1; continue }               // paragraph break
            para.append(raw); i += 1
        }
        flush()
        return blocks
    }

    private static func heading(_ s: String) -> (Int, String)? {
        guard s.hasPrefix("#") else { return nil }
        var n = 0
        for ch in s { if ch == "#" { n += 1 } else { break } }
        guard (1...6).contains(n) else { return nil }
        let after = s.dropFirst(n)
        guard after.first == " " || after.isEmpty else { return nil }
        return (n, after.trimmingCharacters(in: .whitespaces))
    }
    private static func isBullet(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")
    }
    private static func stripBullet(_ s: String) -> String {
        String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }
    private static func isNumbered(_ s: String) -> Bool {
        let head = s.prefix(while: { $0 != " " })
        return head.hasSuffix(".") && head.count > 1 && head.dropLast().allSatisfy(\.isNumber)
    }
    private static func stripNumber(_ s: String) -> String {
        if let r = s.range(of: ". ") { return String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        return s
    }
    private static func isSeparator(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }
    private static func cells(_ s: String) -> [String] {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: Code block (copyable, horizontally scrollable)

fileprivate struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "código"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = code
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                    withAnimation(.snappy(duration: 0.2)) { copied = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "copiado" : "copiar")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, 6)

            Divider().overlay(Color.white.opacity(0.06))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(BeagleTheme.companionInk)
                    .textSelection(.enabled)
                    .padding(BeagleSpacing.sm)
            }
        }
        .background(BeagleTheme.auroraNight.opacity(0.55), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BeagleRadius.md).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: Pipe table

fileprivate struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    let ink: Color

    var body: some View {
        let cols = max(header.count, rows.map(\.count).max() ?? 0)
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: BeagleSpacing.md, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(header[safe: c] ?? "")
                            .font(BeagleFont.footnote.font.weight(.semibold))
                            .foregroundStyle(ink)
                    }
                }
                Divider().gridCellColumns(cols).overlay(ink.opacity(0.2))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { c in
                            Text(mdInline(row[safe: c] ?? ""))
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(ink.opacity(0.9))
                        }
                    }
                }
            }
            .padding(BeagleSpacing.sm)
        }
        .background(BeagleTheme.companionSurface.opacity(0.4), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
    }
}

fileprivate extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
