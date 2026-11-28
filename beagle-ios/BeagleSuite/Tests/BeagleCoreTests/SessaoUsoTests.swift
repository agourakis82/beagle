import Foundation
import Testing
@testable import BeagleCore

/// `aceita` é declarado pelo servidor, nunca deduzido. Existe porque `LaneFamily.of(sid)` devolve
/// `.claude` tanto para `claude-1` (tail, o loomd só LÊ — /prompt e /steer devolvem 404) quanto
/// para `claude-4` (ACP, `promptQueueing` ENFILEIRA) — mesmo prefixo, comportamentos opostos.
/// Estes testes existem para impedir que alguém "simplifique" derivando do sid.
@Suite
@MainActor
struct SessaoUsoTests {

    private func loomObj(_ extra: String = "") -> [String: Any] {
        let json = """
        {"sid":"claude-1","title":"claude-1","kind":"agent_message","confidence":"exact",
         "detail":"x","observedAt":0,"turns":0\(extra)}
        """
        let data = json.data(using: .utf8)!
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func testAceitaVemDoJSONeNaoDoSid() throws {
        let obj = loomObj(#","aceita":"somente_leitura""#)
        let snap = try #require(LaneSnapshot(loom: obj))
        #expect(snap.aceita == .somenteLeitura)
        #expect(snap.family == .claude, "a família segue sendo claude — e não decide capacidade")
    }

    @Test func testAceitaAusenteEhNil() throws {
        let obj = loomObj()
        let snap = try #require(LaneSnapshot(loom: obj))
        #expect(snap.aceita == nil, "lane sem capacidade declarada não pode virar um chute")
    }

    @Test func testAceitaRedirecionaEEnfileiraDecodificamTambem() throws {
        let redireciona = try #require(LaneSnapshot(loom: loomObj(#","aceita":"redireciona""#)))
        #expect(redireciona.aceita == .redireciona)
        let enfileira = try #require(LaneSnapshot(loom: loomObj(#","aceita":"enfileira""#)))
        #expect(enfileira.aceita == .enfileira)
    }

    /// 🚨 O caminho de patch de lane única (`{t:"state"}`) é onde um campo novo some em silêncio
    /// — igual aconteceu com `confidence` antes de o comentário no `handle` existir. Uma lane
    /// com `aceita` conhecido recebe um frame `state` que NÃO menciona `aceita`, e a capacidade
    /// tem de sobreviver (cair para `old.aceita`, nunca para `nil`).
    @Test func testUmPatchDeStateSemAceitaPreservaACapacidade() {
        let c = FleetStateStore(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"somente_leitura"}
        ]}
        """)
        #expect(c.lanes.first { $0.sid == "claude-1" }?.aceita == .somenteLeitura)

        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        #expect(lane?.state == .running, "o patch precisa ter sido aplicado de fato")
        #expect(lane?.aceita == .somenteLeitura, "silêncio sobre aceita não é revogação da capacidade")
    }

    /// 🚨 Achado de review: chave AUSENTE e valor ILEGÍVEL não podem cair no mesmo `?? old.aceita`.
    /// Um valor presente que o vocabulário atual não reconhece (servidor renomeado, binário
    /// velho) tem de zerar para `nil` — o lado SEGURO, que não oferece gesto nenhum — em vez de
    /// preservar `GUIAR`/`ENFILEIRAR` numa lane que pode ter acabado de virar somente-leitura.
    /// `LaneState.init(loom:)` (quadro inteiro) já degrada assim; o patch de lane única tinha de
    /// concordar com ele, não silenciosamente discordar.
    @Test func testUmPatchDeStateComAceitaIlegivelZeraParaNilEmVezDePreservar() {
        let c = FleetStateStore(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"}
        ]}
        """)
        #expect(c.lanes.first { $0.sid == "claude-1" }?.aceita == .redireciona)

