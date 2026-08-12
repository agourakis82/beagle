import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

// SESSÃO — a conversa de uma lane, montada dos eventos do protocolo.
//
// Por que um modelo próprio, e não `ChatMessage`: uma sessão de agente não é uma conversa. Ela
// tem chamada de ferramenta, diff proposto e pedido de aprovação — três coisas que uma bolha de
// chat não sabe carregar, e que são exatamente o que o operador precisa ver para decidir.
// Reaproveitar a bolha faria diff e aprovação virarem anexo dentro de um balão, que é a forma de
// "nem uma coisa nem outra" que motivou esta rodada.
//
// O transporte é polling com cursor, não socket. A escolha é medida, não preguiça: `seq` é
// monotônico e ATRAVESSA reinício do loomd, então um poll perdido se recupera sozinho na próxima
// volta. Um socket dá latência menor e devolve o problema de reconexão, deduplicação e cursor —
// que é justamente o que o `seq` já resolve. Se a latência incomodar, o teto é SSE no loomd; não
// é remendar aqui.

/// O que o agente fez num passo. `Kind` do loomd, traduzido para o que a tela desenha.
public enum SessionStep: Sendable, Equatable, Identifiable {
    /// O que o operador pediu.
    case prompt(id: Int, text: String, at: Date)
    // `turno` é lido de fora por `Turno.agrupar`: sem ele a trilha é uma sopa em que não se vê
    // onde um pedido acaba e o próximo começa.
    /// O que o agente respondeu, inteiro.
    case message(id: Int, text: String, at: Date)
    /// Ferramenta executada — nome e alvo, uma linha. Não é texto para ler, é rastro para varrer.
    case tool(id: Int, name: String, detail: String, at: Date)
    /// Mudança proposta, em unified diff.
    case diff(id: Int, patch: String, at: Date)
    /// O agente parou e está esperando. `kind` decide o rótulo: patch se desfaz por git, comando não.
    ///
    /// 🚨 `diff` existe porque a lane ACP NÃO emite `diff_proposed` — medido em
    /// `loomd/src/event.rs:486-500`: no caminho ACP o patch chega DENTRO do próprio evento
    /// `awaiting_approval` (`c.get("type") == "diff"`), nunca como um passo `.diff` avulso.
    /// `Kind::DiffProposed` só existe no codex. Sem este campo, a lane que esta fatia inteira
    /// existe para servir aprova uma mudança que nunca viu. Valor padrão `nil` para não quebrar
    /// call-sites e testes existentes.
    case approval(id: Int, kind: ApprovalKind, detail: String, diff: String? = nil, at: Date)
    /// Algo quebrou. Erro é conteúdo de primeira classe: escondê-lo faz a tela mentir por omissão.
    case failure(id: Int, text: String, at: Date)
    /// Custo e janela de contexto. **Não é passo desenhado na conversa** — custo não é fala, e
    /// desenhá-lo na linha do diálogo poluiria o que o operador lê. Vira rodapé do turno.
    case uso(id: Int, contextoUsado: Int, contextoTeto: Int, usd: Double, at: Date)

    public enum ApprovalKind: String, Sendable, Codable {
        case command, patch, other

        public var label: String {
            switch self {
            case .command: return "rodar um comando"
            case .patch: return "aplicar uma mudança"
            case .other: return "seguir"
            }
        }
        /// Comando não se desfaz; patch sim. A tela diz isso ANTES do toque, não depois.
        public var reversible: Bool { self == .patch }
    }

    public var id: Int {
        switch self {
        case .prompt(let i, _, _), .message(let i, _, _), .tool(let i, _, _, _),
             .diff(let i, _, _), .approval(let i, _, _, _, _), .failure(let i, _, _):
            return i
        case .uso(let i, _, _, _, _):
            return i
        }
    }
    public var at: Date {
        switch self {
        case .prompt(_, _, let t), .message(_, _, let t), .diff(_, _, let t),
             .failure(_, _, let t):
            return t
        case .tool(_, _, _, let t), .approval(_, _, _, _, let t):
            return t
        case .uso(_, _, _, _, let t):
            return t
        }
    }

    /// Quem falou. A tela alinha e colore por isto — e é a pergunta que o olho faz primeiro.
    public var isOperator: Bool { if case .prompt = self { return true }; return false }

    /// Custo não é fala: não se desenha na linha do diálogo, vira rodapé do turno.
    /// 🚨 Filtrado ANTES do ForEach — um braço que devolve EmptyView() ainda ocupa
    /// posição no VStack e o `spacing` fixo abre um buraco por evento.
    public var desenhavel: Bool {
        if case .uso = self { return false }
        return true
    }
}

