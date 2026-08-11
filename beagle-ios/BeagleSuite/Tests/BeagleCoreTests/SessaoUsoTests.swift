import XCTest
@testable import BeagleCore

/// `aceita` é declarado pelo servidor, nunca deduzido. Existe porque `LaneFamily.of(sid)` devolve
/// `.claude` tanto para `claude-1` (tail, o loomd só LÊ — /prompt e /steer devolvem 404) quanto
/// para `claude-4` (ACP, `promptQueueing` ENFILEIRA) — mesmo prefixo, comportamentos opostos.
/// Estes testes existem para impedir que alguém "simplifique" derivando do sid.
@MainActor
final class SessaoUsoTests: XCTestCase {

    private func loomObj(_ extra: String = "") -> [String: Any] {
        let json = """
        {"sid":"claude-1","title":"claude-1","kind":"agent_message","confidence":"exact",
         "detail":"x","observedAt":0,"turns":0\(extra)}
        """
        let data = json.data(using: .utf8)!
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testAceitaVemDoJSONeNaoDoSid() throws {
        let obj = loomObj(#","aceita":"somente_leitura""#)
        let snap = try XCTUnwrap(LaneSnapshot(loom: obj))
        XCTAssertEqual(snap.aceita, .somenteLeitura)
        XCTAssertEqual(snap.family, .claude, "a família segue sendo claude — e não decide capacidade")
    }

    func testAceitaAusenteEhNil() throws {
        let obj = loomObj()
        let snap = try XCTUnwrap(LaneSnapshot(loom: obj))
        XCTAssertNil(snap.aceita, "lane sem capacidade declarada não pode virar um chute")
    }

    func testAceitaRedirecionaEEnfileiraDecodificamTambem() throws {
        let redireciona = try XCTUnwrap(LaneSnapshot(loom: loomObj(#","aceita":"redireciona""#)))
        XCTAssertEqual(redireciona.aceita, .redireciona)
        let enfileira = try XCTUnwrap(LaneSnapshot(loom: loomObj(#","aceita":"enfileira""#)))
        XCTAssertEqual(enfileira.aceita, .enfileira)
    }

    /// 🚨 O caminho de patch de lane única (`{t:"state"}`) é onde um campo novo some em silêncio
    /// — igual aconteceu com `confidence` antes de o comentário no `handle` existir. Uma lane
    /// com `aceita` conhecido recebe um frame `state` que NÃO menciona `aceita`, e a capacidade
    /// tem de sobreviver (cair para `old.aceita`, nunca para `nil`).
    func testUmPatchDeStateSemAceitaPreservaACapacidade() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"somente_leitura"}
        ]}
        """)
        XCTAssertEqual(c.lanes.first { $0.sid == "claude-1" }?.aceita, .somenteLeitura)

        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        XCTAssertEqual(lane?.state, .running, "o patch precisa ter sido aplicado de fato")
        XCTAssertEqual(lane?.aceita, .somenteLeitura, "silêncio sobre aceita não é revogação da capacidade")
    }

    // MARK: - Uso do turno (custo e contexto)

    /// 🚨 MEDIDO nas fixtures do censo ACP: `cost.amount` vem NULO em 15 dos 16 eventos de um
    /// turno — só o último traz o número. Somar "funciona" por ACIDENTE (os outros são zero) e
    /// quebra no dia em que o protocolo preencher os intermediários. O certo é o ÚLTIMO com custo.
    func testUsoDoTurnoPegaOUltimoComCustoNaoASoma() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .uso(id: 2, contextoUsado: 31_578, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 3, contextoUsado: 36_874, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 4, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = Turno.agrupar(passos)[0]
        let uso = try! XCTUnwrap(turno.uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o último com custo, não a soma")
        XCTAssertEqual(uso.contextoUsado, 38_718, "contexto é absoluto e monotônico: o último vale")
        XCTAssertEqual(uso.contextoTeto, 1_000_000)
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP (medido). O rodapé
    /// mostra proporção, então o teto não pode ser constante no código.
    func testTetoDeContextoVemDoEventoNaoDoCodigo() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 28_795, contextoTeto: 258_400, usd: 0.01, at: t0),
        ]
        XCTAssertEqual(Turno.agrupar(passos)[0].uso?.contextoTeto, 258_400)
    }

    func testTurnoSemUsoNaoInventaZero() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "x", at: t0),
                                     .message(id: 2, text: "y", at: t0)]
        XCTAssertNil(Turno.agrupar(passos)[0].uso, "sem evento de uso, o rodapé não mostra custo")
    }

    /// O evento `usage` da trama traz o custo em `detail`, no formato que o loomd escreve:
    /// "contexto 38718/1000000 · USD 0.3728"
    func testPassoDeUsageParseiaODetail() throws {
        let e = TramaEvent(seq: 9, tsMs: 0, lane: "claude-4", kind: "usage",
                           text: nil, detail: "contexto 38718/1000000 · USD 0.3728", diff: nil,
                           tool: nil, approvalKind: nil)
        let passo = try XCTUnwrap(SessionStore.passo(de: e))
        guard case .uso(_, let usado, let teto, let usd, _) = passo else {
            return XCTFail("usage tem de virar .uso, não sumir no default")
        }
        XCTAssertEqual(usado, 38_718); XCTAssertEqual(teto, 1_000_000)
        XCTAssertEqual(usd, 0.3728, accuracy: 0.0001)
    }

    /// O último evento de `usage` do turno pode vir SEM custo (fechamento). Se o código
    /// sobrescrever o custo com esse zero, o turno perde o preço que já tinha.
    func testUsoNaoPerdeOCustoQuandoOUltimoEventoVemZerado() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 38_000, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0, at: t0),
        ]
        let uso = try! XCTUnwrap(Turno.agrupar(passos)[0].uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o zero de fechamento não apaga o custo")
        XCTAssertEqual(uso.contextoUsado, 38_718, "mas o contexto é o último, sempre")
    }

    /// 🚨 Achado da review: `.uso` devolvia `EmptyView()` na trilha, mas um `EmptyView()` ainda
    /// ocupa posição no `ForEach` dentro do `VStack` — o `spacing` fixo abre um buraco visível a
    /// cada evento `uso`. O passo tem de ser filtrado ANTES de chegar à lista, não desenhado
    /// vazio. Este teste prende as duas metades: o custo não desaparece (`turno.uso` continua
    /// alcançável) e não polui a conversa (`desenhavel` corta para 2 de 3 passos).
    func testUsoNaoEhDesenhavelMasContinuaAlcancavelViaTurnoUso() throws {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .message(id: 2, text: "feito", at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = Turno.agrupar(passos)[0]
        XCTAssertEqual(turno.passos.count, 3, "os três passos existem no turno")
        XCTAssertEqual(turno.passos.filter(\.desenhavel).count, 2,
                        "custo não é fala: não entra na trilha desenhada")
        XCTAssertEqual(try XCTUnwrap(turno.uso).usd, 0.3728, accuracy: 0.0001,
                        "mas o custo continua alcançável pelo rodapé")
    }

    // MARK: - O botão diz o que VAI acontecer

    /// 🚨 A caixa diz "guiar o turno em curso" e o botão diz GUIAR. Verdade no codex; MENTIRA na
    /// lane ACP, que enfileira. Mentir no momento da decisão é pior que contar depois — o
    /// operador já agiu.
    func testRotuloDizAVerdadeAntesDoClique() {
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.redireciona), "GUIAR")
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.enfileira), "ENFILEIRAR")
        XCTAssertNil(SessionStore.rotuloDeGuiar(.somenteLeitura), "lane de leitura não oferece gesto")
        XCTAssertNil(SessionStore.rotuloDeGuiar(nil), "sem capacidade declarada, não se oferece nada")
    }

    func testCaixaDeTextoNaoExisteEmLaneDeLeitura() {
        XCTAssertNil(SessionStore.dicaDaCaixa(.somenteLeitura))
        XCTAssertEqual(SessionStore.dicaDaCaixa(.enfileira), "enfileirar para depois deste…")
        XCTAssertEqual(SessionStore.dicaDaCaixa(.redireciona), "guiar o turno em curso…")
    }

}
