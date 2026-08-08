#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

// FROTA — the Mission Control hero screen (FAROL).
//
// It answers exactly one question: **who needs you?** A lane blocked on the operator does not
// wait its turn in a list — it RISES onto the shelf, tints, and materializes its own Approve
// control. Everything else stays calm and quiet below.
//
// Three strata, and the commandment: **glass is chrome, never content.** Panels and controls are
// glass; the terminal peek and the agent's quoted question live in an opaque "well" so text is
// never read through a blur.
//
// Hue carries identity (per agent family) in three places only: the lamp, the panel's edge tint,
// and an armed control. It never fills a surface. State is encoded three times over — light,
// elevation, and glyph — so it survives for an operator who cannot rely on color alone.
//
// Truth: every card shows WHEN it was observed, and says so plainly when that reading is stale.
// A board that asserts a fresh state it does not have teaches its operator to distrust it.

public struct FrotaView: View {
    @State private var fleet = FleetStateClient()
    @State private var coord = CoordClient()
    @State private var answering: LaneSnapshot?
    @State private var answerText: String = ""
    @Environment(\.scenePhase) private var scenePhase

    /// Opening a lane's full terminal is the caller's business (it owns navigation).
    private let onOpenLane: (String) -> Void

    public init(onOpenLane: @escaping (String) -> Void = { _ in }) {
        self.onOpenLane = onOpenLane
    }

    // MARK: - Canvas

