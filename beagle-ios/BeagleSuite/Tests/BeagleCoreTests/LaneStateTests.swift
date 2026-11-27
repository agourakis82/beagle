import Foundation
import Testing
@testable import BeagleCore

/// The Frota board's rules. Ported from checks run against the live broker on 2026-08-08.
@Suite
struct LaneStateTests {
    private let lanes = [
        LaneSnapshot(sid: "repo", title: "repo", state: .idle),
        LaneSnapshot(sid: "codex-1", title: "codex-1", state: .running),
        LaneSnapshot(sid: "kimi-cli1", title: "kimi-cli1", state: .waiting,
                     detail: "A pergunta: quer que eu rode o pré-registro?",
                     approve: .answerNeeded, observedAt: Date(timeIntervalSince1970: 100)),
        LaneSnapshot(sid: "claude-2", title: "claude-2", state: .stuck),
        LaneSnapshot(sid: "claude-1", title: "claude-1", state: .waiting,
                     detail: "Do you want to proceed?",
                     approve: .enterKey, observedAt: Date(timeIntervalSince1970: 50)),
        LaneSnapshot(sid: "grok-cli1", title: "grok-cli1", state: .unknown),
    ]

    @Test func testShelfHoldsOnlyLanesBlockedOnTheOperator() {
        #expect(FrotaBoard.shelf(lanes).map(\.sid) == ["claude-1", "kimi-cli1", "claude-2"])
        #expect(FrotaBoard.rest(lanes).map(\.sid) == ["codex-1", "repo", "grok-cli1"])
        #expect(!FrotaBoard.rest(lanes).contains { $0.needsOperator })
    }

    @Test func testOneTapApprovalNeverAnswersAnOpenQuestion() {
        // ⌘↩ may clear a permission dialog; it must never "answer" a real question for him.
        #expect(FrotaBoard.oldestApprovable(lanes)?.sid == "claude-1")
        #expect(FrotaBoard.oldestApprovable([lanes[2]]) == nil)
        #expect(ApproveAffordance.answerNeeded.injection == nil)
        #expect(ApproveAffordance.enterKey.injection == "\r")
        #expect(ApproveAffordance.yKey.injection == "y\n")
    }

    @Test func testDecodesALoomSessionsEntry() {
        let s = LaneSnapshot(loom: [
            "sid": "kimi-cli1", "title": "kimi-cli1", "state": "waiting",
            "detail": "A pergunta: quer que eu baixe LEMON/MODMA?",
            "peek": ["• H2: σ_min correlaciona", "A pergunta: ..."],
            "approveKey": NSNull(), "observedAt": 1_700_000_000_000.0,
        ])
        #expect(s?.state == .waiting)
        #expect(s?.family == .kimi)
        #expect(s?.peek.count == 2)
        #expect(s?.approve == .answerNeeded)
        #expect(s?.observedAt != nil)
    }

    @Test func testAnUnobservedLaneIsUnknownAndStaleNeverAComfortableIdle() {
        let thin = LaneSnapshot(loom: ["sid": "codex-3"])
        #expect(thin?.state == .unknown, "a board that guesses idle teaches distrust")
        #expect(thin?.observedAt == nil)
        #expect(thin?.isStale() == true)
        #expect(LaneSnapshot(loom: ["state": "running"]) == nil, "no sid = not a lane")
        #expect(LaneSnapshot(loom: ["sid": "x", "state": "vibing"])?.state == .unknown)
    }

    @Test func testStalenessWindow() {
        #expect(!LaneSnapshot(sid: "a", title: "a", state: .running, observedAt: Date()).isStale())
        #expect(LaneSnapshot(sid: "b", title: "b", state: .running,
                             observedAt: Date().addingTimeInterval(-120)).isStale())
    }
}

/// Acting on a lane — added with Fase 6, when the Frota stopped being read-only.
@Suite
struct LaneActionTests {

    @Test func testTheAffordanceMapsToANamedKeyAndNeverInventsOneForAnOpenQuestion() {
        #expect(ApproveAffordance.enterKey.key == .enter)
        #expect(ApproveAffordance.yKey.key == .y)
        // The whole point: a question that needs a sentence has NO key. The server refuses it
        // too, so this is belt-and-braces rather than the only guard.
        #expect(ApproveAffordance.answerNeeded.key == nil)
    }

    @Test func testAnAbsentLaneIsNotJustAnotherExitedOne() {
        // Measured 2026-08-09: grok-cli1/2 and codex-3 do not exist in tmux at all. The server
        // states it in `detail`; the card must say "ausente" and offer nothing to press.
        let absent = LaneSnapshot(sid: "grok-cli1", title: "grok-cli1", state: .exited,
                                  detail: "sessão não existe no tmux")
        #expect(absent.isAbsent)
        #expect(absent.presenceLabel == "ausente")
        #expect(!absent.isIsolatable, "there is nothing there to move")

        let ended = LaneSnapshot(sid: "codex-1", title: "codex-1", state: .exited,
                                 detail: "Goal achieved (2h 46m)", atShell: true)
        #expect(!ended.isAbsent)
        #expect(ended.presenceLabel == "encerrado")
        #expect(ended.isIsolatable)
    }

