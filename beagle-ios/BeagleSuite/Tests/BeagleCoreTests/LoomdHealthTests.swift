import XCTest
@testable import BeagleCore

/// A saúde da fonte MEDIDA, decodificada do bloco `loomd:{…}` do frame `sessions`.
///
/// O que estes testes protegem é a diferença entre QUEDA e AUSÊNCIA. Uma fonte que respondia e
/// parou merece pixel; uma fonte que nunca existiu neste deploy, não — e confundir as duas
/// produz ou uma queda invisível ou um banner permanente. Os dois erros terminam no mesmo lugar:
/// um aviso que ninguém lê.
final class LoomdHealthTests: XCTestCase {

    private func bloco(
        _ mode: String, lost: [String] = [], error: String? = nil, lanes: Int = 0
    ) -> [String: Any] {
        var o: [String: Any] = ["mode": mode, "lanes": lanes, "lost": lost]
        if let error { o["error"] = error }
        return o
    }

    func testUmaFonteCaidaDizModoMotivoEQuemSaiuDoBoard() {
        let saude = LoomdHealth(loom: bloco(
            "down",
            lost: ["loom-1"],
            error: "loomd não respondeu em 127.0.0.1:4400 dentro do pod (bloco vazio ou fora do contrato)"
        ))
        XCTAssertEqual(saude.mode, .down)
        XCTAssertTrue(saude.isDegraded)
        XCTAssertEqual(saude.modeLabel, "caída")
        // Verbatim do servidor: ele nomeia a porta e o pod, coisa que o cliente não teria como
        // adivinhar. Trocar por texto genérico aqui mandaria o operador caçar o problema errado.
        XCTAssertTrue(saude.reason.contains("127.0.0.1:4400"), saude.reason)
        XCTAssertEqual(saude.lostSentence, "loom-1 saiu do board junto")
        // Uma linha só carrega as três respostas — é o que o leitor de tela ouve.
        XCTAssertTrue(saude.headline.contains("caída"), saude.headline)
        XCTAssertTrue(saude.headline.contains("loom-1"), saude.headline)
    }

    func testDuasLanesPerdidasSaoNomeadasNoPlural() {
        let saude = LoomdHealth(loom: bloco("down", lost: ["loom-1", "loom-2"]))
        XCTAssertEqual(saude.lostSentence, "loom-1 · loom-2 saíram do board junto")
    }

    func testUmaFonteVivaNuncaViraFaixa() {
        let saude = LoomdHealth(loom: bloco("observed", lanes: 1))
        XCTAssertTrue(saude.isHealthy)
        XCTAssertFalse(saude.isDegraded, "fonte ao vivo não pode desenhar faixa de queda")
        XCTAssertNil(saude.lostSentence)
    }

    func testMedicaoRuimFalaMesmoNoArranqueFrio() {
        // `down` e `stale` são MEDIÇÕES: o cockpit perguntou e a resposta foi ruim. Isso é
        // acionável mesmo que o app tenha acabado de abrir e nunca tenha visto a fonte boa.
        for modo in ["down", "stale"] {
            let saude = LoomdHealth(loom: bloco(modo), everObserved: false)
            XCTAssertTrue(saude.isDegraded, "\(modo) frio precisa aparecer")
        }
    }

    func testAusenteFalaSemprePorqueOBuracoMaisProvavelEraOUnicoMudo() {
        // MUDOU em 09-ago-2026. A regra anterior exigia `everObserved` ou `lost` para `absent`
        // falar — e calava exatamente o cenário mais provável: pod novo (o workspace-ssh já
        // reiniciou 25 vezes), loomd nunca subiu, nada observado, `lost` vazio -> silêncio, e o
        // board volta a ser 100% adivinhado sem dizer uma palavra. Hoje um CronJob sobe o loomd
        // a cada 5 min, então ausente deixou de ser "talvez nunca tenha existido" e passou a ser
        // "deveria estar lá e não está".
        XCTAssertTrue(
            LoomdHealth(loom: bloco("absent"), everObserved: false).isDegraded,
            "pod novo com loomd ausente é o caso MAIS provável; ficar mudo nele é o pior desenho"
        )
        XCTAssertTrue(LoomdHealth(loom: bloco("absent"), everObserved: true).isDegraded)
        XCTAssertTrue(LoomdHealth(loom: bloco("absent", lost: ["loom-1"])).isDegraded)
    }

    func testDesconhecidoSegueCaladoPorqueSignificaOutraCoisa() {
        // `unknown` não é "o loomd caiu": é "este cockpit não tem leitor de loomd" (imagem
        // antiga). Não há nada que o operador possa fazer na tela sobre isso, e faixa permanente
        // vira papel de parede — a lei da casa. Mas se a fonte JÁ respondeu nesta sessão, ou se
        // há lane nomeada em `lost`, aí houve perda de verdade e a faixa acende.
        XCTAssertFalse(
            LoomdHealth(loom: bloco("unknown"), everObserved: false).isDegraded,
            "cockpit sem leitor não é queda — é ausência de instrumento"
        )
        XCTAssertTrue(LoomdHealth(loom: bloco("unknown"), everObserved: true).isDegraded)
        XCTAssertTrue(LoomdHealth(loom: bloco("unknown", lost: ["loom-1"])).isDegraded)
    }

    func testUmModoDesconhecidoCaiNoLadoCaladoNuncaEmObserved() {
        // Promover o que não entendemos a `observed` esconderia exatamente a queda que este
        // tipo existe para mostrar.
        let saude = LoomdHealth(loom: bloco("fresquinho"), everObserved: true)
        XCTAssertEqual(saude.mode, .unknown)
        XCTAssertFalse(saude.isHealthy)
        XCTAssertTrue(saude.isDegraded)
    }

    func testOsDoisRelogiosNaoSeMisturam() {
        // `observedAt` é o relógio do loomd; `readAt` é o do sweep do cockpit. Trocar um pelo
        // outro é comparar relógios de máquinas diferentes e chamar o resultado de idade.
        let saude = LoomdHealth(loom: [
            "mode": "stale", "observedAt": 1_700_000_000_000.0, "readAt": 1_700_000_030_000.0,
        ])
        XCTAssertEqual(saude.observedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(saude.readAt, Date(timeIntervalSince1970: 1_700_000_030))
        // Zero/ausente é "nunca", não 1970.
        XCTAssertNil(LoomdHealth(loom: bloco("down")).observedAt)
        XCTAssertNil(LoomdHealth(loom: ["mode": "down", "observedAt": 0.0]).observedAt)
    }

    func testMotivoVazioNaoViraFraseVazia() {
        // O servidor manda `error: null` quando está tudo bem, mas um `""` acidental deixaria a
        // faixa com um modo e nenhuma explicação.
        let saude = LoomdHealth(loom: bloco("down", error: ""))
        XCTAssertNil(saude.error)
        XCTAssertFalse(saude.reason.isEmpty)
    }
}
