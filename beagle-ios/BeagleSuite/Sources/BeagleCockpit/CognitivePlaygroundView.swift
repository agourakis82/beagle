//
//  CognitivePlaygroundView.swift
//  BeagleCockpit
//
//  A real, Settings-reachable surface that exercises the live cognitive endpoints
//  on beagle-core. Truth-mode-honest by construction: it never renders a number the
//  backend didn't actually measure. Sections are wired one per pass.
//

import SwiftUI
import BeagleCore

struct CognitivePlaygroundView: View {
    enum Surface: String, CaseIterable, Identifiable {
        case phi = "Φ"
        case hyperedges = "Hyperedges"
        case fractal = "Fractal"
        case deepThink = "Deep-think"
        var id: String { rawValue }
    }

    @State private var surface: Surface = .phi

    var body: some View {
        VStack(spacing: 0) {
            Picker("Surface", selection: $surface) {
                ForEach(Surface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(BeagleSpacing.md)

            ScrollView {
                switch surface {
                case .phi:        PhiLab()
                case .hyperedges: HyperedgesLab()
                case .fractal:    FractalLab()
                case .deepThink:  DeepThinkLab()
                }
            }
        }
        .navigationTitle("Cognitive Playground")
        .background(BeagleTheme.surface0.ignoresSafeArea())
    }

    @ViewBuilder private func pending(_ title: String, _ message: String) -> some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "hammer")
                .font(.system(size: 26))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(title)
                .font(BeagleFont.headline.font)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(message)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, BeagleSpacing.lg)
    }
}

// MARK: - Φ Lab (IIT-4 over recalled memory atoms)