/// Um TURNO: o pedido, e tudo que o agente fez por causa dele.
///
/// 🚨 Por que agrupar. No primeiro retrato a trilha corria reta — prompt, mensagem, ferramenta,
/// diff, prompt, mensagem — e não havia como ver onde um pedido acabava e o próximo começava. Uma
/// sessão de trabalho de verdade tem dez turnos, e sem fronteira a tela deixa de ser legível
/// exatamente quando fica útil.
public struct UsoDoTurno: Sendable, Equatable {
    public let contextoUsado: Int
    public let contextoTeto: Int
    public let usd: Double
    public var proporcao: Double {
        contextoTeto > 0 ? Double(contextoUsado) / Double(contextoTeto) : 0
    }
}

public struct Turno: Identifiable, Sendable {
    /// O `seq` do primeiro passo — estável e monotônico, então a lista não se reordena sozinha.
    public let id: Int
    public let passos: [SessionStep]

    public var pedido: String? {
        for p in passos { if case .prompt(_, let t, _) = p { return t } }
        return nil
    }
    public var comecouEm: Date { passos.first?.at ?? Date() }
    public var terminouEm: Date { passos.last?.at ?? Date() }
    /// Quanto durou. `nil` enquanto é o último turno e pode ainda estar correndo — afirmar duração
    /// de algo em curso seria dizer que acabou.
    public func duracao(concluido: Bool) -> TimeInterval? {
        concluido ? terminouEm.timeIntervalSince(comecouEm) : nil
    }
    public var temDiff: Bool { passos.contains { if case .diff = $0 { return true }; return false } }
    public var pedePermissao: Bool {
        passos.contains { if case .approval = $0 { return true }; return false }
    }

    /// O uso do turno. **O último passo com custo**, não a soma — medido: `cost.amount` vem nulo
    /// em 15 dos 16 eventos, e somar funciona por acidente até o protocolo preencher os outros.
    public var uso: UsoDoTurno? {
        var ultimo: UsoDoTurno?
        for p in passos {
            if case .uso(_, let usado, let teto, let usd, _) = p {
                // contexto é absoluto e monotônico: o último sempre vale.
                // custo: só sobrescreve quando o evento realmente trouxe número.
                let usdFinal = usd > 0 ? usd : (ultimo?.usd ?? 0)
                ultimo = UsoDoTurno(contextoUsado: usado, contextoTeto: teto, usd: usdFinal)
            }
        }
        return ultimo
    }

    /// Quebra a trilha em turnos. Um turno começa em cada `prompt` do operador.
    ///
    /// O que vem ANTES do primeiro prompt (uma sessão retomada, cujo pedido está fora da janela do
    /// diário) forma um turno sem pedido — e a tela diz isso, em vez de fingir que aquilo pertence
    /// ao próximo pedido, que seria atribuir trabalho ao pedido errado.
    public static func agrupar(_ passos: [SessionStep]) -> [Turno] {
        var fora: [Turno] = []
        var atual: [SessionStep] = []
        for p in passos {
            if p.isOperator, !atual.isEmpty {
                fora.append(Turno(id: atual[0].id, passos: atual))
                atual = []
            }
            atual.append(p)
        }
        if !atual.isEmpty { fora.append(Turno(id: atual[0].id, passos: atual)) }
        return fora
    }
}

/// Um evento cru da trama, como o cockpit o devolve em `/turns`.
public struct TramaEvent: Decodable, Sendable {
    public let seq: Int
    public let tsMs: Double
    public let lane: String
    public let kind: String
    public let text: String?
    public let detail: String?
    public let diff: String?
    public let tool: String?
    public let approvalKind: SessionStep.ApprovalKind?

    enum CodingKeys: String, CodingKey {
        case seq, lane, kind, text, detail, diff, tool
        case tsMs = "ts_ms"
        case approvalKind = "approval_kind"
    }

    public var at: Date { Date(timeIntervalSince1970: tsMs / 1000) }
}

@MainActor
@Observable
public final class SessionStore {
    public enum Link: Sendable, Equatable { case idle, live, failed(String) }

    public private(set) var lane: String
    public private(set) var steps: [SessionStep] = []
    /// A trilha agrupada. Derivada, nunca guardada em paralelo — dois lugares com a mesma verdade
    /// divergem, e a lição já foi paga no `detail`/`text`.
    public var turnos: [Turno] { Turno.agrupar(steps) }
    /// A mensagem SENDO ESCRITA agora — os deltas coalescidos do outro lado. Não é um passo:
    /// vira um quando fecha, e mostrá-la como passo faria a lista piscar a cada volta do poll.
    public private(set) var streaming: String?
    public private(set) var link: Link = .idle
    public private(set) var sending = false
    /// A recusa do servidor, nas palavras dele. Ele sabe o motivo; nós inventaríamos um pior.
    public private(set) var note: String?
    public private(set) var lastPollAt: Date?

