#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

// MARK: - Um turno

/// O turno como UNIDADE. Um cabeçalho fino marca a fronteira e conta o que aconteteu dentro —
/// quantas ferramentas, se houve diff, quanto durou.
///
/// Não é um cartão: cartão dentro de cartão empilha borda sobre borda e a tela vira grade. É uma
/// régua horizontal com um número, que é o mínimo para o olho achar onde um pedido começa.
struct TurnoView: View {
    let turno: SessionTurn
    let numero: Int
    let emCurso: Bool
    let enviando: Bool
    let onAprovar: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            cabecalho
            ForEach(turno.steps.filter(\.isRenderable)) { passo in
                PassoView(passo: passo, enviando: enviando, onAprovar: onAprovar)
            }
            rodape
        }
    }

    private var cabecalho: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Text(turno.prompt == nil ? "antes" : "turno \(numero)")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(BeagleTheme.textTertiary)
            // Um turno sem pedido é sessão RETOMADA: o pedido está fora da janela do diário.
            // Fingir que aquele trabalho pertence ao próximo pedido seria atribuí-lo ao pedido
            // errado — e é o tipo de erro que faz alguém aprovar a coisa errada.
            if turno.prompt == nil {
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

    /// Duração · contexto · custo. O custo vem de `SessionTurn.usage` — a MESMA fonte que o chip da
    /// Frota soma (Task 6). Dois cálculos independentes divergem, e aí o operador não sabe em
    /// qual acreditar — por isso a formatação mora em `SessionStore.turnFooter`, não aqui.
    @ViewBuilder
    private var rodape: some View {
        if let texto = SessionStore.turnFooter(duration: turno.duration(completed: !emCurso),
                                               usage: turno.usage) {
            Text(texto)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 2)
        }
    }

    /// O que aconteceu dentro, em uma linha. Serve para decidir se vale abrir o turno com o olho.
    @ViewBuilder
    private var resumo: some View {
        let ferramentas = turno.steps.filter { if case .tool = $0 { return true }; return false }.count
        HStack(spacing: 5) {
            if ferramentas > 0 {
                Label("\(ferramentas)", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            if turno.hasDiff {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 9))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            if turno.requiresApproval {
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
struct Trilho<Conteudo: View>: View {
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
struct Cursor: View {
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
