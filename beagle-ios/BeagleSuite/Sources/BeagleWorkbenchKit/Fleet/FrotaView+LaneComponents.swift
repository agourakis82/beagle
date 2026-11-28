#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

// MARK: - One lane

struct LaneCard: View {
    let lane: LaneSnapshot
    /// A lane on the shelf sits physically higher — elevation is the second encoding of state.
    let raised: Bool
    /// An action for THIS lane is on the wire.
    let busy: Bool
    /// Why the last action did not happen. Shown on the card, never as a global toast: the
    /// refusal is about this lane and belongs where the operator was looking.
    let note: String?
    let onApprove: () -> Void
    let onAnswer: () -> Void
    let onInterrupt: () -> Void
    let onIsolate: () -> Void
    let onOpen: () -> Void

    @State private var breathing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            // A lane que PEDE DECISÃO mostra o que está sendo decidido; as demais mostram a
            // evidência de sempre. A escolha do QUE mostrar é pura e mora em
            // `SessionStore.pedidoDoCard`; aqui só se escolhe como desenhá-la.
            if lane.state == .waiting {
                if !pedido.vazio { decisao }
            } else if !lane.detail.isEmpty {
                evidence
            }
            if !lane.peek.isEmpty && lane.state != .waiting { peekWell }
            // A lane that does not exist in tmux gets no controls at all — there is nothing
            // there to press a key at.
            if !lane.isAbsent { actions }
            if let note { refusal(note) }
        }
        // 12/10, não 14: no retrato de 10-ago três cartões de prateleira comiam 660px de uma
        // janela de 900, e sobrava uma frota espremida embaixo. O cartão é o lugar da decisão,
        // não um pôster.
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Glass is the panel (chrome). Hue enters only as the edge tint, never as a fill.
        .farolGlass(tint: raised ? hue : nil, frosted: lane.state == .stuck)
        .shadow(color: .black.opacity(raised ? 0.45 : 0.18), radius: raised ? 18 : 6, y: raised ? 8 : 2)
        .contentShape(Rectangle())
        // O toque no card inteiro é o atalho para o terminal. Numa lane sem sessão tmux ele
        // levaria direto a uma tela de erro, então o guarda fica aqui e não no destino.
        .onTapGesture { if lane.hasTerminal { onOpen() } }
        .accessibilityElement(children: .combine)
        // 🚨 Achado de review: `.accessibilityElement(children: .combine)` seguido de
        // `.accessibilityLabel(...)` SUBSTITUI o texto combinado dos filhos, não o soma a ele —
        // e o chip de custo (`header`, abaixo) é um desses filhos. Sem o custo aqui, VoiceOver
        // nunca ouve o número que esta fatia inteira existe para tornar visível.
        .accessibilityLabel(
            "\(lane.title), \(lane.presenceLabel), \(lane.confidenceLabel)"
            // A lane, não o `usd` cru: assim a fala herda o MESMO frescor que o chip desenha.
            + "\(SessionStore.custoParaAcessibilidade(lane)). \(lane.detail)"
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            lamp
            Text(lane.title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
            Text(lane.presenceLabel)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            // O custo, ao lado do estado — mesma fonte que o rodapé da Sessão soma (o loomd).
            // Só aparece quando > 0: "US$ 0,00" em todo card é ruído que treina o olho a ignorar
            // a linha, e aí o número que importa também deixa de ser lido.
            // 🚨 O chip HERDA o frescor da lane (dívida saldada). A decisão mora em
            // `SessionStore.chipDeCusto` — puro, assertável sem SwiftUI, junto de `custoDoChip`
            // e `rodapeDoTurno`; aqui só se escolhe como desenhá-la.
            //
            // A marca NÃO é opacidade: `.caption2` a 60% de branco já é discreto, e baixar mais
            // faria do dado velho o texto MENOS legível da linha — ruído mais fraco, não sinal.
            // São duas marcas que se leem: o sufixo "· antigo" (que sobrevive a quem não
            // distingue cor, e que VoiceOver diz) e a cor. A cor é a MESMA laranja de "leitura
            // antiga" em `observationAge`, dois pontos acima nesta mesma linha — um significado,
            // um vocabulário. `BeagleTheme.truthStale` foi considerado e recusado aqui: sobre
            // este vidro escuro ele é mais APAGADO que o branco a 60%, então diria "velho"
            // tornando o número mais difícil de ler, e o gasto aconteceu.
            if let chip = SessionStore.chipDeCusto(lane) {
                Text(chip.texto)
                    .font(.caption2)
                    .foregroundStyle(chip.velho ? Color.orange : Color.white.opacity(0.6))
            }
            Spacer()
            truthBadge
        }
    }

    /// Light + glyph: two of the three state encodings in one mark.
    private var lamp: some View {
        ZStack {
            Circle()
                .fill(hue.opacity(lane.state == .idle ? 0.35 : 0.9))
                .frame(width: 10, height: 10)
                .shadow(color: hue.opacity(lane.state == .waiting ? 0.9 : 0.35), radius: lane.state == .waiting ? 7 : 3)
                .scaleEffect(breathing && lane.state == .running ? 1.25 : 1.0)
                .animation(
                    lane.state == .running
                        ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                        : .default,
                    value: breathing
                )
            Text(lane.state.glyph)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Self.glyphInk)
                .opacity(0.9)
        }
        .onAppear { breathing = true }
    }

    private static let glyphInk = Color(red: 0.043, green: 0.055, blue: 0.086)

    /// Truth mode, per the platform invariant: never show a state without its provenance.
    /// Duas perguntas, um selo só: QUANDO foi visto (o tempo relativo) e COMO foi visto
    /// (o ponto). Vidro é chrome; a cor aqui é significado, e nada pisca — a diferença entre
    /// medido e adivinhado não é um alerta, é uma propriedade do dado.
    private var truthBadge: some View {
        HStack(spacing: 5) {
            provenanceDot
            observationAge
        }
    }

    /// ● medido no protocolo (loomd) · ○ lido da tela (peek + regex).
    /// Glifo E cor, nunca só cor: o mesmo par que `TruthMode` já usa no resto da plataforma.
    private var provenanceDot: some View {
        Text(lane.confidence.glyph)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(
                lane.confidence == .exact
                    ? BeagleTheme.truthObserved
                    : BeagleTheme.truthDeclared
            )
            .accessibilityHidden(true)   // o texto vive no label do card, não duplicado aqui
    }

    private var observationAge: some View {
        Group {
            if lane.observedAt == nil {
                Text("não observado")
                    .foregroundStyle(BeagleTheme.truthDeclared)
            } else if lane.isStale() {
                Text("leitura antiga")
                    .foregroundStyle(.orange)
            } else if let at = lane.observedAt {
                Text(at, style: .relative)
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.8))
            }
        }
        .font(.system(.caption2, weight: .medium).monospacedDigit())
    }

    /// O que este card está pedindo para aprovar — decidido fora daqui, em
    /// `SessionStore.pedidoDoCard` (pura, assertável sem SwiftUI).
    private var pedido: SessionStore.PedidoDoCard { SessionStore.pedidoDoCard(lane) }

    /// 🚨 O card que pede decisão passou a DIZER o que está sendo aprovado.
    ///
    /// Antes ele mostrava `lane.detail` cru — na frota real, "Press enter to confirm or esc to
    /// cancel": cromo do agente, em inglês, numa interface em português, e IDÊNTICO em duas
    /// lanes pedindo coisas opostas. Para decidir, o operador tinha de sair da tela. O dado
    /// existia: atravessava o loomd (`pending_kind`/`last_diff`) e o cockpit
    /// (`approvalKind`/`diff`) e morria no modelo Swift, que não tinha onde guardá-lo.
    ///
    /// O diff é desenhado pelo MESMO `DiffView` da Sessão — não há um segundo renderizador de
    /// patch neste projeto, e não é para haver.
    private var decisao: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let rotulo = pedido.rotulo {
                HStack(spacing: 6) {
                    Text(rotulo)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    // A reversibilidade é dita ANTES do toque, com a mesma frase que a Sessão já
                    // usa: patch se desfaz por git, comando não — e é essa diferença que decide
                    // se ele lê o que está embaixo ou só aprova.
                    if let reversivel = pedido.reversivel {
                        Text(reversivel ? "reversível por git" : "não se desfaz")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .foregroundStyle(reversivel ? Color.white.opacity(0.7) : Color.orange)
                    }
                    Spacer(minLength: 0)
                }
            }
            switch pedido.prova {
            case .diff(let patch):
                // Fundo opaco pela mesma regra do resto da tela: vidro é chrome, e um patch é
                // conteúdo — nunca se lê código através de blur.
                DiffView(patch: patch)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            case .texto:
                // Sem patch (aprovar um COMANDO não gera diff), a evidência do agente é o que se
                // tem — e é o MESMO poço de sempre, não um segundo desenho.
                evidence
            case .nenhuma:
                EmptyView()
            }
        }
    }

    /// A voz da evidência vem da ORIGEM do texto, não do estado da lane — função pura, testável
    /// sem SwiftUI. Ver `SessionStore.registroDaEvidencia`.
    private var registro: SessionStore.RegistroDaEvidencia {
        SessionStore.registroDaEvidencia(loomdKind: lane.loomdKind, confidence: lane.confidence)
    }

    /// The agent's own words — the reason this card is on the shelf.
    ///
    /// Serifada quando é algo DITO ao operador; monoespaçada quando é leitura de máquina. Esta
    /// linha já dizia isso em comentário e fazia outra coisa: a condição era `lane.state ==
    /// .waiting`, então a fala de um agente que estava TRABALHANDO saía vestida de dado — e neste
    /// sistema monoespaçada é reservada a número, medida e identificador.
    ///
    /// 🚨 Dois eixos, de propósito: a ORIGEM governa a FACE (aqui), o ESTADO governa a
    /// PROMINÊNCIA (poço, opacidade, número de linhas — logo abaixo). Misturá-los foi o defeito.
    private var evidence: some View {
        Text(lane.detail)
            .font(.system(.subheadline, design: registro == .fala ? .serif : .monospaced))
            .foregroundStyle(.white.opacity(lane.state == .waiting ? 0.95 : 0.6))
            .lineLimit(lane.state == .waiting ? 4 : 1)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, lane.state == .waiting ? 7 : 0)
            .padding(.horizontal, lane.state == .waiting ? 10 : 0)
            // Content, never chrome: an opaque well so the words are never read through blur.
            .background(
                lane.state == .waiting
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                    : nil
            )
    }

    /// Two opaque lines of the real terminal — a witness, in mono.
    private var peekWell: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lane.peek.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.30)))
    }

    /// The control materializes only for lanes that are actually blocked — and only offers
    /// one-tap approval when one keystroke can honestly satisfy the prompt.
    private var actions: some View {
        HStack(spacing: 10) {
            if lane.state == .waiting {
                if lane.approve.key != nil || lane.pendingApproval {
                    // One named key, sent without attaching. `y` here is the same `y` he would
                    // press at the keyboard — it is not a command.
                    Button(action: onApprove) {
                        Label("Aprovar", systemImage: "return")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hue)
                } else {
                    // No keystroke can honestly satisfy an open question — do not draw one.
                    Button(action: onAnswer) {
                        Label("Responder", systemImage: "text.bubble")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hue)
                }
            }
            if busy {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("enviando")
            }
            Spacer()

            // Os secundários viram ÍCONE, e vão para a direita. No retrato de 10-ago-2026 eles
            // eram cinza-sobre-cinza, ilegíveis, e ainda assim o elemento mais repetido da tela:
            // "Interromper" e "Abrir lane" em todo cartão, disputando espaço com a única coisa
            // que ele precisa achar em um segundo. Rótulo apagado não é discrição — é ruído que
            // não dá para ler. Ícone com `.help` diz o mesmo e ocupa um sexto.
            if lane.state == .waiting || lane.state == .running {
                // Esc confirms nothing; it is the interrupt the CLIs advertise themselves.
                Button(action: onInterrupt) { Image(systemName: "escape") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .help("Interromper (Esc)")
                    .accessibilityLabel("Interromper")
            }
            if lane.isIsolatable {
                Button(action: onIsolate) { Image(systemName: "arrow.branch") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    // Moving a lane is not free, and the card says the price before he pays it.
                    .help("Isolar em /workspace/.wt/\(lane.sid). Reinicia o agente ali — o contexto dele se perde.")
                    .accessibilityLabel("Isolar em worktree")
            }
            // Só quem tem sessão tmux ganha "Abrir lane". Uma lane do loomd é supervisionada por
            // JSON-RPC e não tem pty do outro lado — o botão ali só podia falhar. No lugar dele
            // fica a razão, porque um botão que some sem explicação vira suspeita de bug.
            if lane.hasTerminal {
                Button(action: onOpen) { Image(systemName: "macwindow") }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .help("Abrir o terminal de \(lane.sid)")
                    .accessibilityLabel("Abrir lane")
            } else {
                Text(lane.noTerminalReason)
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
        }
        .disabled(busy)
        .padding(.top, 2)
    }

    /// The refusal, in the server's own words. It is more specific than anything the client
    /// could infer, and a button that fails silently is worse than no button.
    private func refusal(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color(red: 1.00, green: 0.64, blue: 0.30))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.32)))
    }

    /// Hue = identity. Um lugar só decide isto agora: `BeagleTheme.familyColor` — ver o
    /// comentário lá para o porquê de ter saído daqui.
    private var hue: Color { BeagleTheme.familyColor(lane.family) }
}


