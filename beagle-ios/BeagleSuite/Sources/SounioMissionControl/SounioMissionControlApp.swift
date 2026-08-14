#if os(macOS)
import SwiftUI
import AppKit
import BeagleCore
import BeagleWorkbenchKit
import SwiftTerm

/// SOUNIO MISSION CONTROL — the macOS half of the house.
///
/// Deliberately NOT the Companion. The iPhone app is a personal partner; this is a workshop: a
/// real window, a sidebar, several terminals at once, and screens sized for a desk. They share
/// the same packages (BeagleCore / BeagleWorkbenchKit) and the same backend, and nothing here
/// touches the Companion's surface.
@main
struct SounioMissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Sounio Mission Control") {
            MissionControlWindow()
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 860)
        // A JANELA FLUTUANTE POR LANE. Existe para matar a "tarja" por construção — ver
        // `LaneWindowView.swift`. `for: String.self` porque o valor que a identifica É o nome da
        // lane; `WindowGroup(for:)` já deduplica por valor, então pedir a MESMA lane duas vezes
        // (⌘T repetido) só traz a janela existente à frente em vez de abrir uma segunda — o
        // padrão certo aqui, porque duas janelas do MESMO PTY seriam dois clientes brigando pelo
        // mesmo `tmux attach`.
        WindowGroup("Lane", id: "lane-terminal", for: String.self) { $lane in
            if let lane {
                LaneWindowView(lane: lane)
                    .frame(minWidth: 480, minHeight: 300)
            }
        }
        .defaultSize(width: 760, height: 480)
        .commands {
            // 🚨 SEM ISTO NÃO HÁ COPIAR NEM COLAR, e a causa é estrutural, não do terminal.
            //
            // O `SwiftTerm.TerminalView` JÁ implementa `copy(_:)`, `paste(_:)` e `selectAll(_:)`
            // como `@objc open func` — a responder chain do macOS os encontraria sozinha. O que
            // faltava era o MENU: um app SwiftUI sem grupo `.pasteboard` não tem ⌘C/⌘V ligados a
            // ação nenhuma, e as teclas morrem antes de chegar no terminal.
            //
            // Consequência medida: sem colar, não dá para responder a um prompt de OAuth
            // (`Paste code here if prompted >`), nem colar caminho, nem colar código numa lane.
            // Uma lane ficou presa nesse prompt.
            //
            // `sendAction(to: nil)` percorre a responder chain — é o idioma correto e é o que faz
            // o comando chegar em QUALQUER terminal focado, sem o app saber qual é.
            CommandGroup(replacing: .pasteboard) {
                Button("Copiar") { terminalCopiar() }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Colar") { terminalColar() }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Button("Selecionar tudo") { terminalSelecionarTudo() }
                    .keyboardShortcut("a", modifiers: .command)
            }

            // BUSCA. O `TerminalView` já tem o painel; ele só nunca era chamado.
            // ⚠️ `performFindPanelAction` faz `sender as? NSMenuItem` e desiste se não for —
            // mandar `from: nil` falharia em SILÊNCIO, com menu existindo e atalho respondendo.
            // Por isso `enviarBusca` monta um NSMenuItem com a tag.
            CommandGroup(replacing: .textEditing) {
                Button("Buscar…") { _ = enviarBusca(.showFindPanel) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Buscar próximo") { _ = enviarBusca(.next) }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Buscar anterior") { _ = enviarBusca(.previous) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Usar seleção para buscar") { _ = enviarBusca(.setFindString) }
                    .keyboardShortcut("e", modifiers: .command)
            }

            // O que o SwiftTerm NÃO tem, porque depende da aplicação.
            CommandMenu("Terminal") {
                Button("Aumentar fonte") { enviarAoTerminal(#selector(TerminalView.aumentarFonte(_:))) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Diminuir fonte") { enviarAoTerminal(#selector(TerminalView.diminuirFonte(_:))) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Tamanho original") { enviarAoTerminal(#selector(TerminalView.fonteOriginalTamanho(_:))) }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                // ⌘K limpa o que está DESENHADO, sem mandar nada pelo socket: mandar `^L` seria
                // digitar no agente, e num prompt de agente isso vira entrada, não comando.
                // 🚨 ⇧⌘K, não ⌘K. Eu criei uma COLISÃO ontem: este item (um NSMenuItem de verdade,
                // no nível da Scene) vencia o Button invisível que abre a gaveta em
                // `FleetTerminalsView`. Resultado: ⌘K limpava a tela e a gaveta NUNCA abria — e não
                // havia nenhum outro caminho de UI para ela. Trocar de sessão é muito mais
                // frequente que limpar, então ⌘K fica com a gaveta.
                Button("Limpar tela") { enviarAoTerminal(#selector(TerminalView.limparTela(_:))) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                // O caminho VISÍVEL para a gaveta. Um atalho invisível como único acesso é um
                // recurso que não existe: não se descobre olhando, e não se descobre procurando.
                Button("Trocar de sessão…") {
                    NotificationCenter.default.post(name: .abrirGavetaDeSessoes, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Divider()
                // Abre a lane ativa da aba Terminais numa janela própria — ver
                // `LaneWindowView.swift`. A aba não sabe abrir janela sozinha (comando de Scene é
                // o nível certo para `openWindow`); ela só publica QUAL lane via notificação, e
                // este botão é quem de fato chama `openWindow`.
                Button("Abrir lane em janela própria") {
                    NotificationCenter.default.post(name: .abrirLaneEmJanela, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Frota") { NotificationCenter.default.post(name: .missionControlGo, object: Section.frota) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Oficina") { NotificationCenter.default.post(name: .missionControlGo, object: Section.oficina) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Sessão") { NotificationCenter.default.post(name: .missionControlGo, object: Section.sessao) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Terminais") { NotificationCenter.default.post(name: .missionControlGo, object: Section.terminals) }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let missionControlGo = Notification.Name("missionControlGo")
}

/// A package executable is not a bundled app, so it starts as a background process with no menu
/// bar and no focus. Claiming `.regular` makes it behave like a real Mac app while this lives
/// outside an .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)   // a GUI process redirected to a file would buffer away its own logs
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { await Selftest.run() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 🚨 GARANTE QUE EXISTE JANELA. Ele relatou "terminal travou" — e o `sample` mostrou a main
    /// thread OCIOSA em `mach_msg_trap`, com **zero janelas**. O app não estava travado: estava
    /// sem janela, e sem janela não há terminal nenhum. De fora, é indistinguível de travamento.
    ///
    /// A causa é a restauração de estado do SwiftUI: um app encerrado à força pode voltar com o
    /// estado "nenhuma janela", e aí `WindowGroup` não cria nenhuma. `terminateAfterLastWindowClosed`
    /// já era `true`, então fechar no X encerra — o buraco era só a subida.
    func applicationDidBecomeActive(_ notification: Notification) {
        abrirJanelaSeNaoHouver()
    }

    /// Clicar no ícone do Dock com o app já rodando e sem janela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { abrirJanelaSeNaoHouver() }
        return true
    }

    private func abrirJanelaSeNaoHouver() {
        // `NSWindow` de painel/sheet não conta: procurar só as janelas que o usuário pode usar.
        let usaveis = NSApplication.shared.windows.filter { $0.canBecomeMain && !$0.isExcludedFromWindowsMenu }
        guard usaveis.isEmpty else { return }
        // O caminho suportado é o mesmo comando do menu File — dispará-lo evita duplicar a
        // construção da cena, que só o SwiftUI sabe fazer.
        NSApplication.shared.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        if NSApplication.shared.windows.filter({ $0.canBecomeMain }).isEmpty {
            NSLog("[mission-control] subi sem janela e não consegui abrir uma — File ▸ New Window")
        }
    }
}

enum Section: String, CaseIterable, Identifiable, Hashable {
    case frota, oficina, sessao, terminals
    var id: String { rawValue }

    /// Each entry names the operational question it answers — if a section cannot state one,
    /// it does not belong in the sidebar.
    var title: String {
        switch self {
        case .frota:     return "Frota"
        case .oficina:   return "Oficina"
        case .sessao:    return "Sessão"
        case .terminals: return "Terminais"
        }
    }
    var question: String {
        switch self {
        case .frota:     return "quem precisa de você"
        case .oficina:   return "está verde? o que quebrou?"
        case .sessao:    return "conversar com uma lane"
        case .terminals: return "entrar numa lane"
        }
    }
    var icon: String {
        switch self {
        case .frota:     return "dot.radiowaves.left.and.right"
        case .oficina:   return "wrench.and.screwdriver"
        case .sessao:    return "bubble.left.and.text.bubble.right"
        case .terminals: return "apple.terminal"
        }
    }
}

struct MissionControlWindow: View {
    @State private var section: Section = .frota
    @State private var openLane: String?
    /// A lane que o operador escolheu na gaveta da Sessão. `nil` = ele ainda não escolheu, e a
    /// tela segue o roster.
    ///
    /// 🚨 Tem que ser ESTADO, e opcional. Antes, a lane da Sessão era DERIVADA
    /// (`fleet.loomdRoster.first`) a cada render: não existia onde guardar um clique, então
    /// `onTrocarLane` não tinha o que fazer — e por isso nem era passado. Semear este estado com
    /// uma lane concreta seria o defeito espelho: `"loom-1"` gravado antes do primeiro frame
    /// prenderia a tela na constante mesmo depois do roster do servidor chegar. `nil` distingue
    /// "não escolheu" de "escolheu loom-1"; a conciliação inteira vive em `SessaoLane.exibida`,
    /// que é pura e testada.
    @State private var sessionLaneEscolhida: String?
    /// UM cliente para a janela toda. A Frota e a Sessão concordam sobre o que uma lane aceita
    /// porque leem do MESMO quadro — dois clientes divergiriam no primeiro poll perdido por um
    /// dos dois, e "GUIAR" mentindo por causa de um `FleetStateClient` que a Sessão não tinha é
    /// exatamente o defeito que esta fatia existe para matar.
    ///
    /// 🚨 E É A JANELA QUE CONECTA, não `FrotaView.onAppear`. `fleet` passou a pertencer à
    /// janela nesta fatia — dono do objeto conecta. Antes, `.sessao` só LIA `fleet.aceita(de:)`
    /// sem jamais abrir o socket, e funcionava por acidente: a seção inicial é `.frota`, então
    /// toda janela nova monta a Frota (que conectava) antes de qualquer navegação. Mudar a seção
    /// inicial, ou tirar a Frota, deixaria `aceita` `nil` para sempre — em silêncio. `connect()`
    /// é idempotente (`guard link != .live && link != .connecting`), então não há risco de abrir
    /// um segundo socket com a Frota também tentando conectar seu próprio `fleet` injetado.
    @State private var fleet = FleetStateClient()
    @Environment(\.scenePhase) private var scenePhase

    private static let canvas = Color(red: 0.043, green: 0.055, blue: 0.086)

    var body: some View {
        NavigationSplitView {
            // `List(data, selection:)` binds the DATA'S ID (a String here), so binding it to a
            // `Section?` silently mismatched and the sidebar drove nothing. The ForEach + .tag
            // form is the one that selects by value.
            List(selection: $section) {
                ForEach(Section.allCases) { s in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.body)
                            Text(s.question)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: s.icon)
                    }
                    .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            Group {
                switch section {
                case .frota:
                    FrotaView(fleet: fleet, onOpenLane: { lane in
                        openLane = lane
                        section = .terminals
                    })
                case .oficina:
                    OficinaView()
                case .sessao:
                    // A lane de protocolo tem CONVERSA; a de terminal tem scrollback. As duas categorias
                    // convivem de propósito — nenhuma das 11 muda de natureza sem ele mandar.
                    //
                    // `roster` e `aceita` vêm do MESMO `fleet` da Frota, não de uma constante
                    // global: quem sabe quais lanes existem e o que cada uma aceita é o servidor,
                    // via `FleetStateClient`, e a Sessão só mostra o que a cena lhe entrega.
                    //
                    // `linkDaFrota` é o mesmo `fleet.link` que a Frota já observa — sem ele, um
                    // socket caído congelava `aceita` em `nil` para sempre e a Sessão não tinha
                    // como distinguir "servidor ainda não falou" de "servidor emudeceu".
                    //
                    // A lane exibida é a conciliação de semente, roster e escolha do operador —
                    // regra pura em `SessaoLane.exibida`, presa em teste. `aceita` é consultado
                    // com ESSA lane, não com a semente: `aceita` da lane anterior é a tela
                    // mentindo sobre o que a lane de agora aceita.
                    //
                    // 🚨 O `.id(lane)` não é enfeite. `SessionView` guarda o `SessionStore` em
                    // `@State`, e `@State` SOBREVIVE a uma atualização da view: passar um `lane`
                    // novo trocaria o rótulo e manteria o store — cursor, turnos e parcial — da
                    // lane anterior na tela. Isso é pior que a gaveta morta, porque parece
                    // funcionar. Mudar a identidade da view é o que descarta o `@State` e faz o
                    // store nascer de novo, com `onDisappear`/`onAppear` parando e religando o
                    // fio na ordem certa.
                    let lane = SessaoLane.exibida(roster: fleet.loomdRoster,
                                                  escolha: sessionLaneEscolhida)
                    SessionView(lane: lane, roster: fleet.loomdRoster,
                                aceita: fleet.aceita(de: lane), linkDaFrota: fleet.link,
                                onTrocarLane: { sessionLaneEscolhida = $0 })
                        .id(lane)
                case .terminals:
                    FleetTerminalsView(initialAgent: openLane)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.canvas)
        }
        .onReceive(NotificationCenter.default.publisher(for: .missionControlGo)) { note in
            if let s = note.object as? Section { section = s }
        }
        .task {
            // `-beagleOpen <seção>` abre direto numa tela: é como um screenshot ou um smoke test
            // alcança uma seção sem depender de clique.
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "beagleOpen"),
               let s = Section(rawValue: raw.lowercased()) {
                section = s
            }
            #endif
        }
        // O `connect()` da janela: roda uma vez ao abrir, ANTES de qualquer navegação — é o que
        // faz `.sessao` ter `aceita` correto mesmo se for a primeira tela vista.
        .task { fleet.connect() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { fleet.connect(); fleet.refresh() }
        }
        // 🚨 Achado da review: no macOS `scenePhase` só muda ao trocar de APP (Cmd+Tab,
        // background/foreground) — nunca ao trocar de ABA na sidebar com a janela ainda ativa.
        // Antes desta fatia, `FrotaView.onAppear` chamava `connect()` incondicionalmente, então
        // "voltar para a Frota" era o gesto de fato de "tenta de novo" — e ele sumiu quando o
        // `connect()` da Frota passou a ser suprimido para o `fleet` injetado (dono agora é a
        // janela). `connect()` é idempotente, então religar aqui em toda troca de seção é barato
        // e nunca abre um segundo socket — mas ver `FleetStateClient.drop` para o conserto de
        // fundo: o cliente agora NUNCA para de tentar sozinho, então este gesto é reforço, não a
        // única rede de segurança.
        .onChange(of: section) { _, _ in fleet.connect() }
    }
}
#endif
