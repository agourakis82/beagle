import Foundation
import Testing
@testable import BeagleCore

/// Achado de review pós-Task-4 (Sessão): `FleetStateClient` desistia de vez depois de
/// `maxRetries` quedas e ficava em `.failed` até algo EXTERNO chamar `connect()` de novo. Antes
/// disso "funcionava" porque `FrotaView.onAppear` religava sem condição — mas quem fica parado
/// na Sessão, lendo, não tem esse gesto, e é essa pessoa a mais prejudicada por um link morto que
/// ninguém revive sozinho. Mesmo defeito que `PTYClient` já teve e já consertou — ver
/// `PTYClientKeepaliveTests` — e o mesmo remédio: extrair o backoff numa função PURA e provar que
/// ela nunca "sinaliza desistência", nem depois de centenas de falhas.
@Suite
struct FleetStateClientKeepaliveTests {

    // MARK: - nextRetryDelayMs(retries:)

    @Test func testAtrasoCrescePorRetentativa() {
        let a1 = FleetStateStore.nextRetryDelayMs(retries: 1)
        let a2 = FleetStateStore.nextRetryDelayMs(retries: 2)
        let a3 = FleetStateStore.nextRetryDelayMs(retries: 3)
        #expect(a1 < a2)
        #expect(a2 < a3)
    }

    @Test func testAtrasoTemTeto() {
        // O teto é 10s — sem ele, uma tempestade de retentativa é o tipo de coisa que bota o
        // app em quarentena de log por volume.
        let tetoMs = 10_000
        for r in 1...50 {
            #expect(FleetStateStore.nextRetryDelayMs(retries: r) <= tetoMs,
                    "retries=\(r) deve respeitar o teto de 10s")
        }
    }

    @Test func testAtrasoNuncaZero() {
        // Um atraso zero vira laço apertado — a mesma tempestade, só que mais rápida.
        for r in 1...50 {
            #expect(FleetStateStore.nextRetryDelayMs(retries: r) > 0)
        }
    }

    /// 🚨 A prova central desta rodada de conserto: o cliente NUNCA desiste de vez. `retries`
    /// pode crescer sem limite — o atraso só satura no teto, nunca vira um sinal de "pare". Se
    /// `nextRetryDelayMs` alguma hora ganhar um ramo de desistência (por exemplo, devolvendo um
    /// valor não-positivo depois de N falhas), este teste tem de acusar — é exatamente a
    /// regressão que esta rodada existe para impedir.
    @Test func testAtrasoContinuaNoTetoParaRetriesGrandesENuncaSinalizaDesistencia() {
        let a100 = FleetStateStore.nextRetryDelayMs(retries: 100)
        let a1000 = FleetStateStore.nextRetryDelayMs(retries: 1000)
        #expect(a100 == 10_000)
        #expect(a1000 == 10_000)
        #expect(a100 > 0, "um valor <= 0 seria o cliente dizendo 'desista'")
        #expect(a1000 > 0, "um valor <= 0 seria o cliente dizendo 'desista'")
    }

    // MARK: - linkDescription(_:) — o texto não pode mentir sobre o motor ter parado

    /// 🚨 Achado da terceira rodada de review: a tese desta fatia (não afirmar um estado que não
    /// é verdade) virada contra ela mesma. `.retrying` significa "caiu, mas eu mesmo estou
    /// tentando de novo, sozinho, em segundo plano" — e o texto NÃO pode ler como ".failed"
    /// ("parei, aja você"), porque o motor nunca parou.
    @Test func testInsistindoNuncaAfirmaParada() {
        let texto = FleetStateStore.linkDescription(.retrying(reason: "timeout", attempts: 12))
        #expect(texto.contains("reconectando") || texto.contains("sozinho") || texto.contains("caiu"),
                "o texto tem de dizer que o cliente está tentando por conta própria: \"\(texto)\"")
        #expect(texto != FleetStateStore.linkDescription(.failed("timeout")),
                "retrying não pode reaproveitar o texto de parada — motores diferentes, textos diferentes")
    }

    /// `.failed` continua existindo para o caso que É de verdade permanente (endpoint mal
    /// configurado) — este teste prende que ELE não regride para o texto de "retrying".
    @Test func testFailedContinuaSendoParadaDeVerdade() {
        let texto = FleetStateStore.linkDescription(.failed("bad endpoint"))
        #expect(!texto.contains("sozinho"), "endpoint mal configurado não se resolve retentando")
    }
}
