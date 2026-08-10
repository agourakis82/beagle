#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore
#if os(iOS) || os(macOS)
import class SwiftTerm.TerminalView
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Fleet Terminals screen: status-tinted agent picker (with unread badges) + a ZStack of
/// all *opened* terminals (kept mounted; only the active shown) so switching never tears
/// down a live SwiftTerm buffer. Swipe to switch agents, ⌘K quick switcher (Mac/iPad),
/// haptics, and foreground reconnect.
public struct FleetTerminalsView: View {
    @State private var store = FleetTerminalStore()
    @State private var showSwitcher = false
    @Environment(\.scenePhase) private var scenePhase

    /// A lane to jump straight to (the Frota handing over "open this one"). Nil = last active.
    private let initialAgent: String?

    public init(initialAgent: String? = nil) { self.initialAgent = initialAgent }

    private static let canvas = Color(red: 0.106, green: 0.078, blue: 0.149)   // #1b1426
    private static let amber  = Color(red: 1.0, green: 0.76, blue: 0.27)
    private static let claude = Color(red: 1.0, green: 0.82, blue: 0.40)
    private static let codex  = Color(red: 0.20, green: 0.88, blue: 0.78)
    private static let vendor = Color(red: 1.0, green: 0.57, blue: 0.40)

    public var body: some View {
        VStack(spacing: 0) {
            agentBar
            barraDeControles
            statusLine
            Divider().overlay(Color.white.opacity(0.08))
            terminals
        }
        .background(Self.canvas)
        .onAppear { store.open(initialAgent ?? store.activeAgent) }
        .onChange(of: initialAgent) { _, lane in if let lane { store.open(lane) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reconnectStale() }
        }
        .background(switcherShortcut)
        .sheet(isPresented: $showSwitcher) { agentSwitcher }
        .onReceive(NotificationCenter.default.publisher(for: .abrirGavetaDeSessoes)) { _ in
            showSwitcher = true
        }
        .navigationTitle("Fleet")
    }

    private var terminals: some View {
        ZStack {
            ForEach(store.opened, id: \.self) { agent in
                PTYTerminalView(client: store.client(for: agent),
                                ativo: agent == store.activeAgent)
                    .opacity(agent == store.activeAgent ? 1 : 0)
                    .allowsHitTesting(agent == store.activeAgent)
            }
            if store.opened.isEmpty {
                ContentUnavailableView("Pick an agent", systemImage: "terminal")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.canvas)
        .modifier(TrocaPorSwipe(store: store))
    }

    private var agentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.agents, id: \.self) { agent in
                    chip(agent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Self.canvas)
    }

