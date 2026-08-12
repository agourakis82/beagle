#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

// SESSÃO — dirigir uma lane sem terminal.
//
// A tela responde "o que está acontecendo aqui, e o que você precisa decidir". Não é chat: os
// elementos de primeira classe são TURNO, FERRAMENTA, DIFF e PEDIDO. Uma bolha de conversa
// humana teria que engolir diff e aprovação como anexo, que é a forma exata do "nem uma coisa
// nem outra" que motivou esta rodada.
//
// Três regras de composição:
//   1. **Uma trilha à esquerda.** Tudo pendura no mesmo eixo vertical, com um marcador por tipo.
//      O olho desce a trilha em vez de saltar entre caixas — é como se lê um log e como se lê uma
//      conversa, e aqui é as duas coisas.
//   2. **Texto do agente em largura de leitura.** Prosa a 1180px de largura não se lê; o bloco de
//      fala tem teto. Diff e comando NÃO têm — eles são dado, e cortar dado é pior que rolar.
//   3. **A decisão tem o peso.** O pedido de aprovação é a única coisa com painel, borda e cor.
//      Se tudo tem destaque, nada tem.
public struct SessionView: View {
    @State private var store: SessionStore
    @State private var rascunho: String = ""
    /// O próximo envio GUIA o turno em vez de abrir um novo pedido.
    @State private var guiando = false
    @FocusState private var escrevendo: Bool

    /// Trocar de lane recria o store — cursor, turnos e parcial são de UMA sessão, e reaproveitar
    /// o objeto misturaria a conversa de duas. Quem navega é o dono da cena.
    private let onTrocarLane: ((String) -> Void)?

    /// As lanes de protocolo, injetadas. A Sessão NÃO descobre roster — ela mostra uma sessão. Quem
    /// sabe quais lanes existem é o servidor (via `FleetStateClient.loomdRoster`), e quem navega é
    /// a cena. Deixar a view consultar uma constante global foi o que criou a duplicação que este
    /// commit paga.
    private let roster: [String]

    /// O que ESTA lane aceita, segundo o servidor. `nil` = não declarado (lane fora do último
    /// quadro, ou fonte ainda não respondeu) — e `nil` é o que faz `rotuloDeGuiar`/`dicaDaCaixa`
    /// não oferecer gesto nenhum. A Sessão não descobre isto sozinha: quem sabe é o
    /// `FleetStateClient`, e quem alimenta é a cena — mesmo padrão do `roster` acima.
    private let aceita: Aceita?

    /// O link do `FleetStateClient` — a MESMA fonte que alimenta `aceita`, acima. Existe só para
    /// distinguir, quando `aceita` é `nil`, "o link está de pé e o quadro desta lane ainda não
    /// chegou" (transitório) de "o link caiu e é por isso que nada chega" (a caixa de texto
    /// precisa dizer que a FONTE está muda, não que a lane virou incerta). Sem isto a Sessão não
    /// tinha referência NENHUMA ao estado do transporte — um socket caído congelava `aceita` em
    /// `nil` para sempre e a tela continuava dizendo "aguardando o servidor declarar…" como se
    /// fosse questão de segundos. Ver `SessionStore.razaoSemCapacidadeDeclarada`, que é onde a
    /// distinção vira texto — pura, testável sem esta view.
    private let linkDaFrota: FleetStateClient.Link?

    public init(store: SessionStore, roster: [String] = FleetEndpoint.loomdLanes,
                aceita: Aceita? = nil, linkDaFrota: FleetStateClient.Link? = nil,
                onTrocarLane: ((String) -> Void)? = nil) {
        _store = State(initialValue: store)
        self.roster = roster
        self.aceita = aceita
        self.linkDaFrota = linkDaFrota
        self.onTrocarLane = onTrocarLane
    }

    public init(lane: String, roster: [String] = FleetEndpoint.loomdLanes,
                aceita: Aceita? = nil, linkDaFrota: FleetStateClient.Link? = nil,
                onTrocarLane: ((String) -> Void)? = nil) {
        _store = State(initialValue: SessionStore(lane: lane))
        self.roster = roster
        self.aceita = aceita
        self.linkDaFrota = linkDaFrota
        self.onTrocarLane = onTrocarLane
    }