    @Test func testOnlyALaneAtRestAndAtAShellOffersIsolation() {
        // Moving restarts the agent in the new tree and loses its context, so a busy lane must
        // not even show the button.
        for state in [LaneState.running, .waiting, .stuck, .unknown] {
            #expect(!LaneSnapshot(sid: "claude-1", title: "c", state: state, atShell: true).isIsolatable,
                    "\(state) must not offer isolation")
        }
        // The near-miss of 2026-08-09: a lane parked at its AGENT's input box is idle too, and
        // `cd /workspace/.wt/codex-1` typed there is a request to the agent, not a command.
        #expect(!LaneSnapshot(sid: "codex-1", title: "codex-1", state: .idle, atShell: false).isIsolatable)
        #expect(LaneSnapshot(sid: "repo", title: "repo", state: .idle, atShell: true).isIsolatable)
    }

    @Test func testAnAbsentAtShellFieldIsReadAsNotAShell() {
        // Guessing "shell" would draw a button the server refuses — degrade to the safe side.
        let lane = LaneSnapshot(loom: ["sid": "repo", "state": "idle"])
        #expect(lane?.atShell == false)
        #expect(LaneSnapshot(loom: ["sid": "repo", "state": "idle", "atShell": true])?.atShell == true)
    }

    @Test func testAnAbsentConfidenceFieldIsReadAsInferred() {
        // Gêmeo de `testAnAbsentAtShellFieldIsReadAsNotAShell`. Um cockpit que ainda não manda
        // `confidence` não pode fazer a Frota afirmar que raspagem de tela é medição.
        let mudo = LaneSnapshot(loom: ["sid": "repo", "state": "idle"])
        #expect(mudo?.confidence == .inferred)
        #expect(mudo?.confidenceLabel == "lido da tela")
        // Idem para um valor que não reconhecemos: desconhecido cai no lado seguro.
        #expect(
            LaneSnapshot(loom: ["sid": "repo", "state": "idle", "confidence": "provavelmente"])?
                .confidence == .inferred
        )
        // E o init memberwise, que é como toda a UI de teste/preview constrói lane.
        #expect(LaneSnapshot(sid: "repo", title: "repo", state: .idle).confidence == .inferred)
    }

    @Test func testUmaLaneSemSessaoTmuxNaoOfereceTerminal() {
        // É isto que apaga o botão "Abrir lane" (e o toque no card) numa lane do loomd. Sem
        // este predicado o card oferecia um terminal impossível: o operador toca e cai num erro.
        let doLoomd = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting)
        #expect(!doLoomd.hasTerminal)
        #expect(!doLoomd.noTerminalReason.isEmpty, "o lugar do botão não pode ficar mudo")
        #expect(LaneSnapshot(sid: "claude-1", title: "claude-1", state: .idle).hasTerminal)
        #expect(LaneSnapshot(sid: "repo", title: "repo", state: .idle).hasTerminal)
    }

    @Test func testExactOnlyWhenTheFrameDeclaresIt() {
        let medida = LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting", "confidence": "exact"])
        #expect(medida?.confidence == .exact)
        #expect(medida?.confidenceLabel == "medido no protocolo")
        // Glifo E cor: o selo não pode depender só de matiz.
        #expect(Confidence.exact.glyph != Confidence.inferred.glyph)
    }

    @Test func testTheKeyRequestCarriesTheTokenInAHeaderAndTheKeyInTheBody() throws {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "sekret")
        let req = try #require(ep.laneKeyRequest(sid: "codex-2", key: .y))
        #expect(req.httpMethod == "POST")
        #expect(req.url?.absoluteString == "https://cockpit.example/api/mobile/v1/lanes/codex-2/key")
        // A token in the URL leaks into logs and proxies; it belongs in a header. Same invariant
        // the Loom socket already holds.
        #expect(!(req.url?.absoluteString.contains("sekret") ?? true))
        #expect(req.value(forHTTPHeaderField: "x-cockpit-token") == "sekret")
        let body = String(decoding: try #require(req.httpBody), as: UTF8.self)
        #expect(body.contains("\"key\":\"y\""), "got \(body)")
    }

    @Test func testAnUnknownLaneNeverGetsARequestBuiltForIt() {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "t")
        #expect(ep.laneKeyRequest(sid: "evil; rm -rf", key: .y) == nil)
        #expect(ep.laneIsolateRequest(sid: "not-a-lane") == nil)
        #expect(ep.laneIsolateRequest(sid: "codex-1") != nil)
    }
}

/// Aprovação por RPC — a lane servida pelo loomd não tem tecla, tem um pedido a responder.
@Suite
struct AprovacaoPorRPCTests {

    // MARK: - O que está sendo aprovado (o dado que atravessava Rust e Node e morria aqui)

