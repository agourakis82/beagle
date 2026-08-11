import XCTest
@testable import BeagleCore

/// Achado de review pós-Task-4 (Sessão): `FleetStateClient` desistia de vez depois de
/// `maxRetries` quedas e ficava em `.failed` até algo EXTERNO chamar `connect()` de novo. Antes
/// disso "funcionava" porque `FrotaView.onAppear` religava sem condição — mas quem fica parado
/// na Sessão, lendo, não tem esse gesto, e é essa pessoa a mais prejudicada por um link morto que
/// ninguém revive sozinho. Mesmo defeito que `PTYClient` já teve e já consertou — ver
/// `PTYClientKeepaliveTests` — e o mesmo remédio: extrair o backoff numa função PURA e provar que
/// ela nunca "sinaliza desistência", nem depois de centenas de falhas.
final class FleetStateClientKeepaliveTests: XCTestCase {

    // MARK: - proximoAtrasoMs(retries:)

    func testAtrasoCrescePorRetentativa() {
        let a1 = FleetStateClient.proximoAtrasoMs(retries: 1)
        let a2 = FleetStateClient.proximoAtrasoMs(retries: 2)
        let a3 = FleetStateClient.proximoAtrasoMs(retries: 3)
        XCTAssertLessThan(a1, a2)
        XCTAssertLessThan(a2, a3)
    }

    func testAtrasoTemTeto() {
        // O teto é 10s — sem ele, uma tempestade de retentativa é o tipo de coisa que bota o
        // app em quarentena de log por volume.
        let tetoMs = 10_000
        for r in 1...50 {
            XCTAssertLessThanOrEqual(FleetStateClient.proximoAtrasoMs(retries: r), tetoMs,
                                      "retries=\(r) deve respeitar o teto de 10s")
        }
    }

    func testAtrasoNuncaZero() {
        // Um atraso zero vira laço apertado — a mesma tempestade, só que mais rápida.
        for r in 1...50 {
            XCTAssertGreaterThan(FleetStateClient.proximoAtrasoMs(retries: r), 0)
        }
    }

    /// 🚨 A prova central desta rodada de conserto: o cliente NUNCA desiste de vez. `retries`
    /// pode crescer sem limite — o atraso só satura no teto, nunca vira um sinal de "pare". Se
    /// `proximoAtrasoMs` alguma hora ganhar um ramo de desistência (por exemplo, devolvendo um
    /// valor não-positivo depois de N falhas), este teste tem de acusar — é exatamente a
    /// regressão que esta rodada existe para impedir.
    func testAtrasoContinuaNoTetoParaRetriesGrandesENuncaSinalizaDesistencia() {
        let a100 = FleetStateClient.proximoAtrasoMs(retries: 100)
        let a1000 = FleetStateClient.proximoAtrasoMs(retries: 1000)
        XCTAssertEqual(a100, 10_000)
        XCTAssertEqual(a1000, 10_000)
        XCTAssertGreaterThan(a100, 0, "um valor <= 0 seria o cliente dizendo 'desista'")
        XCTAssertGreaterThan(a1000, 0, "um valor <= 0 seria o cliente dizendo 'desista'")
    }
}
