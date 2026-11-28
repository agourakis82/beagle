//
//  CognitiveRecall+Components.swift
//  BeagleCockpit
//
//  Models, tailnet CognitiveAPI client, CK visual identity, markdown/citation
//  formatting helpers, and reusable components for CognitiveRecallView.
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Models (match the cockpit-web JSON)

struct RecallSource: Codable, Identifiable, Sendable {
    let n: Int
    let text: String
    let date: String?
    let source: String?
    let score: Double?
    var id: Int { n }
}

struct RecallAnswer: Codable, Sendable {
    let answer: String
    let sources: [RecallSource]
    let confidence: Double?
    let model: String?
    let scope: String?
}

struct Proposal: Codable, Identifiable, Sendable {
    let title: String
    let why: String
    let effort: String
    var id: String { title }
}

struct ProposeResult: Codable, Sendable {
    let proposals: [Proposal]
    let sources: [RecallSource]
    let model: String?
    let scope: String?
}

private struct AcceptResult: Codable, Sendable { let ok: Bool? }

// MARK: - API client (tailnet, no auth — cockpit handles backend auth)

/// Typed backend error so the UI can show the real HTTP status + body (not a generic URLError).
struct CognitiveError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? "HTTP \(status)" : "\(status): \(b.prefix(180))"
    }
}

struct CognitiveAPI: Sendable {
    /// Preferred URL first, then the standard cockpit fallback chain (public gateway → tailnet
    /// → IP → in-cluster). Mirrors CockpitClient's resolution so Recall works off-tailnet too.
    var baseURLs: [String]

    static let fallbackChain: [String] = BeagleEndpoints.cockpitURLs.map(\.absoluteString)

    init(preferred: String) {
        var urls: [String] = []
        let p = preferred.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { urls.append(p) }
        for u in Self.fallbackChain where !urls.contains(u) { urls.append(u) }
        baseURLs = urls
    }

    func recall(query: String, scope: String) async throws -> RecallAnswer {
        try await post("/api/recall/answer", ["query": query, "scope": scope])
    }

    func propose(scope: String) async throws -> ProposeResult {
        try await post("/api/propose", ["scope": scope])
    }

    func accept(title: String, why: String, scope: String) async throws {
        let _: AcceptResult = try await post("/api/propose/accept",
                                             ["title": title, "why": why, "scope": scope])
    }

    private func post<T: Decodable & Sendable>(_ path: String, _ body: [String: String]) async throws -> T {
        var lastError: Error = URLError(.badServerResponse)
        for base in baseURLs {
            guard let url = URL(string: base + path) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            BeagleEndpoints.applyCockpitAuth(to: &req)
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            // Synthesis can take up to ~75s; dead hosts fail fast at the connection layer.
            req.timeoutInterval = 75
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else { lastError = URLError(.badServerResponse); continue }
                if (200..<300).contains(http.statusCode) {
                    return try JSONDecoder().decode(T.self, from: data)
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                let err = CognitiveError(status: http.statusCode, body: text)
                // 4xx is deterministic (e.g. 400 "query required") — don't retry other hosts.
                if (400..<500).contains(http.statusCode) { throw err }
                lastError = err // 5xx/502/503 → try the next URL
            } catch let e as CognitiveError {
                throw e
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error // network/timeout → try the next URL
            }
        }
        throw lastError
    }
}

// MARK: - Cockpit visual identity (ported from cockpit-web CSS vars)

enum CK {
    // Surfaces & text defer to the shared BeagleTheme so Recall matches the rest of the
    // app (neutral plaster / deep navy) instead of its old plum canvas. The warm semantic
    // accents below (amber/turquoise/scope dots) are kept — they were never the problem.
    static let bg      = BeagleTheme.surface0
    static let bg2     = BeagleTheme.surface1
    static let panel   = BeagleTheme.surface1
    static let card    = BeagleTheme.surface2
    static let card2   = BeagleTheme.surface3
    static let line    = BeagleTheme.hairline
    static let line2   = Color(light: .black.opacity(0.16), dark: .white.opacity(0.16))
    static let fg      = BeagleTheme.textPrimary
    static let txt     = BeagleTheme.textData
    static let dim     = BeagleTheme.textSecondary
    static let faint   = BeagleTheme.textTertiary
    static let accent  = Color(lightHex: 0xA8620A, darkHex: 0xffc24d)
    static let accent2 = Color(lightHex: 0xCC4E28, darkHex: 0xff7a4c)
    static let turq    = Color(lightHex: 0x0E9886, darkHex: 0x2dd4bf)
    static let ink     = Color(hex: 0x2a1a06)   // text on amber (both modes)
    static let ok      = Color(lightHex: 0x1B9D70, darkHex: 0x56d6a0)
    static let warn    = Color(lightHex: 0xB9760A, darkHex: 0xffb454)
    static let lo      = Color(lightHex: 0xCC4133, darkHex: 0xff7a6b)
    static let beagle  = Color(lightHex: 0xA8620A, darkHex: 0xffc24d)
    static let sounio  = Color(lightHex: 0x3A5BD0, darkHex: 0x7c9cff)
    static let darwin  = Color(lightHex: 0x1B9D70, darkHex: 0x56d6a0)

