//
//  CognitiveRecall.swift
//  BeagleCockpit
//
//  Native surface for the exocortex cognitive loop:
//   • Recall  — composed, cited recall (POST /api/recall/answer → beagle-core native synthesis)
//   • Next    — the fleet proposes next steps (POST /api/propose), accept logs to the board
//
//  Visual identity ported from the cockpit-web surfaces (/recall, /next): plum canvas, amber/turquoise
//  accents, project-colored scope dots, confidence ring, tappable [n] citations that scroll+flash the
//  source, and a vertical source timeline. The app is just another client of the cockpit-web API over
//  the tailnet — no token in the app (cockpit/coord-mcp hold the operator token).
//

import SwiftUI

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

struct CognitiveAPI: Sendable {
    var baseURL: String

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
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 75
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Cockpit visual identity (ported from cockpit-web CSS vars)

private enum CK {
    static let bg      = Color(hex: 0x1b1426)
    static let bg2     = Color(hex: 0x21192d)
    static let panel   = Color(hex: 0x271e36)
    static let card    = Color(hex: 0x2a2038)
    static let card2   = Color(hex: 0x352947)
    static let line    = Color(hex: 0x3c2f50)
    static let line2   = Color(hex: 0x54426b)
    static let fg      = Color(hex: 0xfbf5ef)
    static let txt     = Color(hex: 0xddd2e0)
    static let dim     = Color(hex: 0xa596ad)
    static let faint   = Color(hex: 0x7a6a82)
    static let accent  = Color(hex: 0xffc24d)
    static let accent2 = Color(hex: 0xff7a4c)
    static let turq    = Color(hex: 0x2dd4bf)
    static let ink     = Color(hex: 0x2a1a06)   // text on amber
    static let ok      = Color(hex: 0x56d6a0)
    static let warn    = Color(hex: 0xffb454)
    static let lo      = Color(hex: 0xff7a6b)
    static let beagle  = Color(hex: 0xffc24d)
    static let sounio  = Color(hex: 0x7c9cff)
    static let darwin  = Color(hex: 0x56d6a0)

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

private extension View {
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
private func splitHeadline(_ answer: String) -> (headline: String?, body: [String]) {
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

private func inlineMarkdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(s)
}

private let citationRegex = try! NSRegularExpression(pattern: "\\[(\\d+)\\]")

/// Render a line with inline markdown + amber, tappable, raised [n] citation badges (link: cite://n).
private func composedLine(_ raw: String) -> AttributedString {
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

// MARK: - Tab root (Recall ⇄ Next)

struct CognitiveRecallView: View {
    enum Mode: String, CaseIterable { case recall = "Recall", next = "Next" }
    @State private var mode: Mode = .recall

    var body: some View {
        ZStack {
            CK.canvas
            VStack(spacing: 0) {
                ModeSwitch(mode: $mode)
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                switch mode {
                case .recall: RecallPane()
                case .next: NextPane()
                }
            }
        }
        .tint(CK.accent)
        .navigationTitle("Exocortex")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CK.bg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
    }
}

private struct ModeSwitch: View {
    @Binding var mode: CognitiveRecallView.Mode
    var body: some View {
        HStack(spacing: 4) {
            ForEach(CognitiveRecallView.Mode.allCases, id: \.self) { m in
                let on = mode == m
                Text(m.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(on ? CK.ink : CK.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(on ? CK.accent : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { mode = m } }
            }
        }
        .padding(4)
        .background(CK.card, in: Capsule())
        .overlay(Capsule().strokeBorder(CK.line, lineWidth: 1))
    }
}

// MARK: - Scope pills (project-colored dots)

private struct ScopePills: View {
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

private struct ConfidenceRing: View {
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

private struct ThinkingCard: View {
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

// MARK: - Recall pane

struct RecallPane: View {
    @AppStorage("cognitiveBaseURL") private var baseURL = "http://cockpit-1.tail21cbc4.ts.net"
    @AppStorage("cognitiveScope") private var scope = "all"
    @AppStorage("cognitiveRecents") private var recentsJSON = "[]"
    /// Deep-link: launch arg `-cognitiveAutoQuery "…"` (NSUserDefaults argument domain) runs a recall on appear.
    @AppStorage("cognitiveAutoQuery") private var autoQuery = ""
    @State private var query = ""
    @State private var result: RecallAnswer?
    @State private var loading = false
    @State private var error: String?
    @State private var flash: Int?
    @State private var didAutoRun = false
    @FocusState private var focused: Bool

    private var api: CognitiveAPI { CognitiveAPI(baseURL: baseURL) }

    private let suggestions = [
        "What did we decide about fleet routing?",
        "Latest on GDR / RDMA across nodes",
        "What's the next step for the Sounio compiler?",
        "Cluster scheduling doctrine"
    ]

    private var recents: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(recentsJSON.utf8))) ?? []
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    askBar
                    ScopePills(scope: $scope) { if !query.isEmpty { run() } }
                    if loading { ThinkingCard() }
                    else if let error { errorCard(error) }
                    else if let result {
                        answerCard(result)
                        sourcesTimeline(result.sources)
                    } else { idle }
                }
                .foregroundStyle(CK.txt)
                .padding()
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                if !didAutoRun, !autoQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    didAutoRun = true
                    query = autoQuery
                    run()
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "cite", let n = Int(url.host() ?? "") else { return .systemAction }
                withAnimation(.easeInOut) {
                    flash = n
                    proxy.scrollTo("src-\(n)", anchor: .center)
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation { if flash == n { flash = nil } }
                }
                return .handled
            })
        }
    }