    public var body: some View {
        VStack(spacing: 0) {
            cabecalho
            Divider().overlay(BeagleTheme.hairline)
            trilha
            if let n = store.note { recusa(n) }
            compositor
        }
        .background(BeagleTheme.surface0)
        // O Mission Control é escuro por decisão, e `BeagleTheme` resolve por aparência: sem
        // carimbar o esquema aqui, um Mac em modo claro renderizava texto claro sobre fundo
        // claro. Apareceu no primeiro retrato — e não teria aparecido em nenhum teste de lógica.
        .environment(\.colorScheme, .dark)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
    }

    // MARK: - Cabeçalho

    /// Interno (não privado) pelo mesmo motivo que `conteudo`: o retrato o renderiza sozinho.
    /// É o único lugar onde a lane exibida vira pixel, e portanto o único ponto onde dá para
    /// PROVAR em imagem que a Sessão está de fato na lane escolhida.
    var cabecalho: some View {
        HStack(spacing: BeagleSpacing.sm) {
            // Com mais de uma lane de protocolo o nome fixo deixa de ser cabeçalho e passa a ser
            // uma mentira sobre onde você está. Com uma só, o seletor não aparece — um menu de um
            // item é ruído que ainda pede um clique para não fazer nada.
            if roster.count > 1 {
                Menu {
                    ForEach(roster, id: \.self) { l in
                        Button(l) { onTrocarLane?(l) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.lane).font(.system(.headline, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(BeagleTheme.textPrimary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Text(store.lane)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            Text("sessão de protocolo")
                .font(.caption2)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            // A procedência fica visível o tempo todo, como no resto da plataforma: esta tela SÓ
            // existe para lane medida. Um dia haverá lane de tela ao lado, e a diferença precisa
            // estar dita antes de alguém perguntar.
            Label("medido no protocolo", systemImage: "circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(BeagleTheme.truthObserved)
                .imageScale(.small)
            if store.turnoEmCurso { controlesDoTurno }
            estadoDoFio
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
    }

    @ViewBuilder
    private var estadoDoFio: some View {
        switch store.link {
        case .live:
            if let at = store.lastPollAt {
                Text(at, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        case .idle:
            Text("parada").font(.caption2).foregroundStyle(BeagleTheme.textTertiary)
        case .failed(let porque):
            // O motivo do servidor, verbatim. Ele sabe se a fonte caiu ou se a lane é de tela.
            Label(porque, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(BeagleTheme.stateError)
                .lineLimit(1)
        }
    }

    /// Só aparecem com turno correndo — um botão de parar numa lane parada é um botão que
    /// falha, e o servidor recusaria com 409.
    ///
    /// GUIAR vem primeiro, e não por ordem de leitura: interromper joga fora o que o agente já
    /// fez, guiar aproveita. Quando as duas servem, a barata tem que ser a mais fácil de achar.
    private var controlesDoTurno: some View {
        HStack(spacing: 6) {
            // `nil` = a lane não redireciona nem enfileira (somente leitura, ou capacidade não
            // declarada) — e aí não há gesto de guiar para oferecer, botão nenhum.
            if let rotulo = SessionStore.rotuloDeGuiar(aceita) {
                Button {
                    guiando = true
                    escrevendo = true
                } label: {
                    Label(rotulo, systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.accent)
                .help("Acrescenta instrução ao turno em curso, sem descartar o que ele já fez")
            }

            Button {
                Task { await store.turno(interromper: true) }
            } label: {
                Label("Parar", systemImage: "stop.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BeagleTheme.stateError)
            .help("Encerra o turno. O trabalho já feito é descartado.")
        }
        .disabled(store.sending)
    }

    // MARK: - A trilha

    private var trilha: some View {
        ScrollViewReader { leitor in
            ScrollView {
                conteudo
                    .padding(.horizontal, BeagleSpacing.md)
                    .padding(.vertical, BeagleSpacing.md)
            }
            .onChange(of: store.steps.count) { _, _ in
                withAnimation(BeagleMotion.fast) { leitor.scrollTo("fim", anchor: .bottom) }
            }
        }
    }

    /// Separado do `ScrollView` pelo mesmo motivo da Frota: `ImageRenderer` propõe altura
    /// infinita ao filho de um scroll e devolve branco. Assim a tela é retratável sozinha.
    var conteudo: some View {
        LazyVStack(alignment: .leading, spacing: BeagleSpacing.md) {
            if store.steps.isEmpty && store.streaming == nil { vazio }
            // 🚨 A numeração conta PEDIDOS, não blocos. Com `i + 1`, uma sessão retomada fazia o
            // primeiro turno com pedido sair como "turno 2" — o bloco "antes", que não tem pedido,
            // consumia o número 1. Apareceu no retrato, e é o tipo de erro que faz alguém procurar
            // um turno 1 que nunca existiu.
            ForEach(Array(store.turnos.enumerated()), id: \.element.id) { i, turno in
                TurnoView(turno: turno,
                          numero: store.turnos.prefix(i + 1).filter { $0.pedido != nil }.count,
                          emCurso: i == store.turnos.count - 1 && store.turnoEmCurso,
                          enviando: store.sending,
                          onAprovar: { allow in Task { await store.approve(allow) } })
            }
            if let parcial = store.streaming { escrevendoAgora(parcial) }
            Color.clear.frame(height: 1).id("fim")
        }
    }

    /// Vazio explica e oferece a próxima ação — nunca uma tela em branco.
    private var vazio: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text("Nenhum turno ainda nesta sessão.")
                .font(.callout).foregroundStyle(BeagleTheme.textSecondary)
            Text("Mande um pedido abaixo — ele vai pelo protocolo, não por digitação num terminal.")
                .font(.footnote).foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.vertical, BeagleSpacing.lg)
    }

    /// A mensagem chegando. O cursor pisca para separar "está escrevendo" de "acabou e ficou
    /// curto" — dois estados que, parados, são idênticos na tela.
    private func escrevendoAgora(_ texto: String) -> some View {
        Trilho(marcador: "●", cor: BeagleTheme.accent) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(texto)
                    .font(.system(.body))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                Cursor()
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private func recusa(_ texto: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BeagleTheme.stateError)
            Text(texto)
                .font(.footnote)
                .foregroundStyle(BeagleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(BeagleSpacing.sm)
        .background(BeagleTheme.surface2)
        .padding(.horizontal, BeagleSpacing.md)
    }

    // MARK: - Compositor

    @ViewBuilder
    private var compositor: some View {
        // `nil` = a caixa não existe. Não desabilitada: AUSENTE — controle morto sem explicação é
        // o defeito que esta casa já pagou para aprender. `claude-1/2/3` são tail: o loomd só LÊ,
        // e `POST /prompt` devolve 404. A linha abaixo diz onde falar com a lane, em vez disso.
        if let dica = SessionStore.dicaDaCaixa(aceita) {
            HStack(alignment: .bottom, spacing: BeagleSpacing.sm) {
                TextField(guiando ? dica : "pedir a \(store.lane)…", text: $rascunho, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(.body))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .focused($escrevendo)
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface2)
                    )
                    .onSubmit(enviar)

                Button(action: enviar) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(podeEnviar ? BeagleTheme.surface0 : BeagleTheme.textTertiary)
                .background(
                    Circle().fill(podeEnviar ? BeagleTheme.accent : BeagleTheme.surface2)
                )
                .disabled(!podeEnviar)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Enviar (⌘↩)")
            }
            .padding(BeagleSpacing.md)
            .background(BeagleTheme.surface1)
        } else {
            semCaixaView
                .padding(BeagleSpacing.md)
                .background(BeagleTheme.surface1)
        }
    }

    /// Escolhe entre as duas razões de não haver caixa. `SessionStore.semCaixa` já fez a
    /// distinção; aqui só se escolhe a subview — nenhuma lógica nova.
    @ViewBuilder
    private var semCaixaView: some View {
        switch SessionStore.semCaixa(aceita) {
        case .somenteObservada: apenasObservada
        case .capacidadeDesconhecida: capacidadeDesconhecidaView
        case nil:
            // Não deveria ocorrer: só se chega aqui quando `dicaDaCaixa(aceita)` já é `nil`, e
            // `semCaixa`/`dicaDaCaixa` cobrem os mesmos quatro casos de `Aceita?` em espelho.
            EmptyView()
        }
    }

    /// A ponte entre `semCaixa == .capacidadeDesconhecida` e as DUAS razões possíveis: link vivo
    /// (transitório, o texto de sempre) ou link caído (a fonte está muda — dizer para outra
    /// coisa). A decisão em si é `SessionStore.razaoSemCapacidadeDeclarada`, pura; aqui só se
    /// escolhe a subview, igual `semCaixaView` faz para os quatro casos de `Aceita?`.
    @ViewBuilder
    private var capacidadeDesconhecidaView: some View {
        switch SessionStore.razaoSemCapacidadeDeclarada(link: linkDaFrota) {
        case .transitorio: capacidadeDesconhecida
        case .linkCaido(let motivo): linkCaido(motivo)
        }
    }

    /// O link caiu: a caixa não existe porque a FONTE emudeceu, não porque a lane é incerta ou
    /// virou somente-leitura. Mesmo ícone de alerta que `estadoDoFio` usa para `store.link
    /// .failed`, e o MESMO texto que `FleetStateClient.explicacaoDoLink` já dá à Frota — nenhuma
    /// string nova, para as duas telas nunca poderem divergir sobre o mesmo fato.
    private func linkCaido(_ motivo: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(motivo)
        }
        .font(.system(size: 12))
        .foregroundStyle(BeagleTheme.stateError)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// Controle morto sem explicação é o defeito que esta casa já pagou para aprender. A lane está
    /// viva e o loomd a lê; o caminho para dirigi-la existe, só não é aqui.
    ///
    /// Só para `.somenteLeitura` — o servidor DECLAROU que é tail. Ver `capacidadeDesconhecida`
    /// para o caso em que ninguém disse nada ainda.
    private var apenasObservada: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
            Text("observada pelo transcript — fale com ela pelo terminal")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// 🚨 `nil` não é `.somenteLeitura`. Não sei ≠ é de leitura. Afirmar "observada pelo
    /// transcript" sobre uma lane de codex que só não teve o quadro entregue ainda é a mesma
    /// mentira que esta fatia existe para matar, invertida: negar um gesto que existe. Este texto
    /// não afirma NADA sobre a natureza da lane — só que o servidor ainda não falou, e que isso é
    /// transitório.
    private var capacidadeDesconhecida: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
            Text("aguardando o servidor declarar o que esta lane aceita…")
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var podeEnviar: Bool {
        !store.sending && !rascunho.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func enviar() {
        guard podeEnviar else { return }
        let t = rascunho
        rascunho = ""
        let guiar = guiando
        guiando = false
        Task {
            // Se o servidor recusar, `note` acende e o texto volta para o campo: um pedido que
            // não chegou não pode sumir da tela junto com o que ele dizia.
            let ok = guiar
                ? await store.turno(interromper: false, texto: t)
                : await store.send(t)
            if !ok { rascunho = t; guiando = guiar }
        }
    }
}

// MARK: - Um turno

/// O turno como UNIDADE. Um cabeçalho fino marca a fronteira e conta o que aconteteu dentro —
/// quantas ferramentas, se houve diff, quanto durou.
///
/// Não é um cartão: cartão dentro de cartão empilha borda sobre borda e a tela vira grade. É uma
/// régua horizontal com um número, que é o mínimo para o olho achar onde um pedido começa.
private struct TurnoView: View {
    let turno: Turno
    let numero: Int
    let emCurso: Bool
    let enviando: Bool
    let onAprovar: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            cabecalho
            ForEach(turno.passos.filter(\.desenhavel)) { passo in
                PassoView(passo: passo, enviando: enviando, onAprovar: onAprovar)
            }
            rodape
        }
    }

    private var cabecalho: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Text(turno.pedido == nil ? "antes" : "turno \(numero)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(BeagleTheme.textTertiary)
            // Um turno sem pedido é sessão RETOMADA: o pedido está fora da janela do diário.
            // Fingir que aquele trabalho pertence ao próximo pedido seria atribuí-lo ao pedido
            // errado — e é o tipo de erro que faz alguém aprovar a coisa errada.
            if turno.pedido == nil {
                Text("sessão retomada — o pedido está fora do diário")
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            resumo
            Rectangle().fill(BeagleTheme.hairline).frame(height: 1)
            if emCurso {
                Text("em curso")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BeagleTheme.accent)
            }
        }
        .padding(.top, BeagleSpacing.xs)
    }

    /// Duração · contexto · custo. O custo vem de `Turno.uso` — a MESMA fonte que o chip da
    /// Frota soma (Task 6). Dois cálculos independentes divergem, e aí o operador não sabe em
    /// qual acreditar — por isso a formatação mora em `SessionStore.rodapeDoTurno`, não aqui.
    @ViewBuilder
    private var rodape: some View {
        if let texto = SessionStore.rodapeDoTurno(duracao: turno.duracao(concluido: !emCurso),
                                                    uso: turno.uso) {
            Text(texto)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 2)
        }
    }

    /// O que aconteceu dentro, em uma linha. Serve para decidir se vale abrir o turno com o olho.
    @ViewBuilder
    private var resumo: some View {
        let ferramentas = turno.passos.filter { if case .tool = $0 { return true }; return false }.count
        HStack(spacing: 5) {
            if ferramentas > 0 {
                Label("\(ferramentas)", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            if turno.temDiff {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            if turno.pedePermissao {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.accent)
            }
        }
    }

}

// MARK: - Um passo na trilha

private struct PassoView: View {
    let passo: SessionStep
    let enviando: Bool
    let onAprovar: (Bool) -> Void

    var body: some View {
        switch passo {
        case .prompt(_, let texto, _):
            Trilho(marcador: "▸", cor: BeagleTheme.textSecondary) {
                Text(texto)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
            }

        case .message(_, let texto, _):
            Trilho(marcador: "●", cor: BeagleTheme.accent) {
                Text(texto)
                    .font(.system(.body))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
            }

        case .tool(_, let nome, let detalhe, _):
            // Ferramenta é rastro para varrer, não texto para ler — e são muitas. Recolhida por
            // padrão (mesmo padrão de `DisclosureGroup` do agrupamento "anunciadas e nunca
            // observadas" na Frota); o cabeçalho já basta para varrer, o detalhe completo só
            // aparece a quem abre.
            Trilho(marcador: "⚙", cor: BeagleTheme.textTertiary) {
                FerramentaView(nome: nome, detalhe: detalhe)
            }

        case .diff(_, let patch, _):
            // 🚨 SÓ mostra o patch. Nunca um botão — se um diff avulso (codex) E um pedido de
            // aprovação (`.approval`) coexistem no mesmo turno, um segundo par de Aplicar/Recusar
            // aqui duplicaria a afordância do card abaixo para o MESMO pedido (achado de review).
            // `SessionStore.lugaresDeResposta` é o invariante que prende essa regra: um turno com
            // pedido pendente tem de ter EXATAMENTE UM lugar que responde — o card.
            Trilho(marcador: "◆", cor: BeagleTheme.truthObserved) { DiffView(patch: patch) }

        case .approval(_, let kind, let detalhe, let diff, _):
            // O card é o ÚNICO lugar que responde. Quando o evento trouxe diff — sempre o caso
            // na lane ACP, que não emite `diff_proposed` — ele aparece AQUI, reusando o mesmo
            // `DiffView` que o passo `.diff` usa. Não um segundo renderizador de patch.
            Trilho(marcador: "◉", cor: BeagleTheme.accent) {
                PedidoView(kind: kind, detalhe: detalhe, diff: diff,
                           enviando: enviando, onAprovar: onAprovar)
            }

        case .failure(_, let texto, _):
            Trilho(marcador: "▲", cor: BeagleTheme.stateError) {
                Text(texto)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(BeagleTheme.stateError)
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
            }

        case .uso:
            // Custo não é fala: não é passo desenhado na linha da conversa, vira rodapé do turno.
            EmptyView()
        }
    }
}

/// A ferramenta, recolhida por padrão. O cabeçalho (nome + resumo em uma linha) já basta para
/// varrer a trilha; o detalhe completo — que pode ser longo, e truncado a uma linha perde
/// informação — só aparece a quem abre.
private struct FerramentaView: View {
    let nome: String
    let detalhe: String

    var body: some View {
        DisclosureGroup {
            Text(detalhe)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(BeagleTheme.textTertiary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Text(nome)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textSecondary)
                Text(detalhe)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .tint(BeagleTheme.textTertiary)
    }
}

/// O eixo comum: marcador estreito à esquerda, conteúdo à direita. É o que faz a trilha ler como
/// uma coisa só em vez de uma pilha de caixas.
private struct Trilho<Conteudo: View>: View {
    let marcador: String
    let cor: Color
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Text(marcador)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(cor)
                .frame(width: 14, alignment: .center)
                .padding(.top, 2)
                .accessibilityHidden(true)
            conteudo
            Spacer(minLength: 0)
        }
    }
}

/// O diff, colorido por linha. Sem biblioteca: unified diff é linha a linha, e um parser de 20
/// linhas que se entende inteiro vale mais que uma dependência para isto.
///
/// 🚨 `internal`, não `private`: é o ÚNICO renderizador de patch do projeto, e a `FrotaView`
/// passou a precisar dele para o card de aprovação (que antes mostrava o cromo cru do agente).
/// Um segundo desenho de patch na Frota seria a duplicação que a review anterior já matou aqui
/// ao tirar deste tipo todos os parâmetros de aprovação.
struct DiffView: View {
    let patch: String
    /// 🚨 SÓ o patch — nunca um botão. `PedidoView` é o único lugar que responde a um pedido de
    /// aprovação (ver `SessionStore.lugaresDeResposta`); um `DiffView` que também desenhasse
    /// Aplicar/Recusar duplicaria a afordância quando um `.diff` avulso e um `.approval`
    /// coexistem no mesmo turno — foi exatamente esse achado de review que tirou os parâmetros
    /// que este tipo já teve. `PedidoView` reusa este MESMO `DiffView` (sem botão) quando o
    /// pedido de aprovação traz o diff embutido (a lane ACP nunca emite `.diff` avulso).
    /// Acima disto o diff nasce fechado.
    ///
    /// 🚨 O motivo é de leitura, não de performance: um diff de 200 linhas empurra o pedido de
    /// aprovação para fora da vista, e é justamente o pedido que exige decisão. Fechado, ele
    /// mostra o cabeçalho (arquivo, +N −M) — que é o que decide se vale abrir.
    private static let tetoAberto = 24
    @State private var aberto: Bool?

    private var mostrando: Bool { aberto ?? (corpo.count <= Self.tetoAberto) }

    private var arquivos: [String] {
        patch.split(separator: "\n")
            .filter { $0.hasPrefix("+++ b/") }
            .map { String($0.dropFirst(6)) }
    }
    private var mais: Int { linhas.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
    private var menos: Int { linhas.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }
    private var linhas: [String] { patch.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: BeagleSpacing.xs) {
                Text(arquivos.first ?? "mudança proposta")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1).truncationMode(.head)
                if arquivos.count > 1 {
                    Text("+\(arquivos.count - 1)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text("+\(mais)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Self.verde)
                Text("−\(menos)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Self.vermelho)
                if corpo.count > Self.tetoAberto {
                    Button { aberto = !mostrando } label: {
                        Text(mostrando ? "esconder" : "ver \(corpo.count) linhas")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BeagleTheme.accent)
                }
            }

            // 🚨 Sem `ScrollView` horizontal aqui, e a razão foi medida no primeiro retrato:
            // um scroll horizontal dentro do `ImageRenderer` colapsa e o corpo do diff saía como
            // um retângulo VAZIO. Um bloco de código que só aparece quando alguém está com o app
            // aberto é um bloco que nunca vai ser revisado antes de existir.
            //
            // Linha longa QUEBRA em vez de rolar. Cortar dado é pior que rolar, mas quebrar não
            // esconde nada — e é o que GitHub e o próprio Xcode fazem em soft wrap.
            if mostrando {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(corpo.enumerated()), id: \.offset) { _, l in
                    Text(l.isEmpty ? " " : l)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Self.tinta(l))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Self.fundo(l))
                }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: BeagleRadius.sm).fill(BeagleTheme.surface2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// O cabeçalho `diff --git` / `index` / `---` / `+++` não é conteúdo: o nome do arquivo já
    /// está no topo, e repetir quatro linhas de metadado empurra o código para fora da vista.
    private var corpo: [String] {
        linhas.filter {
            !$0.hasPrefix("diff --git") && !$0.hasPrefix("index ")
                && !$0.hasPrefix("--- ") && !$0.hasPrefix("+++ ")
                && !$0.hasPrefix("new file mode") && !$0.hasPrefix("deleted file mode")
        }
    }

    private static let verde = Color(red: 0.45, green: 0.82, blue: 0.53)
    private static let vermelho = Color(red: 0.95, green: 0.48, blue: 0.48)

    private static func tinta(_ l: String) -> Color {
        if l.hasPrefix("+") { return verde }
        if l.hasPrefix("-") { return vermelho }
        if l.hasPrefix("@@") { return BeagleTheme.textTertiary }
        return BeagleTheme.textSecondary
    }
    private static func fundo(_ l: String) -> Color {
        if l.hasPrefix("+") { return verde.opacity(0.10) }
        if l.hasPrefix("-") { return vermelho.opacity(0.10) }
        return .clear
    }
}

/// O pedido. É a única coisa da tela com painel e borda, porque é a única que pede decisão.
private struct PedidoView: View {
    let kind: SessionStep.ApprovalKind
    let detalhe: String
    /// 🚨 A lane ACP embute o patch NO PRÓPRIO pedido — ela não emite `.diff` avulso (medido em
    /// `loomd/src/event.rs:486-500`). Sem isto, o operador aprova uma mudança que nunca viu.
    let diff: String?
    let enviando: Bool
    let onAprovar: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Text("O agente quer \(kind.label)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                // A reversibilidade é dita ANTES do toque. Patch se desfaz por git; comando não,
                // e essa é a diferença que decide se ele lê o detalhe ou só aprova.
                Text(kind.reversible ? "reversível por git" : "não se desfaz")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(BeagleTheme.surface3))
                    .foregroundStyle(kind.reversible ? BeagleTheme.textSecondary : BeagleTheme.stateError)
            }
            if !detalhe.isEmpty {
                Text(detalhe)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(BeagleSpacing.xs)
                    .background(RoundedRectangle(cornerRadius: BeagleRadius.sm).fill(BeagleTheme.surface2))
            }
            // O MESMO DiffView do passo `.diff` avulso — sem botão, e sem um segundo
            // renderizador de patch. O card, aqui embaixo, é quem responde.
            if let diff, !diff.isEmpty { DiffView(patch: diff) }
            HStack(spacing: BeagleSpacing.sm) {
                Button { onAprovar(true) } label: {
                    Text(kind.reversible ? "Aplicar" : "Rodar")
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.surface0)
                .background(Capsule().fill(BeagleTheme.accent))
                .keyboardShortcut(.return, modifiers: .command)

                Button { onAprovar(false) } label: {
                    Text("Recusar")
                        .font(.system(.subheadline))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textSecondary)
                .background(Capsule().stroke(BeagleTheme.hairline))

                if enviando { ProgressView().controlSize(.small) }
            }
            .disabled(enviando)
        }
        .padding(BeagleSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface1))
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .strokeBorder(BeagleTheme.accent.opacity(0.55), lineWidth: 1.2)
        )
    }
}

/// Cursor de digitação. Respeita `reduce motion`: quem pediu menos animação recebe um bloco
/// parado, que ainda diz "não acabou".
private struct Cursor: View {
    @State private var aceso = true
    @Environment(\.accessibilityReduceMotion) private var reduzir

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(BeagleTheme.accent)
            .frame(width: 7, height: 15)
            .opacity(reduzir ? 0.8 : (aceso ? 0.9 : 0.15))
            .onAppear {
                guard !reduzir else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    aceso = false
                }
            }
            .accessibilityLabel("escrevendo")
    }
}
#endif
