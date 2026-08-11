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
}
