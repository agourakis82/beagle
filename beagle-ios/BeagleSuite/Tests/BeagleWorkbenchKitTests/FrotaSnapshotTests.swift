#if os(macOS)
import XCTest
import SwiftUI
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// RENDERIZA a Frota em PNG, sem cluster e sem permissão de gravação de tela.
///
/// Por que isto existe: a tela vinha sendo desenhada às cegas. Ver a Frota exigia o cluster de
/// pé e um agente parado no instante certo, então cada rodada de design era palpite — e três
/// rodadas seguidas voltaram como "ainda tá ruim" sem ninguém conseguir apontar o quê.
/// `ImageRenderer` rasteriza a hierarquia SwiftUI em processo: não precisa de janela, de Xcode,
/// nem de Screen Recording no ssh.
///
///     swift test --filter FrotaSnapshotTests
///     open /tmp/frota-snapshots
///
/// Os dados são os MEDIDOS na frota real em 10-ago-2026 (11 lanes de agente + 4 sessões do t560
/// + loom-1). Inventar dados bonitos aqui esconderia justamente o que quebra o layout: título
/// comprido, detalhe que estoura, lane ausente, leitura velha.
final class FrotaSnapshotTests: XCTestCase {

    private static let outDir = "/tmp/frota-snapshots"

    @MainActor
    private func render(_ view: some View, size: CGSize, name: String) throws {
        _ = size.height  // a altura vem do conteúdo: recortar aqui esconderia o que estoura
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, alignment: .top)
            .environment(\.farolFlatGlass, true))
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("ImageRenderer não produziu PNG para \(name)")
        }
        try FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        let path = "\(Self.outDir)/\(name).png"
        try png.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT \(path) \(Int(size.width))x\(Int(size.height))")
    }


    /// O que vai para o PNG: o CONTEÚDO da Frota sobre o mesmo chão que a tela usa.
    /// Sem o `ScrollView`, que faz o `ImageRenderer` propor altura infinita e devolver branco.
    @MainActor
    private func retrato(_ fleet: FleetStateClient) -> some View {
        FrotaView(fleet: fleet).conteudo
            .background(Color(red: 0.043, green: 0.055, blue: 0.086))
    }

    // MARK: - A frota real, medida

    private static func frotaReal(now: Date) -> [LaneSnapshot] {
        [
            .init(sid: "codex-1", title: "codex-1", state: .waiting,
                  detail: "Press enter to confirm or esc to cancel",
                  peek: ["› apply_patch stdlib/epistemic/knowledge.sio",
                         "  Press enter to confirm or esc to cancel"],
                  approve: .enterKey, observedAt: now.addingTimeInterval(-8)),
            .init(sid: "codex-2", title: "codex-2", state: .waiting,
                  detail: "Press enter to confirm or esc to cancel",
                  peek: ["› rm -rf /workspace/.wt/codex-2/target",
                         "  Press enter to confirm or esc to cancel"],
                  approve: .enterKey, observedAt: now.addingTimeInterval(-8)),
            .init(sid: "loom-1", title: "loom-1", state: .stuck,
                  detail: "thread anotada não existe mais no store; o próximo turno abre uma nova",
                  peek: [], approve: .answerNeeded,
                  observedAt: now.addingTimeInterval(-3), confidence: .exact, pendingApproval: true),
            .init(sid: "claude-1", title: "claude-1", state: .running,
                  detail: "✻ Effecting… (13m 43s · ↓ 6.6k tokens)",
                  peek: ["● Running 3 shell commands · 1m 45s"],
                  observedAt: now.addingTimeInterval(-9)),
            .init(sid: "claude-2", title: "claude-2", state: .running,
                  detail: "✻ Churned for 2m 1s · 1 shell still running",
                  observedAt: now.addingTimeInterval(-9)),
            .init(sid: "claude-3", title: "claude-3", state: .idle,
                  detail: "❯ e pq vc nao construiu....para de queimar token",
                  atShell: false, observedAt: now.addingTimeInterval(-11)),
            .init(sid: "codex-3", title: "codex-3", state: .running,
                  detail: "• O transporte está implementado, revisado e provado ponta a ponta",
                  observedAt: now.addingTimeInterval(-11)),
            .init(sid: "kimi-cli1", title: "kimi-cli1", state: .idle,
                  detail: "● N-back full (18 subj, 10 epochs/level) running",
                  observedAt: now.addingTimeInterval(-12)),
            .init(sid: "kimi-cli2", title: "kimi-cli2", state: .running,
                  detail: "● I have a picture: compiler has ~30 open bugs — here is the triage",
                  observedAt: now.addingTimeInterval(-12)),
            .init(sid: "grok-cli1", title: "grok-cli1", state: .idle,
                  detail: "❯ /skill-gen", atShell: false, observedAt: now.addingTimeInterval(-13)),
            .init(sid: "grok-cli2", title: "grok-cli2", state: .idle,
                  detail: " research/zd-fiber-antisymmetry-lemma-20260731",
                  atShell: false, observedAt: now.addingTimeInterval(-13)),
            .init(sid: "repo", title: "repo", state: .idle, detail: "< /dev/null",
                  atShell: true, observedAt: now.addingTimeInterval(-14)),
            .init(sid: "t560-beagle", title: "t560-beagle", state: .unknown, detail: "",
                  observedAt: nil),
            .init(sid: "t560-darwin-ops", title: "t560-darwin-ops", state: .unknown, detail: "",
                  observedAt: nil),
            .init(sid: "t560-clops", title: "t560-clops", state: .unknown, detail: "", observedAt: nil),
            .init(sid: "sounio-dev", title: "sounio-dev", state: .unknown, detail: "", observedAt: nil),
        ]
    }

    // MARK: - Retratos

    @MainActor
    func testRetratoDaFrotaReal() throws {
        let now = Date()
        let fleet = FleetStateClient.fixture(
            lanes: Self.frotaReal(now: now),
            loomd: LoomdHealth(mode: .observed, observedAt: now.addingTimeInterval(-998),
                               readAt: now, lanes: 1, everObserved: true))
        // Janela típica no Mac e a mesma tela estreita, porque quebra de layout mora na estreita.
        try render(retrato(fleet), size: CGSize(width: 1180, height: 900), name: "01-frota-mac")
        try render(retrato(fleet), size: CGSize(width: 430, height: 932), name: "02-frota-estreita")
    }

    @MainActor
    func testRetratoCalmo() throws {
        let now = Date()
        // Nada na prateleira: o estado MAIS comum do dia, e o que decide se a tela vale a pena
        // ficar aberta. Uma Frota que só é boa em emergência é um alarme, não um posto de trabalho.
        let calmas = Self.frotaReal(now: now).filter { !$0.needsOperator }
        let fleet = FleetStateClient.fixture(
            lanes: calmas,
            loomd: LoomdHealth(mode: .observed, readAt: now, lanes: 1, everObserved: true))
        try render(retrato(fleet), size: CGSize(width: 1180, height: 900), name: "03-frota-calma")
    }

    @MainActor
    func testRetratoDegradado() throws {
        let now = Date()
        // Fonte caída + leitura velha + lane ausente: os três jeitos de a tela ter que ADMITIR
        // que não sabe. É onde um painel bonito costuma mentir.
        var lanes = Self.frotaReal(now: now.addingTimeInterval(-300))
        lanes.append(.init(sid: "grok-cli3", title: "grok-cli3", state: .exited,
                           detail: "sessão não existe no tmux", observedAt: now))
        let fleet = FleetStateClient.fixture(
            lanes: lanes,
            loomd: LoomdHealth(mode: .down, readAt: now, lanes: 0, lost: ["loom-1"],
                               error: "connection refused", everObserved: true),
            link: .reconnecting, lastFrameAt: now.addingTimeInterval(-300))
        try render(retrato(fleet), size: CGSize(width: 1180, height: 900), name: "04-frota-degradada")
    }

    /// Quais SF Symbols realmente RESOLVEM neste contexto. No primeiro retrato, `escape` e
    /// `macwindow` saíram como quadrado amarelo de símbolo faltando — e um ícone que não resolve
    /// é pior que rótulo apagado. Medir é mais barato que chutar.
    @MainActor
    func testSimbolos() throws {
        let nomes = ["return", "escape", "macwindow", "xmark", "xmark.circle",
                     "stop.circle", "arrow.branch", "arrow.triangle.branch",
                     "terminal", "rectangle.on.rectangle", "arrow.up.forward.app",
                     "text.bubble", "chevron.right"]
        try render(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(nomes, id: \.self) { n in
                    HStack(spacing: 10) {
                        Image(systemName: n).frame(width: 22)
                        Text(n).font(.system(size: 11, design: .monospaced))
                    }.foregroundStyle(.white)
                }
            }.padding(16).background(Color.black),
            size: CGSize(width: 320, height: 300), name: "05-simbolos")
    }
}
#endif