/// UMA LINHA para quem TRABALHA. O contrário do cartão: aqui não há decisão a tomar, há estado
/// a varrer — e varrer é olhar de canto, não ler.
///
/// Ordem da esquerda para a direita segue a pergunta que ele faz ao olhar: *quem* (lâmpada+nome),
/// *fazendo o quê* (a última linha do agente, cortada em fronteira de palavra).
///
/// 🚨 O que SUMIU daqui, e por quê:
/// • a palavra `trabalhando`, repetida em toda linha — nesta fileira ela é sempre a mesma, e o
///   que é sempre igual não distingue nada. Volta sozinha quando o estado é anomalia
///   (`ausente`, `encerrado`), aí sim como notícia;
/// • a idade FRESCA — nove "9 seg" alinhados dizem "está tudo bem" gastando nove sacadas de olho;
/// • o prévio cortado no meio da palavra — agora é `SessionStore.previaCurta`, que prefere não
///   mostrar nada a mostrar um fragmento.
///
/// Nada disso é decidido aqui: `SessionStore.linhaPeriferica` decide, esta view desenha.
struct LaneRow: View {
    let lane: LaneSnapshot
    let busy: Bool
    let onOpen: () -> Void
    @State private var hover = false

    private var linha: SessionStore.LinhaPeriferica { SessionStore.linhaPeriferica(lane) }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(hue).frame(width: 7, height: 7)