    /// The inert ground the glass refracts. Dusk, so a lit lamp reads as light.
    private static let canvas = Color(red: 0.043, green: 0.055, blue: 0.086)

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !coord.state.hazards.isEmpty || !coord.state.conflicts.isEmpty { coordSection }
                if !fleet.shelf.isEmpty { shelfSection }
                restSection
                linkFooter
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
        .background(Self.canvas.ignoresSafeArea())
        .navigationTitle("Frota")
        .onAppear { fleet.connect(); coord.start() }
        .onDisappear { coord.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { fleet.connect(); fleet.refresh(); Task { await coord.refresh() } }
        }
        .background(approveShortcut)
        .sheet(item: $answering) { lane in answerSheet(lane) }
    }

    // MARK: - Coordination: what is about to ruin whose work

    /// Shown ONLY when there is something real to warn about — an always-on banner becomes
    /// wallpaper and stops being read. Advisory: it states the risk, it does not block anything.
    private var coordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(coord.state.hazards) { tree in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.2").foregroundStyle(.orange)
                        Text("\(tree.lanes.count) lanes na mesma árvore")
                            .font(.system(.subheadline, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        if coord.state.isStale {
                            Text("leitura antiga").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Text("Uma edição de qualquer uma pode ser sobrescrita pelas outras — sem conflito de git para avisar.")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tree.cwd)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        if !tree.branch.isEmpty {
                            Text(tree.branch)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Text(tree.lanes.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .farolGlass(tint: .orange.opacity(0.6), frosted: false)
            }

            ForEach(coord.state.conflicts) { c in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.red)
                        Text(c.lanes.joined(separator: " ↔ "))
                            .font(.system(.subheadline, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                    }
                    ForEach(Array(c.overlaps.enumerated()), id: \.offset) { _, path in
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    // Both agents' own words, so he can judge who should yield.
                    ForEach(Array(c.notes.enumerated()), id: \.offset) { _, note in
                        Text("“\(note)”")
                            .font(.system(.caption, design: .serif))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .farolGlass(tint: .red.opacity(0.55), frosted: false)
            }
        }
    }

    // MARK: - The shelf: PRECISA DE VOCÊ

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("PRECISA DE VOCÊ")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(fleet.shelf.count)")
                    .font(.system(.caption2, weight: .bold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .foregroundStyle(.white)
                Spacer()
            }
            ForEach(fleet.shelf) { lane in
                LaneCard(lane: lane, raised: true,
                         onApprove: { approve(lane) },
                         onAnswer: { answering = lane; answerText = "" },
                         onOpen: { onOpenLane(lane.sid) })
            }
        }
    }

    // MARK: - The calm half

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fleet.shelf.isEmpty ? "A FROTA" : "TRABALHANDO")
                .font(.system(.caption, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.5))
            if fleet.rest.isEmpty && fleet.shelf.isEmpty {
                emptyState
            } else {
                ForEach(fleet.rest) { lane in
                    LaneCard(lane: lane, raised: false,
                             onApprove: {}, onAnswer: {},
                             onOpen: { onOpenLane(lane.sid) })
                }
            }
        }
    }

    /// An empty state must explain itself and offer the next action (never a bare blank).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nenhuma lane observada ainda.")
                .font(.callout).foregroundStyle(.white.opacity(0.85))
            Text(linkExplanation)
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
            Button("Tentar de novo") { fleet.connect(); fleet.refresh() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .farolGlass(tint: nil, frosted: false)
    }

    /// Errors are legible and actionable — never a bare "Error".
    private var linkExplanation: String {
        // A missing token is not a network fault, and saying "reconectando" forever would send
        // him hunting the wrong problem.
        if CockpitToken.resolve() == nil { return CockpitToken.missingReason }
        switch fleet.link {
        case .failed(let why): return "O broker não respondeu: \(why). Tailnet ativa? Cockpit no ar?"
        case .reconnecting: return "Reconectando ao broker…"
        case .connecting: return "Conectando ao broker…"
        case .live: return "Conectado, mas o broker ainda não observou nenhuma lane."
        case .idle: return "Sem conexão com o broker."
        }
    }

    private var linkFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(fleet.link == .live ? BeagleTheme.truthObserved : Color.orange)
                .frame(width: 6, height: 6)
            Text(fleet.link == .live ? "broker ao vivo" : linkExplanation)
                .font(.caption2).foregroundStyle(.white.opacity(0.5))
            Spacer()
            if let at = fleet.lastFrameAt {
                Text(at, style: .relative).font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func approve(_ lane: LaneSnapshot) {
        if fleet.approve(lane) {
            haptic()
        } else {
            answering = lane; answerText = ""   // needs a real answer, not a keystroke
        }
    }

    /// ⌘↩ clears the oldest lane that can HONESTLY be cleared with one keystroke.
    private var approveShortcut: some View {
        Button("") { if let lane = fleet.nextApprovable { approve(lane) } }
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private func answerSheet(_ lane: LaneSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lane.title).font(.headline)
            Text(lane.detail)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            TextField("Sua resposta", text: $answerText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
            HStack {
                Button("Cancelar") { answering = nil }
                Spacer()
                Button("Enviar") {
                    fleet.answer(lane, text: answerText)
                    answering = nil
                    haptic()
                }
                .buttonStyle(.borderedProminent)
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        #if os(macOS)
        .frame(minWidth: 420)
        #endif
    }

    private func haptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}

// MARK: - One lane

private struct LaneCard: View {
    let lane: LaneSnapshot
    /// A lane on the shelf sits physically higher — elevation is the second encoding of state.
    let raised: Bool
    let onApprove: () -> Void
    let onAnswer: () -> Void
    let onOpen: () -> Void

    @State private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !lane.detail.isEmpty { evidence }
            if !lane.peek.isEmpty && lane.state != .waiting { peekWell }
            if lane.state == .waiting { actions }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Glass is the panel (chrome). Hue enters only as the edge tint, never as a fill.
        .farolGlass(tint: raised ? hue : nil, frosted: lane.state == .stuck)
        .shadow(color: .black.opacity(raised ? 0.45 : 0.18), radius: raised ? 18 : 6, y: raised ? 8 : 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lane.title), \(lane.state.label). \(lane.detail)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            lamp
            Text(lane.title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
            Text(lane.state.label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            truthBadge
        }
    }

    /// Light + glyph: two of the three state encodings in one mark.
    private var lamp: some View {
        ZStack {
            Circle()
                .fill(hue.opacity(lane.state == .idle ? 0.35 : 0.9))
                .frame(width: 10, height: 10)
                .shadow(color: hue.opacity(lane.state == .waiting ? 0.9 : 0.35), radius: lane.state == .waiting ? 7 : 3)
                .scaleEffect(breathing && lane.state == .running ? 1.25 : 1.0)
                .animation(
                    lane.state == .running
                        ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        : .default,
                    value: breathing
                )
            Text(lane.state.glyph)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Self.glyphInk)
                .opacity(0.9)
        }
        .onAppear { breathing = true }
    }

    private static let glyphInk = Color(red: 0.043, green: 0.055, blue: 0.086)

    /// Truth mode, per the platform invariant: never show a state without its provenance.
    private var truthBadge: some View {
        Group {
            if lane.observedAt == nil {
                Text("não observado")
                    .foregroundStyle(BeagleTheme.truthDeclared)
            } else if lane.isStale() {
                Text("leitura antiga")
                    .foregroundStyle(.orange)
            } else if let at = lane.observedAt {
                Text(at, style: .relative)
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.8))
            }
        }
        .font(.system(.caption2, weight: .medium).monospacedDigit())
    }

    /// The agent's own words — the reason this card is on the shelf. Serif, because it is
    /// something being SAID to the operator, not a machine reading.
    private var evidence: some View {
        Text(lane.detail)
            .font(.system(.subheadline, design: lane.state == .waiting ? .serif : .monospaced))
            .foregroundStyle(.white.opacity(lane.state == .waiting ? 0.95 : 0.6))
            .lineLimit(lane.state == .waiting ? 4 : 1)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, lane.state == .waiting ? 8 : 0)
            .padding(.horizontal, lane.state == .waiting ? 10 : 0)
            // Content, never chrome: an opaque well so the words are never read through blur.
            .background(
                lane.state == .waiting
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                    : nil
            )
    }

    /// Two opaque lines of the real terminal — a witness, in mono.
    private var peekWell: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lane.peek.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.30)))
    }

    /// The control materializes only for lanes that are actually blocked — and only offers
    /// one-tap approval when one keystroke can honestly satisfy the prompt.
    private var actions: some View {
        HStack(spacing: 10) {
            if lane.approve.injection != nil {
                Button(action: onApprove) {
                    Label("Aprovar", systemImage: "return")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(hue)
            } else {
                Button(action: onAnswer) {
                    Label("Responder", systemImage: "text.bubble")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(hue)
            }
            Button(action: onOpen) { Text("Abrir lane").font(.subheadline) }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.top, 2)
    }

    /// Hue = identity. One accent per agent family.
    private var hue: Color {
        switch lane.family {
        case .claude: return Color(red: 1.00, green: 0.76, blue: 0.34)   // amber
        case .codex:  return Color(red: 0.28, green: 0.86, blue: 0.82)   // cyan
        case .kimi:   return Color(red: 0.72, green: 0.56, blue: 1.00)   // violet
        case .grok:   return Color(red: 0.72, green: 0.90, blue: 0.32)   // chartreuse
        case .glm:    return Color(red: 0.44, green: 0.66, blue: 1.00)   // blue
        case .repo:   return Color(red: 0.85, green: 0.72, blue: 0.50)   // brass
        case .other:  return Color(white: 0.75)
        }
    }
}

// MARK: - The glass stratum

private extension View {
    /// A floating glass panel. `tint` is the identity edge-light (never a fill); `frosted`
    /// clouds the pane for a stuck lane — the third encoding of that state.
    /// Falls back to a material on pre-26 systems so the screen degrades instead of breaking.
    @ViewBuilder
    func farolGlass(tint: Color?, frosted: Bool) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(
                frosted ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
            )
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
                )
        }
    }
}
#endif
