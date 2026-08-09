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
    @State private var fleet: FleetStateClient
    @State private var coord = CoordClient()
    @State private var answering: LaneSnapshot?
    @State private var answerText: String = ""
    /// The lane whose one-touch action is in flight. A button that looks idle while a keystroke
    /// is on the wire invites a second press — and a second `y` lands in whatever came next.
    @State private var acting: String?
    /// The last refusal or failure, kept next to the lane it belongs to. The server's own wording
    /// is shown verbatim: it knows why ("a lane está running, não esperando por você").
    @State private var actionNote: ActionNote?

    private struct ActionNote: Equatable {
        let sid: String
        let message: String
    }
    @Environment(\.scenePhase) private var scenePhase

    /// Opening a lane's full terminal is the caller's business (it owns navigation).
    private let onOpenLane: (String) -> Void

    /// `fleet` injetável para que a tela possa ser RENDERIZADA sem cluster. Não é ornamento de
    /// teste: enquanto a única forma de ver a Frota era conectar no broker e torcer para um
    /// agente estar parado, cada rodada de design era um palpite.
    public init(fleet: FleetStateClient? = nil, onOpenLane: @escaping (String) -> Void = { _ in }) {
        _fleet = State(initialValue: fleet ?? FleetStateClient())
        self.onOpenLane = onOpenLane
    }

    // MARK: - Canvas

    /// The inert ground the glass refracts. Dusk, so a lit lamp reads as light.
    private static let canvas = Color(red: 0.043, green: 0.055, blue: 0.086)

    /// O CONTEÚDO, separado do scroll de propósito.
    ///
    /// `ImageRenderer` propõe altura infinita ao filho de um `ScrollView` e o resultado sai em
    /// branco — foi exatamente o que aconteceu na primeira tentativa de retratar esta tela, e o
    /// branco parecia bug da Frota. Com o conteúdo apartado, ele é rasterizável sozinho, e o
    /// `ScrollView` volta a ser só o transporte.
    var conteudo: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !coord.state.hazards.isEmpty || !coord.state.conflicts.isEmpty { coordSection }
            // Acima da prateleira de propósito: isto não é sobre UMA lane, é sobre o quanto
            // se pode confiar em tudo que vem abaixo.
            if let saude = fleet.loomd, saude.isDegraded { loomdBand(saude) }
            if !fleet.shelf.isEmpty { shelfSection }
            restSection
            linkFooter
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    public var body: some View {
        ScrollView { conteudo }
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

    // MARK: - A queda da fonte medida

    /// A faixa que dá NOME à queda do loomd. Só existe quando `isDegraded` — mesma lei do
    /// `coordSection` logo acima: um aviso permanente vira papel de parede e para de ser lido.
    ///
    /// Ela responde as três coisas que sumiam juntas quando o cliente descartava o bloco
    /// `loomd` do frame: em que MODO a fonte está, POR QUE (nas palavras do servidor, que sabe
    /// mais que o cliente), e QUAIS lanes saíram do board com ela. Vidro é chrome, a cor é
    /// significado, e nada pisca — a queda de uma fonte é um fato, não um alarme.
    @ViewBuilder
    private func loomdBand(_ saude: LoomdHealth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: loomdSymbol(saude))
                    .foregroundStyle(loomdTint(saude))
                Text("Fonte medida \(saude.modeLabel)")
                    .font(.system(.subheadline, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                // O carimbo do LOOMD, não o do cockpit: é o relógio da coisa que caiu.
                if let at = saude.observedAt {
                    Text(at, style: .relative)
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                }
            }
            Text(saude.reason)
                .font(.caption).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            // As lanes perdidas, nomeadas em poço opaco — o mesmo tratamento que o hazard dá aos
            // nomes de lane. Sem esta linha, a queda é "um card a menos", que ninguém nota.
            if let perdidas = saude.lostSentence {
                Text(perdidas)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .farolGlass(tint: loomdTint(saude).opacity(0.55), frosted: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(saude.headline)
    }

    /// Duas cores, não cinco. Uma MEDIÇÃO ruim (`down`/`stale`) usa o mesmo laranja que os cards
    /// já usam para "leitura antiga"; a AUSÊNCIA de medição usa o tom de "declarado, não
    /// observado" que o resto da plataforma usa. A cor diz de que tipo é a falta.
    private func loomdTint(_ saude: LoomdHealth) -> Color {
        switch saude.mode {
        case .down, .stale:          return .orange
        case .absent, .unknown:      return BeagleTheme.truthDeclared
        case .observed:              return BeagleTheme.truthObserved
        }
    }

    private func loomdSymbol(_ saude: LoomdHealth) -> String {
        switch saude.mode {
        case .down:                  return "antenna.radiowaves.left.and.right.slash"
        case .stale:                 return "clock.badge.exclamationmark"
        case .absent, .unknown:      return "questionmark.circle"
        case .observed:              return "antenna.radiowaves.left.and.right"
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
                         busy: acting == lane.sid,
                         note: actionNote?.sid == lane.sid ? actionNote?.message : nil,
                         onApprove: { approve(lane) },
                         onAnswer: { answering = lane; answerText = "" },
                         onInterrupt: { interrupt(lane) },
                         onIsolate: { isolate(lane) },
                         onOpen: { onOpenLane(lane.sid) })
            }
        }
    }

    // MARK: - The calm half

    /// A metade calma vira ROSTER, não pilha de cartões.
    ///
    /// Medido no retrato de 10-ago-2026, antes disto: 16 lanes ocupavam **3.760px** de altura numa
    /// janela de 900 — a frota inteira nunca cabia na tela, que é o único motivo de existir um
    /// painel de frota. Cada lane gastava ~235px para mostrar uma linha de 40 caracteres, e os
    /// botões desligados ("Interromper", "Abrir lane") eram o elemento mais repetido da tela.
    /// Um `tmux ls` mostrava as mesmas 16 em 16 linhas, e melhor.
    ///
    /// Agora: uma LINHA por lane, em colunas que se adaptam à largura. O cartão continua
    /// existindo — mas só na prateleira, onde há uma decisão a tomar. Peso visual passa a
    /// significar "isto te pede algo", em vez de "isto é uma lane".
    private var restSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(fleet.shelf.isEmpty ? "A FROTA" : "TRABALHANDO")
                    .font(.system(.caption, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(trabalhando.count)")
                    .font(.system(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            }
            if fleet.rest.isEmpty && fleet.shelf.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 620), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(trabalhando) { lane in
                        LaneRow(lane: lane,
                                busy: acting == lane.sid,
                                onOpen: { onOpenLane(lane.sid) })
                    }
                }
                if !naoObservadas.isEmpty { grupoNaoObservado }
            }
        }
    }

    /// As lanes com estado de verdade — as que ele realmente opera.
    private var trabalhando: [LaneSnapshot] { fleet.rest.filter { $0.state != .unknown } }

    /// `unknown` = anunciada e nunca observada. No retrato eram QUATRO cartões `t560-*` com o mesmo
    /// peso visual de uma lane esperando aprovação, cada um repetindo a mesma frase de rodapé.
    /// Informação que não muda e não pede nada não merece área — merece uma linha.
    private var naoObservadas: [LaneSnapshot] { fleet.rest.filter { $0.state == .unknown } }

    private var grupoNaoObservado: some View {
        DisclosureGroup {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 620), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(naoObservadas) { lane in
                    LaneRow(lane: lane, busy: false, onOpen: { onOpenLane(lane.sid) })
                }
            }
            .padding(.top, 8)
        } label: {
            Text("\(naoObservadas.count) anunciadas e nunca observadas")
                .font(.caption).foregroundStyle(.white.opacity(0.45))
        }
        .tint(.white.opacity(0.45))
        .padding(.top, 6)
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

    /// One touch = one named key, sent over HTTP. No attach, so approving from the Mac never
    /// resizes the pane the agent (and his cmux) is looking at.
    private func approve(_ lane: LaneSnapshot) {
        // A lane whose question needs a sentence has no honest keystroke — go straight to typing.
        // Pendência TIPADA responde por RPC, sem tecla. Só cai na folha de texto quem de fato
        // precisa de uma frase digitada — e não o card exato, que tinha o que responder e era
        // mandado para o caminho que engolia a resposta.
        guard lane.approve.key != nil || lane.pendingApproval else {
            answering = lane; answerText = ""; return
        }
        act(lane) { await fleet.approve(lane) }
    }

    private func interrupt(_ lane: LaneSnapshot) { act(lane) { await fleet.interrupt(lane) } }
    private func isolate(_ lane: LaneSnapshot) { act(lane) { await fleet.isolate(lane) } }

    /// Every lane action goes through here so none of them can fail invisibly: in-flight is
    /// shown, and a refusal lands as text on the card that was refused.
    private func act(_ lane: LaneSnapshot, _ body: @escaping () async -> FleetStateClient.ActionResult) {
        guard acting == nil else { return }
        acting = lane.sid
        actionNote = nil
        Task {
            let out = await body()
            acting = nil
            if out.ok { haptic() } else { actionNote = ActionNote(sid: lane.sid, message: out.message) }
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
    /// An action for THIS lane is on the wire.
    let busy: Bool
    /// Why the last action did not happen. Shown on the card, never as a global toast: the
    /// refusal is about this lane and belongs where the operator was looking.
    let note: String?
    let onApprove: () -> Void
    let onAnswer: () -> Void
    let onInterrupt: () -> Void
    let onIsolate: () -> Void
    let onOpen: () -> Void

    @State private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if !lane.detail.isEmpty { evidence }
            if !lane.peek.isEmpty && lane.state != .waiting { peekWell }
            // A lane that does not exist in tmux gets no controls at all — there is nothing
            // there to press a key at.
            if !lane.isAbsent { actions }
            if let note { refusal(note) }
        }
        // 12/10, não 14: no retrato de 10-ago três cartões de prateleira comiam 660px de uma
        // janela de 900, e sobrava uma frota espremida embaixo. O cartão é o lugar da decisão,
        // não um pôster.
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Glass is the panel (chrome). Hue enters only as the edge tint, never as a fill.
        .farolGlass(tint: raised ? hue : nil, frosted: lane.state == .stuck)
        .shadow(color: .black.opacity(raised ? 0.45 : 0.18), radius: raised ? 18 : 6, y: raised ? 8 : 2)
        .contentShape(Rectangle())
        // O toque no card inteiro é o atalho para o terminal. Numa lane sem sessão tmux ele
        // levaria direto a uma tela de erro, então o guarda fica aqui e não no destino.
        .onTapGesture { if lane.hasTerminal { onOpen() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(lane.title), \(lane.presenceLabel), \(lane.confidenceLabel). \(lane.detail)"
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            lamp
            Text(lane.title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
            Text(lane.presenceLabel)
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
    /// Duas perguntas, um selo só: QUANDO foi visto (o tempo relativo) e COMO foi visto
    /// (o ponto). Vidro é chrome; a cor aqui é significado, e nada pisca — a diferença entre
    /// medido e adivinhado não é um alerta, é uma propriedade do dado.
    private var truthBadge: some View {
        HStack(spacing: 5) {
            provenanceDot
            observationAge
        }
    }

    /// ● medido no protocolo (loomd) · ○ lido da tela (peek + regex).
    /// Glifo E cor, nunca só cor: o mesmo par que `TruthMode` já usa no resto da plataforma.
    private var provenanceDot: some View {
        Text(lane.confidence.glyph)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(
                lane.confidence == .exact
                    ? BeagleTheme.truthObserved
                    : BeagleTheme.truthDeclared
            )
            .accessibilityHidden(true)   // o texto vive no label do card, não duplicado aqui
    }

    private var observationAge: some View {
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
            .padding(.vertical, lane.state == .waiting ? 7 : 0)
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
            if lane.state == .waiting {
                if lane.approve.key != nil || lane.pendingApproval {
                    // One named key, sent without attaching. `y` here is the same `y` he would
                    // press at the keyboard — it is not a command.
                    Button(action: onApprove) {
                        Label("Aprovar", systemImage: "return")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hue)
                } else {
                    // No keystroke can honestly satisfy an open question — do not draw one.
                    Button(action: onAnswer) {
                        Label("Responder", systemImage: "text.bubble")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hue)
                }
            }
            if busy {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("enviando")
            }
            Spacer()

            // Os secundários viram ÍCONE, e vão para a direita. No retrato de 10-ago-2026 eles
            // eram cinza-sobre-cinza, ilegíveis, e ainda assim o elemento mais repetido da tela:
            // "Interromper" e "Abrir lane" em todo cartão, disputando espaço com a única coisa
            // que ele precisa achar em um segundo. Rótulo apagado não é discrição — é ruído que
            // não dá para ler. Ícone com `.help` diz o mesmo e ocupa um sexto.
            if lane.state == .waiting || lane.state == .running {
                // Esc confirms nothing; it is the interrupt the CLIs advertise themselves.
                Button(action: onInterrupt) { Image(systemName: "escape") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .help("Interromper (Esc)")
                    .accessibilityLabel("Interromper")
            }
            if lane.isIsolatable {
                Button(action: onIsolate) { Image(systemName: "arrow.branch") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    // Moving a lane is not free, and the card says the price before he pays it.
                    .help("Isolar em /workspace/.wt/\(lane.sid). Reinicia o agente ali — o contexto dele se perde.")
                    .accessibilityLabel("Isolar em worktree")
            }
            // Só quem tem sessão tmux ganha "Abrir lane". Uma lane do loomd é supervisionada por
            // JSON-RPC e não tem pty do outro lado — o botão ali só podia falhar. No lugar dele
            // fica a razão, porque um botão que some sem explicação vira suspeita de bug.
            if lane.hasTerminal {
                Button(action: onOpen) { Image(systemName: "macwindow") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .help("Abrir o terminal de \(lane.sid)")
                    .accessibilityLabel("Abrir lane")
            } else {
                Text(lane.noTerminalReason)
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
        }
        .disabled(busy)
        .padding(.top, 2)
    }

    /// The refusal, in the server's own words. It is more specific than anything the client
    /// could infer, and a button that fails silently is worse than no button.
    private func refusal(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color(red: 1.00, green: 0.64, blue: 0.30))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
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


/// UMA LINHA por lane. O contrário do cartão: aqui não há decisão a tomar, há estado a varrer.
///
/// Ordem da esquerda para a direita segue a pergunta que ele faz ao olhar: *quem* (lâmpada+nome),
/// *como está* (estado), *fazendo o quê* (a última linha do agente), *desde quando* (idade).
/// A idade fica à direita, em dígitos tabulares, para as linhas alinharem em coluna.
private struct LaneRow: View {
    let lane: LaneSnapshot
    let busy: Bool
    let onOpen: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(hue).frame(width: 7, height: 7)
                .opacity(lane.state == .unknown ? 0.35 : 1)

            Text(lane.sid)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(lane.state == .unknown ? 0.5 : 0.92))
                .lineLimit(1)
                .frame(minWidth: 74, alignment: .leading)

            Text(lane.presenceLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .frame(minWidth: 62, alignment: .leading)

            // O que o agente está de fato fazendo. É A informação da linha, então ganha o espaço
            // que sobra — e não pode ser menor nem mais fraca que o nome, que ele já sabe de cor.
            Text(lane.detail.isEmpty ? "—" : lane.detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(lane.state == .unknown ? 0.28 : 0.62))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if busy { ProgressView().controlSize(.mini) }

            if let at = lane.observedAt {
                Text(at, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .lineLimit(1).frame(width: 52, alignment: .trailing)
            } else {
                Text("—").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(hover ? 0.07 : 0.035))
        )
        .overlay(
            // A identidade entra por uma barra na borda, nunca por preenchimento: 12 linhas
            // tingidas viram um arco-íris e param de significar qualquer coisa.
            RoundedRectangle(cornerRadius: 8)
                .fill(hue.opacity(lane.state == .unknown ? 0.15 : 0.5))
                .frame(width: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        .contentShape(Rectangle())
        .onTapGesture { if lane.hasTerminal { onOpen() } }
        .onHover { hover = $0 }
        .help(lane.hasTerminal ? "Abrir o terminal de \(lane.sid)" : lane.noTerminalReason)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lane.sid), \(lane.presenceLabel), \(lane.confidenceLabel)")
    }

    private var hue: Color {
        switch lane.family {
        case .claude: return Color(red: 1.00, green: 0.76, blue: 0.34)
        case .codex:  return Color(red: 0.28, green: 0.86, blue: 0.82)
        case .kimi:   return Color(red: 0.72, green: 0.56, blue: 1.00)
        case .grok:   return Color(red: 0.72, green: 0.90, blue: 0.32)
        case .glm:    return Color(red: 0.44, green: 0.66, blue: 1.00)
        case .repo:   return Color(red: 0.85, green: 0.72, blue: 0.50)
        case .other:  return Color(white: 0.75)
        }
    }
}

// MARK: - The glass stratum

/// Achata o vidro para um painel OPACO.
///
/// Existe por um motivo medido, não por gosto: `glassEffect` é Metal, e `ImageRenderer` não
/// rasteriza Metal — a Frota inteira saía como um retângulo vazio, o que é exatamente o estado
/// em que essa tela vinha sendo projetada. Com isto ela pode ser VISTA fora de uma janela viva.
///
/// O modo opaco não é só andaime de teste: é o degrade honesto para quando o vidro não estiver
/// disponível, e a única variante em que dá para julgar contraste de texto sem o borrão por baixo.
struct FarolFlatGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var farolFlatGlass: Bool {
        get { self[FarolFlatGlassKey.self] }
        set { self[FarolFlatGlassKey.self] = newValue }
    }
}

private struct FarolGlassModifier: ViewModifier {
    let tint: Color?
    let frosted: Bool
    @Environment(\.farolFlatGlass) private var flat

    private var edge: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08),
                          lineWidth: tint == nil ? 0.5 : 1.2)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if flat {
            content
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13).opacity(0.92)))
                .overlay(edge)
        } else {
            content.modifier(FarolRealGlass(tint: tint, frosted: frosted))
        }
    }
}

private struct FarolRealGlass: ViewModifier {
    let tint: Color?
    let frosted: Bool
    @ViewBuilder
    func body(content: Content) -> some View { content.farolGlassReal(tint: tint, frosted: frosted) }
}

private extension View {
    /// A floating glass panel. `tint` is the identity edge-light (never a fill); `frosted`
    /// clouds the pane for a stuck lane — the third encoding of that state.
    /// Falls back to a material on pre-26 systems so the screen degrades instead of breaking.
    func farolGlass(tint: Color?, frosted: Bool) -> some View {
        modifier(FarolGlassModifier(tint: tint, frosted: frosted))
    }

    @ViewBuilder
    func farolGlassReal(tint: Color?, frosted: Bool) -> some View {
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
