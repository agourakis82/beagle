import XCTest
@testable import BeagleCore

/// A lógica da Sessão, sem rede.
///
/// 🚨 POR QUE ESTES TESTES FALTAVAM, e é a dívida que eles pagam: a Sessão foi construída com
/// RETRATO (PNG) e prova ao vivo. As duas coisas são necessárias e nenhuma cobre isto — o retrato
/// mostra um estado parado, e a prova ao vivo mostra o caminho felizes. O que decide se a tela
/// mente é a redução: cursor que não anda, evento repetido que duplica a fala, turno que agrupa
/// errado. Nada disso aparece num PNG bonito nem num turno que deu certo.
final class SessionStoreTests: XCTestCase {

    private func ev(_ seq: Int, _ kind: String, text: String? = nil, diff: String? = nil,
                    tool: String? = nil, approval: SessionStep.ApprovalKind? = nil) -> TramaEvent {
        var o: [String: Any] = ["seq": seq, "ts_ms": 1_786_000_000_000.0 + Double(seq) * 1000,
                                "lane": "codex-4", "kind": kind]
        if let text { o["text"] = text }
        if let diff { o["diff"] = diff }
        if let tool { o["tool"] = tool }
        if let approval { o["approval_kind"] = approval.rawValue }
        let data = try! JSONSerialization.data(withJSONObject: o)
        return try! JSONDecoder().decode(TramaEvent.self, from: data)
    }

    private func page(_ eventos: [TramaEvent], since: Int = 0, cursor: Int? = nil,
                      streaming: String? = nil, turnRunning: Bool? = nil) -> SessionStore.Page {
        let c = cursor ?? (eventos.map(\.seq).max() ?? since)
        var o: [String: Any] = ["lane": "codex-4", "since": since, "cursor": c,
                                "events": eventos.map { e -> [String: Any] in
                                    var d: [String: Any] = ["seq": e.seq, "ts_ms": e.tsMs,
                                                            "lane": e.lane, "kind": e.kind]
                                    if let t = e.text { d["text"] = t }
                                    if let d2 = e.diff { d["diff"] = d2 }
                                    if let t = e.tool { d["tool"] = t }
                                    if let a = e.approvalKind { d["approval_kind"] = a.rawValue }
                                    return d
                                }]
        if let streaming { o["streaming"] = streaming }
        if let turnRunning { o["turnRunning"] = turnRunning }
        let data = try! JSONSerialization.data(withJSONObject: o)
        return try! JSONDecoder().decode(SessionStore.Page.self, from: data)
    }

    // ─── tradução ────────────────────────────────────────────────────────────────────────

    @MainActor
    func testDeltaNuncaViraPasso() {
        // O loomd coalesce os 70 deltas de um turno e manda o parcial em `streaming`. Se `delta`
        // também virasse passo, a mesma frase apareceria N vezes na trilha — e a lista piscaria a
        // cada volta do poll.
        XCTAssertNil(SessionStore.passo(de: ev(1, "delta", text: "Vou")))
        for ruido in ["turn_started", "turn_ended", "session_started", "session_ended",
                      "idle", "approval_answered", "unknown"] {
            XCTAssertNil(SessionStore.passo(de: ev(2, ruido)),
                         "\(ruido) é ciclo de vida, não conteúdo nem decisão")
        }
    }

    @MainActor
    func testDiffVazioNaoViraPasso() {
        // Um `diff_proposed` sem texto desenharia um bloco de código em branco, que lê como
        // "o agente propôs nada" em vez de "não houve diff".
        XCTAssertNil(SessionStore.passo(de: ev(1, "diff_proposed")))
        XCTAssertNil(SessionStore.passo(de: ev(2, "diff_proposed", diff: "")))
        XCTAssertNotNil(SessionStore.passo(de: ev(3, "diff_proposed", diff: "--- a\n+++ b\n")))
    }

    @MainActor
    func testErroSemDescricaoAindaDizAlgo() {
        // Erro é conteúdo de primeira classe. Um erro vazio na tela é pior que nenhum: some sem
        // deixar rastro de que houve falha.
        guard case .failure(_, let t, _)? = SessionStore.passo(de: ev(1, "error")) else {
            return XCTFail("erro deveria virar passo")
        }
        XCTAssertFalse(t.isEmpty)
    }