    static func scopeColor(_ s: String) -> Color {
        switch s { case "beagle": return beagle; case "sounio": return sounio; case "darwin": return darwin; default: return fg }
    }

    @ViewBuilder static var canvas: some View {
        ZStack {
            bg
            RadialGradient(colors: [accent2.opacity(0.10), .clear],
                           center: UnitPoint(x: 0.85, y: -0.08), startRadius: 0, endRadius: 540)
            RadialGradient(colors: [turq.opacity(0.07), .clear],
                           center: UnitPoint(x: -0.05, y: 0.10), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255.0,
                  green: Double((hex >> 8) & 0xff) / 255.0,
                  blue: Double(hex & 0xff) / 255.0,
                  opacity: 1)
    }

    /// Adaptive color from two hex values — light/dark aware, local to Recall
    /// so its `CK` palette flips with the system appearance.
    init(lightHex: UInt32, darkHex: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(Color(hex: darkHex)) : UIColor(Color(hex: lightHex)) })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(Color(hex: darkHex)) : NSColor(Color(hex: lightHex)) })
        #else
        self.init(hex: darkHex)
        #endif
    }
}

// A gradient panel matching the web .answer / .think card.
private struct CockpitPanel: ViewModifier {
    var radius: CGFloat = 16
    var emphasized: Bool = false
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(colors: [CK.panel, CK.bg2], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(emphasized ? CK.line2 : CK.line, lineWidth: 1))
    }
}

extension View {
    func cockpitPanel(radius: CGFloat = 16, emphasized: Bool = false) -> some View {
        modifier(CockpitPanel(radius: radius, emphasized: emphasized))
    }
}

// MARK: - Shared helpers

private let cognitiveScopes = ["all", "beagle", "sounio", "darwin"]

private func relativeDate(_ iso: String?) -> String {
    guard let iso else { return "" }
    let plain = ISO8601DateFormatter()
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = frac.date(from: iso) ?? plain.date(from: iso) else { return "" }
    return date.formatted(.relative(presentation: .named))
}

/// Split a composed answer into a headline (leading **bold** / short line) + the body lines.
func splitHeadline(_ answer: String) -> (headline: String?, body: [String]) {
    let lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
        return (nil, lines)
    }
    let t = first.trimmingCharacters(in: .whitespaces)
    let isHeadline = (t.hasPrefix("**") && t.hasSuffix("**")) ||
        (t.count <= 110 && !t.hasPrefix("-") && !t.hasPrefix("*") && !t.hasPrefix("#"))
    if isHeadline {
        let head = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)
        let rest = lines.firstIndex(of: first).map { Array(lines[($0 + 1)...]) } ?? []
        return (head, rest)
    }
    return (nil, lines)
}

func inlineMarkdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

private let citationRegex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]")

/// Render a line with inline markdown + amber, tappable, raised [n] citation badges (link: cite://n).
func composedLine(_ raw: String) -> AttributedString {
    let ns = raw as NSString
    var out = AttributedString()
    var idx = 0
    for m in citationRegex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
        if m.range.location > idx {
            out += inlineMarkdown(ns.substring(with: NSRange(location: idx, length: m.range.location - idx)))
        }
        let num = ns.substring(with: m.range(at: 1))
        var badge = AttributedString("\(num)")
        badge.foregroundColor = CK.accent
        badge.font = .caption2.weight(.bold).monospaced()
        badge.baselineOffset = 4
        if let n = Int(num), let url = URL(string: "cite://\(n)") { badge.link = url }
        var lb = AttributedString("[")
        lb.foregroundColor = CK.accent; lb.font = .caption2.weight(.bold).monospaced(); lb.baselineOffset = 4
        var rb = AttributedString("]")
        rb.foregroundColor = CK.accent; rb.font = .caption2.weight(.bold).monospaced(); rb.baselineOffset = 4
        out += lb; out += badge; out += rb
        idx = m.range.location + m.range.length
    }
    if idx < ns.length { out += inlineMarkdown(ns.substring(from: idx)) }
    return out
}


// MARK: - Scope pills (project-colored dots)