    /// Encurta o título para caber num chip.
    ///
    /// O tmux publica coisas como `openvscode-server@sounio-workspace-control-0:/workspace/sounio`
    /// ou `claude — Decide whether to land PR #1672 for self-compilation`. Duas regras, e as duas
    /// são sobre onde a informação REALMENTE está:
    ///
    /// 1. de `user@host:/caminho/longo`, o que interessa é o último componente do caminho — o
    ///    resto é o mesmo em todas as lanes e não distingue nada;
    /// 2. de uma frase, o COMEÇO, porque é onde o assunto está; e o corte fica no fim da palavra,
    ///    com reticência, em vez de partir uma no meio.
    static func encurtar(_ t: String, teto: Int = 28) -> String {
        var s = t
        // `user@host:/caminho` → o último componente. O `:` só conta se vier depois de um `@`,
        // senão um título com dois-pontos legítimo ("build: falhou") perderia a primeira metade.
        if let arroba = s.firstIndex(of: "@"), let dp = s[arroba...].firstIndex(of: ":") {
            let caminho = String(s[s.index(after: dp)...])
            let ultimo = caminho.split(separator: "/").last.map(String.init) ?? caminho
            if !ultimo.isEmpty { s = ultimo }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > teto else { return s }
        let corte = String(s.prefix(teto))
        if let esp = corte.lastIndex(of: " "), corte.distance(from: esp, to: corte.endIndex) < 10 {
            return String(corte[..<esp]) + "…"
        }
        return corte + "…"
    }

    private func chip(_ agent: String) -> some View {
        let active = agent == store.activeAgent
        return Button {
            store.open(agent); haptic()
        } label: {
            HStack(spacing: 6) {
                if store.opened.contains(agent) {
                    Circle().fill(stateColor(store.state(for: agent))).frame(width: 7, height: 7)
                }
                Text(agent).font(.system(.caption, design: .monospaced))
                // O TÍTULO que o processo remoto anunciou (OSC 0/2) — o tmux publica ali o que a
                // lane está fazendo. Vem DEPOIS do nome e mais apagado: o nome é o endereço, que
                // ele usa para navegar; o título é o assunto, que muda toda hora. Trocar um pelo
                // outro faria a barra reordenar-se no olho a cada mudança de tarefa.
                if let t = store.titulo(agent) {
                    Text(Self.encurtar(t))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? Self.amber.opacity(0.22) : Color.white.opacity(0.06))
            .overlay(Capsule().stroke(active ? Self.amber.opacity(0.6) : .clear, lineWidth: 1))
            .clipShape(Capsule())
            // 🔔 Dois avisos DIFERENTES, e a distinção é o ponto: saída nova é a lane
            // TRABALHANDO — acontece o tempo todo e não pede nada. O sino é a lane CHAMANDO: um
            // agente que terminou, ou que travou esperando decisão. Um badge só para os dois
            // transformaria o pedido de atenção em ruído de fundo, que é como um alarme morre.
            //
            // O sino VENCE quando os dois valem: quem chamou é mais urgente que quem falou.
            .overlay(alignment: .topTrailing) {
                if store.chamou(agent) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Self.canvas)
                        .padding(2.5)
                        .background(Circle().fill(Self.amber))
                        .overlay(Circle().stroke(Self.canvas, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                        // Pulsa só ENQUANTO chama — animação perpétua num canto vira wallpaper e
                        // para de ser vista. `reduce motion` recebe o sino parado, que ainda diz
                        // tudo: a forma é o sinal, o movimento é o reforço.
                        .modifier(PulsoDoSino())
                        .accessibilityLabel("\(agent) chamou você")
                } else if store.hasUnread(agent) {
                    Circle().fill(Self.amber)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Self.canvas, lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                        .accessibilityLabel("\(agent) tem saída nova")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(color(for: agent))
        // Leaving a lane must be possible, and it is not cosmetic: each open lane holds a live
        // socket AND a real `tmux attach` on the workspace pod. Closing releases both.
        .contextMenu {
            if store.opened.contains(agent) {
                Button("Fechar \(agent)", systemImage: "xmark.circle") { store.close(agent) }
                Button("Fechar as outras", systemImage: "rectangle.on.rectangle.slash") {
                    store.open(agent); store.closeAllExceptActive()
                }
            }
        }
    }

    /// A BARRA DE CONTROLES.
    ///
    /// 🚨 Existe porque ele disse "não tem controle nenhum", e estava certo: tudo morava em menu, e
    /// menu não se descobre olhando. Um recurso que só existe atrás de um atalho invisível é um
    /// recurso que não existe — foi literalmente o caso da gaveta, que tinha ⌘K colidindo e nenhum
    /// botão.
    ///
    /// Os mesmos despachos do menu (`TerminalTools.swift`), não uma segunda implementação: dois
    /// caminhos para a mesma ação divergem, e aí um funciona e o outro não.
    #if os(macOS)
    private var barraDeControles: some View {
        HStack(spacing: 10) {
            // O título que a lane anuncia (OSC 0/2) — o que ela está fazendo AGORA.
            if let t = store.titulo(store.activeAgent) {
                Text(Self.encurtar(t, teto: 46))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            controle("magnifyingglass", "Buscar (⌘F)") { _ = enviarBusca(.showFindPanel) }
            controle("textformat.size.smaller", "Diminuir fonte (⌘−)") {
                enviarAoTerminal(#selector(TerminalView.diminuirFonte(_:)))
            }
            controle("textformat.size.larger", "Aumentar fonte (⌘+)") {
                enviarAoTerminal(#selector(TerminalView.aumentarFonte(_:)))
            }
            controle("delete.left", "Limpar tela (⇧⌘K) — apaga o que está desenhado, sem mandar nada para o agente") {
                enviarAoTerminal(#selector(TerminalView.limparTela(_:)))
            }
            Divider().frame(height: 12).overlay(Color.white.opacity(0.12))
            controle("rectangle.stack", "Trocar de sessão (⌘K)") { showSwitcher = true }
            controle("arrow.clockwise", "Reconectar esta lane") {
                store.client(for: store.activeAgent).connect()
            }
            // Fechar é o único destrutivo da barra, e o custo é real: solta o socket E o
            // `tmux attach` no pod. Por isso fica separado e nomeia a lane no tooltip.
            controle("xmark", "Fechar \(store.activeAgent) — solta o socket e o attach no pod") {
                store.close(store.activeAgent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Self.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    /// Um controle da barra. `.plain` + `.contentShape` pelo mesmo motivo da gaveta: sem eles a
    /// área clicável no macOS fica só no glifo, e um alvo de 11pt é um alvo que se erra.
    private func controle(_ icone: String, _ ajuda: String, _ acao: @escaping () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: icone)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.62))
        .help(ajuda)
        .accessibilityLabel(ajuda)
    }
    #else
    private var barraDeControles: some View { EmptyView() }
    #endif

    @ViewBuilder private var statusLine: some View {
        let s = store.state(for: store.activeAgent)
        if s != .connected {
            HStack(spacing: 6) {
                Circle().fill(stateColor(s)).frame(width: 7, height: 7)
                Text(statusText(s)).font(.caption2).foregroundStyle(.white.opacity(0.7))
                if case .failed = s {
                    Button("Retry") { store.client(for: store.activeAgent).connect() }
                        .font(.caption2).buttonStyle(.borderless).tint(Self.amber)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Self.canvas)
        }
    }

    // ⌘K quick switcher (Mac/iPad hardware keyboard); harmless on iPhone.
    private var switcherShortcut: some View {
        Button("Switch agent") { showSwitcher = true }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private var agentSwitcher: some View {
        NavigationStack {
            List(store.agents, id: \.self) { agent in
                // 🚨 `.buttonStyle(.plain)` + `.contentShape` NÃO são cosméticos aqui: sem eles, no
                // macOS a área clicável de um Button dentro de List fica só no TEXTO, não na linha.
                // Ele clicava na linha e nada acontecia — "selecionar outra sessão não vai". No iPad
                // a área maior escondia o problema; esta tela foi escrita para iPad.
                Button {
                    store.open(agent); haptic(); showSwitcher = false
                } label: {
                    HStack {
                        Circle().fill(stateColor(store.state(for: agent))).frame(width: 8, height: 8)
                        Text(agent).font(.system(.body, design: .monospaced))
                            .foregroundStyle(color(for: agent))
                        if store.hasUnread(agent) {
                            Circle().fill(Self.amber).frame(width: 7, height: 7)
                        }
                        Spacer()
                        if agent == store.activeAgent {
                            Image(systemName: "checkmark").foregroundStyle(Self.amber)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Trocar de sessão")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSwitcher = false }
                }
            }
        }
        // API de iOS — no macOS é no-op, e deixá-la solta esconde que a gaveta nunca foi portada.
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func haptic() {
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func statusText(_ s: PTYClient.State) -> String {
        switch s {
        case .idle: return "idle"
        case .connecting: return "connecting…"
        case .reconnecting: return "reconnecting…"
        case .connected: return "connected"
        case .failed(let m): return "offline — \(m)"
        }
    }

    private func stateColor(_ s: PTYClient.State) -> Color {
        switch s {
        case .connected: return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .connecting, .reconnecting: return Self.amber
        case .failed: return Color(red: 0.95, green: 0.36, blue: 0.36)
        case .idle: return .gray
        }
    }

    private func color(for agent: String) -> Color {
        if agent.hasPrefix("claude") { return Self.claude }
        if agent.hasPrefix("codex") { return Self.codex }
        return Self.vendor
    }
}
#endif

/// Pulso do sino: chama a atenção e depois para de insistir.
///
/// `reduce motion` recebe o sino PARADO — a forma (um sino, não um ponto) já é o sinal; o
/// movimento é reforço. Quem pediu menos animação continua vendo que foi chamado.
private struct PulsoDoSino: ViewModifier {
    @State private var grande = false
    @Environment(\.accessibilityReduceMotion) private var reduzir

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduzir ? 1 : (grande ? 1.18 : 1))
            .onAppear {
                guard !reduzir else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatCount(6, autoreverses: true)) {
                    grande = true
                }
            }
    }
}

/// Trocar de lane por swipe — SÓ no iOS.
///
/// 🚨 No Mac isto custava o mouse inteiro. Medido pelo sintoma que ele relatou: o clique DIREITO
/// não abria menu nenhum no terminal. `contentShape(Rectangle())` faz o ZStack virar alvo e o
/// gesto no pai fica na frente do `NSView` — os eventos param antes do SwiftTerm, que é quem tem
/// o menu de contexto, a seleção por arrasto e o clique que dá foco.
///
/// No iPad o swipe é o jeito natural de navegar e vale o preço. No Mac não paga nada: já existem
/// os chips, o seletor e os atalhos.
///
/// Vive num `ViewModifier` e não num `#if` no meio da cadeia porque ali o type-checker do Swift
/// estourou — "unable to type-check this expression in reasonable time".
private struct TrocaPorSwipe: ViewModifier {
    let store: FleetTerminalStore

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        if abs(dx) > 80, abs(dx) > abs(dy) * 1.5 {
                            store.cycle(dx < 0 ? 1 : -1)
                        }
                    }
            )
        #else
        content
        #endif
    }
}