    /// O maior `seq` já visto. LEGÍVEL de propósito: era `private`, e por isso o teste que dizia
    /// guardar a monotonicidade do cursor ficava VERDE com a regressão aplicada — `apply` guarda o
    /// cursor mas não o observa, então a consequência (o próximo poll pedir do lugar errado) não
    /// era alcançável por nenhuma asserção. Estado que decide a próxima requisição precisa ser
    /// observável, senão o teste sobre ele é teatro.
    public private(set) var cursor = 0
    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var loop: Task<Void, Never>?
    /// Intervalo do poll. 900ms porque é o teto em que texto chegando ainda LÊ como chegando;
    /// mais rápido gasta exec no cluster sem o olho perceber a diferença.
    private let intervalo: Duration = .milliseconds(900)

    public init(lane: String, endpoint: FleetEndpoint = FleetEndpoint(), session: URLSession = .shared) {
        self.lane = lane
        self.endpoint = endpoint
        self.session = session
    }

    /// Fonte PARADA, para retrato e teste — sem rede, como a da Frota. Uma tela que só se
    /// inspeciona ao vivo é uma tela que se desenha no escuro.
    public static func fixture(lane: String, steps: [SessionStep], streaming: String? = nil,
                               link: Link = .live, note: String? = nil) -> SessionStore {
        let s = SessionStore(lane: lane)
        s.steps = steps
        s.streaming = streaming
        s.link = link
        s.note = note
        s.lastPollAt = Date()
        s.parada = true
        return s
    }
    private var parada = false

    public func start() {
        guard !parada, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: self?.intervalo ?? .milliseconds(900))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func poll() async {
        guard let req = endpoint.laneTurnsRequest(sid: lane, since: cursor) else {
            link = .failed("lane inválida: \(lane)")
            return
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                link = .failed(Self.motivo(data) ?? "HTTP \(code)")
                return
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            apply(env.data)
            link = .live
            lastPollAt = Date()
        } catch {
            link = .failed(error.localizedDescription)
        }
    }

    /// Aplica uma resposta de poll. Separado da rede de propósito: é aqui que mora a decisão de
    /// como um evento vira passo, e decisão que só se alcança abrindo socket não é testável.
    public func apply(_ page: Page) {
        // O cursor vem PRONTO do servidor. Derivar do último elemento devolve nil num poll sem
        // novidade — e o cliente voltaria ao começo do diário a cada volta silenciosa.
        cursor = max(cursor, page.cursor)
        streaming = page.streaming
        turnoEmCurso = page.turnoEmCurso ?? (page.streaming != nil)
        for e in page.events {
            guard let passo = Self.passo(de: e) else { continue }
            // A trama é append-only e o cursor é monotônico, então repetição só acontece se um
            // poll for reaplicado. Guardar por `seq` é barato e evita a lista duplicar na tela.
            if steps.contains(where: { $0.id == passo.id }) { continue }
            steps.append(passo)
        }
    }

    /// A tradução. `Delta` nunca chega aqui — ele é coalescido no loomd e vem em `streaming`.
    public static func passo(de e: TramaEvent) -> SessionStep? {
        let corpo = e.text ?? e.detail ?? ""
        switch e.kind {
        case "user_prompt":
            return .prompt(id: e.seq, text: corpo, at: e.at)
        case "agent_message":
            return .message(id: e.seq, text: corpo, at: e.at)
        case "diff_proposed":
            guard let d = e.diff, !d.isEmpty else { return nil }
            return .diff(id: e.seq, patch: d, at: e.at)
        case "awaiting_approval":
            // 🚨 A lane ACP embute o diff AQUI — ela não emite `diff_proposed`. Descartar
            // `e.diff` neste braço era o operador aprovando uma mudança que nunca viu.
            return .approval(id: e.seq, kind: e.approvalKind ?? .other, detail: corpo,
                              diff: e.diff, at: e.at)
        case "error":
            return .failure(id: e.seq, text: corpo.isEmpty ? "erro sem descrição" : corpo, at: e.at)
        case "tool_call", "tool_result":
            return .tool(id: e.seq, name: e.tool ?? "ferramenta", detail: corpo, at: e.at)
        // Ruído de ciclo de vida: existe na trama porque é verdade, e não vira linha na tela
        // porque não é decisão nem conteúdo. Um turno que começa não é notícia.
        case "usage":
            guard let u = Self.uso(de: e.detail ?? "") else { return nil }
            return .uso(id: e.seq, contextoUsado: u.usado, contextoTeto: u.teto, usd: u.usd, at: e.at)
        case "turn_started", "turn_ended", "session_started", "session_ended",
             "idle", "approval_answered", "unknown", "delta":
            return nil
        default:
            return nil
        }
    }

    /// "contexto 38718/1000000 · USD 0.3728" → os três números.
    /// Formato escrito pelo loomd em `from_acp_update`; se ele mudar lá, este teste quebra aqui,
    /// que é o lugar certo para descobrir.
    static func uso(de detail: String) -> (usado: Int, teto: Int, usd: Double)? {
        let nums = detail.split(whereSeparator: { !"0123456789.".contains($0) })
        guard nums.count >= 3,
              let usado = Int(nums[0]), let teto = Int(nums[1]), let usd = Double(nums[2])
        else { return nil }
        return (usado, teto, usd)
    }