            Text(lane.sid)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(minWidth: 74, alignment: .leading)

            if let presenca = linha.presenca {
                Text(presenca)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            // O que o agente está de fato fazendo. É A informação da linha, então ganha o espaço
            // que sobra — e não pode ser menor nem mais fraca que o nome, que ele já sabe de cor.
            if let previa = linha.previa {
                Text(previa)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if busy { ProgressView().controlSize(.mini) }

            // A idade só CHEGA aqui quando envelheceu — então é notícia, e se desenha como
            // notícia: mais clara que a prévia, não mais apagada. E sem largura fixa: não há
            // mais uma coluna de números a alinhar, porque na maioria dos dias não há números.
            if let at = linha.idade {
                Text(at, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(hover ? 0.08 : 0.045))
        )
        .overlay(
            // A identidade entra por uma barra na borda, nunca por preenchimento: 12 linhas
            // tingidas viram um arco-íris e param de significar qualquer coisa.
            RoundedRectangle(cornerRadius: 8)
                .fill(hue.opacity(0.5))
                .frame(width: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        .contentShape(Rectangle())
        .onTapGesture { if lane.hasTerminal { onOpen() } }
        .onHover { hover = $0 }
        .help(lane.hasTerminal ? "Abrir o terminal de \(lane.sid)" : lane.noTerminalReason)
        .accessibilityElement(children: .combine)
        // Mesmo defeito e mesmo conserto do `LaneCard` acima: o `.combine` some sob o
        // `.accessibilityLabel` explícito, e sem o custo aqui VoiceOver nunca ouve o número
        // nesta linha densa — mesmo que a linha não o desenhe visualmente, é a única forma de
        // um leitor de tela saber o custo desta lane sem abrir o card.
        //
        // 🚨 O rótulo diz a presença SEMPRE, mesmo quando o desenho a omite: quem ouve a tela
        // não tem visão periférica, e a economia que faz sentido para o olho de canto seria
        // apagamento puro para VoiceOver.
        .accessibilityLabel(
            "\(lane.sid), \(lane.presenceLabel), \(lane.confidenceLabel)"
            + SessionStore.custoParaAcessibilidade(lane)
        )
    }

    private var hue: Color { BeagleTheme.familyColor(lane.family) }
}

/// UMA FICHA para quem está em REPOUSO. O terceiro nível de peso da Frota, depois do cartão
/// (decisão) e da linha (trabalho).
///
/// 🚨 Aqui a subtração é quase total: ficam a lâmpada e o nome, e mais nada — sem fundo, sem
/// barra de identidade, sem prévia, sem idade fresca. O que uma lane parada "estava dizendo" é
/// a coisa menos acionável da tela, e seis dessas frases lado a lado eram a maior mancha de
/// texto de uma faixa cujo trabalho é NÃO chamar atenção. O que sobra é posição e cor, que é o
/// que a visão periférica de fato registra.
///
/// Um estado anômalo (`ausente`, `encerrado`) e uma leitura vencida ainda falam — e falam mais
/// alto justamente porque ao redor delas ninguém está falando.
struct LaneChip: View {
    let lane: LaneSnapshot
    let onOpen: () -> Void
    @State private var hover = false

    private var linha: SessionStore.LinhaPeriferica { SessionStore.linhaPeriferica(lane) }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(BeagleTheme.familyColor(lane.family).opacity(0.5))
                .frame(width: 5, height: 5)

            Text(lane.sid)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(hover ? 0.85 : 0.5))
                .lineLimit(1)

            if let presenca = linha.presenca {
                Text(presenca)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            // `fixedSize`: uma idade cortada ("5 min e 11…") é pior que nenhuma — vira um
            // número que não se pode ler. Quem cede espaço é o nome, que ele sabe de cor.
            if let at = linha.idade {
                Text(at, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture { if lane.hasTerminal { onOpen() } }
        .onHover { hover = $0 }
        .help(lane.hasTerminal ? "Abrir o terminal de \(lane.sid)" : lane.noTerminalReason)
        .accessibilityElement(children: .combine)
        // Mesma razão do `LaneRow`: o desenho pode calar, o rótulo não.
        .accessibilityLabel(
            "\(lane.sid), \(lane.presenceLabel), \(lane.confidenceLabel)"
            + SessionStore.custoParaAcessibilidade(lane)
        )
    }
}


// MARK: - The glass stratum

/// Achata o vidro para um painel OPACO.
///
/// Existe por um motivo medido, não por gosto: `glassEffect` é Metal, e `ImageRenderer` não
/// rasteriza Metal — a Frota inteira saía como um retângulo vazio, o que é exatamente o estado
/// em que essa tela vinha sendo projetada. Com isto ela pode ser VISTA fora de uma janela viva.
///
/// O modo opaco não é só andaime de teste: é o degrade honesto para quando o vidro não estiver
/// disponível, e a única variante em que dá para julgar contraste de texto sem o borrão por baixo.
struct FarolFlatGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var farolFlatGlass: Bool {
        get { self[FarolFlatGlassKey.self] }
        set { self[FarolFlatGlassKey.self] = newValue }
    }
}

private struct FarolGlassModifier: ViewModifier {
    let tint: Color?
    let frosted: Bool
    @Environment(\.farolFlatGlass) private var flat

    private var edge: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08),
                          lineWidth: tint == nil ? 0.5 : 1.2)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if flat {
            content
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.13).opacity(0.92)))
                .overlay(edge)
        } else {
            content.modifier(FarolRealGlass(tint: tint, frosted: frosted))
        }
    }
}

private struct FarolRealGlass: ViewModifier {
    let tint: Color?
    let frosted: Bool
    @ViewBuilder
    func body(content: Content) -> some View { content.farolGlassReal(tint: tint, frosted: frosted) }
}

extension View {
    /// A floating glass panel. `tint` is the identity edge-light (never a fill); `frosted`
    /// clouds the pane for a stuck lane — the third encoding of that state.
    /// Falls back to a material on pre-26 systems so the screen degrades instead of breaking.
    func farolGlass(tint: Color?, frosted: Bool) -> some View {
        modifier(FarolGlassModifier(tint: tint, frosted: frosted))
    }

    @ViewBuilder
    func farolGlassReal(tint: Color?, frosted: Bool) -> some View {
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            self.glassEffect(
                frosted ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
            )
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tint?.opacity(0.55) ?? Color.white.opacity(0.08), lineWidth: tint == nil ? 0.5 : 1.2)
                )
        }
    }
}
#endif