    /// 🚨 O diff vem do JSON do quadro `sessions`. Até esta fatia o `LaneSnapshot` não tinha
    /// onde guardá-lo: o loomd emitia `last_diff`, o cockpit repassava `diff`, e o campo morria
    /// no modelo Swift — então o card que pede DECISÃO mostrava "Press enter to confirm or esc
    /// to cancel" e dois cards de lanes diferentes ficavam idênticos.
    @Test func testODiffVemDoJSONNoCaminhoSessions() throws {
        let patch = "diff --git a/alvo.txt b/alvo.txt\n@@ -0,0 +1 @@\n+oi\n"
        let s = try #require(LaneSnapshot(loom: [
            "sid": "loom-1", "title": "loom-1", "state": "waiting",
            "detail": "Press enter to confirm or esc to cancel",
            "diff": patch, "approvalKind": "patch",
            "confidence": "exact", "observedAt": 1_700_000_000_000.0,
        ]))
        #expect(s.diff == patch, "o patch INTEIRO, para a tela poder desenhá-lo")
        #expect(s.approvalKind == .patch)
    }

    /// Ausente, `null` e VAZIO são todos "não há mudança proposta" — vazio degrada a `nil` de
    /// propósito, senão a tela abriria um bloco de diff sem uma linha dentro.
    @Test func testDiffAusenteNuloOuVazioNaoViraUmPatchEmBranco() {
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting"])?.diff == nil)
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting", "diff": NSNull()])?.diff == nil)
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting", "diff": ""])?.diff == nil)
    }

    /// Tipo ausente ou fora do vocabulário deste binário = silêncio, NUNCA `.other`. Rebaixar
    /// aqui faria o card afirmar "o agente quer seguir" sobre algo que pode não se desfazer.
    @Test func testTipoDeAprovacaoAusenteOuDesconhecidoNaoViraUmChute() {
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting"])?.approvalKind == nil)
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting",
                                    "approvalKind": "detonar"])?.approvalKind == nil)
        #expect(LaneSnapshot(loom: ["sid": "a", "state": "waiting",
                                    "approvalKind": "command"])?.approvalKind == .command)
    }

    @Test func testPendenciaTipadaEDecodificadaEAusenciaNaoInventaPedido() {
        // Ausente = não há pendência. Degradar para "tem pedido" desenharia um botão sem nada
        // para responder, e o servidor devolveria 409.
        let com = LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting",
                                      "pendingApproval": ["7", "item/fileChange/requestApproval"]])
        #expect(com?.pendingApproval == true)
        #expect(com?.approve.key == nil, "lane do loomd NÃO tem tecla — é RPC")
        #expect(LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting"])?.pendingApproval == false)
        #expect(LaneSnapshot(loom: ["sid": "l", "state": "waiting",
                                    "pendingApproval": NSNull()])?.pendingApproval == false)
    }

    @Test func testOTransporteDaAprovacaoEEscolhidoPeloQueALaneOFERECE() {
        // Este é o teste que faltava: a mutação mostrou que trocar o ramo do RPC por `false`
        // deixava a suíte inteira VERDE — ou seja, o comportamento central da mudança não tinha
        // guarda nenhuma. Enquanto a escolha morava dentro da função que faz rede, não havia
        // costura para testar; agora é pura.
        let doLoomd = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting, pendingApproval: true)
        #expect(FleetStateClient.approveTransport(for: doLoomd) == .rpc,
                "pendência tipada NÃO pode virar tecla nem folha de texto")

        let deTela = LaneSnapshot(sid: "codex-2", title: "codex-2", state: .waiting, approve: .enterKey)
        #expect(FleetStateClient.approveTransport(for: deTela) == .key(.enter))

        let perguntaAberta = LaneSnapshot(sid: "kimi-cli1", title: "kimi-cli1", state: .waiting, approve: .answerNeeded)
        #expect(FleetStateClient.approveTransport(for: perguntaAberta) == .answer,
                "pergunta que pede frase nunca ganha botão de um toque")

        // E a precedência importa: se as duas coisas chegarem, o RPC vence — é o caminho que
        // responde ao pedido REAL, enquanto a tecla seria enviada a um pane que não existe.
        let ambos = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting,
                                 approve: .yKey, pendingApproval: true)
        #expect(FleetStateClient.approveTransport(for: ambos) == .rpc)
    }

    @Test func testARotaDeAprovarNaoLevaOTokenNaURLERecusaSidHostil() throws {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "sekret")
        let req = try #require(ep.laneApproveRequest(sid: "loom-1"))
        #expect(req.httpMethod == "POST")
        #expect(req.url?.absoluteString == "https://cockpit.example/api/mobile/v1/lanes/loom-1/approve")
        #expect(!(req.url?.absoluteString.contains("sekret") ?? true))
        #expect(req.value(forHTTPHeaderField: "x-cockpit-token") == "sekret")
        // O sid vem do frame do servidor, mas entra num caminho de URL — charset é verificado.
        #expect(ep.laneApproveRequest(sid: "../../etc") == nil)
        #expect(ep.laneApproveRequest(sid: "loom 1") == nil)
        #expect(ep.laneApproveRequest(sid: "") == nil)
    }
}
