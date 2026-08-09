import XCTest
@testable import BeagleCore

/// The Frota board's rules. Ported from checks run against the live broker on 2026-08-08.
final class LaneStateTests: XCTestCase {
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

    func testShelfHoldsOnlyLanesBlockedOnTheOperator() {
        XCTAssertEqual(FrotaBoard.shelf(lanes).map(\.sid), ["claude-1", "kimi-cli1", "claude-2"])
        XCTAssertEqual(FrotaBoard.rest(lanes).map(\.sid), ["codex-1", "repo", "grok-cli1"])
        XCTAssertFalse(FrotaBoard.rest(lanes).contains { $0.needsOperator })
    }

    func testOneTapApprovalNeverAnswersAnOpenQuestion() {
        // ⌘↩ may clear a permission dialog; it must never "answer" a real question for him.
        XCTAssertEqual(FrotaBoard.oldestApprovable(lanes)?.sid, "claude-1")
        XCTAssertNil(FrotaBoard.oldestApprovable([lanes[2]]))
        XCTAssertNil(ApproveAffordance.answerNeeded.injection)
        XCTAssertEqual(ApproveAffordance.enterKey.injection, "\r")
        XCTAssertEqual(ApproveAffordance.yKey.injection, "y\n")
    }

    func testDecodesALoomSessionsEntry() {
        let s = LaneSnapshot(loom: [
            "sid": "kimi-cli1", "title": "kimi-cli1", "state": "waiting",
            "detail": "A pergunta: quer que eu baixe LEMON/MODMA?",
            "peek": ["• H2: σ_min correlaciona", "A pergunta: ..."],
            "approveKey": NSNull(), "observedAt": 1_700_000_000_000.0,
        ])
        XCTAssertEqual(s?.state, .waiting)
        XCTAssertEqual(s?.family, .kimi)
        XCTAssertEqual(s?.peek.count, 2)
        XCTAssertEqual(s?.approve, .answerNeeded)
        XCTAssertNotNil(s?.observedAt)
    }

    func testAnUnobservedLaneIsUnknownAndStaleNeverAComfortableIdle() {
        let thin = LaneSnapshot(loom: ["sid": "codex-3"])
        XCTAssertEqual(thin?.state, .unknown, "a board that guesses idle teaches distrust")
        XCTAssertNil(thin?.observedAt)
        XCTAssertTrue(thin?.isStale() ?? false)
        XCTAssertNil(LaneSnapshot(loom: ["state": "running"]), "no sid = not a lane")
        XCTAssertEqual(LaneSnapshot(loom: ["sid": "x", "state": "vibing"])?.state, .unknown)
    }

    func testStalenessWindow() {
        XCTAssertFalse(LaneSnapshot(sid: "a", title: "a", state: .running, observedAt: Date()).isStale())
        XCTAssertTrue(LaneSnapshot(sid: "b", title: "b", state: .running,
                                   observedAt: Date().addingTimeInterval(-120)).isStale())
    }
}

/// Acting on a lane — added with Fase 6, when the Frota stopped being read-only.
final class LaneActionTests: XCTestCase {

    func testTheAffordanceMapsToANamedKeyAndNeverInventsOneForAnOpenQuestion() {
        XCTAssertEqual(ApproveAffordance.enterKey.key, .enter)
        XCTAssertEqual(ApproveAffordance.yKey.key, .y)
        // The whole point: a question that needs a sentence has NO key. The server refuses it
        // too, so this is belt-and-braces rather than the only guard.
        XCTAssertNil(ApproveAffordance.answerNeeded.key)
    }

    func testAnAbsentLaneIsNotJustAnotherExitedOne() {
        // Measured 2026-08-09: grok-cli1/2 and codex-3 do not exist in tmux at all. The server
        // states it in `detail`; the card must say "ausente" and offer nothing to press.
        let absent = LaneSnapshot(sid: "grok-cli1", title: "grok-cli1", state: .exited,
                                  detail: "sessão não existe no tmux")
        XCTAssertTrue(absent.isAbsent)
        XCTAssertEqual(absent.presenceLabel, "ausente")
        XCTAssertFalse(absent.isIsolatable, "there is nothing there to move")

        let ended = LaneSnapshot(sid: "codex-1", title: "codex-1", state: .exited,
                                 detail: "Goal achieved (2h 46m)", atShell: true)
        XCTAssertFalse(ended.isAbsent)
        XCTAssertEqual(ended.presenceLabel, "encerrado")
        XCTAssertTrue(ended.isIsolatable)
    }