    private var askBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(CK.accent).font(.system(size: 17, weight: .semibold))
            TextField("", text: $query, axis: .vertical)
                .focused($focused)
                .submitLabel(.search)
                .foregroundStyle(CK.fg)
                .tint(CK.accent)
                .onSubmit(run)
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text("Ask your exocortex…").foregroundStyle(CK.faint).allowsHitTesting(false)
                    }
                }
            Button(action: run) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(CK.ink)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [CK.accent, CK.accent2], startPoint: .top, endPoint: .bottom),
                        in: Circle())
                    .opacity(canRun ? 1 : 0.5)
            }
            .disabled(!canRun)
        }
        .padding(6)
        .padding(.leading, 9)
        .background(
            LinearGradient(colors: [CK.panel, CK.bg2], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? CK.accent : CK.line2, lineWidth: focused ? 2 : 1))
    }

    private var canRun: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty && !loading }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(CK.line2)
                Text("Composed recall")
                    .font(.title3.weight(.bold)).foregroundStyle(CK.fg)
                Text("Ask a question — your exocortex retrieves the memory and the fleet composes the answer, with sources.")
                    .font(.subheadline)
                    .foregroundStyle(CK.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)

            chipGroup(title: recents.isEmpty ? "TRY" : "RECENT",
                      items: recents.isEmpty ? suggestions : recents)
        }
    }

    private func chipGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(CK.faint)
                .tracking(1.3)
            FlowChips(items: items) { picked in
                query = picked
                run()
            }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(CK.lo)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .cockpitPanel()
    }

    private func answerCard(_ r: RecallAnswer) -> some View {
        let (headline, body) = splitHeadline(r.answer)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(CK.turq).frame(width: 8, height: 8)
                        .shadow(color: CK.turq, radius: 5)
                    Text("COMPOSED ANSWER")
                        .font(.caption2.weight(.semibold).monospaced())
                        .tracking(1.5)
                        .foregroundStyle(CK.dim)
                }
                Spacer()
                if let c = r.confidence { ConfidenceRing(value: c) }
            }
            if let headline {
                Text(composedLine(headline))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(CK.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(body.enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("-") || t.hasPrefix("*") {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(CK.accent).frame(width: 5, height: 5)
                            .shadow(color: CK.accent.opacity(0.6), radius: 3)
                            .padding(.top, 7)
                        Text(composedLine(String(t.dropFirst().drop(while: { $0 == " " || $0 == "*" }))))
                            .foregroundStyle(CK.txt)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !t.isEmpty {
                    Text(composedLine(t))
                        .foregroundStyle(CK.txt)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let model = r.model {
                HStack(spacing: 7) {
                    Image(systemName: "cpu").font(.caption2).foregroundStyle(CK.accent)
                    Text(model).font(.caption.monospaced()).foregroundStyle(CK.dim)
                }
                .padding(.top, 4)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(CK.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CK.line, lineWidth: 1))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitPanel(emphasized: true)
    }

    private func sourcesTimeline(_ sources: [RecallSource]) -> some View {
        let sorted = sources.sorted { ($0.date ?? "") > ($1.date ?? "") }
        return VStack(alignment: .leading, spacing: 0) {
            if !sorted.isEmpty {
                HStack(spacing: 8) {
                    Text("SOURCES · \(sorted.count)")
                        .font(.caption2.weight(.semibold).monospaced())
                        .tracking(1.5)
                        .foregroundStyle(CK.dim)
                    Rectangle().fill(CK.line).frame(height: 1)
                }
                .padding(.top, 26).padding(.bottom, 14)
            }
            ForEach(sorted) { s in
                SourceRow(source: s, isFlash: flash == s.n)
                    .id("src-\(s.n)")
            }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        focused = false; loading = true; error = nil
        pushRecent(q)
        Task {
            do { result = try await api.recall(query: q, scope: scope) }
            catch { self.error = "request failed: \(error.localizedDescription)" }
            loading = false
        }
    }

    private func pushRecent(_ q: String) {
        var r = recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        r.insert(q, at: 0)
        r = Array(r.prefix(6))
        if let data = try? JSONEncoder().encode(r), let s = String(data: data, encoding: .utf8) {
            recentsJSON = s
        }
    }
}

// MARK: - Source row (timeline node + expandable card)

private struct SourceRow: View {
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

private struct FlowChips: View {
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

// MARK: - Next pane (propositor)

struct NextPane: View {
    @AppStorage("cognitiveBaseURL") private var baseURL = "http://cockpit-1.tail21cbc4.ts.net"
    @AppStorage("cognitiveScope") private var scope = "all"
    @State private var result: ProposeResult?
    @State private var loading = false
    @State private var error: String?
    @State private var accepted: Set<String> = []

    private var api: CognitiveAPI { CognitiveAPI(baseURL: baseURL) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("What should we do next?")
                        .font(.title3.weight(.bold)).foregroundStyle(CK.fg)
                    Spacer()
                    Button(action: run) {
                        Label("Propose", systemImage: "bolt.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(CK.ink)
                            .padding(.horizontal, 13).padding(.vertical, 9)
                            .background(
                                LinearGradient(colors: [CK.accent, CK.accent2], startPoint: .top, endPoint: .bottom),
                                in: Capsule())
                            .opacity(loading ? 0.5 : 1)
                    }
                    .disabled(loading)
                }
                ScopePills(scope: $scope) { run() }

                if loading {
                    ThinkingCardNext()
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(CK.lo)
                        .padding().frame(maxWidth: .infinity, alignment: .leading).cockpitPanel()
                } else if let result {
                    if !result.sources.isEmpty {
                        Text("based on \(result.sources.count) memories")
                            .font(.caption2.monospaced()).foregroundStyle(CK.faint)
                    }
                    ForEach(Array(result.proposals.enumerated()), id: \.offset) { i, p in
                        proposalCard(i + 1, p)
                    }
                } else {
                    idle
                }
            }
            .foregroundStyle(CK.txt)
            .padding()
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { if result == nil { run() } }
    }

    private var idle: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.fill").font(.system(size: 34)).foregroundStyle(CK.line2)
            Text("Next steps").font(.title3.weight(.bold)).foregroundStyle(CK.fg)
            Text("The organism reads recent state + memory and the fleet proposes the next moves — you decide.")
                .font(.subheadline).foregroundStyle(CK.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 30)
    }

    private func proposalCard(_ n: Int, _ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(n)")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(CK.accent)
                    .frame(width: 24, height: 24)
                    .background(CK.card2, in: RoundedRectangle(cornerRadius: 7))
                Text(p.title).font(.headline).foregroundStyle(CK.fg)
                Spacer(minLength: 6)
                Text(p.effort.uppercased())
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(effortTint(p.effort).opacity(0.18), in: Capsule())
                    .foregroundStyle(effortTint(p.effort))
            }
            Text(inlineMarkdown(p.why)).font(.callout).foregroundStyle(CK.txt)
            if accepted.contains(p.title) {
                Label("accepted — logged to the board", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(CK.turq)
            } else {
                Button { accept(p) } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(CK.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(CK.turq, in: Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitPanel(emphasized: true)
    }

    private func effortTint(_ e: String) -> Color {
        switch e.uppercased() { case "S": return CK.ok; case "L": return CK.lo; default: return CK.warn }
    }

    private func run() {
        loading = true; error = nil
        Task {
            do { result = try await api.propose(scope: scope) }
            catch { self.error = "request failed: \(error.localizedDescription)" }
            loading = false
        }
    }

    private func accept(_ p: Proposal) {
        Task {
            try? await api.accept(title: p.title, why: p.why, scope: scope)
            accepted.insert(p.title)
        }
    }
}

private struct ThinkingCardNext: View {
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
