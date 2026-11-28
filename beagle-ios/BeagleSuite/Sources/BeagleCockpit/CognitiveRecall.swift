//
//  CognitiveRecall.swift
//  BeagleCockpit
//
//  Native surface for the exocortex cognitive loop:
//   • Recall  — composed, cited recall (POST /api/recall/answer → beagle-core native synthesis)
//   • Next    — the fleet proposes next steps (POST /api/propose), accept logs to the board
//
//  Visual identity follows the shared BeagleTheme (neutral plaster / deep navy surfaces) with the
//  cockpit-web amber/turquoise accents, project-colored scope dots, confidence ring, tappable [n]
//  citations that scroll+flash the
//  source, and a vertical source timeline. The app is just another client of the cockpit-web API over
//  the tailnet — no token in the app (cockpit/coord-mcp hold the operator token).
//

import SwiftUI

// MARK: - Tab root (Recall ⇄ Propor)

struct CognitiveRecallView: View {
    // "Next" used to collide with SpatialDeskMissionControlView's "Next Best Place" (a
    // different concept — spatial navigation, not fleet task proposals). Renamed to
    // "Propor", matching what this mode actually does (POST /api/propose).
    enum Mode: String, CaseIterable { case recall = "Recall", next = "Propor" }
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


// MARK: - Recall pane

struct RecallPane: View {
    @AppStorage("cognitiveBaseURL") private var baseURL = "https://beagle.chiuratto.ai"
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
    @State private var recallTask: Task<Void, Never>?

    /// Programmatic entry point (e.g. SpatialDeskMissionControlView's Action Menu) — runs
    /// this query on appear instead of relying on the `-cognitiveAutoQuery` launch-argument
    /// deep link, which is meant for CLI/test automation, not in-app callers.
    private let presetQuery: String?
    private let presetScope: String?

    init(presetQuery: String? = nil, presetScope: String? = nil) {
        self.presetQuery = presetQuery
        self.presetScope = presetScope
    }

    private var api: CognitiveAPI { CognitiveAPI(preferred: baseURL) }

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
                    if loading {
                        ThinkingCard()
                        Button { recallTask?.cancel(); loading = false; error = "cancelled" } label: {
                            Label("Cancel", systemImage: "xmark.circle").font(.caption)
                        }
                        .buttonStyle(.borderless).tint(CK.accent).padding(.top, 4)
                    }
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
                guard !didAutoRun else { return }
                if let presetQuery, !presetQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    didAutoRun = true
                    if let presetScope { scope = presetScope }
                    query = presetQuery
                    run()
                } else if !autoQuery.trimmingCharacters(in: .whitespaces).isEmpty {
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
        recallTask = Task {
            do { result = try await api.recall(query: q, scope: scope) }
            catch is CancellationError { /* user cancelled; state already reset */ }
            catch { self.error = error.localizedDescription }
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


// MARK: - Next pane (propositor)

struct NextPane: View {
    @AppStorage("cognitiveBaseURL") private var baseURL = "https://beagle.chiuratto.ai"
    @AppStorage("cognitiveScope") private var scope = "all"
    @State private var result: ProposeResult?
    @State private var loading = false
    @State private var error: String?
    @State private var accepted: Set<String> = []

    private var api: CognitiveAPI { CognitiveAPI(preferred: baseURL) }

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
            Text("Próximos passos propostos").font(.title3.weight(.bold)).foregroundStyle(CK.fg)
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