struct ScopePills: View {
    @Binding var scope: String
    var onChange: () -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(cognitiveScopes, id: \.self) { s in
                    let on = scope == s
                    HStack(spacing: 6) {
                        Circle()
                            .fill(CK.scopeColor(s))
                            .frame(width: 7, height: 7)
                            .shadow(color: on ? CK.scopeColor(s) : .clear, radius: 4)
                        Text(s.capitalized)
                            .font(.caption.weight(.semibold).monospaced())
                    }
                    .foregroundStyle(on ? CK.fg : CK.dim)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(on ? CK.card2 : CK.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? CK.line2 : CK.line, lineWidth: 1))
                    .contentShape(Capsule())
                    .onTapGesture { scope = s; onChange() }
                }
            }
            .padding(.vertical, 1)
        }
    }
}

// MARK: - Confidence ring

struct ConfidenceRing: View {
    let value: Double
    private var color: Color { value >= 0.75 ? CK.ok : value >= 0.5 ? CK.warn : CK.lo }
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(CK.card2, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            Text("\(Int(value * 100))%")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Thinking (animated steps + skeleton)

struct ThinkingCard: View {
    @State private var composing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(label: "Retrieving from memory", state: composing ? .done : .active)
            StepRow(label: "Composing with the fleet…", state: composing ? .active : .pending)
            SkeletonLines()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitPanel(emphasized: true)
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation(.easeInOut) { composing = true }
        }
    }
}

private struct StepRow: View {
    enum St { case pending, active, done }
    let label: String
    let state: St
    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .strokeBorder(state == .active ? CK.accent : (state == .done ? CK.turq : CK.line2), lineWidth: 2)
                    .frame(width: 18, height: 18)
                switch state {
                case .active: ProgressView().controlSize(.mini).tint(CK.accent)
                case .done:
                    Circle().fill(CK.turq).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(CK.bg)
                case .pending: EmptyView()
                }
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(state == .pending ? CK.faint : (state == .done ? CK.dim : CK.fg))
            Spacer(minLength: 0)
        }
    }
}

private struct SkeletonLines: View {
    @State private var shimmer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(CK.card2)
                    .frame(height: 12)
                    .frame(maxWidth: i == 2 ? 170 : .infinity, alignment: .leading)
                    .opacity(shimmer ? 0.35 : 0.85)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }
}


// MARK: - Source row (timeline node + expandable card)

struct SourceRow: View {
    let source: RecallSource
    let isFlash: Bool
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                Rectangle().fill(CK.line).frame(width: 2)
                Circle()
                    .fill(isFlash ? CK.accent : CK.bg)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(isFlash ? CK.accent : CK.line2, lineWidth: 2))
                    .padding(.top, 15)
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    Text("\(source.n)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(CK.accent)
                        .frame(width: 21, height: 21)
                        .background(CK.card2, in: RoundedRectangle(cornerRadius: 6))
                    if let d = source.date, !relativeDate(d).isEmpty {
                        Text(relativeDate(d)).font(.caption.monospaced()).foregroundStyle(CK.turq)
                    }
                    Text(source.source ?? "exocortex")
                        .font(.caption.monospaced())
                        .foregroundStyle(CK.faint)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let score = source.score {
                        ZStack(alignment: .leading) {
                            Capsule().fill(CK.card2).frame(width: 38, height: 4)
                            Capsule()
                                .fill(LinearGradient(colors: [CK.accent2, CK.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, 38 * min(1, max(0, score))), height: 4)
                        }
                    }
                }
                Text(source.text)
                    .font(.callout)
                    .foregroundStyle(CK.txt)
                    .lineLimit(expanded ? nil : 3)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CK.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isFlash ? CK.accent : CK.line, lineWidth: isFlash ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 13))
            .onTapGesture { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } }
            .padding(.bottom, 11)
        }
    }
}

// MARK: - Flowing chips (suggestions / recents)

struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.left").font(.system(size: 10, weight: .bold)).foregroundStyle(CK.faint)
                    Text(item).font(.footnote).foregroundStyle(CK.dim).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(CK.card, in: Capsule())
                .overlay(Capsule().strokeBorder(CK.line, lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { onTap(item) }
            }
        }
    }
}

/// Minimal flow layout (wraps chips to multiple rows).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x - bounds.minX + s.width > maxW, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}


struct ThinkingCardNext: View {
    @State private var planning = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(label: "Reading recent state & memory", state: planning ? .done : .active)
            StepRow(label: "Planning next steps with the fleet…", state: planning ? .active : .pending)
            SkeletonLines()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).cockpitPanel(emphasized: true)
        .task { try? await Task.sleep(for: .seconds(1.3)); withAnimation(.easeInOut) { planning = true } }
    }
}