    func testOnlyALaneAtRestAndAtAShellOffersIsolation() {
        // Moving restarts the agent in the new tree and loses its context, so a busy lane must
        // not even show the button.
        for state in [LaneState.running, .waiting, .stuck, .unknown] {
            XCTAssertFalse(LaneSnapshot(sid: "claude-1", title: "c", state: state, atShell: true).isIsolatable,
                           "\(state) must not offer isolation")
        }
        // The near-miss of 2026-08-09: a lane parked at its AGENT's input box is idle too, and
        // `cd /workspace/.wt/codex-1` typed there is a request to the agent, not a command.
        XCTAssertFalse(LaneSnapshot(sid: "codex-1", title: "codex-1", state: .idle, atShell: false).isIsolatable)
        XCTAssertTrue(LaneSnapshot(sid: "repo", title: "repo", state: .idle, atShell: true).isIsolatable)
    }

    func testAnAbsentAtShellFieldIsReadAsNotAShell() {
        // Guessing "shell" would draw a button the server refuses — degrade to the safe side.
        let lane = LaneSnapshot(loom: ["sid": "repo", "state": "idle"])
        XCTAssertEqual(lane?.atShell, false)
        XCTAssertEqual(LaneSnapshot(loom: ["sid": "repo", "state": "idle", "atShell": true])?.atShell, true)
    }

    func testAnAbsentConfidenceFieldIsReadAsInferred() {
        // Gêmeo de `testAnAbsentAtShellFieldIsReadAsNotAShell`. Um cockpit que ainda não manda
        // `confidence` não pode fazer a Frota afirmar que raspagem de tela é medição.
        let mudo = LaneSnapshot(loom: ["sid": "repo", "state": "idle"])
        XCTAssertEqual(mudo?.confidence, .inferred)
        XCTAssertEqual(mudo?.confidenceLabel, "lido da tela")
        // Idem para um valor que não reconhecemos: desconhecido cai no lado seguro.
        XCTAssertEqual(
            LaneSnapshot(loom: ["sid": "repo", "state": "idle", "confidence": "provavelmente"])?
                .confidence,
            .inferred
        )
        // E o init memberwise, que é como toda a UI de teste/preview constrói lane.
        XCTAssertEqual(LaneSnapshot(sid: "repo", title: "repo", state: .idle).confidence, .inferred)
    }

    func testUmaLaneSemSessaoTmuxNaoOfereceTerminal() {
        // É isto que apaga o botão "Abrir lane" (e o toque no card) numa lane do loomd. Sem
        // este predicado o card oferecia um terminal impossível: o operador toca e cai num erro.
        let doLoomd = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting)
        XCTAssertFalse(doLoomd.hasTerminal)
        XCTAssertFalse(doLoomd.noTerminalReason.isEmpty, "o lugar do botão não pode ficar mudo")
        XCTAssertTrue(LaneSnapshot(sid: "claude-1", title: "claude-1", state: .idle).hasTerminal)
        XCTAssertTrue(LaneSnapshot(sid: "repo", title: "repo", state: .idle).hasTerminal)
    }

    func testExactOnlyWhenTheFrameDeclaresIt() {
        let medida = LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting", "confidence": "exact"])
        XCTAssertEqual(medida?.confidence, .exact)
        XCTAssertEqual(medida?.confidenceLabel, "medido no protocolo")
        // Glifo E cor: o selo não pode depender só de matiz.
        XCTAssertNotEqual(Confidence.exact.glyph, Confidence.inferred.glyph)
    }

    func testTheKeyRequestCarriesTheTokenInAHeaderAndTheKeyInTheBody() throws {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "sekret")
        let req = try XCTUnwrap(ep.laneKeyRequest(sid: "codex-2", key: .y))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "https://cockpit.example/api/mobile/v1/lanes/codex-2/key")
        // A token in the URL leaks into logs and proxies; it belongs in a header. Same invariant
        // the Loom socket already holds.
        XCTAssertFalse(req.url?.absoluteString.contains("sekret") ?? true)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-cockpit-token"), "sekret")
        let body = try XCTUnwrap(req.httpBody).flatMap { String(decoding: [$0], as: UTF8.self) }.joined()
        XCTAssertTrue(body.contains("\"key\":\"y\""), "got \(body)")
    }

    func testAnUnknownLaneNeverGetsARequestBuiltForIt() {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "t")
        XCTAssertNil(ep.laneKeyRequest(sid: "evil; rm -rf", key: .y))
        XCTAssertNil(ep.laneIsolateRequest(sid: "not-a-lane"))
        XCTAssertNotNil(ep.laneIsolateRequest(sid: "codex-1"))
    }
}