private struct PhiLab: View {
    @State private var query = ""
    @State private var measurement: PhiMeasurement?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Integrated Information (Φ)")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Real IIT-4 Φ measured over the memory atoms recalled for your query. A measurement, not a gauge — it only shows a number when the substrate is sufficient.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            HStack(spacing: BeagleSpacing.xs) {
                TextField("Query to measure Φ over…", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(BeagleSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.6)))
                Button(action: measure) {
                    Image(systemName: "function")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .buttonStyle(.plain)
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }

            if loading {
                HStack(spacing: BeagleSpacing.xs) {
                    ProgressView().tint(BeagleTheme.truthObserved)
                    Text("Measuring Φ over recalled substrate…")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                .padding(.top, BeagleSpacing.xs)
            } else if let error {
                card {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.stateError)
                }
            } else if let m = measurement {
                result(m)
            }

            Spacer(minLength: 0)
        }
        .padding(BeagleSpacing.md)
    }

    // MARK: Honest rendering — number ONLY when truth_mode == measured

    @ViewBuilder private func result(_ m: PhiMeasurement) -> some View {
        if m.truthMode == "measured", let phi = m.phi {
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Φ")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Spacer()
                        TruthBadge(.observed, observedAt: m.measuredAt.iso8601Date)
                    }
                    Text(String(format: "%.4f", phi))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(BeagleTheme.truthObserved)

                    stat("substrate", "\(m.substrateSize ?? 0) memory atoms")
                    if let a = m.awarenessLevel { stat("awareness", a) }
                    if let d = m.durationMs { stat("compute", "\(d) ms") }
                    if let t = m.routerTier { stat("router tier", t) }

                    if let mip = m.mipPartition, mip.count >= 2 {
                        Divider().overlay(Color.white.opacity(0.06))
                        Text("MINIMUM INFORMATION PARTITION")
                            .font(BeagleFont.dataSmall.font).tracking(1)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        ForEach(Array(mip.prefix(2).enumerated()), id: \.offset) { idx, group in
                            partitionGroup(index: idx, atoms: group)
                        }
                    }
                }
            }
        } else {
            // truth_mode in {insufficient_substrate, verb_unavailable, empty_query, ...}
            // → explicit explanatory state. NEVER a fake 0/φ, never an endless spinner.
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    HStack {
                        TruthBadge(.stale)
                        Spacer()
                        Text(m.truthMode ?? "unknown")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text(emptyTitle(m.truthMode))
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(emptyDetail(m.truthMode))
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    private func partitionGroup(index: Int, atoms: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(index == 0 ? "PART A" : "PART B")
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.truthRemembered)
            ForEach(Array(atoms.prefix(4).enumerated()), id: \.offset) { _, atom in
                Text("• \(atom)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeagleSpacing.xs)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface0.opacity(0.6)))
    }

    private func emptyTitle(_ mode: String?) -> String {
        switch mode {
        case "insufficient_substrate": return "Not enough memory to measure Φ"
        case "verb_unavailable":       return "Φ engine is unavailable"
        case "empty_query":            return "Enter a query first"
        default:                       return "No Φ measurement"
        }
    }

    private func emptyDetail(_ mode: String?) -> String {
        switch mode {
        case "insufficient_substrate":
            return "Φ needs at least 2 memory atoms recalled for this query. Capture or recall more on this topic, then measure again."
        case "verb_unavailable":
            return "The Sounio phi.compute verb is down right now, so no integrated-information measurement is possible. Nothing is faked."
        case "empty_query":
            return "Φ is measured over the memory recalled for a query. Type something to measure over."
        default:
            return "The backend returned no measurable Φ for this substrate. No number is shown because none was measured."
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value)
                .font(BeagleFont.caption.font.weight(.medium))
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(BeagleSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.lg).fill(BeagleTheme.surface1.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func measure() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        loading = true; error = nil; measurement = nil
        Task {
            let result = await BeagleClient.shared.measurePhi(prompt: q)
            if let m = result.value {
                measurement = m
            } else {
                error = result.error ?? "Φ measurement failed to reach the backend."
            }
            loading = false
        }
    }
}

// MARK: - Hyperedges Lab (real knowledge-graph edges)

private struct HyperedgesLab: View {
    @State private var edges: [Hyperedge] = []
    @State private var observedAt: Date?
    @State private var loading = false
    @State private var error: String?
    @State private var nodeFilter = ""

    @State private var showCreate = false
    @State private var newLabel = ""
    @State private var newSubject = ""
    @State private var newObject = ""
    @State private var creating = false

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Knowledge-Graph Edges")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Real memory relations from /api/hyperedges")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
                Spacer()
                if !edges.isEmpty { TruthBadge(.observed, observedAt: observedAt) }
            }

            HStack(spacing: BeagleSpacing.xs) {
                TextField("Filter by node id…", text: $nodeFilter)
                    .autocorrectionDisabled()
                    .padding(BeagleSpacing.sm)
                    .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.6)))
                    .onSubmit { load(node: nodeFilter) }
                Button { load(node: nodeFilter) } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .buttonStyle(.plain)
            }

            DisclosureGroup(isExpanded: $showCreate) {
                VStack(spacing: BeagleSpacing.xs) {
                    field("predicate (label)", $newLabel)
                    field("subject node id", $newSubject)
                    field("object node id", $newObject)
                    Button(action: create) {
                        Text(creating ? "Creating…" : "Create edge")
                            .font(BeagleFont.subheadline.font.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BeagleSpacing.sm)
                            .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    .buttonStyle(.plain)
                    .disabled(creating || newLabel.isEmpty || newSubject.isEmpty || newObject.isEmpty)
                }
                .padding(.top, BeagleSpacing.xs)
            } label: {
                Text("New edge")
                    .font(BeagleFont.subheadline.font.weight(.medium))
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            .tint(BeagleTheme.truthObserved)

            if loading {
                HStack(spacing: BeagleSpacing.xs) {
                    ProgressView().tint(BeagleTheme.truthObserved)
                    Text("Loading edges…").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textSecondary)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.stateError)
            } else if edges.isEmpty {
                Text(nodeFilter.isEmpty ? "No edges returned." : "No edges for that node.")
                    .font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textTertiary)
            } else {
                Text("\(edges.count) edge\(edges.count == 1 ? "" : "s")")
                    .font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary)
                ForEach(edges) { edgeRow($0) }
            }

            Spacer(minLength: 0)
        }
        .padding(BeagleSpacing.md)
        .task { if edges.isEmpty { load(node: nil) } }
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .autocorrectionDisabled()
            .font(BeagleFont.caption.font)
            .padding(BeagleSpacing.sm)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface0.opacity(0.7)))
    }

    private func edgeRow(_ e: Hyperedge) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.label ?? "relation")
                    .font(BeagleFont.subheadline.font.weight(.semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                Spacer()
                if let c = e.metadata?["confidence"] {
                    Text("conf \(c)").font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            if let nodes = e.nodeIds, nodes.count >= 2 {
                HStack(spacing: 6) {
                    Text(nodes[0]).lineLimit(1)
                    Image(systemName: e.directed == true ? "arrow.right" : "arrow.left.arrow.right")
                        .font(.system(size: 10)).foregroundStyle(BeagleTheme.textTertiary)
                    Text(nodes[1]).lineLimit(1)
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(BeagleTheme.textSecondary)
            } else if let nodes = e.nodeIds {
                Text(nodes.joined(separator: ", "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textSecondary).lineLimit(1)
            }
            if let s = e.metadata?["source"] {
                Text("source: \(s)").font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .padding(BeagleSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: BeagleRadius.md).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func load(node: String?) {
        loading = true; error = nil
        let trimmed = (node ?? "").trimmingCharacters(in: .whitespaces)
        Task {
            let result = await BeagleClient.shared.queryHyperedges(nodeId: trimmed.isEmpty ? nil : trimmed)
            if let e = result.value {
                edges = e
                observedAt = result.observedAt ?? Date()
            } else {
                error = result.error ?? "Could not reach the hyperedge graph."
            }
            loading = false
        }
    }

    private func create() {
        creating = true; error = nil
        Task {
            let result = await BeagleClient.shared.createHyperedge(label: newLabel, nodeIds: [newSubject, newObject])
            if let edge = result.value {
                edges.insert(edge, at: 0)
                newLabel = ""; newSubject = ""; newObject = ""; showCreate = false
            } else {
                error = result.error ?? "Edge creation failed."
            }
            creating = false
        }
    }
}

// MARK: - Fractal Lab (Sounio deterministic fractal-tree growth)

private struct FractalLab: View {
    @State private var prompt = ""
    @State private var depth = 4
    @State private var branching = 2
    @State private var tree: FractalTree?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Fractal Recursion")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Deterministic fractal-tree growth computed by the Sounio fractal.recurse verb. Real node and depth counts — no decorative geometry.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            TextField("Seed prompt…", text: $prompt, axis: .vertical)
                .lineLimit(1...3)
                .padding(BeagleSpacing.sm)
                .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.6)))

            HStack(spacing: BeagleSpacing.lg) {
                Stepper("depth \(depth)", value: $depth, in: 1...12)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                Stepper("branching \(branching)", value: $branching, in: 2...8)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            Button(action: grow) {
                Text(loading ? "Growing…" : "Grow fractal")
                    .font(BeagleFont.subheadline.font.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, BeagleSpacing.sm)
                    .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || loading)

            if loading {
                HStack(spacing: BeagleSpacing.xs) {
                    ProgressView().tint(BeagleTheme.truthObserved)
                    Text("Growing fractal in Sounio…").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textSecondary)
                }
            } else if let error {
                card { Label(error, systemImage: "exclamationmark.triangle").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.stateError) }
            } else if let t = tree {
                result(t)
            }

            Spacer(minLength: 0)
        }
        .padding(BeagleSpacing.md)
    }

    @ViewBuilder private func result(_ t: FractalTree) -> some View {
        if t.truthMode == "computed", let nodes = t.nodeCount {
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("NODES").font(.system(size: 13, weight: .bold)).foregroundStyle(BeagleTheme.textTertiary)
                        Spacer()
                        TruthBadge(.observed, observedAt: t.generatedAt.iso8601Date)
                    }
                    Text("\(nodes)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    stat("max depth", "\(t.maxDepth ?? 0)")
                    stat("branching", "\(t.branching ?? branching)")
                    if let d = t.durationMs { stat("compute", "\(d) ms") }
                    Divider().overlay(Color.white.opacity(0.06))
                    levelBreakdown(depth: t.maxDepth ?? 0, branching: t.branching ?? branching, total: nodes)
                }
            }
        } else {
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    HStack {
                        TruthBadge(.stale)
                        Spacer()
                        Text(t.truthMode ?? "unknown").font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text("Fractal engine unavailable")
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("The Sounio fractal.recurse verb didn't return a computed tree. No node counts are shown because none were computed.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    // Faithful per-level breakdown of the budget-bounded growth (mirrors the verb's BFS).
    @ViewBuilder private func levelBreakdown(depth: Int, branching: Int, total: Int) -> some View {
        let rows = levels(depth: depth, branching: branching, total: total)
        VStack(alignment: .leading, spacing: 4) {
            Text("NODES PER LEVEL").font(BeagleFont.dataSmall.font).tracking(1).foregroundStyle(BeagleTheme.textTertiary)
            ForEach(rows, id: \.level) { row in
                HStack(spacing: BeagleSpacing.xs) {
                    Text("L\(row.level)").font(.system(.caption2, design: .monospaced)).foregroundStyle(BeagleTheme.textTertiary).frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BeagleTheme.truthObserved.opacity(0.5))
                            .frame(width: max(2, geo.size.width * CGFloat(row.count) / CGFloat(max(total, 1))))
                    }
                    .frame(height: 8)
                    Text("\(row.count)").font(.system(.caption2, design: .monospaced)).foregroundStyle(BeagleTheme.textSecondary).frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private func levels(depth: Int, branching: Int, total: Int) -> [(level: Int, count: Int)] {
        var rows: [(level: Int, count: Int)] = []
        var remaining = total
        var levelSize = 1
        var i = 0
        while i <= depth && remaining > 0 {
            let count = min(levelSize, remaining)
            rows.append((i, count))
            remaining -= count
            if levelSize <= total { levelSize *= max(branching, 1) }
            i += 1
        }
        return rows
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value).font(BeagleFont.caption.font.weight(.medium)).foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(BeagleSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.lg).fill(BeagleTheme.surface1.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func grow() {
        let p = prompt.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        loading = true; error = nil; tree = nil
        Task {
            let result = await BeagleClient.shared.startFractalTree(prompt: p, maxDepth: depth, branching: branching)
            if let t = result.value {
                tree = t
            } else {
                error = result.error ?? "Fractal growth failed to reach the backend."
            }
            loading = false
        }
    }
}

// MARK: - Deep-think Lab (multi-pass reasoning via TieredRouter)

private struct DeepThinkLab: View {
    @State private var prompt = ""
    @State private var depth = 3
    @State private var response: ChatResponse?
    @State private var observedAt: Date?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Deep-think")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Multi-pass reasoning routed through the live TieredRouter. The model badge shows which tier actually answered — a LocalFallback answer looks different from a premium one.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            TextField("Topic to reason about…", text: $prompt, axis: .vertical)
                .lineLimit(1...4)
                .padding(BeagleSpacing.sm)
                .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1.opacity(0.6)))

            HStack {
                Stepper("passes \(depth)", value: $depth, in: 1...6)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                Spacer()
                Button(action: think) {
                    Text(loading ? "Thinking…" : "Think")
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .buttonStyle(.plain)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }

            if loading {
                HStack(spacing: BeagleSpacing.xs) {
                    ProgressView().tint(BeagleTheme.truthObserved)
                    Text("Reasoning in \(depth) pass\(depth == 1 ? "" : "es")…").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textSecondary)
                }
            } else if let error {
                card { Label(error, systemImage: "exclamationmark.triangle").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.stateError) }
            } else if let r = response {
                result(r)
            }

            Spacer(minLength: 0)
        }
        .padding(BeagleSpacing.md)
    }

    @ViewBuilder private func result(_ r: ChatResponse) -> some View {
        if let text = r.response, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            card {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(spacing: BeagleSpacing.xs) {
                        if let model = r.model {
                            Text(model)
                                .font(BeagleFont.dataSmall.font)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(BeagleTheme.truthObserved.opacity(0.15), in: Capsule())
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        if let flow = r.flowState {
                            Text(flow).font(BeagleFont.dataSmall.font).foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Spacer()
                        TruthBadge(.observed, observedAt: observedAt)
                    }
                    Text(text)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                    if let tk = r.tokensUsed { stat("tokens", "\(tk)") }
                }
            }
        } else {
            card { Label("The router returned no reasoning text.", systemImage: "exclamationmark.triangle").font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.stateError) }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(BeagleFont.caption.font).foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value).font(BeagleFont.caption.font.weight(.medium)).foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(BeagleSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.lg).fill(BeagleTheme.surface1.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func think() {
        let p = prompt.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        loading = true; error = nil; response = nil
        Task {
            let result = await BeagleClient.shared.deepThink(prompt: p, depth: depth)
            if let r = result.value {
                response = r
                observedAt = result.observedAt ?? Date()
            } else {
                error = result.error ?? "Deep-think failed to reach the backend."
            }
            loading = false
        }
    }
}