    // MARK: - O que o servidor deixa fazer

    /// O rótulo do gesto, derivado do que a lane aceita. `nil` = não oferecer botão nenhum.
    public static func rotuloDeGuiar(_ aceita: Aceita?) -> String? {
        switch aceita {
        case .redireciona: return "GUIAR"
        case .enfileira: return "ENFILEIRAR"
        case .somenteLeitura, nil: return nil
        }
    }

    /// A dica da caixa. `nil` = a caixa não existe (não desabilitada: AUSENTE).
    public static func dicaDaCaixa(_ aceita: Aceita?) -> String? {
        switch aceita {
        case .redireciona: return "guiar o turno em curso…"
        case .enfileira: return "enfileirar para depois deste…"
        case .somenteLeitura, nil: return nil
        }
    }

    /// A explicação que substitui a caixa, quando não há caixa. Distingue "o servidor DECLAROU
    /// leitura" de "ainda não sei" — a tela não pode afirmar a primeira quando é a segunda.
    ///
    /// 🚨 `nil` de `Aceita?` não é `.somenteLeitura`. São estados diferentes: um é o servidor
    /// dizendo "esta lane é tail, /prompt dá 404"; o outro é "o quadro ainda não chegou, o sid
    /// não bateu, ou o socket caiu" — nada foi dito sobre a NATUREZA da lane. Desenhar a mesma
    /// frase ("observada pelo transcript — fale com ela pelo terminal") para os dois é a mentira
    /// que esta fatia existe para matar, invertida: antes prometia um gesto que não existia,
    /// assim NEGA um gesto que existe (uma lane de codex plenamente dirigível, só sem quadro
    /// ainda). `nil` de retorno aqui = há caixa; não chame isto sem checar `dicaDaCaixa` antes.
    public enum SemCaixa: Equatable { case somenteObservada, capacidadeDesconhecida }

    public static func semCaixa(_ aceita: Aceita?) -> SemCaixa? {
        switch aceita {
        case .somenteLeitura: return .somenteObservada
        case nil: return .capacidadeDesconhecida
        case .redireciona, .enfileira: return nil
        }
    }

    /// Distingue as duas razões de `capacidadeDesconhecida` (o caso `aceita == nil` de
    /// `semCaixa`): o link do `FleetStateClient` está de PÉ e o servidor só ainda não falou desta
    /// lane (transitório — o texto atual "aguardando o servidor declarar…" está certo), OU o
    /// link CAIU e é por isso que `aceita` nunca chegou (a fonte emudeceu; dizer "aguardando"
    /// mentiria por omissão sobre QUEM está em silêncio).
    ///
    /// 🚨 Achado de review: `SessionView` não tinha referência nenhuma ao estado do link do
    /// `FleetStateClient`. Se o transporte caísse, `aceita` congelava em `nil` para sempre, a
    /// tela continuava dizendo "aguardando o servidor declarar…" como se fosse transitório, e o
    /// operador perdia a ÚNICA caixa de texto que tinha sem nenhum aviso de que a culpa era da
    /// rede, não do agente. `dicaDaCaixa`/`semCaixa` não bastam para consertar isto: os dois só
    /// enxergam `aceita`, que é justamente o que fica mudo quando o link cai.
    ///
    /// Reaproveita `FleetStateClient.explicacaoDoLink` — a MESMA frase que a `FrotaView` já usa
    /// para "o broker caiu" (inclusive `.insistindo`, que nunca pode implicar que o cliente
    /// desistiu: ele está retentando sozinho, em segundo plano). Inventar uma segunda string
    /// aqui para o mesmo fato seria a duplicação que esta fatia já pagou lição para não repetir.
    public enum RazaoSemCapacidadeDeclarada: Equatable {
        /// O link está de pé; o servidor só não declarou nada sobre esta lane ainda.
        case transitorio
        /// O link caiu. O texto é o de `FleetStateClient.explicacaoDoLink`, verbatim.
        case linkCaido(String)
    }

    public static func razaoSemCapacidadeDeclarada(link: FleetStateClient.Link?) -> RazaoSemCapacidadeDeclarada {
        guard let link else { return .transitorio }
        switch link {
        case .idle, .connecting, .live:
            // `.idle`/`.connecting` são o arranque, antes de qualquer queda — dizer "o broker
            // caiu" aí seria alarmar sobre uma queda que nunca aconteceu. `.live` é a fonte de
            // pé; se `aceita` ainda é `nil` com o link vivo, é porque o quadro desta lane
            // específica não chegou, não porque o transporte está mudo.
            return .transitorio
        case .reconnecting, .insistindo, .failed:
            return .linkCaido(FleetStateClient.explicacaoDoLink(link))
        }
    }

    // MARK: - Dinheiro, num app escrito em português