    @MainActor
    func testAprovacaoSemTipoCaiEmOther() {
        // Um evento antigo, relido de um diário escrito antes de `approval_kind` existir, não pode
        // virar `patch` por otimismo — patch diz "reversível por git", e isso decide se ele lê o
        // comando antes de aprovar.
        guard case .approval(_, let k, _, _)? = SessionStore.passo(de: ev(1, "awaiting_approval")) else {
            return XCTFail("aprovação deveria virar passo")
        }
        XCTAssertEqual(k, .other)
        XCTAssertFalse(k.reversible, "sem saber o tipo, não prometa reversibilidade")
    }

    // ─── cursor e dedup ──────────────────────────────────────────────────────────────────

    @MainActor
    func testEventoRepetidoNaoDuplicaAFala() {
        // O cursor vem do servidor e a trama é append-only, então repetição só acontece se um poll
        // for reaplicado — o que acontece de verdade quando a resposta chega duas vezes. Sem a
        // guarda por `seq`, a mesma fala aparece duas vezes na trilha.
        let s = SessionStore(lane: "codex-4")
        let p = page([ev(1, "user_prompt", text: "oi"), ev(2, "agent_message", text: "olá")])
        s.apply(p)
        s.apply(p)
        XCTAssertEqual(s.steps.count, 2)
    }

    @MainActor
    func testCursorNuncaAndaParaTras() {
        // Uma página que chega fora de ordem (rede) não pode reverter o cursor: reverter faria o
        // próximo poll pedir de novo o que já se viu, e a dedup por `seq` esconderia o sintoma — a
        // tela pararia de crescer sem dizer por quê.
        //
        // 🚨 A ASSERÇÃO É SOBRE O CURSOR, não sobre a contagem de passos. A primeira versão deste
        // teste contava `steps` e ficava VERDE com a regressão: `apply` guarda o cursor mas não o
        // usa para filtrar, então trocar `max(...)` por atribuição direta não mudava passo nenhum.
        // Foi a mutação que revelou — e a lição é a de sempre: verde só vale se a condição foi
        // exercida.
        let s = SessionStore(lane: "codex-4")
        s.apply(page([ev(10, "agent_message", text: "dez")], cursor: 10))
        XCTAssertEqual(s.cursor, 10)
        s.apply(page([], since: 3, cursor: 3))
        XCTAssertEqual(s.cursor, 10, "uma página velha não pode fazer o cliente reler o diário")
        s.apply(page([ev(11, "agent_message", text: "onze")], cursor: 11))
        XCTAssertEqual(s.cursor, 11)
        XCTAssertEqual(s.steps.count, 2)
    }

    @MainActor
    func testTurnoEmCursoVemDoServidorEnaoDoParcial() {
        // 🚨 `turnRunning` é EXPLÍCITO. Um turno que ainda não emitiu texto também é um turno, e é
        // justamente aí que mais se quer o botão de parar. Derivar do parcial perderia esse caso.
        let s = SessionStore(lane: "codex-4")
        s.apply(page([], turnRunning: true))
        XCTAssertTrue(s.turnoEmCurso, "sem parcial nenhum, o servidor disse que há turno")
        s.apply(page([], turnRunning: false))
        XCTAssertFalse(s.turnoEmCurso)
    }

    @MainActor
    func testOParcialSomeQuandoOServidorParaDeMandar() {
        let s = SessionStore(lane: "codex-4")
        s.apply(page([], streaming: "Vou ler os"))
        XCTAssertEqual(s.streaming, "Vou ler os")
        s.apply(page([ev(5, "agent_message", text: "Vou ler os módulos.")]))
        XCTAssertNil(s.streaming, "a mensagem completa chegou; o parcial não pode ficar embaixo")
        XCTAssertEqual(s.steps.count, 1)
    }

    // ─── agrupamento em turnos ───────────────────────────────────────────────────────────

