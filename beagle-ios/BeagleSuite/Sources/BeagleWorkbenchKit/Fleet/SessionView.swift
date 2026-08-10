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

    public init(store: SessionStore) {
        _store = State(initialValue: store)
    }

    public init(lane: String) {
        _store = State(initialValue: SessionStore(lane: lane))
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

    private var cabecalho: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Text(store.lane)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(BeagleTheme.textPrimary)
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
            Button {
                guiando = true
                escrevendo = true
            } label: {
                Label("Guiar", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BeagleTheme.accent)
            .help("Acrescenta instrução ao turno em curso, sem descartar o que ele já fez")

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
            ForEach(store.steps) { passo in
                PassoView(passo: passo,
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

    private var compositor: some View {
        HStack(alignment: .bottom, spacing: BeagleSpacing.sm) {
            TextField(guiando ? "guiar o turno em curso…" : "pedir a \(store.lane)…", text: $rascunho, axis: .vertical)
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
            // Uma linha. Ferramenta é rastro para varrer, não texto para ler — e são muitas.
            Trilho(marcador: "⚙", cor: BeagleTheme.textTertiary) {
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

        case .diff(_, let patch, _):
            Trilho(marcador: "◆", cor: BeagleTheme.truthObserved) { DiffView(patch: patch) }

        case .approval(_, let kind, let detalhe, _):
            Trilho(marcador: "◉", cor: BeagleTheme.accent) {
                PedidoView(kind: kind, detalhe: detalhe, enviando: enviando, onAprovar: onAprovar)
            }

        case .failure(_, let texto, _):
            Trilho(marcador: "▲", cor: BeagleTheme.stateError) {
                Text(texto)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(BeagleTheme.stateError)
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
            }
        }
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
private struct DiffView: View {
    let patch: String

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
            }

            // 🚨 Sem `ScrollView` horizontal aqui, e a razão foi medida no primeiro retrato:
            // um scroll horizontal dentro do `ImageRenderer` colapsa e o corpo do diff saía como
            // um retângulo VAZIO. Um bloco de código que só aparece quando alguém está com o app
            // aberto é um bloco que nunca vai ser revisado antes de existir.
            //
            // Linha longa QUEBRA em vez de rolar. Cortar dado é pior que rolar, mas quebrar não
            // esconde nada — e é o que GitHub e o próprio Xcode fazem em soft wrap.
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
