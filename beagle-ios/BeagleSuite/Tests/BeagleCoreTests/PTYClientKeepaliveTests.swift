import Foundation
import Testing
@testable import BeagleCore

/// Dois defeitos medidos no Mac do operador faziam as lanes congelarem para sempre:
/// (1) um socket half-open não lança erro em `receive()` — fica pendurado sem nunca
///     detectar a queda; (2) depois de `maxRetries` falhas a lane virava `.failed` de
///     vez e nunca mais tentava, mesmo com a rede de volta.
///
/// As duas decisões que resolvem isso são extraídas em funções PURAS — sem isso, testar
/// o cão de guarda do pong exigiria esperar 45s de verdade a cada `swift test`.
@Suite
struct PTYClientKeepaliveTests {

    // MARK: - deveDerrubar(ultimoPong:agora:tetoSegundos:)

    @Test func testSemPongAindaDentroDoTetoNaoDerruba() {
        #expect(!PTYClient.deveDerrubar(ultimoPong: 0, agora: 30, tetoSegundos: 45))
    }

    @Test func testSemPongAlemDoTetoDerruba() {
        #expect(PTYClient.deveDerrubar(ultimoPong: 0, agora: 46, tetoSegundos: 45))
    }

    @Test func testExatamenteNoTetoAindaNaoDerruba() {
        // Fronteira: só depois de passar do teto, não no instante exato.
        #expect(!PTYClient.deveDerrubar(ultimoPong: 0, agora: 45, tetoSegundos: 45))
    }

    @Test func testPongRecenteReiniciaAJanela() {
        #expect(!PTYClient.deveDerrubar(ultimoPong: 100, agora: 130, tetoSegundos: 45))
    }

    // MARK: - proximoAtrasoMs(retries:)

    @Test func testAtrasoCrescePorRetentativa() {
        let a1 = PTYClient.proximoAtrasoMs(retries: 1)
        let a2 = PTYClient.proximoAtrasoMs(retries: 2)
        let a3 = PTYClient.proximoAtrasoMs(retries: 3)
        #expect(a1 < a2)
        #expect(a2 < a3)
    }

    @Test func testAtrasoTemTeto() {
        // O teto é ~30s — sem ele, uma tempestade de retentativa é exatamente o que
        // fez o macOS pôr o app em quarentena de log por volume.
        let tetoMs = 30_000
        for r in 1...50 {
            #expect(PTYClient.proximoAtrasoMs(retries: r) <= tetoMs,
                    "retries=\(r) deve respeitar o teto de 30s")
        }
    }

    @Test func testAtrasoNuncaZero() {
        // Um atraso zero vira laço apertado — a mesma tempestade, só que mais rápida.
        for r in 1...50 {
            #expect(PTYClient.proximoAtrasoMs(retries: r) > 0)
        }
    }

    @Test func testAtrasoContinuaNoTetoParaRetriesGrandes() {
        // A lane NUNCA desiste de vez: retries pode crescer sem limite, o atraso apenas
        // satura no teto — não existe mais um "retries < maxRetries" que trava a lane.
        let a100 = PTYClient.proximoAtrasoMs(retries: 100)
        let a1000 = PTYClient.proximoAtrasoMs(retries: 1000)
        #expect(a100 == 30_000)
        #expect(a1000 == 30_000)
    }
}
