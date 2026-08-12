import XCTest
@testable import BeagleCore

/// O caminho de PATCH de lane única (`{t:"state"}`) — onde um campo novo desaparece sem erro.
/// O frame `sessions` reconstrói a lane inteira e portanto se defende sozinho; o `state`
/// reescreve a lane a partir de campos avulsos, e tudo que ele esquecer de copiar é perdido.
@MainActor
final class FleetStateClientTests: XCTestCase {

    private func client(comLaneExata sid: String) -> FleetStateClient {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"\(sid)","title":"\(sid)","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000},
          {"sid":"claude-1","title":"claude-1","state":"running","detail":"…","observedAt":1000}
        ]}
        """)
        return c
    }

    func testTheSessionsFrameCarriesBothProvenancesAtOnce() {
        let c = client(comLaneExata: "loom-1")
        XCTAssertEqual(c.lanes.count, 2)
        XCTAssertEqual(c.lanes.first(where: { $0.sid == "loom-1" })?.confidence, .exact)
        // A lane sem o campo é a frota de hoje: raspada da tela.
        XCTAssertEqual(c.lanes.first(where: { $0.sid == "claude-1" })?.confidence, .inferred)
    }

    func testAStatePatchWithoutConfidencePreservesTheLanesProvenance() {
        let c = client(comLaneExata: "loom-1")
        c.handle(#"{"t":"state","sid":"loom-1","state":"running","detail":"trabalhando"}"#)
        let lane = c.lanes.first { $0.sid == "loom-1" }
        XCTAssertEqual(lane?.state, .running, "o patch precisa ter sido aplicado de fato")
        // O silêncio sobre a procedência não é a afirmação de que ela piorou. Rebaixar aqui
        // apagaria o contraste no primeiro evento depois do snapshot — regressão silenciosa,
        // sem erro e sem log.
        XCTAssertEqual(lane?.confidence, .exact)
    }

    // MARK: - aceita(de:)

    /// A lane presente devolve o que o último quadro declarou.
    func testAceitaDeDevolveOValorDaLanePresente() {
        let c = client(comLaneExata: "loom-1")
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"},
          {"sid":"claude-1","title":"claude-1","state":"running","detail":"…","observedAt":1000}
        ]}
        """)
        XCTAssertEqual(c.aceita(de: "loom-1"), .redireciona)
    }

    /// Uma lane que não está no último quadro não pode virar um chute: `nil`, não um valor
    /// inventado.
    func testAceitaDeDevolveNilParaLaneAusente() {
        let c = client(comLaneExata: "loom-1")
        XCTAssertNil(c.aceita(de: "não-existe"))
    }

    /// 🚨 Distinção que a mutação (Step 6 do brief) mata se a implementação "simplificar" para a
    /// primeira lane: uma lane PRESENTE cujo `aceita` é `nil` (o servidor não declarou) também
    /// devolve `nil` — mas pelo motivo certo (silêncio sobre AQUELA lane), não por confundi-la
    /// com "não achei" nem com a lane errada.
    func testAceitaDeDevolveNilParaLanePresenteSemCapacidadeDeclarada() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"},
          {"sid":"claude-1","title":"claude-1","state":"running","detail":"…","observedAt":1000}
        ]}
        """)
        XCTAssertNil(c.aceita(de: "claude-1"), "presente, mas sem aceita declarado — nil, não a da primeira lane")
    }

    func testAStatePatchThatDeclaresConfidenceWins() {
        let c = client(comLaneExata: "loom-1")
        c.handle(#"{"t":"state","sid":"loom-1","state":"idle","confidence":"inferred"}"#)
        XCTAssertEqual(c.lanes.first { $0.sid == "loom-1" }?.confidence, .inferred)
        // E um valor que não conhecemos não promove nem rebaixa: mantém o que havia.
        let d = client(comLaneExata: "loom-1")
        d.handle(#"{"t":"state","sid":"loom-1","state":"idle","confidence":"talvez"}"#)
        XCTAssertEqual(d.lanes.first { $0.sid == "loom-1" }?.confidence, .exact)
    }

    func testAPatchNeverPromotesAScrapedLaneToExactByAccident() {
        let c = client(comLaneExata: "loom-1")
        c.handle(#"{"t":"state","sid":"claude-1","state":"waiting","detail":"Do you want to proceed?"}"#)
        XCTAssertEqual(c.lanes.first { $0.sid == "claude-1" }?.confidence, .inferred)
    }

    // MARK: - O que está sendo aprovado sobrevive ao patch de lane única

    /// Um cliente cuja lane medida já trouxe diff e tipo de aprovação no quadro `sessions`.
    private func clienteComPedido() -> FleetStateClient {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"waiting",
           "detail":"Press enter to confirm or esc to cancel",
           "diff":"diff --git a/x b/x\\n@@ -0,0 +1 @@\\n+oi\\n","approvalKind":"patch",
           "confidence":"exact","observedAt":1000}
        ]}
        """)
        return c
    }

    /// 🚨 A regressão que já aconteceu QUATRO vezes neste mesmo ponto (`confidence`, `aceita`,
    /// `usd` — e agora `diff`): o frame `state` remonta a lane a partir de campos avulsos, e
    /// tudo que ele esquecer de copiar some sem erro e sem log. Um frame que NÃO menciona o
    /// diff é silêncio sobre a mudança proposta, não a revogação dela.
    func testUmPatchSemDiffPRESERVAOPatchAnterior() throws {
        let c = clienteComPedido()
        let antes = try XCTUnwrap(c.lanes.first { $0.sid == "loom-1" }?.diff)
        c.handle(#"{"t":"state","sid":"loom-1","state":"waiting","detail":"ainda esperando"}"#)
        let lane = try XCTUnwrap(c.lanes.first { $0.sid == "loom-1" })
        XCTAssertEqual(lane.detail, "ainda esperando", "o patch precisa ter sido aplicado de fato")
        XCTAssertEqual(lane.diff, antes, "o silêncio sobre o diff não pode apagar o diff")
    }

    /// Mesma disciplina para o TIPO: sem ele o card volta a não saber dizer o que está aprovando.
    func testUmPatchSemTipoDeAprovacaoPRESERVAOTipoAnterior() throws {
        let c = clienteComPedido()
        c.handle(#"{"t":"state","sid":"loom-1","state":"waiting","detail":"ainda esperando"}"#)
        XCTAssertEqual(c.lanes.first { $0.sid == "loom-1" }?.approvalKind, .patch)
    }

    /// A outra metade da regra, e a que impede o `?? old` cru: chave PRESENTE é o servidor
    /// DIZENDO que não há mais pedido — e aí manter o patch na tela seria mostrar a mudança de
    /// um pedido já respondido.
    func testUmPatchQueDECLARAAAusenciaDoPedidoLimpaOCard() throws {
        let c = clienteComPedido()
        c.handle(#"{"t":"state","sid":"loom-1","state":"running","diff":null,"approvalKind":null}"#)
        let lane = try XCTUnwrap(c.lanes.first { $0.sid == "loom-1" })
        XCTAssertNil(lane.diff)
        XCTAssertNil(lane.approvalKind)
    }

    /// E um patch que TRAZ diff novo troca o anterior — senão o card ficaria preso no primeiro.
    func testUmPatchComDiffNovoSubstituiOAnterior() throws {
        let c = clienteComPedido()
        c.handle(#"{"t":"state","sid":"loom-1","state":"waiting","diff":"diff --git a/y b/y\n","approvalKind":"command"}"#)
        let lane = try XCTUnwrap(c.lanes.first { $0.sid == "loom-1" })
        XCTAssertEqual(lane.diff, "diff --git a/y b/y\n")
        XCTAssertEqual(lane.approvalKind, .command)
    }

    // MARK: - A queda da fonte medida, do frame até a propriedade que a tela lê

    /// Frame `sessions` com a fonte VIVA e a lane medida presente.
    private func frameVivo() -> String {
        """
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000},
          {"sid":"claude-1","title":"claude-1","state":"running","detail":"…","observedAt":1000}
        ],"loomd":{"mode":"observed","truthMode":"observed","observedAt":1000,"readAt":1000,
          "lanes":1,"lost":[],"error":null}}
        """
    }

    /// Frame `sessions` DEPOIS da queda: a lane medida sumiu do array — que é exatamente como o
    /// bug se apresentava — e o servidor manda o modo e o motivo.
    private func frameCaido(lost: String = #"["loom-1"]"#) -> String {
        """
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"running","detail":"…","observedAt":2000}
        ],"loomd":{"mode":"down","truthMode":"unknown","observedAt":1000,"readAt":2000,
          "lanes":0,"lost":\(lost),
          "error":"loomd não respondeu em 127.0.0.1:4400 dentro do pod (bloco vazio ou fora do contrato)"}}
        """
    }

    func testOFrameDeSessoesTrazASaudeDaFonteENaoSoAsLanes() {
        // Antes disto o cliente fazia `arr.compactMap(...)` e descartava o resto do frame: o
        // bloco chegava e morria no parser.
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        XCTAssertEqual(c.loomd?.mode, .observed)
        XCTAssertEqual(c.loomd?.lanes, 1)
        XCTAssertFalse(c.loomd?.isDegraded ?? true, "fonte viva não desenha faixa")
    }

    func testQuandoAFonteCaiALaneNaoSomeSemNome() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        c.handle(frameCaido())
        // O card realmente sumiu do board — é o comportamento que se estava vendo…
        XCTAssertNil(c.lanes.first { $0.sid == "loom-1" })
        // …mas agora a queda tem modo, motivo e NOME.
        XCTAssertEqual(c.loomd?.mode, .down)
        XCTAssertTrue(c.loomd?.isDegraded ?? false)
        XCTAssertEqual(c.loomd?.lost, ["loom-1"])
        XCTAssertTrue(c.loomd?.reason.contains("127.0.0.1:4400") ?? false)
    }

    func testOClienteNomeiaALanePerdidaMesmoQuandoOServidorEsquece() {
        // O `lost[]` do servidor zera quando o cockpit reinicia — e a lane continua fora do
        // board. O diff antes/depois feito do lado do cliente é o único que o outro lado não
        // pode apagar.
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        c.handle(frameCaido(lost: "[]"))
        XCTAssertEqual(c.loomd?.lost, ["loom-1"], "o cliente viu a lane exata sair; tem que dizer o nome")
    }

    func testONomeDaLanePerdidaSobreviveAosFramesSeguintes() {
        // No sweep seguinte a lane já não está no estado anterior, então o diff não a reencontra.
        // Sem a trava, o nome apareceria por um frame e sumiria — pior que nunca ter aparecido.
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        c.handle(frameCaido(lost: "[]"))
        c.handle(frameCaido(lost: "[]"))
        XCTAssertEqual(c.loomd?.lost, ["loom-1"])
    }

    func testAFonteQueVoltaParaDeAcusarPerda() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        c.handle(frameCaido(lost: "[]"))
        c.handle(frameVivo())
        XCTAssertEqual(c.loomd?.lost, [], "a lane voltou; manter a acusação seria mentira")
        XCTAssertFalse(c.loomd?.isDegraded ?? true)
    }

    func testUmaLaneRaspadaQueSomeNaoEPenduradaNaQuedaDoLoomd() {
        // `claude-1` some por tmux/pod, não pela fonte medida. Acusar o loomd aqui mandaria o
        // operador depurar o processo errado.
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle(frameVivo())
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"idle","confidence":"exact","observedAt":2000}
        ],"loomd":{"mode":"stale","observedAt":1000,"readAt":2000,"lanes":1,"lost":[],"error":null}}
        """)
        XCTAssertEqual(c.loomd?.lost, [], "claude-1 é lane raspada; a queda do loomd não a levou")
    }

    func testUmCockpitAntigoNaoInventaUmaQueda() {
        // Frame sem o bloco: o servidor não falou da fonte. Silêncio não é afirmação, e um
        // `.unknown` fabricado aqui desenharia faixa sobre algo que ninguém mencionou.
        let c = client(comLaneExata: "loom-1")
        XCTAssertNil(c.loomd)
    }
}