    /// O ÚNICO produtor de string de dinheiro do app — chip, rodapé e VoiceOver passam por aqui.
    ///
    /// 🚨 O defeito que esta função existe para fechar: `String(format: "US$ %.2f", …)` é
    /// INSENSÍVEL A LOCALE. `%f` emite ponto sempre, então o chip imprimia "US$ 12.35" na mesma
    /// coluna, logo abaixo do literal "< US$ 0,01" — dois separadores decimais diferentes lado a
    /// lado na mesma tela. A interface inteira é em português ("guiar o turno em curso…"); a
    /// vírgula é a forma certa e o ponto era o defeito, não o contrário.
    ///
    /// 🚨 Locale EXPLÍCITO `pt_BR`, NUNCA `Locale.current`. Com `.current` o mesmo teste passa
    /// nesta máquina e falha noutra, e um teste que depende do ambiente não prova nada. Não é
    /// preferência do sistema: o app não é multilíngue, o idioma dele é uma decisão do produto.
    ///
    /// Agrupamento de milhar LIGADO — `NumberFormatter` dá "US$ 1.234,56" de graça, que o `%.2f`
    /// não dava, e o chip mede o acumulado da lane, que cresce o dia inteiro até chegar lá. Em
    /// pt-BR o ponto é o separador de MILHAR legítimo; ele não reabre o defeito, que era o ponto
    /// no lugar do separador DECIMAL. É por isso que o teste de consistência olha o ÚLTIMO
    /// separador da string, não a ausência de todo ponto.
    ///
    /// `.decimal` com o prefixo literal "US$ ", e não `.currency`: o estilo de moeda depende do
    /// código de moeda e da tabela do ICU para decidir entre "US$", "$" e "USD" — o prefixo
    /// literal é o que já está na tela e não muda debaixo do app numa atualização do sistema.
    ///
    /// O formatador nasce a cada chamada de propósito: `NumberFormatter` é classe mutável e não
    /// `Sendable`, e um `static let` compartilhado neste alvo (modo Swift 6, StrictConcurrency)
    /// seria estado global não isolado. São poucas strings por quadro; o custo não aparece.
    static func moeda(_ usd: Double, casas: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = casas
        f.maximumFractionDigits = casas
        f.usesGroupingSeparator = true
        guard let numero = f.string(from: usd as NSNumber) else {
            // Inalcançável para um `Double` finito. Se acontecesse, o caminho de recuo não pode
            // trazer o ponto de volta — é exatamente o defeito que esta função conserta.
            let cru = String(format: "%.\(casas)f", usd)
            return "US$ " + cru.replacingOccurrences(of: ".", with: ",")
        }
        return "US$ " + numero
    }

    // MARK: - O rodapé do turno

