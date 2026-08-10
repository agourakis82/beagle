#if os(macOS)
import XCTest
import SwiftUI
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// RENDERIZA a Sessão em PNG, sem cluster e sem permissão de gravação de tela.
///
/// Irmão de `FrotaSnapshotTests`, e existe pelo mesmo motivo: as três rodadas anteriores de
/// design foram feitas às cegas e voltaram como "ainda tá ruim". Esta tela é revisada em imagem
/// ANTES de existir de verdade.
///
///     swift test --filter SessionSnapshotTests && open /tmp/frota-snapshots
///
/// Os dados são os MEDIDOS no censo do `codex app-server` de 10-ago-2026 — o mesmo turno real que
/// escreveu `alvo.txt`. Fixture bonita esconderia o que quebra o layout: diff longo, comando com
/// caminho gigante, erro cru.
final class SessionSnapshotTests: XCTestCase {

    private static let outDir = "/tmp/frota-snapshots"

    @MainActor
    private func render(_ view: some View, width: CGFloat, name: String) throws {
        let r = ImageRenderer(content: view
            .frame(width: width, alignment: .top)
            .environment(\.farolFlatGlass, true)
            .environment(\.colorScheme, .dark))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("ImageRenderer não produziu PNG para \(name)")
        }
        try FileManager.default.createDirectory(atPath: Self.outDir, withIntermediateDirectories: true)
        let path = "\(Self.outDir)/\(name).png"
        try png.write(to: URL(fileURLWithPath: path))
        print("SNAPSHOT \(path) \(Int(width))w")
    }

    /// O que vai para o PNG: o conteúdo da Sessão sobre o chão da tela, sem o `ScrollView` —
    /// `ImageRenderer` propõe altura infinita ao filho de um scroll e devolve branco.
    @MainActor
    private func retrato(_ store: SessionStore) -> some View {
        SessionView(store: store).conteudo
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BeagleTheme.surface0)
            .environment(\.colorScheme, .dark)
    }

    // ─── O turno real, medido ────────────────────────────────────────────────────────────

    /// O diff que o codex realmente propôs no censo.
    private static let diffReal = """
    diff --git a/alvo.txt b/alvo.txt
    new file mode 100644
    index 0000000000000000000000000000000000000000..c09fc3cf1b3b73ae5210ed9a224034a409287dd4
    --- /dev/null
    +++ b/alvo.txt
    @@ -0,0 +1 @@
    +oi
    """

    private static let diffLongo = """
    diff --git a/stdlib/epistemic/knowledge.sio b/stdlib/epistemic/knowledge.sio
    --- a/stdlib/epistemic/knowledge.sio
    +++ b/stdlib/epistemic/knowledge.sio
    @@ -142,9 +142,14 @@ pub fn zero_divisor(a: Knowledge[T], b: Knowledge[T]) -> bool {
    -pub fn zero_divisor(a: Knowledge[T], b: Knowledge[T]) -> bool {
    -    // E175: consumível de fora, e não deveria ser
    -    a.support * b.support == 0
    +fn zero_divisor(a: Knowledge[T], b: Knowledge[T]) -> bool {
    +    // Visibilidade fechada: o divisor de zero é detalhe de implementação da álgebra,
    +    // e exportá-lo fazia o import errado devolver silenciosamente 0.
    +    a.support * b.support == 0
     }
    +
    +pub fn dissociated(a: Knowledge[T], b: Knowledge[T]) -> bool {
    +    zero_divisor(a, b) && a.evidence != b.evidence
    +}
    """

    private func agora(_ atras: TimeInterval) -> Date { Date().addingTimeInterval(-atras) }

    @MainActor
    func testRetratoDeUmTurnoCompleto() throws {
        let s = SessionStore.fixture(lane: "codex-1", steps: [
            .prompt(id: 1, text: "Arruma o E175 da stdlib: zero_divisor não deveria ser consumível de fora.", at: agora(180)),
            .message(id: 2, text: "Vou ler os módulos afetados antes de mexer — o E175 costuma vir de visibilidade, não de tipo.", at: agora(174)),
            .tool(id: 3, name: "Read", detail: "stdlib/epistemic/knowledge.sio", at: agora(170)),
            .tool(id: 4, name: "Grep", detail: "\"zero_divisor\" — 14 achados em 6 arquivos", at: agora(168)),
            .diff(id: 5, patch: Self.diffLongo, at: agora(160)),
            .message(id: 6, text: "Fechei a visibilidade e expus `dissociated`, que é o que os call-sites de fora realmente queriam. Os 14 achados viram 2.", at: agora(150)),
        ])
        try render(retrato(s), width: 900, name: "10-sessao-turno")
    }

    @MainActor
    func testRetratoComPedidoDeAprovacao() throws {
        // O estado que a tela existe para resolver: ele parado, esperando decisão.
        let s = SessionStore.fixture(lane: "codex-1", steps: [
            .prompt(id: 1, text: "Escreva um arquivo alvo.txt com exatamente a linha `oi`.", at: agora(40)),
            .message(id: 2, text: "Vou criar o arquivo na raiz do workspace.", at: agora(35)),
            .diff(id: 3, patch: Self.diffReal, at: agora(30)),
            .approval(id: 4, kind: .patch, detail: "alvo.txt (novo arquivo, 1 linha)", at: agora(28)),
        ])
        try render(retrato(s), width: 900, name: "11-sessao-pedido")
    }

    @MainActor
    func testRetratoComComandoQueNaoSeDesfaz() throws {
        // A distinção que muda o risco. O rótulo tem que ser diferente do patch, e visivelmente.
        let s = SessionStore.fixture(lane: "codex-1", steps: [
            .prompt(id: 1, text: "Limpa os artefatos de build da worktree.", at: agora(20)),
            .approval(id: 2, kind: .command,
                      detail: "rm -rf /workspace/.wt/codex-1/target /workspace/.wt/codex-1/.build",
                      at: agora(18)),
        ])
        try render(retrato(s), width: 900, name: "12-sessao-comando")
    }

    @MainActor
    func testRetratoEscrevendoEComFalha() throws {
        let s = SessionStore.fixture(lane: "codex-1", steps: [
            .prompt(id: 1, text: "roda o gate da stdlib", at: agora(60)),
            .failure(id: 2, text: "turn/start failed: thread already has an active writer (-32600)", at: agora(50)),
            .prompt(id: 3, text: "tenta de novo", at: agora(20)),
        ], streaming: "Vou retomar a thread e rodar o gate")
        try render(retrato(s), width: 900, name: "13-sessao-escrevendo")
    }

    @MainActor
    func testRetratoVazioEEstreito() throws {
        // Vazio é o primeiro contato com a tela, e a largura estreita é onde o layout quebra.
        try render(retrato(SessionStore.fixture(lane: "codex-2", steps: [])),
                   width: 900, name: "14-sessao-vazia")
        let cheia = SessionStore.fixture(lane: "codex-1", steps: [
            .prompt(id: 1, text: "arruma o E175", at: agora(30)),
            .diff(id: 2, patch: Self.diffReal, at: agora(20)),
            .approval(id: 3, kind: .patch, detail: "alvo.txt", at: agora(18)),
        ])
        try render(retrato(cheia), width: 430, name: "15-sessao-estreita")
    }

    // ─── o ícone ────────────────────────────────────────────────────────────────────────────

    /// Rasteriza o ícone nos tamanhos que o `.icns` exige, e um contato-folha para revisão.
    ///
    /// O tamanho que importa é 32: é onde o ícone vive de verdade (Dock, ⌘Tab, barra de título).
    /// Desenho que só funciona a 1024 é pôster, não ícone — então o retrato inclui os pequenos
    /// lado a lado, para a decisão ser tomada no tamanho em que ele vai ser visto.
    @MainActor
    func testIcone() throws {
        for lado in [16, 32, 64, 128, 256, 512, 1024] {
            // ≤32pt recebe a arte simplificada. É o mesmo que o sistema faz, e o contato-folha
            // provou que é necessário: onze fios a 16pt são um borrão.
            try render(AppIconArt(pequeno: lado <= 32).frame(width: CGFloat(lado), height: CGFloat(lado)),
                       width: CGFloat(lado), name: "icone-\(lado)")
        }
        // Contato-folha: os pequenos sobre o cinza do Dock, que é onde eles competem.
        try render(
            HStack(spacing: 18) {
                ForEach([16, 24, 32, 48, 64, 128], id: \.self) { l in
                    AppIconArt(pequeno: l <= 32).frame(width: CGFloat(l), height: CGFloat(l))
                }
            }
            .padding(24)
            .background(Color(white: 0.62)),
            width: 460, name: "icone-contato")
    }
}
#endif