    @MainActor
    func testUmTurnoPorPEDIDO() {
        let passos = [
            SessionStep.prompt(id: 1, text: "a", at: .init()),
            .message(id: 2, text: "ra", at: .init()),
            .prompt(id: 3, text: "b", at: .init()),
            .tool(id: 4, name: "Read", detail: "x", at: .init()),
            .message(id: 5, text: "rb", at: .init()),
        ]
        let t = Turno.agrupar(passos)
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(t[0].pedido, "a")
        XCTAssertEqual(t[1].pedido, "b")
        XCTAssertEqual(t[1].passos.count, 3)
        XCTAssertEqual(t[0].id, 1, "o id é o seq do primeiro passo — estável, então a lista não reordena")
    }

    @MainActor
    func testOQueVemANTESDoPrimeiroPedidoNaoEDoPedidoSEGUINTE() {
        // 🚨 Sessão RETOMADA: o pedido está fora da janela do diário. Pendurar aquele trabalho no
        // próximo pedido seria atribuí-lo ao pedido errado — e é o tipo de erro que faz alguém
        // aprovar a coisa errada por ler o contexto trocado.
        let t = Turno.agrupar([
            .message(id: 90, text: "terminei a varredura", at: .init()),
            .prompt(id: 91, text: "quais?", at: .init()),
            .message(id: 92, text: "três", at: .init()),
        ])
        XCTAssertEqual(t.count, 2)
        XCTAssertNil(t[0].pedido, "o primeiro bloco não tem pedido, e a tela precisa poder dizer isso")
        XCTAssertEqual(t[0].passos.count, 1)
        XCTAssertEqual(t[1].pedido, "quais?")
    }

    @MainActor
    func testTurnoSabeSeTemDiffESePedePermissao() {
        // É o que o cabeçalho do turno resume — serve para decidir se vale abrir com o olho.
        let t = Turno.agrupar([
            .prompt(id: 1, text: "arruma", at: .init()),
            .diff(id: 2, patch: "--- a\n+++ b\n", at: .init()),
            .approval(id: 3, kind: .patch, detail: "x", at: .init()),
        ])[0]
        XCTAssertTrue(t.temDiff)
        XCTAssertTrue(t.pedePermissao)

        let simples = Turno.agrupar([.prompt(id: 1, text: "oi", at: .init())])[0]
        XCTAssertFalse(simples.temDiff)
        XCTAssertFalse(simples.pedePermissao)
    }

    @MainActor
    func testDuracaoNaoEAFIRMADAParaTurnoEmCurso() {
        // Afirmar duração de algo que está correndo é dizer que acabou.
        let t = Turno.agrupar([
            .prompt(id: 1, text: "oi", at: Date(timeIntervalSince1970: 1000)),
            .message(id: 2, text: "olá", at: Date(timeIntervalSince1970: 1042)),
        ])[0]
        XCTAssertNil(t.duracao(concluido: false))
        XCTAssertEqual(t.duracao(concluido: true) ?? 0, 42, accuracy: 0.001)
    }

    // ─── o roster vivo ───────────────────────────────────────────────────────────────────

    @MainActor
    func testORosterVivoVemDoServidorMasNaoESVAZIANumaQueda() {
        // 🚨 A dívida que isto paga: `loomdLanes` era constante espelhando o launcher do pod, e eu
        // editei os dois lados à mão ao adotar `codex-4`. Agora quem manda é o servidor — MAS um
        // roster vazio numa queda do loomd significa "não sei", não "não há lane". Tratar os dois
        // igual esvaziaria o allowlist e toda ação seria descartada em silêncio.
        let c = FleetStateClient.fixture(lanes: [], loomd: LoomdHealth(
            mode: .observed, lanes: 2, roster: ["codex-4", "loom-1"], everObserved: true))
        XCTAssertEqual(c.loomdRoster, ["codex-4", "loom-1"], "observado: manda o servidor")

        let caido = FleetStateClient.fixture(lanes: [], loomd: LoomdHealth(
            mode: .down, lanes: 0, roster: [], error: "connection refused", everObserved: true))
        XCTAssertEqual(caido.loomdRoster, FleetEndpoint.loomdLanes,
                       "fonte caída: cai na semente em vez de esvaziar")

        let vazioObservado = FleetStateClient.fixture(lanes: [], loomd: LoomdHealth(
            mode: .observed, lanes: 0, roster: [], everObserved: true))
        XCTAssertEqual(vazioObservado.loomdRoster, FleetEndpoint.loomdLanes,
                       "observado mas vazio também cai na semente — nunca uma lista vazia")
    }
}