        // "colaborativo" não existe no vocabulário de `Aceita` — o servidor mudou de ideia ou
        // renomeou, e este binário ainda não sabe ler o valor novo.
        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando","aceita":"colaborativo"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        #expect(lane?.state == .running, "o patch precisa ter sido aplicado de fato")
        #expect(lane?.aceita == nil, "valor ilegível tem de zerar — não sei ler não é o mesmo que não mudou")
    }

    /// Terceiro caso do trio: um valor VÁLIDO no patch é aplicado normalmente (nem preserva o
    /// antigo, nem zera).
    @Test func testUmPatchDeStateComAceitaValidoAplicaOValorNovo() {
        let c = FleetStateStore(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"aceita":"redireciona"}
        ]}
        """)
        c.handle(#"{"t":"state","sid":"claude-1","state":"waiting","aceita":"somente_leitura"}"#)
        #expect(c.lanes.first { $0.sid == "claude-1" }?.aceita == .somenteLeitura,
                "valor válido novo tem de substituir o antigo")
    }

    // MARK: - Uso do turno (custo e contexto)

    /// 🚨 MEDIDO nas fixtures do censo ACP: `cost.amount` vem NULO em 15 dos 16 eventos de um
    /// turno — só o último traz o número. Somar "funciona" por ACIDENTE (os outros são zero) e
    /// quebra no dia em que o protocolo preencher os intermediários. O certo é o ÚLTIMO com custo.
    @Test func testUsoDoTurnoPegaOUltimoComCustoNaoASoma() throws {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .uso(id: 2, contextoUsado: 31_578, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 3, contextoUsado: 36_874, contextoTeto: 1_000_000, usd: 0, at: t0),
            .uso(id: 4, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = SessionTurn.group(passos)[0]
        let uso = try #require(turno.usage)
        #expect(abs(uso.usd - 0.3728) <= 0.0001, "o último com custo, não a soma")
        #expect(uso.contextUsed == 38_718, "contexto é absoluto e monotônico: o último vale")
        #expect(uso.contextLimit == 1_000_000)
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP (medido). O rodapé
    /// mostra proporção, então o teto não pode ser constante no código.
    @Test func testTetoDeContextoVemDoEventoNaoDoCodigo() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 28_795, contextoTeto: 258_400, usd: 0.01, at: t0),
        ]
        #expect(SessionTurn.group(passos)[0].usage?.contextLimit == 258_400)
    }

    @Test func testTurnoSemUsoNaoInventaZero() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "x", at: t0),
                                     .message(id: 2, text: "y", at: t0)]
        #expect(SessionTurn.group(passos)[0].usage == nil, "sem evento de uso, o rodapé não mostra custo")
    }

    /// O evento `usage` da trama traz o custo em `detail`, no formato que o loomd escreve:
    /// "contexto 38718/1000000 · USD 0.3728"
    @Test func testPassoDeUsageParseiaODetail() throws {
        let e = TramaEvent(seq: 9, tsMs: 0, lane: "claude-4", kind: "usage",
                           text: nil, detail: "contexto 38718/1000000 · USD 0.3728", diff: nil,
                           tool: nil, approvalKind: nil)
        let passo = try #require(SessionStore.step(from: e))
        guard case .uso(_, let usado, let teto, let usd, _) = passo else {
            Issue.record("usage tem de virar .uso, não sumir no default")
            return
        }
        #expect(usado == 38_718)
        #expect(teto == 1_000_000)
        #expect(abs(usd - 0.3728) <= 0.0001)
    }

    /// O último evento de `usage` do turno pode vir SEM custo (fechamento). Se o código
    /// sobrescrever o custo com esse zero, o turno perde o preço que já tinha.
    @Test func testUsoNaoPerdeOCustoQuandoOUltimoEventoVemZerado() throws {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "x", at: t0),
            .uso(id: 2, contextoUsado: 38_000, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0, at: t0),
        ]
        let uso = try #require(SessionTurn.group(passos)[0].usage)
        #expect(abs(uso.usd - 0.3728) <= 0.0001, "o zero de fechamento não apaga o custo")
        #expect(uso.contextUsed == 38_718, "mas o contexto é o último, sempre")
    }

    /// 🚨 Achado da review: `.uso` devolvia `EmptyView()` na trilha, mas um `EmptyView()` ainda
    /// ocupa posição no `ForEach` dentro do `VStack` — o `spacing` fixo abre um buraco visível a
    /// cada evento `uso`. O passo tem de ser filtrado ANTES de chegar à lista, não desenhado
    /// vazio. Este teste prende as duas metades: o custo não desaparece (`turno.usage` continua
    /// alcançável) e não polui a conversa (`isRenderable` corta para 2 de 3 passos).
    @Test func testUsoNaoEhDesenhavelMasContinuaAlcancavelViaTurnoUso() throws {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "faz", at: t0),
            .message(id: 2, text: "feito", at: t0),
            .uso(id: 3, contextoUsado: 38_718, contextoTeto: 1_000_000, usd: 0.3728, at: t0),
        ]
        let turno = SessionTurn.group(passos)[0]
        #expect(turno.steps.count == 3, "os três passos existem no turno")
        #expect(turno.steps.filter(\.isRenderable).count == 2,
                "custo não é fala: não entra na trilha desenhada")
        let uso = try #require(turno.usage)
        #expect(abs(uso.usd - 0.3728) <= 0.0001, "mas o custo continua alcançável pelo rodapé")
    }

    // MARK: - O botão diz o que VAI acontecer

    /// 🚨 A caixa diz "guiar o turno em curso" e o botão diz GUIAR. Verdade no codex; MENTIRA na
    /// lane ACP, que enfileira. Mentir no momento da decisão é pior que contar depois — o
    /// operador já agiu.
    @Test func testRotuloDizAVerdadeAntesDoClique() {
        #expect(SessionStore.rotuloDeGuiar(.redireciona) == "GUIAR")
        #expect(SessionStore.rotuloDeGuiar(.enfileira) == "ENFILEIRAR")
        #expect(SessionStore.rotuloDeGuiar(.somenteLeitura) == nil, "lane de leitura não oferece gesto")
        #expect(SessionStore.rotuloDeGuiar(nil) == nil, "sem capacidade declarada, não se oferece nada")
    }

    @Test func testCaixaDeTextoNaoExisteEmLaneDeLeitura() {
        #expect(SessionStore.dicaDaCaixa(.somenteLeitura) == nil)
        #expect(SessionStore.dicaDaCaixa(.enfileira) == "enfileirar para depois deste…")
        #expect(SessionStore.dicaDaCaixa(.redireciona) == "guiar o turno em curso…")
    }

    /// 🚨 Achado da segunda rodada de review: `nil` (ainda não sei o que a lane aceita) NÃO pode
    /// desenhar a mesma coisa que `.somenteLeitura` (o servidor DECLAROU que é tail). Confundir
    /// os dois é a mesma mentira que esta fatia mata, invertida — nega um gesto que existe numa
    /// lane de codex cujo quadro só ainda não chegou.
    @Test func testSemCaixaDistingueNaoSeiDeSomenteLeitura() {
        #expect(SessionStore.semCaixa(.somenteLeitura) == .somenteObservada,
                "o servidor declarou leitura — a tela pode afirmar isso")
        #expect(SessionStore.semCaixa(nil) == .capacidadeDesconhecida,
                "silêncio não é declaração de leitura")
        #expect(SessionStore.semCaixa(.redireciona) == nil, "há caixa; semCaixa não se aplica")
        #expect(SessionStore.semCaixa(.enfileira) == nil, "há caixa; semCaixa não se aplica")
    }

    // MARK: - O rodapé do turno (Task 5)

    /// 🚨 Um "US$ 0,0000" no rodapé de todo turno é ruído que treina o olho a ignorar a linha
    /// inteira — e aí o custo que importa também deixa de ser visto.
    @Test func testRodapeComCustoMostraOUSD() throws {
        let uso = TurnUsage(contextUsed: 38_718, contextLimit: 1_000_000, usd: 0.3728)
        let texto = try #require(SessionStore.turnFooter(duration: 12, usage: uso))
        #expect(texto.contains("US$"), "custo > 0 tem de aparecer")
        // Ajustado: afirmava "0.3728" — o ponto do `%.4f` insensível a locale. As quatro
        // casas seguem sendo o contrato do rodapé; só o separador mudou para vírgula.
        #expect(texto.contains("0,3728"), "\(texto)")
        #expect(!texto.contains("0.3728"), "app em pt-BR: ponto decimal é o defeito")
    }

    @Test func testRodapeComCustoZeroNaoMostraUSD() throws {
        let uso = TurnUsage(contextUsed: 38_718, contextLimit: 1_000_000, usd: 0)
        let texto = try #require(SessionStore.turnFooter(duration: 12, usage: uso))
        #expect(!texto.contains("US$"),
                "custo zero é ruído que treina o olho a ignorar a linha inteira")
    }

    @Test func testRodapeSemUsoMostraSoADuracao() throws {
        let texto = try #require(SessionStore.turnFooter(duration: 12, usage: nil))
        #expect(!texto.contains("contexto"))
        #expect(!texto.contains("US$"))
    }

    /// 🚨 Contrato NOVO (Important da review): duração é opcional DENTRO da linha, não um portão
    /// para a linha inteira. Um turno em curso (duração `nil`) com uso já reportado ainda mostra
    /// contexto e custo — é exatamente o turno que o operador está olhando agora, e esconder o
    /// rodapé por falta de duração jogaria fora o único dado que diz QUAL turno está caro
    /// enquanto ele ainda corre. O Rust já conta o turno aberto sem esperar por um `TurnEnded`
    /// que pode nunca chegar antes do olho passar pela tela; o rodapé não pode ser mais
    /// conservador que a fonte. Este teste substitui `testRodapeSemDuracaoEhNil`, que pinava o
    /// comportamento antigo (linha inteira sumia sem duração).
    @Test func testRodapeSemDuracaoMasComUsoMostraContextoEUSD() throws {
        let uso = TurnUsage(contextUsed: 38_718, contextLimit: 1_000_000, usd: 0.3728)
        let texto = try #require(
            SessionStore.turnFooter(duration: nil, usage: uso),
            "sem duração mas com uso, o rodapé não pode sumir — é o turno em curso, o único que ainda importa parar ou deixar ir"
        )
        #expect(texto.contains("contexto"), "\(texto)")
        #expect(texto.contains("US$"), "\(texto)")
        #expect(!(texto.contains("s ·") || texto.hasPrefix("0s")),
                "sem duração, a linha não pode fingir uma — só o que se sabe: \(texto)")
    }

    /// Nem duração, nem uso: aí sim não há nada para o rodapé dizer.
    @Test func testRodapeSemDuracaoESemUsoEhNil() {
        #expect(SessionStore.turnFooter(duration: nil, usage: nil) == nil)
    }

    /// O teto varia por agente — 1.000.000 no Claude, 258.400 no Codex via ACP. Dois `uso` com o
    /// mesmo `contextoUsado` e tetos diferentes têm de dar porcentagens diferentes no rodapé.
    @Test func testRodapeUsaOTetoDoEventoNaoUmaConstante() throws {
        let claude = TurnUsage(contextUsed: 20_000, contextLimit: 1_000_000, usd: 0.01)
        let codex = TurnUsage(contextUsed: 20_000, contextLimit: 258_400, usd: 0.01)
        let textoClaude = try #require(SessionStore.turnFooter(duration: 5, usage: claude))
        let textoCodex = try #require(SessionStore.turnFooter(duration: 5, usage: codex))
        #expect(textoClaude.contains("contexto 2%"), "\(textoClaude)")
        #expect(textoCodex.contains("contexto 8%"), "\(textoCodex)")
        #expect(textoClaude != textoCodex, "tetos diferentes têm de render porcentagens diferentes")
    }

    // MARK: - Rodapé arredonda, não trunca (Minor da review)

    /// 🚨 `Int(u.proporcao * 100)` TRUNCA — 0,6% de contexto mostrava "contexto 0%". Mesmo
    /// raciocínio do custo zero: um número que existe e é apagado pelo truncamento é ruído
    /// silencioso. `.rounded()` resolve.
    @Test func testRodapeArredondaAPorcentagemDeContextoEmVezDeTruncar() throws {
        // 6_000 / 1_000_000 = 0,6% — truncado vira "0%"; arredondado, "1%".
        let uso = TurnUsage(contextUsed: 6_000, contextLimit: 1_000_000, usd: 0.01)
        let texto = try #require(SessionStore.turnFooter(duration: 5, usage: uso))
        #expect(texto.contains("contexto 1%"), "\(texto)")
    }

    // MARK: - O 5º "arredonda para zero": contexto < 1% (Minor da review)

    /// 🚨 Trocar truncamento por `.rounded()` só moveu o limiar de <1% para <0,5% — com um teto
    /// de 1.000.000 de tokens, qualquer uso abaixo de 5.000 ainda imprimia "contexto 0%". Mesmo
    /// defeito do "US$ 0,0000"/"US$ 0,00" já consertados duas vezes, na quarta forma.
    @Test func testRodapeContextoAbaixoDeUmPorCentoNaoMostraZero() throws {
        // 2.000 / 1.000.000 = 0,2% — arredondado ainda dá 0. O limiar explícito diz a verdade.
        let uso = TurnUsage(contextUsed: 2_000, contextLimit: 1_000_000, usd: 0.01)
        let texto = try #require(SessionStore.turnFooter(duration: 5, usage: uso))
        #expect(texto.contains("contexto < 1%"), "\(texto)")
        #expect(!texto.contains("contexto 0%"), "\(texto)")
    }

    /// Contexto usado exatamente 0 (praticamente impossível — o próprio pedido já consome
    /// tokens) é o único caso em que "contexto 0%" é a verdade honesta, não um valor pequeno
    /// escondido pelo arredondamento — por isso ele NÃO passa pelo limiar de "< 1%".
    @Test func testRodapeContextoExatamenteZeroMostraZeroSemLimiar() throws {
        let uso = TurnUsage(contextUsed: 0, contextLimit: 1_000_000, usd: 0)
        let texto = try #require(SessionStore.turnFooter(duration: 5, usage: uso))
        #expect(texto.contains("contexto 0%"), "\(texto)")
        #expect(!texto.contains("< 1%"), "\(texto)")
    }

    /// >= 1% (arredondado) mostra o número normal, sem o limiar — cobertura do terceiro ramo.
    @Test func testRodapeContextoAcimaDeUmPorCentoMostraNumeroNormal() throws {
        let uso = TurnUsage(contextUsed: 20_000, contextLimit: 1_000_000, usd: 0.01)
        let texto = try #require(SessionStore.turnFooter(duration: 5, usage: uso))
        #expect(texto.contains("contexto 2%"), "\(texto)")
        #expect(!texto.contains("< 1%"), "\(texto)")
    }

    // MARK: - Um pedido, uma resposta (Important da review)

    /// 🚨 Achado de review: `.diff` avulso (codex) e `.approval` (o card) podem coexistir no
    /// mesmo turno — o agente propõe o patch, depois pede para aplicá-lo. Se os dois widgets
    /// desenhassem Aplicar/Recusar, seria o MESMO pedido respondido por dois lugares. A decisão:
    /// o card é o único lugar. Este predicado prende o invariante — a asserção é sempre 1 (nunca
    /// 2) quando o turno tem um pedido pendente, não importa quantos `.diff` avulsos existam.
    @Test func testExatamenteUmLugarOfereceRespostaQuandoHaDiffEAprovacaoJuntos() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "muda o arquivo", at: t0),
            .message(id: 2, text: "vou propor um patch", at: t0),
            .diff(id: 3, patch: "--- a\n+++ b\n-x\n+y", at: t0),
            .approval(id: 4, kind: .patch, detail: "aplicar?", at: t0),
        ]
        #expect(SessionStore.lugaresDeResposta(passos) == 1,
                "diff avulso e card no mesmo turno — só o card responde")
    }

    @Test func testZeroLugaresOferecemRespostaSemPedidoPendente() {
        let t0 = Date()
        let passos: [SessionStep] = [.prompt(id: 1, text: "muda", at: t0),
                                     .diff(id: 2, patch: "--- a\n+++ b", at: t0)]
        #expect(SessionStore.lugaresDeResposta(passos) == 0,
                "diff sem pedido pendente é só leitura — nada responde")
    }

    /// A lane ACP: o diff chega EMBUTIDO no `.approval`, sem `.diff` avulso nenhum. Ainda assim,
    /// exatamente um lugar responde — o mesmo card, agora mostrando o patch que carrega.
    @Test func testExatamenteUmLugarQuandoODiffVemEmbutidoNoPedidoACP() {
        let t0 = Date()
        let passos: [SessionStep] = [
            .prompt(id: 1, text: "aplica no ACP", at: t0),
            .approval(id: 2, kind: .patch, detail: "aplicar?",
                      diff: "--- a\n+++ b\n-x\n+y", at: t0),
        ]
        #expect(SessionStore.lugaresDeResposta(passos) == 1)
    }

    // MARK: - Custo do chip da Frota (Task 6b) — o servidor já somou, o Swift só lê

    /// 🚨 O chip NÃO usa o `%.4f` do rodapé do turno — de propósito. O rodapé mede um turno
    /// (a quarta casa é o dado); o chip mede o acumulado da lane, que cresce o dia inteiro, e
    /// quatro casas nesse número empurrariam o dígito que importa para fora do card. A
    /// coerência entre os dois é de PRINCÍPIO (zero não aparece; nada arredonda para zero), não
    /// de string de formato.
    @Test func testCustoDoChipZeroEhNil() {
        #expect(SessionStore.custoDoChip(0) == nil, "zero é ruído — o servidor já omite a chave")
    }

    /// `>= 0,01`: duas casas — é dinheiro, e é como dinheiro se lê.
    @Test func testCustoDoChipComValorMostraOUSD() throws {
        let texto = try #require(SessionStore.custoDoChip(0.42))
        // Ajustado: o `||` aceitava as duas formas e foi o que deixou o defeito viver.
        #expect(texto.contains("0,42"), "\(texto)")
        #expect(!texto.contains("0.42"), "\(texto)")
    }

    @Test func testCustoDoChipAcimaDeUmCentavoUsaDuasCasas() throws {
        let texto = try #require(SessionStore.custoDoChip(12.3456))
        // Ajustado: idem — de "12.35 OU 12,35" para vírgula exigida e ponto proibido.
        #expect(texto.contains("12,35"), "\(texto)")
        #expect(!texto.contains("12.35"), "\(texto)")
    }

    /// 🚨 O ramo que a rodada de conserto existe para prender: `0,0042` NÃO pode virar
    /// "US$ 0,00" — duas casas sozinhas trariam de volta o "US$ 0,0000"/"contexto 0%" que esta
    /// fatia já consertou duas vezes. Um número que arredonda para zero mente com mais
    /// confiança que um campo vazio.
    @Test func testCustoDoChipAbaixoDeUmCentavoNaoArredondaParaZero() throws {
        let texto = try #require(SessionStore.custoDoChip(0.0042))
        #expect(!(texto.contains("0.00") || texto.contains("0,00")),
                "abaixo de um centavo não pode afirmar zero: \(texto)")
        // Acrescentado: o limiar é uma string de dinheiro como as outras e obedece à
        // mesma vírgula. Era a única certa por acidente de digitação; agora é derivada.
        #expect(texto.contains(","), "\(texto)")
        #expect(texto == "< US$ 0,01", "\(texto)")
    }

    /// 🚨 O limiar não pode ser um literal paralelo ao formatador: um centavo escrito à mão
    /// e um centavo formatado têm de ser a MESMA string, senão o dia em que o formato mudar
    /// o limiar fica para trás calado — que é exatamente como "< US$ 0,01" e "US$ 12.35"
    /// foram parar um em cima do outro na mesma coluna da tela.
    @Test func testLimiarDeUmCentavoEhDerivadoDoMesmoFormatador() throws {
        // 0,01 NÃO é `< 0,01`, então este caminho devolve o centavo formatado, sem limiar.
        let umCentavo = try #require(SessionStore.custoDoChip(0.01))
        #expect(SessionStore.custoDoChip(0.0042) == "< " + umCentavo,
                "o limiar tem de sair do mesmo formatador, não de um literal")
    }

    /// Agrupamento de milhar: `NumberFormatter` em pt_BR dá "US$ 1.234,56", que o `%.2f`
    /// não dava e que passa a importar conforme o acumulado da lane cresce. O ponto aqui é
    /// separador de MILHAR — legítimo em pt-BR — e a vírgula segue sendo a decimal.
    @Test func testCustoDoChipAgrupaMilharNaFormaBrasileira() {
        #expect(SessionStore.custoDoChip(1234.5678) == "US$ 1.234,57")
    }

    /// 🚨 O teste que prende a CONSISTÊNCIA, e a razão desta rodada existir: os três
    /// caminhos de dinheiro (chip, rodapé, VoiceOver) aparecem na mesma tela, e um quarto
    /// call-site que voltasse a `String(format:)` traria o ponto decimal de volta ao lado
    /// da vírgula. A asserção é sobre o ÚLTIMO separador da string, não sobre a ausência de
    /// todo ponto — em "US$ 1.234,56" o ponto é o milhar, e proibi-lo proibiria o
    /// agrupamento correto junto com o defeito.
    @Test func testNenhumaStringDeDinheiroUsaPontoComoSeparadorDecimal() throws {
        var produzidas: [String] = []
        for usd in [0.0042, 0.01, 0.42, 12.3456, 1234.5678, 987654.321] {
            produzidas.append(try #require(SessionStore.custoDoChip(usd)))
            produzidas.append(SessionStore.custoParaAcessibilidade(usd))
            let uso = TurnUsage(contextUsed: 38_718, contextLimit: 1_000_000, usd: usd)
            produzidas.append(try #require(SessionStore.turnFooter(duration: 12, usage: uso)))
        }
        for s in produzidas {
            #expect(s.contains("US$"), "amostra sem dinheiro, o teste não provaria nada: \(s)")
            #expect(separadorDecimalDe(s) == ",",
                    "separador decimal errado numa string de dinheiro: \(s)")
        }
    }

    /// O separador decimal de uma string de dinheiro é o ÚLTIMO "," ou "." dela — o que vem
    /// antes pode ser agrupamento de milhar.
    private func separadorDecimalDe(_ s: String) -> Character? {
        s.last { $0 == "," || $0 == "." }
    }

    /// `usd` vem do JSON no caminho `sessions` — a lane carrega o que o loomd já somou.
    @Test func testUsdVemDoJSONNoCaminhoSessions() throws {
        let obj = loomObj(#","usd":0.42"#)
        let snap = try #require(LaneSnapshot(loom: obj))
        #expect(abs(snap.usd - 0.42) <= 0.0001)
    }

    /// A chave é OMITIDA quando o custo é zero (serde skip_serializing_if) — ausência não é erro.
    @Test func testUsdAusenteEhZero() throws {
        let obj = loomObj()
        let snap = try #require(LaneSnapshot(loom: obj))
        #expect(abs(snap.usd - 0) <= 0.0001)
    }

    /// 🚨 O caminho de patch de lane única (`{t:"state"}`) é onde um campo novo some em
    /// silêncio — igual `confidence` e `aceita` antes dele. Uma lane com custo recebe um frame
    /// `state` que NÃO menciona `usd`, e o valor tem de sobreviver (cair para `old.usd`, nunca 0).
    @Test func testUmPatchDeStateSemUsdPreservaOCusto() {
        let c = FleetStateStore(endpoint: FleetEndpoint(host: "h", scheme: "ws", token: "t"))
        c.handle("""
        {"t":"sessions","sessions":[
          {"sid":"claude-1","title":"claude-1","state":"waiting","detail":"aprovar?",
           "confidence":"exact","observedAt":1000,"usd":0.42}
        ]}
        """)
        #expect(abs((c.lanes.first { $0.sid == "claude-1" }?.usd ?? -1) - 0.42) <= 0.0001)

        c.handle(#"{"t":"state","sid":"claude-1","state":"running","detail":"trabalhando"}"#)
        let lane = c.lanes.first { $0.sid == "claude-1" }
        #expect(lane?.state == .running, "o patch precisa ter sido aplicado de fato")
        #expect(abs((lane?.usd ?? -1) - 0.42) <= 0.0001,
                "silêncio sobre usd não é o custo virando zero")
    }

    // MARK: - Custo no accessibilityLabel (Minor da review)

    /// 🚨 `.accessibilityElement(children: .combine)` seguido de `.accessibilityLabel(...)`
    /// SUBSTITUI o texto combinado dos filhos — o chip de custo (um desses filhos) nunca chegava
    /// a VoiceOver. `custoParaAcessibilidade` é o trecho a ANEXAR; vazio quando não há custo.
    @Test func testCustoParaAcessibilidadeVazioQuandoZero() {
        #expect(SessionStore.custoParaAcessibilidade(0) == "",
                "custo zero não deve aparecer nem na fala nem no texto")
    }

    @Test func testCustoParaAcessibilidadeContemOValorQuandoPositivo() {
        let trecho = SessionStore.custoParaAcessibilidade(0.42)
        #expect(!trecho.isEmpty, "custo positivo tem de anunciar algo")
        // Ajustado: idem. Reusa `custoDoChip`, então tem de herdar a vírgula sem esforço.
        #expect(trecho.contains("0,42"), "\(trecho)")
        #expect(!trecho.contains("0.42"), "\(trecho)")
    }

    @Test func testCustoParaAcessibilidadeAbaixoDeUmCentavoNaoArredondaParaZero() {
        // Mesma disciplina do chip visual: 0,0042 não pode virar "0,00" nem aqui.
        let trecho = SessionStore.custoParaAcessibilidade(0.0042)
        #expect(!(trecho.contains("0.00") || trecho.contains("0,00")), "\(trecho)")
        #expect(!trecho.isEmpty)
    }

    // MARK: - O chip de custo herda o frescor da lane (a dívida do "número mais perigoso")

    /// Uma lane com custo e uma observação de `segundos` atrás. O limiar é o de
    /// `LaneSnapshot.isStale` (45s) — os testes ficam de um lado e do outro dele de propósito,
    /// sem redefinir limiar próprio para dinheiro.
    private func laneComCusto(_ usd: Double, observadaHa segundos: TimeInterval) -> LaneSnapshot {
        LaneSnapshot(sid: "claude-1", title: "claude-1", state: .running,
                     observedAt: Date().addingTimeInterval(-segundos),
                     confidence: .exact, usd: usd)
    }

    /// Custo fresco não leva marca nenhuma: se todo chip fosse marcado, a marca pararia de
    /// significar "não confie neste número" — o mesmo erro do "US$ 0,00" em todo card.
    @Test func testChipDeCustoFrescoNaoLevaMarcaDeVelho() throws {
        let chip = try #require(SessionStore.chipDeCusto(laneComCusto(12.3456, observadaHa: 5)))
        #expect(!chip.velho, "5s atrás está dentro da tolerância de frescor da lane")
        #expect(chip.texto == chip.valor, "sem marca, o chip é só o valor")
        #expect(!chip.texto.contains(SessionStore.marcaDeCustoVelho), "\(chip.texto)")
        #expect(chip.texto.contains("12,35"), "\(chip.texto)")
    }

    /// 🚨 O teste que a dívida existia para pedir: o servidor CONGELA o último custo conhecido
    /// quando perde a fonte exata, então o número pode estar velho POR CONSTRUÇÃO. Sem herdar
    /// `isStale` da lane, ele ficava parado na tela afirmando um valor atual — e o operador
    /// decide continuar ou PARAR uma lane cara com base nele.
    @Test func testChipDeCustoVelhoLevaMarcaEOValorContinuaLegivel() throws {
        let chip = try #require(SessionStore.chipDeCusto(laneComCusto(12.3456, observadaHa: 600)))
        #expect(chip.velho, "10 minutos sem observação não é um número atual")
        #expect(chip.texto.contains(SessionStore.marcaDeCustoVelho),
                "dado velho tem de PARECER velho, e a marca precisa ser texto: \(chip.texto)")
        // 🚨 Marcar não é ESCONDER: o gasto aconteceu, e o operador precisa da ordem de grandeza
        // mesmo quando a leitura envelheceu. Um chip velho que apaga o número troca um defeito
        // (número errado sem aviso) por outro (nenhum número).
        #expect(chip.texto.contains("12,35"),
                "o valor tem de continuar legível ao lado da marca: \(chip.texto)")
        #expect(chip.valor == "US$ 12,35", "o valor sozinho não muda por estar velho")
        #expect(chip.texto.hasPrefix(chip.valor),
                "o número vem primeiro; a marca é sufixo: \(chip.texto)")
    }

    /// Lane que nunca foi observada é o caso mais velho de todos — `isStale` já devolve `true`
    /// para `observedAt == nil`, e o chip tem de concordar com o selo do card, não discordar.
    @Test func testChipDeCustoDeLaneNuncaObservadaEhVelho() throws {
        let lane = LaneSnapshot(sid: "claude-1", title: "claude-1", state: .running,
                                observedAt: nil, usd: 0.42)
        let chip = try #require(SessionStore.chipDeCusto(lane))
        #expect(chip.velho, "sem observação nenhuma, nada garante que o custo seja atual")
        #expect(chip.texto.contains("0,42"), "\(chip.texto)")
    }

    /// A regra "zero não aparece" NÃO se mexe: uma leitura envelhecer não faz surgir um gasto
    /// que nunca houve, e "US$ 0,00 · antigo" em todo card seria o ruído de sempre com um
    /// carimbo a mais.
    @Test func testChipDeCustoZeroNaoAparecePorVelhoQueSeja() {
        #expect(SessionStore.chipDeCusto(laneComCusto(0, observadaHa: 5)) == nil,
                "custo zero fresco: nada a desenhar")
        #expect(SessionStore.chipDeCusto(laneComCusto(0, observadaHa: 600)) == nil,
                "custo zero velho segue sem chip — velho não inventa gasto")
    }

    /// 🚨 Se o número pode estar velho, quem OUVE tem de ouvir isso também. Sem esta asserção o
    /// conserto seria só visual, e VoiceOver continuaria recebendo a versão CONFIANTE do mesmo
    /// número — que é a forma mais silenciosa possível do defeito original.
    @Test func testCustoParaAcessibilidadeVelhoDizOValorEAIdade() {
        let velho = SessionStore.custoParaAcessibilidade(laneComCusto(12.3456, observadaHa: 600))
        #expect(velho.contains("12,35"), "o valor tem de ser falado: \(velho)")
        #expect(velho.contains("antiga"),
                "a idade da leitura tem de ser falada junto do valor: \(velho)")

        let fresco = SessionStore.custoParaAcessibilidade(laneComCusto(12.3456, observadaHa: 5))
        #expect(fresco.contains("12,35"), "\(fresco)")
        #expect(!fresco.contains("antiga"),
                "custo fresco não pode ser anunciado como antigo: \(fresco)")
    }

    /// O caminho por lane e o caminho por `usd` são o MESMO caminho — um chama o outro. Se
    /// alguém abrir um segundo, o chip e a fala voltam a poder discordar sobre o mesmo número.
    @Test func testFalaEDesenhoConcordamSobreOFrescorDoMesmoNumero() throws {
        for segundos in [5.0, 600.0] {
            let lane = laneComCusto(0.42, observadaHa: segundos)
            let chip = try #require(SessionStore.chipDeCusto(lane))
            #expect(SessionStore.custoParaAcessibilidade(lane) ==
                    SessionStore.custoParaAcessibilidade(lane.usd, velho: chip.velho),
                    "a fala tem de sair da mesma decisão que o desenho")
        }
    }

    // MARK: - Link caído esconde a caixa sem mentir (Important da review)

    /// 🚨 Achado de review: `SessionView` não tinha referência nenhuma ao estado do link do
    /// `FleetStateClient`. Um socket caído congelava `aceita` em `nil` para sempre, e a tela
    /// continuava dizendo "aguardando o servidor declarar…" como se fosse questão de segundos —
    /// mentindo por omissão sobre QUEM está em silêncio (a fonte, não o agente).
    @Test func testRazaoSemCapacidadeENilOuLinkVivoEhTransitorio() {
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: nil) == .transitorio,
                "sem link nenhum ainda (ex.: retrato/fixture), o texto de sempre está certo")
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: .idle) == .transitorio,
                "arranque, antes de qualquer queda")
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: .connecting) == .transitorio)
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: .live) == .transitorio,
                "link de pé: se aceita é nil, é o quadro DESTA lane que não chegou")
    }

    /// O link caído reaproveita `FleetStateClient.explicacaoDoLink` verbatim — a mesma frase que
    /// a Frota já mostra para "o broker caiu" — em vez de uma segunda string inventada aqui.
    @Test func testRazaoSemCapacidadeQuandoOLinkCaiuUsaAExplicacaoDaFrota() {
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: .failed("boom")) ==
                .linkCaido(FleetStateStore.linkDescription(.failed("boom"))))
        #expect(SessionStore.razaoSemCapacidadeDeclarada(link: .reconnecting) ==
                .linkCaido(FleetStateStore.linkDescription(.reconnecting)))

        guard case .linkCaido(let motivo) = SessionStore.razaoSemCapacidadeDeclarada(
            link: .retrying(reason: "connection refused", attempts: 13)
        ) else {
            Issue.record(".insistindo tem de virar .linkCaido, nunca .transitorio")
            return
        }
        #expect(motivo.contains("connection refused"), "\(motivo)")
        #expect(motivo.contains("13"), "\(motivo)")
        // 🚨 `.insistindo` NUNCA pode ler como "o cliente desistiu" — ele está retentando
        // sozinho. `explicacaoDoLink` já garante isto; este teste prende que a Sessão herda a
        // MESMA garantia por reaproveitar a função, não por reimplementar a frase.
        #expect(!motivo.localizedCaseInsensitiveContains("desisti"), "\(motivo)")
    }
}
