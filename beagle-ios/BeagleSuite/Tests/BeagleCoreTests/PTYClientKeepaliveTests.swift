import XCTest
@testable import BeagleCore

/// Dois defeitos medidos no Mac do operador faziam as lanes congelarem para sempre:
/// (1) um socket half-open não lança erro em `receive()` — fica pendurado sem nunca
///     detectar a queda; (2) depois de `maxRetries` falhas a lane virava `.failed` de
///     vez e nunca mais tentava, mesmo com a rede de volta.
///
/// As duas decisões que resolvem isso são extraídas em funções PURAS — sem isso, testar
/// o cão de guarda do pong exigiria esperar 45s de verdade a cada `swift test`.
final class PTYClientKeepaliveTests: XCTestCase {

    // MARK: - deveDerrubar(ultimoPong:agora:tetoSegundos:)

    func testSemPongAindaDentroDoTetoNaoDerruba() {
        XCTAssertFalse(PTYClient.deveDerrubar(ultimoPong: 0, agora: 30, tetoSegundos: 45))
    }

    func testSemPongAlemDoTetoDerruba() {
        XCTAssertTrue(PTYClient.deveDerrubar(ultimoPong: 0, agora: 46, tetoSegundos: 45))
    }

    func testExatamenteNoTetoAindaNaoDerruba() {
        // Fronteira: só depois de passar do teto, não no instante exato.
        XCTAssertFalse(PTYClient.deveDerrubar(ultimoPong: 0, agora: 45, tetoSegundos: 45))
    }

    func testPongRecenteReiniciaAJanela() {
        XCTAssertFalse(PTYClient.deveDerrubar(ultimoPong: 100, agora: 130, tetoSegundos: 45))
    }

    // MARK: - proximoAtrasoMs(retries:)

    func testAtrasoCrescePorRetentativa() {
        let a1 = PTYClient.proximoAtrasoMs(retries: 1)
        let a2 = PTYClient.proximoAtrasoMs(retries: 2)
        let a3 = PTYClient.proximoAtrasoMs(retries: 3)
        XCTAssertLessThan(a1, a2)
        XCTAssertLessThan(a2, a3)
    }

    func testAtrasoTemTeto() {
        // O teto é ~30s — sem ele, uma tempestade de retentativa é exatamente o que
        // fez o macOS pôr o app em quarentena de log por volume.
        let tetoMs = 30_000
        for r in 1...50 {
            XCTAssertLessThanOrEqual(PTYClient.proximoAtrasoMs(retries: r), tetoMs,
                                      "retries=\(r) deve respeitar o teto de 30s")
        }
    }

    func testAtrasoNuncaZero() {
        // Um atraso zero vira laço apertado — a mesma tempestade, só que mais rápida.
        for r in 1...50 {
            XCTAssertGreaterThan(PTYClient.proximoAtrasoMs(retries: r), 0)
        }
    }

    func testAtrasoContinuaNoTetoParaRetriesGrandes() {
        // A lane NUNCA desiste de vez: retries pode crescer sem limite, o atraso apenas
        // satura no teto — não existe mais um "retries < maxRetries" que trava a lane.
        let a100 = PTYClient.proximoAtrasoMs(retries: 100)
        let a1000 = PTYClient.proximoAtrasoMs(retries: 1000)
        XCTAssertEqual(a100, 30_000)
        XCTAssertEqual(a1000, 30_000)
    }
}
