import XCTest
@testable import BeagleCore

/// A faixa periférica da Frota — a metade que NÃO pede decisão.
///
/// O que estes testes prendem não é uma aparência, é uma SUBTRAÇÃO: prévia que some, idade que
/// some, palavra de estado que some. Subtração é o que um retrato em PNG não consegue afirmar
/// (um pixel ausente e um pixel esquecido são o mesmo pixel), então a regra mora numa função
/// pura e é aqui que ela fica presa.
final class PeriferiaDaFrotaTests: XCTestCase {

    private let agora = Date(timeIntervalSince1970: 1_770_000_000)

    private func lane(_ sid: String, _ state: LaneState, detail: String = "",
                      hasVisto: TimeInterval? = -5) -> LaneSnapshot {
        LaneSnapshot(sid: sid, title: sid, state: state, detail: detail,
                     observedAt: hasVisto.map { agora.addingTimeInterval($0) })
    }

    // MARK: - Quem trabalha tem presença; quem está ocioso recua

    /// A distinção que mais importa na faixa tem de sobreviver ao olho de canto — e, antes do
    /// pixel, tem de existir no DADO. Se `ativa` e `previa` lerem igual para os dois estados,
    /// nenhuma escolha de desenho conserta: a view não teria o que diferenciar.
    func testTrabalhandoEOciosoSeDistinguemNaSaidaDaFuncaoPura() {
        let trabalhando = SessionStore.linhaPeriferica(
            lane("claude-1", .running, detail: "Effecting"), agora: agora)
        let ocioso = SessionStore.linhaPeriferica(
            lane("claude-3", .idle, detail: "Effecting"), agora: agora)

        XCTAssertTrue(trabalhando.ativa)
        XCTAssertFalse(ocioso.ativa)
        // Mesmo detalhe nos dois: o que difere é a REGRA, não o texto de entrada.
        XCTAssertNotEqual(trabalhando, ocioso)
    }

    /// O que uma lane parada "estava dizendo" é a coisa menos acionável da tela.
    ///
    /// 🚨 O detalhe TEM de ter espaços. Com o texto de uma única palavra que estava aqui antes
    /// (`research/zd-fiber-…`), este teste passava mesmo tratando ocioso como trabalhando —
    /// `previaCurta` devolvia `nil` por falta de fronteira, não por causa da regra. Um teste que
    /// acerta pelo motivo errado não prende nada.
    func testLaneOciosaNaoMostraPrevia() {
        let linha = SessionStore.linhaPeriferica(
            lane("claude-3", .idle, detail: "❯ e pq vc nao construiu....para de queimar token"),
            agora: agora)
        XCTAssertNil(linha.previa)
    }

    // MARK: - Ou termina em fronteira de palavra, ou não existe

    /// 🚨 O defeito medido no retrato: `✻ Effecting… (13m…`. Um fragmento cortado no meio da
    /// palavra não informa — custa ruído e não paga.
    ///
    /// A asserção é ESTRUTURAL de propósito (não compara com uma string literal): o que se
    /// prende é o invariante "o caractere logo depois do corte é um espaço", que continua valendo
    /// se o orçamento mudar.
    func testPreviaDeLaneTrabalhandoTerminaEmFronteiraDePalavra() throws {
        let detalhe = "✻ Effecting… (13m 43s · ↓ 6.6k tokens) e mais um bocado de texto"
        let linha = SessionStore.linhaPeriferica(
            lane("claude-1", .running, detail: detalhe), agora: agora)

        let previa = try XCTUnwrap(linha.previa)
        XCTAssertTrue(previa.hasSuffix("…"), previa)
        let miolo = String(previa.dropLast())
        XCTAssertTrue(detalhe.hasPrefix(miolo), "a prévia não é um prefixo do detalhe: \(previa)")
        let resto = detalhe.dropFirst(miolo.count)
        XCTAssertEqual(resto.first?.isWhitespace, true,
                       "cortou no meio da palavra: …\(miolo.suffix(12))|\(resto.prefix(8))…")
        XCTAssertLessThanOrEqual(previa.count, SessionStore.orcamentoDaPrevia)
    }

    /// Texto curto passa inteiro — o corte não pode virar imposto sobre quem já cabia.
    func testPreviaCurtaPassaInteira() {
        XCTAssertEqual(SessionStore.previaCurta("● N-back full"), "● N-back full")
    }

    /// Quando a primeira palavra sozinha já estoura o orçamento não existe prévia honesta.
    /// Metade de uma palavra é o defeito, não a solução.
    func testPrimeiraPalavraGiganteNaoViraFragmento() {
        XCTAssertNil(SessionStore.previaCurta(String(repeating: "x", count: 120)))
    }

    // MARK: - A idade só quando é notícia

    /// Nove "9 seg" na tela dizem "está tudo bem" e competem com o conteúdo para não informar
    /// nada. Leitura fresca não gasta um número.
    func testLeituraFrescaNaoMostraIdade() {
        let linha = SessionStore.linhaPeriferica(
            lane("claude-1", .running, detail: "Effecting", hasVisto: -9), agora: agora)
        XCTAssertNil(linha.idade)
    }

    /// Leitura velha, sim: aí o número É a notícia. O limiar não é novo — é o `isStale` que o
    /// resto do painel já usa.
    func testLeituraVelhaMostraIdade() {
        let velha = lane("claude-1", .running, detail: "Effecting", hasVisto: -300)
        XCTAssertTrue(velha.isStale(now: agora), "a fixture tem de estar vencida para o teste valer")
        XCTAssertEqual(SessionStore.linhaPeriferica(velha, agora: agora).idade, velha.observedAt)
    }

