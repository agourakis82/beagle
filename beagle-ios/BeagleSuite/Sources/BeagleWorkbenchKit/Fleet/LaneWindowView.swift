#if os(macOS)
import SwiftUI
import BeagleCore

/// UMA lane, numa janela própria — nada mais na hierarquia.
///
/// 🚨 Existe para matar a "tarja" por CONSTRUÇÃO, não por remendo. Em `FleetTerminalsView` cada
/// lane aberta é um `PTYTerminalView` empilhado num `ZStack`, com `opacity 0` escondendo as
/// inativas — exatamente o padrão (vários `NSHostingView` de terminal na mesma hierarquia) que
/// dispara a regressão confirmada do macOS 26.2 (FB21579636, ver `TerminalDaFrota.swift`). Uma
/// janela própria não empilha: só existe UM `NSHostingView` de terminal ali, então a classe
/// inteira de bug não tem onde acontecer — não é um remendo em cima do `ZStack`, é a ausência do
/// `ZStack`.
///
/// Cliente PRÓPRIO, não emprestado do `FleetTerminalStore` da aba Terminais: abrir esta janela já
/// é um `tmux attach` novo no pod (como qualquer lane recém-aberta na aba), e a janela sobrevive
/// independente da aba — fechar uma não deve soltar o socket da outra.
public struct LaneWindowView: View {
    let lane: String
    let client: PTYClient

    public init(lane: String, endpoint: FleetEndpoint = FleetEndpoint()) {
        self.lane = lane
        self.client = PTYClient(agent: lane, endpoint: endpoint)
    }

    private static let canvas = Color(red: 0.106, green: 0.078, blue: 0.149)   // #1b1426, mesmo tom da aba Terminais

    public var body: some View {
        VStack(spacing: 0) {
            barra
            Divider().overlay(Color.white.opacity(0.08))
            PTYTerminalView(client: client, ativo: true)
        }
        .background(Self.canvas)
        .navigationTitle(lane)
        .onAppear { client.connect() }
    }

    /// Mesma info que o chip da aba Terminais mostra — estado da conexão e o título que a lane
    /// anunciou (OSC 0/2) — porque esta janela é a MESMA lane, só sem o resto da aba ao redor.
    private var barra: some View {
        HStack(spacing: 6) {
            Circle().fill(corDoEstado).frame(width: 7, height: 7)
            Text(lane).font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.85))
            if let t = client.titulo?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != lane {
                Text(FleetTerminalsView.encurtar(t, teto: 46))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var corDoEstado: Color {
        switch client.state {
        case .connected: return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .connecting, .reconnecting: return Color(red: 1.0, green: 0.76, blue: 0.27)
        case .failed: return Color(red: 0.95, green: 0.36, blue: 0.36)
        case .idle: return .gray
        }
    }
}
#endif
