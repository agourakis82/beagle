import Foundation
import Testing
@testable import BeagleCore

/// A VOZ da linha de evidência do card da Frota.
///
/// O defeito que estes testes fixam: a face era escolhida por `lane.state == .waiting`, então a
/// fala de um agente que estava TRABALHANDO saía em monoespaçada — e neste sistema monoespaçada
/// é reservada a DADO. O comentário no código já dizia a intenção certa e a condição não a
/// cumpria. Agora a face vem da ORIGEM do texto; o estado governa só a prominência.
@Suite
struct RegistroDaEvidenciaTests {

    // MARK: - A função pura

    @Test func testFalaDoAgenteEFalaEmQualquerEstado() {
        // O ponto da fatia: não há `state` nesta assinatura. Trabalhando ou esperando, a prosa
        // do agente é a mesma espécie de coisa.
        #expect(
            SessionStore.registroDaEvidencia(loomdKind: "agent_message", confidence: .exact) == .fala
        )
    }

    @Test func testPerguntaAoOperadorTambemEFala() {
        // Sem estes dois a mudança seria REGRESSÃO: hoje a lane que espera já sai em serifada.
        for k in ["awaiting_approval", "awaiting_input"] {
            #expect(
                SessionStore.registroDaEvidencia(loomdKind: k, confidence: .exact) == .fala,
                "`\(k)` é uma pergunta DIRIGIDA ao operador"
            )
        }
    }

    @Test func testCromoDeProtocoloELeitura() {
        for k in ["tool_call", "tool_result", "idle", "turn_ended", "usage", "error"] {
            #expect(
                SessionStore.registroDaEvidencia(loomdKind: k, confidence: .exact) == .leitura,
                "`\(k)` não é fala — é máquina relatando"
            )
        }
    }

    /// 🚨 A ambiguidade MEDIDA que segura o registro `titulo`. Numa lane ACP o `detail` de
    /// `session_started` é `"sessao ACP 979fc90f-8a56-…"` — um identificador, e monoespaçada é a
    /// face certa para ele. Enquanto o loomd não der ao título um kind próprio, `session_started`
    /// tem de cair no lado seguro.
    @Test func testSessionStartedFicaEmLeituraEnquantoOKindForAmbiguo() {
        #expect(
            SessionStore.registroDaEvidencia(loomdKind: "session_started", confidence: .exact) == .leitura,
            "o mesmo kind carrega título numa lane de transcrição e um UUID numa lane ACP"
        )
    }

    @Test func testKindDesconhecidoOuAusenteNaoViraFala() {
        #expect(SessionStore.registroDaEvidencia(loomdKind: nil, confidence: .exact) == .leitura)
        #expect(
            SessionStore.registroDaEvidencia(loomdKind: "kind_que_ainda_nao_existe", confidence: .exact) == .leitura,
            "um binário que não sabe ler um kind novo cala em vez de promover cromo a fala"
        )
    }

    /// Procedência ANTES do kind: `inferred` é `capture-pane` + regex, e o cockpit manda
    /// `loomdKind: null` justamente nesse ramo. Confiar no kind aqui seria confiar num campo que
    /// naquele caminho não existe.
    @Test func testProcedenciaVenceOKind() {
        #expect(
            SessionStore.registroDaEvidencia(loomdKind: "agent_message", confidence: .inferred) == .leitura,
            "texto raspado da tela nunca é lido como fala, mesmo que venha rotulado como tal"
        )
    }

    // MARK: - O campo atravessando o fio

    @Test func testQuadroCheioDecodificaOLoomdKind() throws {
        let l = try #require(LaneSnapshot(loom: [
            "sid": "claude-2", "title": "claude-2", "state": "running",
            "detail": "Parei de chutar.", "confidence": "exact", "loomdKind": "agent_message",
        ]))
        #expect(l.loomdKind == "agent_message")
        #expect(
            SessionStore.registroDaEvidencia(loomdKind: l.loomdKind, confidence: l.confidence) == .fala
        )
    }

    @Test func testCampoAusenteNoQuadroCheioNaoViraChute() {
        let l = LaneSnapshot(loom: [
            "sid": "claude-2", "title": "claude-2", "state": "running", "confidence": "exact",
        ])
        #expect(l?.loomdKind == nil, "um cockpit antigo não pode fazer a Frota afirmar uma voz")
    }

    // MARK: - O PATCH de lane única, onde os campos morrem nesta plataforma

    /// Sexta vez que um campo atravessa Rust e Node e some no caminho de patch. Duas asserções,
    /// porque são dois modos de falha diferentes: chave AUSENTE (cockpit antigo) tem de PRESERVAR,
    /// chave presente com `null` (o servidor perdeu a fonte exata) tem de DEGRADAR. Somar os dois
    /// no mesmo `?? old` manteria a fala em serifada sobre texto que voltou a vir da tela.
    @Test @MainActor
    func testPatchDistingueChaveAusenteDeChaveNula() {
        let c = FleetStateClient()
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"loom-1","title":"loom-1","state":"running","detail":"falando",
           "confidence":"exact","observedAt":1000,"loomdKind":"agent_message"}
        ]}
        """)
        #expect(c.lanes.first?.loomdKind == "agent_message")

        // Chave AUSENTE: silêncio sobre o kind, não revogação dele.
        c.handle(#"{"t":"state","sid":"loom-1","state":"running","detail":"ainda falando"}"#)
        #expect(
            c.lanes.first?.loomdKind == "agent_message",
            "chave ausente é silêncio — rebaixar aqui apagaria a voz no primeiro evento"
        )

        // Chave presente com `null`: o servidor dizendo que não sabe mais.
        c.handle(#"{"t":"state","sid":"loom-1","state":"running","detail":"lido da tela","loomdKind":null}"#)
        #expect(
            c.lanes.first?.loomdKind == nil,
            "`null` explícito é o servidor admitindo que perdeu a fonte — não pode virar `?? old`"
        )
    }
}