    /// O rodapé do turno, em texto. `nil` = sem rodapé (nem duração, nem uso).
    /// 🚨 Custo zero NÃO entra: "US$ 0,0000" em todo turno treina o olho a ignorar a linha, e aí
    /// o número que importa também deixa de ser lido.
    ///
    /// 🚨 Achado de review: a duração é OPCIONAL DENTRO da linha, não um portão para a linha
    /// inteira. Antes, `guard let d = duracao else { return nil }` apagava contexto E custo
    /// sempre que o turno ainda estava em curso (`duracao(concluido:)` é `nil` enquanto corre) —
    /// exatamente o turno que o operador está olhando AGORA, e o único momento em que "quanto
    /// isto está custando" decide se ele deixa correr ou aperta parar. O lado Rust já conta o
    /// turno aberto sem esperar por um `TurnEnded` que pode não chegar antes do olho passar pela
    /// tela; o rodapé não pode ser mais conservador que a fonte que ele lê.
    public static func rodapeDoTurno(duracao: TimeInterval?, uso: UsoDoTurno?) -> String? {
        var partes: [String] = []
        if let d = duracao { partes.append(rodapeDur(d)) }
        if let u = uso {
            partes.append(contextoDoRodape(u.proporcao))
            // Quatro casas: o rodapé mede UM turno, e a quarta casa É o dado. Ver `moeda`.
            if u.usd > 0 { partes.append(moeda(u.usd, casas: 4)) }
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    /// A porcentagem de contexto usado, para o rodapé. O 5º "arredonda para zero" desta fatia:
    /// trocar truncamento por `.rounded()` só moveu o limiar de <1% para <0,5% — com um teto de
    /// 1.000.000 de tokens, qualquer uso abaixo de 5.000 ainda imprimia "contexto 0%". Mesma
    /// disciplina de `custoDoChip`: um limiar explícito diz a verdade ("gastou contexto, menos
    /// de 1%") em vez de deixar o arredondamento afirmar zero.
    ///
    /// Contexto EXATAMENTE zero (`proporcao == 0`, ou seja `contextoUsado == 0`) é praticamente
    /// impossível na prática — o próprio pedido do operador já consome tokens antes de qualquer
    /// resposta — mas quando acontece mesmo assim, mostra "contexto 0%" sem o limiar: aí zero é
    /// a verdade honesta, não um valor pequeno escondido pelo arredondamento.
    private static func contextoDoRodape(_ proporcao: Double) -> String {
        guard proporcao > 0 else { return "contexto 0%" }
        let arredondado = Int((proporcao * 100).rounded())
        return arredondado < 1 ? "contexto < 1%" : "contexto \(arredondado)%"
    }

    private static func rodapeDur(_ s: TimeInterval) -> String {
        let t = Int(s.rounded())
        if t < 60 { return "\(t)s" }
        if t < 3600 { return "\(t / 60)m \(t % 60)s" }
        return "\(t / 3600)h \((t % 3600) / 60)m"
    }

    /// O custo da lane para o chip. `nil` = não mostrar nada.
    /// 🚨 Zero NÃO se mostra: "US$ 0,00" em todo chip treina o olho a ignorar a linha, e aí o
    /// número que importa também deixa de ser lido. O servidor omite a chave quando é zero.
    ///
    /// 🚨 NÃO usa o `%.4f` do rodapé do turno — de propósito. O rodapé mede UM TURNO (centavos
    /// de centavo: a quarta casa É o dado). O chip mede o ACUMULADO da lane, que cresce o dia
    /// inteiro — com `%.4f` ele vira "US$ 12,3456" num card estreito, quatro casas que ninguém
    /// lê empurrando o dígito que importa para fora do campo visual. A coerência entre os dois
    /// números é de PRINCÍPIO (custo zero não aparece; nada arredonda para zero), não de string
    /// de formato — copiar o `%.4f` aqui seria coerência de forma às custas da de fundo.
    ///
    /// `>= 0,01`: duas casas, como dinheiro se lê. `> 0` e `< 0,01`: NÃO arredonda para zero —
    /// duas casas sozinhas trariam de volta o "US$ 0,0000"/"contexto 0%" que esta fatia já
    /// consertou duas vezes; um limiar explícito diz a verdade ("gastou algo, menos de um
    /// centavo") sem gastar quatro dígitos no card.
    public static func custoDoChip(_ usd: Double) -> String? {
        guard usd > 0 else { return nil }
        // 🚨 O limiar é DERIVADO do mesmo formatador, não digitado. Como literal ele era a
        // única string certa por acidente de digitação — e se o formato mudasse, ficaria
        // para trás em silêncio, que é como o ponto e a vírgula foram parar na mesma tela.
        if usd < 0.01 { return "< " + moeda(0.01, casas: 2) }
        return moeda(usd, casas: 2)
    }

    /// O trecho ", custo US$ 0,42" a ANEXAR num `accessibilityLabel` que já fala presença e
    /// procedência — string vazia quando não há custo a anunciar. Reaproveita `custoDoChip`
    /// (mesma regra: zero não aparece, nada arredonda para zero) em vez de reimplementar.
    ///
    /// 🚨 Achado de review: `FrotaView` tinha `.accessibilityElement(children: .combine)`
    /// SEGUIDO de `.accessibilityLabel(...)` — o label explícito SUBSTITUI o texto combinado dos
    /// filhos, não o soma a ele. O chip de custo é um desses filhos, então VoiceOver nunca ouvia
    /// o número que esta fatia inteira existe para tornar visível. Extraído aqui (em vez de
    /// montado inline na view) para ser testável sem SwiftUI, no mesmo padrão do resto do
    /// arquivo.
    ///
    /// 🚨 O parâmetro `velho` é a extensão DESTE caminho, não um segundo caminho: se o número
    /// pode estar velho (ver `chipDeCusto`), quem OUVE tem de ouvir isso também — senão o
    /// conserto visual deixaria VoiceOver com a versão confiante do mesmo número, que é
    /// exatamente o defeito que esta função foi criada para não repetir.
    public static func custoParaAcessibilidade(_ usd: Double, velho: Bool = false) -> String {
        guard let custo = custoDoChip(usd) else { return "" }
        // A frase é a MESMA que o selo de procedência do card já usa para uma observação
        // vencida ("leitura antiga"): um significado, um vocabulário.
        return velho ? ", custo \(custo) (leitura antiga)" : ", custo \(custo)"
    }

    /// O caminho que as views usam: a MESMA decisão de `chipDeCusto` alimenta a fala, para o
    /// desenho e o rótulo nunca discordarem sobre o frescor do mesmo número.
    public static func custoParaAcessibilidade(_ lane: LaneSnapshot, agora: Date = Date()) -> String {
        guard let chip = chipDeCusto(lane, agora: agora) else { return "" }
        return custoParaAcessibilidade(lane.usd, velho: chip.velho)
    }

    // MARK: - O frescor do número, não só o número

    /// O chip de custo JÁ MARCADO quando o número pode estar velho — a decisão, pura, fora da
    /// view. A `LaneCard` só escolhe COMO desenhar o que esta função decidiu.
    ///
    /// 🚨 Por que isto existe: o chip mostrava o acumulado da lane sem herdar `isStale` da lane,
    /// ao contrário do `observationAge` logo abaixo dele no MESMO card. Pior: o servidor CONGELA
    /// o último custo conhecido quando perde a fonte exata (antes mandava zero, o que apagava o
    /// gasto), e o cliente faz o mesmo com `?? old.usd` — então o número pode estar velho POR
    /// CONSTRUÇÃO, sem prazo visível, e não apenas atrasado por polling. É o número mais
    /// perigoso de estar errado sem aviso: o operador decide continuar ou PARAR uma lane cara
    /// com base nele.
    ///
    /// 🚨 A marca é TEXTO, não opacidade. Num chip que já é `.caption2` a 60% de branco, baixar
    /// a opacidade não é sinal — é o mesmo ruído, mais fraco: o dado velho ficaria menos
    /// LEGÍVEL em vez de mais suspeito, e opacidade não tem nome que um leitor de tela possa
    /// dizer. Por isso a marca é um sufixo (mais a cor, escolhida na view), e o `valor`
    /// continua inteiro na string: marcar não é esconder, porque o gasto ACONTECEU e o operador
    /// precisa da ordem de grandeza mesmo quando a leitura envelheceu.
    public struct ChipDeCusto: Equatable, Sendable {
        /// O valor sozinho — exatamente o que `custoDoChip` já dizia, sem a marca.
        public let valor: String
        /// O que desenhar: `valor`, mais a marca quando velho.
        public let texto: String
        /// A observação por trás deste número está vencida (`LaneSnapshot.isStale`).
        public let velho: Bool
    }

    /// O sufixo que marca um custo velho. Curto de propósito: cabe num card estreito ao lado de
    /// "US$ 1.234,57" sem empurrar o dígito que importa para fora do campo visual.
    public static let marcaDeCustoVelho = "· antigo"

    /// `nil` = não desenhar chip nenhum.
    ///
    /// 🚨 A regra de zero NÃO muda com o frescor: custo zero segue sem chip, velho ou não — uma
    /// leitura envelhecer não faz aparecer um gasto que nunca houve.
    public static func chipDeCusto(_ lane: LaneSnapshot, agora: Date = Date()) -> ChipDeCusto? {
        guard let valor = custoDoChip(lane.usd) else { return nil }
        // Herda o MESMO predicado de frescor que `observationAge` desenha logo abaixo, em vez
        // de inventar um limiar próprio para o dinheiro. Um card, um relógio.
        let velho = lane.isStale(now: agora)
        return ChipDeCusto(valor: valor,
                           texto: velho ? "\(valor) \(marcaDeCustoVelho)" : valor,
                           velho: velho)
    }

    // MARK: - O que o card de aprovação DIZ que está sendo aprovado

    /// A prova que o card mostra para quem tem de decidir. Três casos, e o terceiro é o que
    /// separa esta função de um `??` encadeado: quando não há NADA, ela não afirma nada.
    public enum ProvaDoPedido: Equatable, Sendable {
        /// A mudança proposta, em unified diff. O melhor que existe: o operador vê o que aprova.
        case diff(String)
        /// A evidência em texto — a frase do agente. É o que se tem quando não há patch (aprovar
        /// um COMANDO não gera diff nenhum), e é honesta: veio do agente, não foi inventada aqui.
        case texto(String)
        /// Não há prova. O card cala em vez de encher a área com cromo do agente.
        case nenhuma
    }

    /// O que o card de aprovação da Frota mostra. PURA, e é esse o ponto: a decisão de "o que se
    /// vê antes de aprovar" é a coisa mais importante desta tela, e enquanto morasse dentro de
    /// uma `View` não haveria como afirmá-la sem SwiftUI. Mesma disciplina de `custoDoChip`,
    /// `rotuloDeGuiar` e `semCaixa` — a view só escolhe COMO desenhar o que aqui se decidiu.
    ///
    /// 🚨 O defeito que isto fecha: o card mostrava `lane.detail` cru, que na frota real é
    /// "Press enter to confirm or esc to cancel" — cromo do agente, em inglês, numa interface em
    /// português, e IDÊNTICO entre duas lanes pedindo coisas opostas. Para decidir, o operador
    /// tinha de sair da tela. O dado para dizer o que era já existia no loomd (`pending_kind`,
    /// `last_diff`) e no cockpit (`approvalKind`, `diff`); só não existia no modelo Swift.
    public struct PedidoDoCard: Equatable, Sendable {
        /// O QUE está sendo aprovado, em uma frase. `nil` quando o servidor não declarou o tipo —
        /// e aí o card não afirma natureza nenhuma (não é "seguir": é silêncio).
        public let rotulo: String?
        /// A reversibilidade, que decide se ele lê o detalhe ou só aprova. `nil` pelo mesmo
        /// motivo de `rotulo`: sem tipo declarado não há promessa a fazer sobre desfazer.
        public let reversivel: Bool?
        public let prova: ProvaDoPedido

        /// Não há uma palavra a dizer sobre este pedido. A view usa isto para não abrir um bloco
        /// vazio (um `VStack` com `spacing` fixo abre buraco mesmo sem conteúdo dentro).
        public var vazio: Bool { rotulo == nil && prova == .nenhuma }
    }

    /// 🚨 O DIFF GANHA DO DETALHE quando os dois existem. Não é preferência estética: o `detail`
    /// de uma lane que traz patch é justamente a linha de cromo ("Press enter…"), e o patch é a
    /// única coisa que responde à pergunta que o card faz. Preferir o texto aí seria manter o
    /// defeito de sempre, agora com um campo novo por baixo, sem uso.
    /// `nonisolated` porque é PURA — mesma disciplina de `FleetStateClient.approveTransport`:
    /// uma decisão que só pode ser consultada de dentro do main actor não é testável como
    /// decisão, e é justamente para ser assertável sem SwiftUI que ela mora aqui.
    public nonisolated static func pedidoDoCard(_ lane: LaneSnapshot) -> PedidoDoCard {
        let prova: ProvaDoPedido
        if let d = lane.diff, !d.isEmpty {
            prova = .diff(d)
        } else if !lane.detail.isEmpty {
            prova = .texto(lane.detail)
        } else {
            prova = .nenhuma
        }
        // O rótulo vem do tipo que o SERVIDOR declarou, e do `label` que `ApprovalKind` já expõe
        // (o mesmo que a `PedidoView` da Sessão usa) — nenhuma string nova inventada aqui.
        return PedidoDoCard(
            rotulo: lane.approvalKind.map { "O agente quer \($0.label)" },
            reversivel: lane.approvalKind?.reversible,
            prova: prova
        )
    }

    // MARK: - Um pedido, uma resposta

    /// Quantos LUGARES na trilha ofereceriam Aplicar/Recusar para o pedido pendente deste turno.
    ///
    /// 🚨 Achado de review: quando o agente propõe um patch (`.diff`) e depois pede para
    /// aplicá-lo (`.approval`), os dois passos coexistem no mesmo turno. Se AMBOS os widgets
    /// desenhassem botão — `DiffView` do `.diff` avulso E o card de `.approval` —, o operador
    /// veria dois pares de Aplicar/Recusar chamando o MESMO `onAprovar` para o MESMO pedido.
    /// A decisão: o card de aprovação (`PedidoView`) é o ÚNICO lugar — é ele que carrega o
    /// pedido (e agora o diff, embutido ou referenciado), e `DiffView` nunca desenha botão, em
    /// nenhum contexto. Este predicado é o invariante executável dessa decisão: um turno com
    /// pedido pendente tem de dar EXATAMENTE 1, não importa quantos passos `.diff` existam ao
    /// lado. Sem isto extraído puro, só um teste de UI (que este projeto não tem) pegaria a
    /// regressão — os snapshots existentes (`SessionSnapshotTests`) renderizam PNG e não
    /// afirmam nada sobre quantos botões apareceram.
    public static func lugaresDeResposta(_ passos: [SessionStep]) -> Int {
        passos.filter { if case .approval = $0 { return true }; return false }.count
    }

    // MARK: - Escrever

    /// Manda um pedido. Falha VISÍVEL: um prompt que não chegou não pode parecer que chegou.
    @discardableResult
    public func send(_ text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return false }
        guard let req = endpoint.lanePromptRequest(sid: lane, text: t) else {
            note = "lane inválida: \(lane)"
            return false
        }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// Há um turno correndo? É o que decide se a tela oferece parar/guiar — e a resposta vem do
    /// servidor (a trama), nunca de um palpite do cliente sobre o último passo visto.
    public private(set) var turnoEmCurso = false

    /// Parar o turno, ou guiá-lo. `texto` vazio = interromper.
    @discardableResult
    public func turno(interromper: Bool, texto: String = "") async -> Bool {
        guard let req = endpoint.laneTurnRequest(sid: lane, interromper: interromper, text: texto) else { return false }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                // 409 aqui costuma ser "nenhum turno em curso" — recusa do chamador, com motivo.
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// Responde ao pedido de aprovação pendente.
    @discardableResult
    public func approve(_ allow: Bool) async -> Bool {
        guard let req = endpoint.laneApproveRequest(sid: lane, allow: allow) else { return false }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// O motivo que o SERVIDOR deu. Ele sabe se a lane é de tela, se a fonte caiu ou se o texto
    /// passou do teto; qualquer frase nossa aqui seria menos específica.
    static func motivo(_ data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (o["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Fio

    public struct Page: Decodable, Sendable {
        public let lane: String
        public let since: Int
        public let cursor: Int
        public let events: [TramaEvent]
        public let streaming: String?
        /// O servidor diz se há turno. Enquanto não disser, um parcial em voo é a melhor pista —
        /// mas ela é PISTA, e o campo explícito manda quando existe.
        public let turnoEmCurso: Bool?

        enum CodingKeys: String, CodingKey {
            case lane, since, cursor, events, streaming
            case turnoEmCurso = "turnRunning"
        }
    }
    struct Envelope: Decodable { let ok: Bool; let data: Page }
}