/// Aprovação por RPC — a lane servida pelo loomd não tem tecla, tem um pedido a responder.
final class AprovacaoPorRPCTests: XCTestCase {

    func testPendenciaTipadaEDecodificadaEAusenciaNaoInventaPedido() {
        // Ausente = não há pendência. Degradar para "tem pedido" desenharia um botão sem nada
        // para responder, e o servidor devolveria 409.
        let com = LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting",
                                      "pendingApproval": ["7", "item/fileChange/requestApproval"]])
        XCTAssertEqual(com?.pendingApproval, true)
        XCTAssertNil(com?.approve.key, "lane do loomd NÃO tem tecla — é RPC")
        XCTAssertEqual(LaneSnapshot(loom: ["sid": "loom-1", "state": "waiting"])?.pendingApproval, false)
        XCTAssertEqual(LaneSnapshot(loom: ["sid": "l", "state": "waiting",
                                           "pendingApproval": NSNull()])?.pendingApproval, false)
    }

    func testOTransporteDaAprovacaoEEscolhidoPeloQueALaneOFERECE() {
        // Este é o teste que faltava: a mutação mostrou que trocar o ramo do RPC por `false`
        // deixava a suíte inteira VERDE — ou seja, o comportamento central da mudança não tinha
        // guarda nenhuma. Enquanto a escolha morava dentro da função que faz rede, não havia
        // costura para testar; agora é pura.
        let doLoomd = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting, pendingApproval: true)
        XCTAssertEqual(FleetStateClient.approveTransport(for: doLoomd), .rpc,
                       "pendência tipada NÃO pode virar tecla nem folha de texto")

        let deTela = LaneSnapshot(sid: "codex-2", title: "codex-2", state: .waiting, approve: .enterKey)
        XCTAssertEqual(FleetStateClient.approveTransport(for: deTela), .key(.enter))

        let perguntaAberta = LaneSnapshot(sid: "kimi-cli1", title: "kimi-cli1", state: .waiting, approve: .answerNeeded)
        XCTAssertEqual(FleetStateClient.approveTransport(for: perguntaAberta), .answer,
                       "pergunta que pede frase nunca ganha botão de um toque")

        // E a precedência importa: se as duas coisas chegarem, o RPC vence — é o caminho que
        // responde ao pedido REAL, enquanto a tecla seria enviada a um pane que não existe.
        let ambos = LaneSnapshot(sid: "loom-1", title: "loom-1", state: .waiting,
                                 approve: .yKey, pendingApproval: true)
        XCTAssertEqual(FleetStateClient.approveTransport(for: ambos), .rpc)
    }

    func testARotaDeAprovarNaoLevaOTokenNaURLERecusaSidHostil() throws {
        let ep = FleetEndpoint(host: "cockpit.example", scheme: "wss", token: "sekret")
        let req = try XCTUnwrap(ep.laneApproveRequest(sid: "loom-1"))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString,
                       "https://cockpit.example/api/mobile/v1/lanes/loom-1/approve")
        XCTAssertFalse(req.url?.absoluteString.contains("sekret") ?? true)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-cockpit-token"), "sekret")
        // O sid vem do frame do servidor, mas entra num caminho de URL — charset é verificado.
        XCTAssertNil(ep.laneApproveRequest(sid: "../../etc"))
        XCTAssertNil(ep.laneApproveRequest(sid: "loom 1"))
        XCTAssertNil(ep.laneApproveRequest(sid: ""))
    }
}
