//
//  CognitiveRecall.swift
//  BeagleCockpit
//
//  Native surface for the exocortex cognitive loop:
//   • Recall  — composed, cited recall (POST /api/recall/answer → beagle-core native synthesis)
//   • Next    — the fleet proposes next steps (POST /api/propose), accept logs to the board
//
//  The app is just another client of the cockpit-web API over the tailnet — no token in the app
//  (the cockpit/coord-mcp hold the operator token); reachable on the phone via the tailnet host.
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

// MARK: - Tab root (Recall ⇄ Next)

struct CognitiveRecallView: View {
    enum Mode: String, CaseIterable { case recall = "Recall", next = "Next" }
    @State private var mode: Mode = .recall

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 6)

            switch mode {
            case .recall: RecallPane()
            case .next: NextPane()
            }
        }
        .navigationTitle("Exocortex")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Recall pane

struct RecallPane: View {
    @AppStorage("cognitiveBaseURL") private var baseURL = "http://cockpit-1.tail21cbc4.ts.net"
    @AppStorage("cognitiveScope") private var scope = "all"
    @State private var query = ""
    @State private var result: RecallAnswer?
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var api: CognitiveAPI { CognitiveAPI(baseURL: baseURL) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                askBar
                scopePicker
                if loading { thinking }
                else if let error { errorCard(error) }
                else if let result { answerCard(result); sourcesList(result.sources) }
                else { idle }
            }
            .padding()
        }
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Ask your exocortex…", text: $query, axis: .vertical)
                .focused($focused)
                .submitLabel(.search)
                .onSubmit(run)
            Button(action: run) {
                Image(systemName: "arrow.right.circle.fill").font(.title2)
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $scope) {
            ForEach(cognitiveScopes, id: \.self) { Text($0.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: scope) { _, _ in if !query.isEmpty { run() } }
    }

    private var idle: some View {
        ContentUnavailableView(
            "Composed recall",
            systemImage: "brain.head.profile",
            description: Text("Ask a question — your exocortex retrieves the memory and the fleet composes the answer, with sources.")
        )
        .padding(.top, 40)
    }

    private var thinking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Retrieving from memory", systemImage: "circle.dotted")
            Label("Composing with the fleet…", systemImage: "sparkles")
            ProgressView()
        }
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func answerCard(_ r: RecallAnswer) -> some View {
        let (headline, body) = splitHeadline(r.answer)
        return VStack(alignment: .leading, spacing: 12) {
            Label("COMPOSED ANSWER", systemImage: "circle.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.teal)
            if let headline {
                Text(headline).font(.title3.weight(.bold))
            }
            ForEach(Array(body.enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("-") || t.hasPrefix("*") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(.orange).frame(width: 5, height: 5).padding(.top, 7)
                        Text(inlineMarkdown(String(t.dropFirst().drop(while: { $0 == " " || $0 == "*" }))))
                    }
                } else if !t.isEmpty {
                    Text(inlineMarkdown(t))
                }
            }
            HStack(spacing: 12) {
                if let model = r.model { Text(model).font(.caption.monospaced()).foregroundStyle(.secondary) }
                if let c = r.confidence {
                    Text("\(Int(c * 100))% \(c >= 0.75 ? "high" : c >= 0.5 ? "medium" : "low")")
                        .font(.caption.monospaced())
                        .foregroundStyle(c >= 0.75 ? .green : c >= 0.5 ? .yellow : .red)
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sourcesList(_ sources: [RecallSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !sources.isEmpty {
                Text("SOURCES · \(sources.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(sources.sorted { ($0.date ?? "") > ($1.date ?? "") }) { s in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(s.n)").font(.caption2.monospaced().weight(.bold))
                            .frame(width: 20, height: 20).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        if let d = s.date { Text(relativeDate(d)).font(.caption.monospaced()).foregroundStyle(.teal) }
                        Text(s.source ?? "exocortex").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Text(s.text).font(.callout).foregroundStyle(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        focused = false; loading = true; error = nil
        Task {
            do { result = try await api.recall(query: q, scope: scope) }
            catch { self.error = "request failed: \(error.localizedDescription)" }
            loading = false
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
                    Text("What should we do next?").font(.title3.weight(.bold))
                    Spacer()
                    Button(action: run) { Label("Propose", systemImage: "bolt.fill") }
                        .buttonStyle(.borderedProminent).disabled(loading)
                }
                Picker("Scope", selection: $scope) {
                    ForEach(cognitiveScopes, id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: scope) { _, _ in run() }

                if loading {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Reading recent state & memory", systemImage: "circle.dotted")
                        Label("Planning next steps with the fleet…", systemImage: "sparkles")
                        ProgressView()
                    }.foregroundStyle(.secondary)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if let result {
                    ForEach(Array(result.proposals.enumerated()), id: \.offset) { i, p in proposalCard(i + 1, p) }
                } else {
                    ContentUnavailableView("Next steps", systemImage: "bolt.fill",
                        description: Text("The organism reads recent state + memory and the fleet proposes the next moves — you decide."))
                        .padding(.top, 30)
                }
            }
            .padding()
        }
        .task { if result == nil { run() } }
    }

    private func proposalCard(_ n: Int, _ p: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(n)").font(.caption.monospaced().weight(.bold))
                    .frame(width: 24, height: 24).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                Text(p.title).font(.headline)
                Spacer()
                Text(p.effort).font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(effortTint(p.effort).opacity(0.18), in: Capsule())
                    .foregroundStyle(effortTint(p.effort))
            }
            Text(inlineMarkdown(p.why)).font(.callout).foregroundStyle(.secondary)
            if accepted.contains(p.title) {
                Label("accepted — logged to the board", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.teal)
            } else {
                HStack(spacing: 10) {
                    Button { accept(p) } label: { Label("Accept", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(.teal).controlSize(.small)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func effortTint(_ e: String) -> Color {
        switch e.uppercased() { case "S": return .green; case "L": return .red; default: return .yellow }
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