    /// 🚨 A idade SUBSTITUI a prévia, não divide a linha com ela. Uma prévia de leitura vencida
    /// afirma o presente ("está fazendo X") com cinco minutos de atraso — e, de quebra, era
    /// espremendo a prévia contra a idade que o SwiftUI voltava a cortar no meio da palavra, por
    /// pixel, onde nenhum teste de string chega.
    func testLeituraVelhaTrocaAPreviaPelaIdade() {
        let velha = lane("claude-1", .running,
                         detail: "✻ Effecting… (13m 43s · ↓ 6.6k tokens)", hasVisto: -300)
        let linha = SessionStore.linhaPeriferica(velha, agora: agora)
        XCTAssertNil(linha.previa)
        XCTAssertNotNil(linha.idade)
    }

    /// Nunca observada: está vencida por definição, mas não há data a desenhar — e a linha diz
    /// isso com a PALAVRA, em vez de inventar um instante.
    func testNuncaObservadaNaoInventaUmInstante() {
        let linha = SessionStore.linhaPeriferica(
            lane("t560-beagle", .unknown, hasVisto: nil), agora: agora)
        XCTAssertNil(linha.idade)
        XCTAssertEqual(linha.presenca, "não observado")
    }

    // MARK: - Quantas colunas: a última fileira o mais cheia possível

    /// 🚨 O caso do retrato: QUATRO lanes trabalhando. Com três colunas fixas saía `3 + 1` e a
    /// quarta ficava órfã, sozinha numa fileira com um vão largo à direita.
    ///
    /// O teto é 3 porque é o que a janela de 1180pt comporta sem furar `larguraMinimaDaColuna`
    /// (4 × 340 + 3 × 6 = 1378 > 1148 disponíveis). Dentro desse teto, 2 + 2 é a única divisão
    /// sem vão nenhum.
    func testQuatroLanesNaJanelaRealViram2Mais2() {
        XCTAssertEqual(SessionStore.colunasParaPeriferia(4, teto: 3), 2)
    }

    /// 🚨 A tabela inteira, caso a caso, no teto que cada linha pressupõe.
    ///
    /// As duas primeiras colunas de `teto` NÃO são um detalhe de implementação: são a
    /// reconciliação de dois casos que, sem elas, se contradizem. `n = 4` com espaço para
    /// quatro colunas é uma fileira cheia de quatro — vazio zero, órfão nenhum, e a regra
    /// escolhe isso. `n = 4` com espaço para três é 2 + 2, porque 3 deixaria o órfão. Quem
    /// decide qual dos dois vale é o PISO de largura, nunca o gosto.
    func testATabelaDeColunas() {
        // (n, teto, esperado)
        let casos: [(Int, Int, Int)] = [
            (1, 4, 1),   // um item nunca merece duas colunas — e não sobra vão
            (2, 4, 2),   // fileira cheia
            (3, 4, 3),   // fileira cheia
            (4, 3, 2),   // 2 + 2 — o caso do retrato
            (4, 4, 4),   // com espaço para quatro, uma fileira cheia de quatro também não tem órfão
            (5, 4, 3),   // 3 + 2: última com dois, sem órfão
            (7, 4, 4),   // 4 + 3 — 3 fixas dariam 3+3+1
            (9, 4, 3)    // fileira cheia
        ]
        for (n, teto, esperado) in casos {
            XCTAssertEqual(SessionStore.colunasParaPeriferia(n, teto: teto), esperado,
                           "n=\(n), teto=\(teto)")
        }
    }

    /// Faixa vazia não quebra e não pede uma grade de zero colunas.
    func testZeroItensNaoQuebra() {
        XCTAssertEqual(SessionStore.colunasParaPeriferia(0), 1)
        XCTAssertEqual(SessionStore.colunasParaPeriferia(0, teto: 1), 1)
    }

    /// 🚨 O piso de largura MANDA na contagem, e é isso que mantém a fronteira de palavra de pé:
    /// a largura que `c` colunas exigem nunca deixa uma coluna abaixo dos 340pt de onde
    /// `orcamentoDaPrevia` tira os 33 caracteres.
    func testALarguraExigidaHonraOPisoDaColuna() {
        for c in 1...4 {
            let exigida = SessionStore.larguraExigida(colunas: c)
            let porColuna = (exigida - Double(c - 1) * SessionStore.espacoEntreColunas) / Double(c)
            XCTAssertEqual(porColuna, SessionStore.larguraMinimaDaColuna, accuracy: 0.001,
                           "c=\(c) espremeria a coluna abaixo do piso")
        }
        // Quatro colunas NÃO cabem na janela de 1180 (16pt de folga de cada lado): é por isso
        // que o retrato tem teto 3.
        XCTAssertGreaterThan(SessionStore.larguraExigida(colunas: 4), 1180 - 32)
        XCTAssertLessThanOrEqual(SessionStore.larguraExigida(colunas: 3), 1180 - 32)
    }

    // MARK: - A palavra de estado só quando é anomalia

    func testEstadosNormaisNaoGastamPalavra() {
        XCTAssertNil(SessionStore.linhaPeriferica(lane("a", .running, detail: "x"), agora: agora).presenca)
        XCTAssertNil(SessionStore.linhaPeriferica(lane("b", .idle), agora: agora).presenca)
    }

    /// `isAbsent` continua mandando no rótulo — a regra dele não muda aqui, só é reaproveitada.
    func testAusenteContinuaEscritaPorExtenso() {
        let sumida = LaneSnapshot(sid: "grok-cli3", title: "grok-cli3", state: .exited,
                                  detail: "sessão não existe no tmux", observedAt: agora)
        XCTAssertEqual(SessionStore.linhaPeriferica(sumida, agora: agora).presenca, "ausente")
    }
}
