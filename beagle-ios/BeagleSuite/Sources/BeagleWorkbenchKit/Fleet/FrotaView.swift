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
    @State private var fleet: FleetStateStore
    @State private var coord = CoordStore()
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
    public init(fleet: FleetStateStore? = nil, onOpenLane: @escaping (String) -> Void = { _ in }) {
        self.init(fleet: fleet, scrollable: true, onOpenLane: onOpenLane)
    }

    init(fleet: FleetStateStore? = nil, scrollable: Bool, onOpenLane: @escaping (String) -> Void = { _ in }) {
        injetado = fleet != nil
        self.scrollable = scrollable
        _fleet = State(initialValue: fleet ?? FleetStateStore())
        self.onOpenLane = onOpenLane
    }

    private let scrollable: Bool

    /// `fleet` veio de fora (o Mission Control passa o cliente da JANELA) ou a Frota criou o
    /// próprio? Decide quem tem a responsabilidade de conectar.
    ///
    /// 🚨 Achado de review: quando `fleet` é injetado, ele pode pertencer a uma janela com MAIS
    /// telas que leem dele (a Sessão lê `fleet.aceita(de:)` sem nunca montar a Frota). Conectar
    /// aqui funcionava só porque a seção inicial é `.frota` — dependência implícita entre um caso
    /// de `switch` e o efeito colateral de um caso irmão. Dono do objeto conecta: se foi
    /// injetado, quem conecta é quem injetou. Se a Frota criou o próprio cliente (outros
    /// call-sites, como o Cockpit em `BeagleCockpitApp.swift`, e os testes de snapshot que só
    /// leem `.conteudo` e nunca chamam `body`), ninguém mais vai conectá-lo — aqui é o único
    /// lugar, e por isso o caminho autônomo tem de sobreviver.
    private let injetado: Bool

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
        Group {
            if scrollable {
                ScrollView { conteudo }
            } else {
                conteudo
            }
        }
        .background(Self.canvas.ignoresSafeArea())
        .navigationTitle("Frota")
        .onAppear {
            guard scrollable else { return }
            if !injetado { fleet.connect() }
            coord.start()
        }
        .onDisappear { coord.stop() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if !injetado { fleet.connect() }
            fleet.refresh()
            Task { await coord.refresh() }
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
    ///
    /// 🚨 E a faixa tem DOIS andares, não um. Medido no retrato de 10-ago-2026: nove linhas
    /// iguais, das quais três eram lanes trabalhando e seis estavam paradas — a distinção que
    /// mais importa aqui era invisível, porque todas pagavam o mesmo preço em área, opacidade e
    /// texto. Agora quem trabalha tem PRESENÇA (linha com fundo, prévia e a barra de identidade)
    /// e quem está em repouso RECUA para uma ficha muda. A regra do que cada uma exibe é pura e
    /// mora em `SessionStore.linhaPeriferica`; aqui só se escolhe como desenhá-la.
    private var restSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("TRABALHANDO")
                    .font(.system(.caption, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.5))
                // 🚨 O número conta as ATIVAS, não a faixa inteira. Antes ele dizia 9 debaixo de
                // um título que prometia "trabalhando" e só três de fato trabalhavam.
                Text("\(ativas.count)")
                    .font(.system(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                Spacer()
            }
            if fleet.rest.isEmpty && fleet.shelf.isEmpty {
                emptyState
            } else {
                faixaDeTrabalho
                if !emRepouso.isEmpty { fileiraEmRepouso }
                if !naoObservadas.isEmpty { grupoNaoObservado }
            }
        }
    }

    /// A faixa de quem trabalha, em tantas colunas quantas deixem a ÚLTIMA FILEIRA mais cheia.
    ///
    /// 🚨 O defeito medido no retrato de 11-ago-2026: quatro lanes trabalhando numa grade que
    /// só sabia contar 3 saíam `3 + 1`, e a quarta (`kimi-cli2`) ficava sozinha com um vão
    /// largo à direita. Um órfão de layout chama atenção numa faixa cujo trabalho é justamente
    /// NÃO chamar atenção. A contagem de colunas agora é decidida (`colunasParaPeriferia`), não
    /// herdada do que a largura por acaso comportava.
    ///
    /// 🚨 A escada desce o TETO, não a contagem. Baixar 4 → 3 → 2 seria errado: com quatro
    /// lanes, três colunas CABEM na janela de 1180 e trazem de volta exatamente o órfão. O que
    /// se pergunta a cada degrau é "se coubessem no máximo `t` colunas, quantas seriam as
    /// melhores?" — e o `ViewThatFits` escolhe o primeiro degrau que cabe de fato.
    ///
    /// 🚨 E é assim que o PISO ganha da coluna extra: cada degrau declara a largura que exige
    /// (`larguraExigida`), que nunca deixa uma coluna abaixo de `larguraMinimaDaColuna` — o
    /// mesmo 340 de onde `orcamentoDaPrevia` tira os 33 caracteres. Se a coluna a mais não
    /// couber sem furar o piso, ela simplesmente não acontece, e a fronteira de palavra fica
    /// de pé.
    private var faixaDeTrabalho: some View {
        let escada = [4, 3, 2].map { SessionStore.colunasParaPeriferia(ativas.count, teto: $0) }
        return ViewThatFits(in: .horizontal) {
            grade(colunas: escada[0])
            grade(colunas: escada[1])
            grade(colunas: escada[2])
            grade(colunas: 1)
        }
    }

    private func grade(colunas c: Int) -> some View {
        let n = max(c, 1)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: SessionStore.larguraMinimaDaColuna,
                                                         maximum: 620),
                                               spacing: SessionStore.espacoEntreColunas),
                           count: n),
            alignment: .leading, spacing: 6) {
                ForEach(ativas) { lane in
                    LaneRow(lane: lane,
                            busy: acting == lane.sid,
                            onOpen: { onOpenLane(lane.sid) })
                }
            }
            // A largura que ESTA contagem exige, dita como ideal para o `ViewThatFits` medir.
            // Só vale na medição (proposta indefinida); no desenho a proposta é definida e este
            // modificador é transparente.
            .frame(idealWidth: SessionStore.larguraExigida(colunas: n))
    }

    /// As lanes que estão DE FATO trabalhando. `SessionStore.linhaPeriferica(_:).ativa` é a
    /// mesma regra que decide o conteúdo da linha — um predicado, não dois que podem divergir.
    private var ativas: [LaneSnapshot] {
        fleet.rest.filter { SessionStore.linhaPeriferica($0).ativa }
    }

    /// Paradas, encerradas, ausentes: observadas, sem pedir nada. Ocupam UMA fileira de fichas
    /// no lugar de seis linhas com prévia, estado e idade que ninguém aciona.
    private var emRepouso: [LaneSnapshot] {
        fleet.rest.filter { $0.state != .unknown && !SessionStore.linhaPeriferica($0).ativa }
    }

    /// 🚨 O rótulo fica na CALHA à esquerda, não numa linha própria: uma linha só para dizer
    /// "em repouso" custava ~23pt de altura numa faixa cujo defeito medido era justamente
    /// empurrar tudo para baixo. Aqui ele é uma palavra, uma vez — em vez da mesma palavra
    /// repetida dentro de cada uma das seis linhas, que era o estado anterior.
    private var fileiraEmRepouso: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("em repouso · \(emRepouso.count)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 96, alignment: .leading)
                .padding(.top, 3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 4)],
                      alignment: .leading, spacing: 2) {
                ForEach(emRepouso) { lane in
                    LaneChip(lane: lane, onOpen: { onOpenLane(lane.sid) })
                }
            }
        }
        .padding(.top, 2)
    }

    /// `unknown` = anunciada e nunca observada. No retrato eram QUATRO cartões `t560-*` com o mesmo
    /// peso visual de uma lane esperando aprovação, cada um repetindo a mesma frase de rodapé.
    /// Informação que não muda e não pede nada não merece área — merece uma linha.
    private var naoObservadas: [LaneSnapshot] { fleet.rest.filter { $0.state == .unknown } }

    private var grupoNaoObservado: some View {
        DisclosureGroup {
            // Fichas, pelo mesmo motivo do repouso: uma lane nunca observada é a coisa mais
            // quieta da tela, e já estava escondida atrás de um disclosure.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 4)],
                      alignment: .leading, spacing: 2) {
                ForEach(naoObservadas) { lane in
                    LaneChip(lane: lane, onOpen: { onOpenLane(lane.sid) })
                }
            }
            .padding(.top, 6)
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
            // 🚨 "Tentar de novo" implicava que a reconexão dependia do clique — mentira desde
            // que o cliente passou a nunca desistir de vez (ver `FleetStateClient.drop`). O botão
            // fica como ATALHO ("agora", não "de novo"), nunca como a única saída.
            Button("Tentar agora") { fleet.connect(); fleet.refresh() }
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
        // A tradução de `Link` para texto é PURA e mora em `FleetStateClient` — mesmo padrão de
        // `SessionStore.rotuloDeGuiar`/`semCaixa`, testável sem esta view.
        return FleetStateStore.linkDescription(fleet.link)
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
    private func act(_ lane: LaneSnapshot, _ body: @escaping () async -> FleetStateStore.ActionResult) {
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

#endif
