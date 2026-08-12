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

    /// 🚨 Achado de review: chave AUSENTE e valor ILEGÍVEL não podem cair no mesmo `?? old.aceita`.
    /// Um valor presente que o vocabulário atual não reconhece (servidor renomeado, binário
    /// velho) tem de zerar para `nil` — o lado SEGURO, que não oferece gesto nenhum — em vez de
    /// preservar `GUIAR`/`ENFILEIRAR` numa lane que pode ter acabado de virar somente-leitura.
    /// `LaneState.init(loom:)` (quadro inteiro) já degrada assim; o patch de lane única tinha de
    /// concordar com ele, não silenciosamente discordar.
    func testUmPatchDeStateComAceitaIlegivelZeraParaNilEmVezDePreservar() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"}
        ]}
        """)
        XCTAssertEqual(c.lanes.first { $0.sid == "claude-1" }?.aceita, .redireciona)

        // "colaborativo" não existe no vocabulário de `Aceita` — o servidor mudou de ideia ou
        // renomeou, e este binário ainda não sabe ler o valor novo.
        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando","aceita":"colaborativo"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        XCTAssertEqual(lane?.state, .running, "o patch precisa ter sido aplicado de fato")
        XCTAssertNil(lane?.aceita, "valor ilegível tem de zerar — não sei ler não é o mesmo que não mudou")
    }

    /// Terceiro caso do trio: um valor VÁLIDO no patch é aplicado normalmente (nem preserva o
    /// antigo, nem zera).
    func testUmPatchDeStateComAceitaValidoAplicaOValorNovo() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"}
        ]}
        """)
        c.handle(#"{"t":"state","sid":"claude-1","state":"waiting","aceita":"somente_leitura"}"#)
        XCTAssertEqual(c.lanes.first { $0.sid == "claude-1" }?.aceita, .somenteLeitura,
                        "valor válido novo tem de substituir o antigo")
    }

    // MARK: - Uso do turno (custo e contexto)

    /// 🚨 MEDIDO nas fixtures do censo ACP: `cost.amount` vem NULO em 15 dos 16 eventos de um
    /// turno — só o último traz o número. Somar "funciona" por ACIDENTE (os outros são zero) e
    /// quebra no dia em que o protocolo preencher os intermediários. O certo é o ÚLTIMO com custo.
    func testUsoDoTurnoPegaOUltimoComCustoNaoASoma() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .uso(id: 2, contextoUsado: 31_578, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 3, contextoUsado: 36_874, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 4, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = Turno.agrupar(passos)[0]
        let uso = try! XCTUnwrap(turno.uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o último com custo, não a soma")
        XCTAssertEqual(uso.contextoUsado, 38_718, "contexto é absoluto e monotônico: o último vale")
        XCTAssertEqual(uso.contextoTeto, 1_000_000)
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP (medido). O rodapé
    /// mostra proporção, então o teto não pode ser constante no código.
    func testTetoDeContextoVemDoEventoNaoDoCodigo() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 28_795, contextoTeto: 258_400, usd: 0.01, at: t0),
        ]
        XCTAssertEqual(Turno.agrupar(passos)[0].uso?.contextoTeto, 258_400)
    }

    func testTurnoSemUsoNaoInventaZero() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "x", at: t0),
                                     .message(id: 2, text: "y", at: t0)]
        XCTAssertNil(Turno.agrupar(passos)[0].uso, "sem evento de uso, o rodapé não mostra custo")
    }

    /// O evento `usage` da trama traz o custo em `detail`, no formato que o loomd escreve:
    /// "contexto 38718/1000000 · USD 0.3728"
    func testPassoDeUsageParseiaODetail() throws {
        let e = TramaEvent(seq: 9, tsMs: 0, lane: "claude-4", kind: "usage",
                           text: nil, detail: "contexto 38718/1000000 · USD 0.3728", diff: nil,
                           tool: nil, approvalKind: nil)
        let passo = try XCTUnwrap(SessionStore.passo(de: e))
        guard case .uso(_, let usado, let teto, let usd, _) = passo else {
            return XCTFail("usage tem de virar .uso, não sumir no default")
        }
        XCTAssertEqual(usado, 38_718); XCTAssertEqual(teto, 1_000_000)
        XCTAssertEqual(usd, 0.3728, accuracy: 0.0001)
    }

    /// O último evento de `usage` do turno pode vir SEM custo (fechamento). Se o código
    /// sobrescrever o custo com esse zero, o turno perde o preço que já tinha.
    func testUsoNaoPerdeOCustoQuandoOUltimoEventoVemZerado() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 38_000, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0, at: t0),
        ]
        let uso = try! XCTUnwrap(Turno.agrupar(passos)[0].uso)
        XCTAssertEqual(uso.usd, 0.3728, accuracy: 0.0001, "o zero de fechamento não apaga o custo")
        XCTAssertEqual(uso.contextoUsado, 38_718, "mas o contexto é o último, sempre")
    }

    /// 🚨 Achado da review: `.uso` devolvia `EmptyView()` na trilha, mas um `EmptyView()` ainda
    /// ocupa posição no `ForEach` dentro do `VStack` — o `spacing` fixo abre um buraco visível a
    /// cada evento `uso`. O passo tem de ser filtrado ANTES de chegar à lista, não desenhado
    /// vazio. Este teste prende as duas metades: o custo não desaparece (`turno.uso` continua
    /// alcançável) e não polui a conversa (`desenhavel` corta para 2 de 3 passos).
    func testUsoNaoEhDesenhavelMasContinuaAlcancavelViaTurnoUso() throws {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .message(id: 2, text: "feito", at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = Turno.agrupar(passos)[0]
        XCTAssertEqual(turno.passos.count, 3, "os três passos existem no turno")
        XCTAssertEqual(turno.passos.filter(\.desenhavel).count, 2,
                        "custo não é fala: não entra na trilha desenhada")
        XCTAssertEqual(try XCTUnwrap(turno.uso).usd, 0.3728, accuracy: 0.0001,
                        "mas o custo continua alcançável pelo rodapé")
    }

    // MARK: - O botão diz o que VAI acontecer

    /// 🚨 A caixa diz "guiar o turno em curso" e o botão diz GUIAR. Verdade no codex; MENTIRA na
    /// lane ACP, que enfileira. Mentir no momento da decisão é pior que contar depois — o
    /// operador já agiu.
    func testRotuloDizAVerdadeAntesDoClique() {
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.redireciona), "GUIAR")
        XCTAssertEqual(SessionStore.rotuloDeGuiar(.enfileira), "ENFILEIRAR")
        XCTAssertNil(SessionStore.rotuloDeGuiar(.somenteLeitura), "lane de leitura não oferece gesto")
        XCTAssertNil(SessionStore.rotuloDeGuiar(nil), "sem capacidade declarada, não se oferece nada")
    }

    func testCaixaDeTextoNaoExisteEmLaneDeLeitura() {
        XCTAssertNil(SessionStore.dicaDaCaixa(.somenteLeitura))
        XCTAssertEqual(SessionStore.dicaDaCaixa(.enfileira), "enfileirar para depois deste…")
        XCTAssertEqual(SessionStore.dicaDaCaixa(.redireciona), "guiar o turno em curso…")
    }

    /// 🚨 Achado da segunda rodada de review: `nil` (ainda não sei o que a lane aceita) NÃO pode
    /// desenhar a mesma coisa que `.somenteLeitura` (o servidor DECLAROU que é tail). Confundir
    /// os dois é a mesma mentira que esta fatia mata, invertida — nega um gesto que existe numa
    /// lane de codex cujo quadro só ainda não chegou.
    func testSemCaixaDistingueNaoSeiDeSomenteLeitura() {
        XCTAssertEqual(SessionStore.semCaixa(.somenteLeitura), .somenteObservada,
                        "o servidor declarou leitura — a tela pode afirmar isso")
        XCTAssertEqual(SessionStore.semCaixa(nil), .capacidadeDesconhecida,
                        "silêncio não é declaração de leitura")
        XCTAssertNil(SessionStore.semCaixa(.redireciona), "há caixa; semCaixa não se aplica")
        XCTAssertNil(SessionStore.semCaixa(.enfileira), "há caixa; semCaixa não se aplica")
    }

    // MARK: - O rodapé do turno (Task 5)

    /// 🚨 Um "US$ 0,0000" no rodapé de todo turno é ruído que treina o olho a ignorar a linha
    /// inteira — e aí o custo que importa também deixa de ser visto.
    func testRodapeComCustoMostraOUSD() {
        let uso = UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 12, uso: uso))
        XCTAssertTrue(texto.contains("US$"), "custo > 0 tem de aparecer")
        // Ajustado: afirmava "0.3728" — o ponto do `%.4f` insensível a locale. As quatro
        // casas seguem sendo o contrato do rodapé; só o separador mudou para vírgula.
        XCTAssertTrue(texto.contains("0,3728"), texto)
        XCTAssertFalse(texto.contains("0.3728"), "app em pt-BR: ponto decimal é o defeito")
    }

    func testRodapeComCustoZeroNaoMostraUSD() {
        let uso = UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 12, uso: uso))
        XCTAssertFalse(texto.contains("US$"),
                        "custo zero é ruído que treina o olho a ignorar a linha inteira")
    }

    func testRodapeSemUsoMostraSoADuracao() {
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 12, uso: nil))
        XCTAssertFalse(texto.contains("contexto"))
        XCTAssertFalse(texto.contains("US$"))
    }

    /// 🚨 Contrato NOVO (Important da review): duração é opcional DENTRO da linha, não um portão
    /// para a linha inteira. Um turno em curso (duração `nil`) com uso já reportado ainda mostra
    /// contexto e custo — é exatamente o turno que o operador está olhando agora, e esconder o
    /// rodapé por falta de duração jogaria fora o único dado que diz QUAL turno está caro
    /// enquanto ele ainda corre. O Rust já conta o turno aberto sem esperar por um `TurnEnded`
    /// que pode nunca chegar antes do olho passar pela tela; o rodapé não pode ser mais
    /// conservador que a fonte. Este teste substitui `testRodapeSemDuracaoEhNil`, que pinava o
    /// comportamento antigo (linha inteira sumia sem duração).
    func testRodapeSemDuracaoMasComUsoMostraContextoEUSD() {
        let uso = UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: nil, uso: uso),
                                   "sem duração mas com uso, o rodapé não pode sumir — é o " +
                                   "turno em curso, o único que ainda importa parar ou deixar ir")
        XCTAssertTrue(texto.contains("contexto"), texto)
        XCTAssertTrue(texto.contains("US$"), texto)
        XCTAssertFalse(texto.contains("s ·") || texto.hasPrefix("0s"),
                        "sem duração, a linha não pode fingir uma — só o que se sabe: \(texto)")
    }

    /// Nem duração, nem uso: aí sim não há nada para o rodapé dizer.
    func testRodapeSemDuracaoESemUsoEhNil() {
        XCTAssertNil(SessionStore.rodapeDoTurno(duracao: nil, uso: nil))
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP. Dois `uso` com o
    /// mesmo `contextoUsado` e tetos diferentes têm de dar porcentagens diferentes no rodapé.
    func testRodapeUsaOTetoDoEventoNaoUmaConstante() {
        let claude = UsoDoTurno(contextoUsado: 20_000, contextoTeto: 1_000_000, usd: 0.01)
        let codex = UsoDoTurno(contextoUsado: 20_000, contextoTeto: 258_400, usd: 0.01)
        let textoClaude = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: claude))
        let textoCodex = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: codex))
        XCTAssertTrue(textoClaude.contains("contexto 2%"), textoClaude)
        XCTAssertTrue(textoCodex.contains("contexto 8%"), textoCodex)
        XCTAssertNotEqual(textoClaude, textoCodex, "tetos diferentes têm de render porcentagens diferentes")
    }

    // MARK: - Rodapé arredonda, não trunca (Minor da review)

    /// 🚨 `Int(u.proporcao * 100)` TRUNCA — 0,6% de contexto mostrava "contexto 0%". Mesmo
    /// raciocínio do custo zero: um número que existe e é apagado pelo truncamento é ruído
    /// silencioso. `.rounded()` resolve.
    func testRodapeArredondaAPorcentagemDeContextoEmVezDeTruncar() {
        // 6_000 / 1_000_000 = 0,6% — truncado vira "0%"; arredondado, "1%".
        let uso = UsoDoTurno(contextoUsado: 6_000, contextoTeto: 1_000_000, usd: 0.01)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: uso))
        XCTAssertTrue(texto.contains("contexto 1%"), texto)
    }

    // MARK: - O 5º "arredonda para zero": contexto < 1% (Minor da review)

    /// 🚨 Trocar truncamento por `.rounded()` só moveu o limiar de <1% para <0,5% — com um teto
    /// de 1.000.000 de tokens, qualquer uso abaixo de 5.000 ainda imprimia "contexto 0%". Mesmo
    /// defeito do "US$ 0,0000"/"US$ 0,00" já consertados duas vezes, na quarta forma.
    func testRodapeContextoAbaixoDeUmPorCentoNaoMostraZero() {
        // 2.000 / 1.000.000 = 0,2% — arredondado ainda dá 0. O limiar explícito diz a verdade.
        let uso = UsoDoTurno(contextoUsado: 2_000, contextoTeto: 1_000_000, usd: 0.01)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: uso))
        XCTAssertTrue(texto.contains("contexto < 1%"), texto)
        XCTAssertFalse(texto.contains("contexto 0%"), texto)
    }

    /// Contexto usado exatamente 0 (praticamente impossível — o próprio pedido já consome
    /// tokens) é o único caso em que "contexto 0%" é a verdade honesta, não um valor pequeno
    /// escondido pelo arredondamento — por isso ele NÃO passa pelo limiar de "< 1%".
    func testRodapeContextoExatamenteZeroMostraZeroSemLimiar() {
        let uso = UsoDoTurno(contextoUsado: 0, contextoTeto: 1_000_000, usd: 0)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: uso))
        XCTAssertTrue(texto.contains("contexto 0%"), texto)
        XCTAssertFalse(texto.contains("< 1%"), texto)
    }

    /// >= 1% (arredondado) mostra o número normal, sem o limiar — cobertura do terceiro ramo.
    func testRodapeContextoAcimaDeUmPorCentoMostraNumeroNormal() {
        let uso = UsoDoTurno(contextoUsado: 20_000, contextoTeto: 1_000_000, usd: 0.01)
        let texto = try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 5, uso: uso))
        XCTAssertTrue(texto.contains("contexto 2%"), texto)
        XCTAssertFalse(texto.contains("< 1%"), texto)
    }

    // MARK: - Um pedido, uma resposta (Important da review)

    /// 🚨 Achado de review: `.diff` avulso (codex) e `.approval` (o card) podem coexistir no
    /// mesmo turno — o agente propõe o patch, depois pede para aplicá-lo. Se os dois widgets
    /// desenhassem Aplicar/Recusar, seria o MESMO pedido respondido por dois lugares. A decisão:
    /// o card é o único lugar. Este predicado prende o invariante — a asserção é sempre 1 (nunca
    /// 2) quando o turno tem um pedido pendente, não importa quantos `.diff` avulsos existam.
    func testExatamenteUmLugarOfereceRespostaQuandoHaDiffEAprovacaoJuntos() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "muda o arquivo", at: t0),
            .message(id: 2, text: "vou propor um patch", at: t0),
            .diff(id: 3, patch: "--- a\n+++ b\n-x\n+y", at: t0),
            .approval(id: 4, kind: .patch, detail: "aplicar?", at: t0),
        ]
        XCTAssertEqual(SessionStore.lugaresDeResposta(passos), 1,
                       "diff avulso e card no mesmo turno — só o card responde")
    }

    func testZeroLugaresOferecemRespostaSemPedidoPendente() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "muda", at: t0),
                                     .diff(id: 2, patch: "--- a\n+++ b", at: t0)]
        XCTAssertEqual(SessionStore.lugaresDeResposta(passos), 0,
                       "diff sem pedido pendente é só leitura — nada responde")
    }

    /// A lane ACP: o diff chega EMBUTIDO no `.approval`, sem `.diff` avulso nenhum. Ainda assim,
    /// exatamente um lugar responde — o mesmo card, agora mostrando o patch que carrega.
    func testExatamenteUmLugarQuandoODiffVemEmbutidoNoPedidoACP() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "aplica no ACP", at: t0),
            .approval(id: 2, kind: .patch, detail: "aplicar?",
                      diff: "--- a\n+++ b\n-x\n+y", at: t0),
        ]
        XCTAssertEqual(SessionStore.lugaresDeResposta(passos), 1)
    }


    // MARK: - Custo do chip da Frota (Task 6b) — o servidor já somou, o Swift só lê

    /// 🚨 O chip NÃO usa o `%.4f` do rodapé do turno — de propósito. O rodapé mede um turno
    /// (a quarta casa é o dado); o chip mede o acumulado da lane, que cresce o dia inteiro, e
    /// quatro casas nesse número empurrariam o dígito que importa para fora do card. A
    /// coerência entre os dois é de PRINCÍPIO (zero não aparece; nada arredonda para zero), não
    /// de string de formato.
    func testCustoDoChipZeroEhNil() {
        XCTAssertNil(SessionStore.custoDoChip(0), "zero é ruído — o servidor já omite a chave")
    }

    /// `>= 0,01`: duas casas — é dinheiro, e é como dinheiro se lê.
    func testCustoDoChipComValorMostraOUSD() {
        let texto = try! XCTUnwrap(SessionStore.custoDoChip(0.42))
        // Ajustado: o `||` aceitava as duas formas e foi o que deixou o defeito viver.
        XCTAssertTrue(texto.contains("0,42"), texto)
        XCTAssertFalse(texto.contains("0.42"), texto)
    }

    func testCustoDoChipAcimaDeUmCentavoUsaDuasCasas() {
        let texto = try! XCTUnwrap(SessionStore.custoDoChip(12.3456))
        // Ajustado: idem — de "12.35 OU 12,35" para vírgula exigida e ponto proibido.
        XCTAssertTrue(texto.contains("12,35"), texto)
        XCTAssertFalse(texto.contains("12.35"), texto)
    }

    /// 🚨 O ramo que a rodada de conserto existe para prender: `0,0042` NÃO pode virar
    /// "US$ 0,00" — duas casas sozinhas trariam de volta o "US$ 0,0000"/"contexto 0%" que esta
    /// fatia já consertou duas vezes. Um número que arredonda para zero mente com mais
    /// confiança que um campo vazio.
    func testCustoDoChipAbaixoDeUmCentavoNaoArredondaParaZero() {
        let texto = try! XCTUnwrap(SessionStore.custoDoChip(0.0042))
        XCTAssertFalse(texto.contains("0.00") || texto.contains("0,00"),
                        "abaixo de um centavo não pode afirmar zero: \(texto)")
        // Acrescentado: o limiar é uma string de dinheiro como as outras e obedece à
        // mesma vírgula. Era a única certa por acidente de digitação; agora é derivada.
        XCTAssertTrue(texto.contains(","), texto)
        XCTAssertEqual(texto, "< US$ 0,01", texto)
    }

    /// 🚨 O limiar não pode ser um literal paralelo ao formatador: um centavo escrito à mão
    /// e um centavo formatado têm de ser a MESMA string, senão o dia em que o formato mudar
    /// o limiar fica para trás calado — que é exatamente como "< US$ 0,01" e "US$ 12.35"
    /// foram parar um em cima do outro na mesma coluna da tela.
    func testLimiarDeUmCentavoEhDerivadoDoMesmoFormatador() {
        // 0,01 NÃO é `< 0,01`, então este caminho devolve o centavo formatado, sem limiar.
        let umCentavo = try! XCTUnwrap(SessionStore.custoDoChip(0.01))
        XCTAssertEqual(SessionStore.custoDoChip(0.0042), "< " + umCentavo,
                        "o limiar tem de sair do mesmo formatador, não de um literal")
    }

    /// Agrupamento de milhar: `NumberFormatter` em pt_BR dá "US$ 1.234,56", que o `%.2f`
    /// não dava e que passa a importar conforme o acumulado da lane cresce. O ponto aqui é
    /// separador de MILHAR — legítimo em pt-BR — e a vírgula segue sendo a decimal.
    func testCustoDoChipAgrupaMilharNaFormaBrasileira() {
        XCTAssertEqual(SessionStore.custoDoChip(1234.5678), "US$ 1.234,57")
    }

    /// 🚨 O teste que prende a CONSISTÊNCIA, e a razão desta rodada existir: os três
    /// caminhos de dinheiro (chip, rodapé, VoiceOver) aparecem na mesma tela, e um quarto
    /// call-site que voltasse a `String(format:)` traria o ponto decimal de volta ao lado
    /// da vírgula. A asserção é sobre o ÚLTIMO separador da string, não sobre a ausência de
    /// todo ponto — em "US$ 1.234,56" o ponto é o milhar, e proibi-lo proibiria o
    /// agrupamento correto junto com o defeito.
    func testNenhumaStringDeDinheiroUsaPontoComoSeparadorDecimal() {
        var produzidas: [String] = []
        for usd in [0.0042, 0.01, 0.42, 12.3456, 1234.5678, 987654.321] {
            produzidas.append(try! XCTUnwrap(SessionStore.custoDoChip(usd)))
            produzidas.append(SessionStore.custoParaAcessibilidade(usd))
            let uso = UsoDoTurno(contextoUsado: 38_718, contextoTeto: 1_000_000, usd: usd)
            produzidas.append(try! XCTUnwrap(SessionStore.rodapeDoTurno(duracao: 12, uso: uso)))
        }
        for s in produzidas {
            XCTAssertTrue(s.contains("US$"), "amostra sem dinheiro, o teste não provaria nada: \(s)")
            XCTAssertEqual(separadorDecimalDe(s), ",",
                            "separador decimal errado numa string de dinheiro: \(s)")
        }
    }

    /// O separador decimal de uma string de dinheiro é o ÚLTIMO "," ou "." dela — o que vem
    /// antes pode ser agrupamento de milhar.
    private func separadorDecimalDe(_ s: String) -> Character? {
        s.last { $0 == "," || $0 == "." }
    }

    /// `usd` vem do JSON no caminho `sessions` — a lane carrega o que o loomd já somou.
    func testUsdVemDoJSONNoCaminhoSessions() throws {
        let obj = loomObj(#","usd":0.42"#)
        let snap = try XCTUnwrap(LaneSnapshot(loom: obj))
        XCTAssertEqual(snap.usd, 0.42, accuracy: 0.0001)
    }

    /// A chave é OMITIDA quando o custo é zero (serde skip_serializing_if) — ausência não é erro.
    func testUsdAusenteEhZero() throws {
        let obj = loomObj()
        let snap = try XCTUnwrap(LaneSnapshot(loom: obj))
        XCTAssertEqual(snap.usd, 0, accuracy: 0.0001)
    }

    /// 🚨 O caminho de patch de lane única (`{t:"state"}`) é onde um campo novo some em
    /// silêncio — igual `confidence` e `aceita` antes dele. Uma lane com custo recebe um frame
    /// `state` que NÃO menciona `usd`, e o valor tem de sobreviver (cair para `old.usd`, nunca 0).
    func testUmPatchDeStateSemUsdPreservaOCusto() {
        let c = FleetStateClient(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"usd":0.42}
        ]}
        """)
        XCTAssertEqual(c.lanes.first { $0.sid == "claude-1" }?.usd ?? -1, 0.42, accuracy: 0.0001)

        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        XCTAssertEqual(lane?.state, .running, "o patch precisa ter sido aplicado de fato")
        XCTAssertEqual(lane?.usd ?? -1, 0.42, accuracy: 0.0001,
                        "silêncio sobre usd não é o custo virando zero")
    }

    // MARK: - Custo no accessibilityLabel (Minor da review)

    /// 🚨 `.accessibilityElement(children: .combine)` seguido de `.accessibilityLabel(...)`
    /// SUBSTITUI o texto combinado dos filhos — o chip de custo (um desses filhos) nunca chegava
    /// a VoiceOver. `custoParaAcessibilidade` é o trecho a ANEXAR; vazio quando não há custo.
    func testCustoParaAcessibilidadeVazioQuandoZero() {
        XCTAssertEqual(SessionStore.custoParaAcessibilidade(0), "",
                        "custo zero não deve aparecer nem na fala nem no texto")
    }

    func testCustoParaAcessibilidadeContemOValorQuandoPositivo() {
        let trecho = SessionStore.custoParaAcessibilidade(0.42)
        XCTAssertFalse(trecho.isEmpty, "custo positivo tem de anunciar algo")
        // Ajustado: idem. Reusa `custoDoChip`, então tem de herdar a vírgula sem esforço.
        XCTAssertTrue(trecho.contains("0,42"), trecho)
        XCTAssertFalse(trecho.contains("0.42"), trecho)
    }

    func testCustoParaAcessibilidadeAbaixoDeUmCentavoNaoArredondaParaZero() {
        // Mesma disciplina do chip visual: 0,0042 não pode virar "0,00" nem aqui.
        let trecho = SessionStore.custoParaAcessibilidade(0.0042)
        XCTAssertFalse(trecho.contains("0.00") || trecho.contains("0,00"), trecho)
        XCTAssertFalse(trecho.isEmpty)
    }

    // MARK: - Link caído esconde a caixa sem mentir (Important da review)

    /// 🚨 Achado de review: `SessionView` não tinha referência nenhuma ao estado do link do
    /// `FleetStateClient`. Um socket caído congelava `aceita` em `nil` para sempre, e a tela
    /// continuava dizendo "aguardando o servidor declarar…" como se fosse questão de segundos —
    /// mentindo por omissão sobre QUEM está em silêncio (a fonte, não o agente).
    func testRazaoSemCapacidadeENilOuLinkVivoEhTransitorio() {
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: nil), .transitorio,
                        "sem link nenhum ainda (ex.: retrato/fixture), o texto de sempre está certo")
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: .idle), .transitorio,
                        "arranque, antes de qualquer queda")
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: .connecting), .transitorio)
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: .live), .transitorio,
                        "link de pé: se aceita é nil, é o quadro DESTA lane que não chegou")
    }

    /// O link caído reaproveita `FleetStateClient.explicacaoDoLink` verbatim — a mesma frase que
    /// a Frota já mostra para "o broker caiu" — em vez de uma segunda string inventada aqui.
    func testRazaoSemCapacidadeQuandoOLinkCaiuUsaAExplicacaoDaFrota() {
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: .failed("boom")),
                       .linkCaido(FleetStateClient.explicacaoDoLink(.failed("boom"))))
        XCTAssertEqual(SessionStore.razaoSemCapacidadeDeclarada(link: .reconnecting),
                       .linkCaido(FleetStateClient.explicacaoDoLink(.reconnecting)))

        guard case .linkCaido(let motivo) = SessionStore.razaoSemCapacidadeDeclarada(
            link: .insistindo(motivo: "connection refused", tentativas: 13)
        ) else {
            return XCTFail(".insistindo tem de virar .linkCaido, nunca .transitorio")
        }
        XCTAssertTrue(motivo.contains("connection refused"), motivo)
        XCTAssertTrue(motivo.contains("13"), motivo)
        // 🚨 `.insistindo` NUNCA pode ler como "o cliente desistiu" — ele está retentando
        // sozinho. `explicacaoDoLink` já garante isto; este teste prende que a Sessão herda a
        // MESMA garantia por reaproveitar a função, não por reimplementar a frase.
        XCTAssertFalse(motivo.localizedCaseInsensitiveContains("desisti"), motivo)
    }
}
