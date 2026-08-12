import XCTest
@testable import BeagleCore

/// O CONTRATO DO FIO — o teste que as duas pesquisas profundas apontaram como o único mecanismo
/// real contra perda silenciosa de campo.
///
/// Nenhum formato de fio detecta um consumidor que esqueceu de LER um campo: Protobuf resolve
/// ausência para o default por especificação, o FlatBuffers admite na doc que não consegue
/// desambiguar "default escrito" de "não escrito", e no Cap'n Proto escalares são XOR com o default
/// — nos três, o campo esquecido é indistinguível do campo zerado. Ler é propriedade do CÓDIGO, não
/// do encoding. Então o detector tem de estar no código, e é isto.
///
/// Os dois testes abaixo falham SOZINHOS quando alguém acrescenta uma propriedade ao `LaneSnapshot`
/// e esquece de ligá-la — sem que ninguém precise lembrar de atualizar uma lista.
@MainActor
final class ContratoDoFioTests: XCTestCase {

    /// Um frame com TODA chave que o servidor emite, cada uma com valor distinguível de vazio.
    /// Quando o cockpit ganhar uma chave nova, é aqui que ela entra — e o teste abaixo cobra.
    private let frameCompleto: [String: Any] = [
        "sid": "loom-1",
        "title": "loom-1 · madaros",
        "state": "waiting",
        "detail": "posso escrever em src/main.rs?",
        "peek": ["● lowering the IR", "› aguardando"],
        "approveKey": "enter",
        "atShell": true,
        "observedAt": 1_786_536_000_000.0,
        "confidence": "exact",
        "pendingApproval": ["id": "7", "method": "item/fileChange/requestApproval"],
        "aceita": "redireciona",
        "usd": 12.35,
        "diff": "--- a/src/main.rs\n+++ b/src/main.rs\n-velho\n+novo",
        "approvalKind": "patch",
        "loomdKind": "agent_message",
        "ausente": true,
    ]

    /// `Mirror` sobre as propriedades ARMAZENADAS. Uma propriedade que o `init?(loom:)` não lê fica
    /// no seu valor vazio, e aparece aqui nomeada — inclusive uma que ainda não existe hoje.
    private func vazio(_ v: Any) -> Bool {
        let m = Mirror(reflecting: v)
        if m.displayStyle == .optional { return m.children.isEmpty }   // Optional.none
        if let s = v as? String { return s.isEmpty }
        if let a = v as? [String] { return a.isEmpty }
        if let b = v as? Bool { return b == false }
        if let d = v as? Double { return d == 0 }
        if let st = v as? LaneState { return st == .unknown }
        return false
    }

    func testTodaPropriedadeDoLaneSnapshotEPreenchidaPorUmFrameCompleto() {
        guard let l = LaneSnapshot(loom: frameCompleto) else {
            return XCTFail("o frame completo tem de decodificar")
        }
        let naoLidas = Mirror(reflecting: l).children
            .compactMap { $0.label }
            .filter { rotulo in
                guard let filho = Mirror(reflecting: l).children.first(where: { $0.label == rotulo })
                else { return false }
                return vazio(filho.value)
            }
        XCTAssertEqual(
            naoLidas, [],
            "estas propriedades ficaram no valor vazio com um frame COMPLETO no fio — ou o "
            + "`init?(loom:)` não as lê, ou a chave falta em `frameCompleto`. As duas hipóteses "
            + "são defeito: foi assim que 6 campos morreram atravessando Rust → Node → Swift."
        )
        // Enums cujo valor "vazio" é legítimo não entram no Mirror-check; ficam nomeados aqui.
        XCTAssertEqual(l.confidence, .exact, "procedência tem de vir do fio, não de default")
        XCTAssertNotEqual(l.approve, ApproveAffordance(approveKey: nil), "approveKey foi lido?")
    }

    /// 🚨 O detector das SEIS mortes. Um patch `{t:"state"}` que só traz `sid` e `state` é SILÊNCIO
    /// sobre todo o resto — e silêncio tem de preservar. Se a política de ausência de qualquer campo
    /// deixar cair em vez de preservar, a lane mesclada deixa de ser igual à original e isto falha.
    ///
    /// Antes do caminho único, este teste era impossível de escrever: a reconstrução campo-a-campo
    /// dentro do `FleetStateClient` tinha de ser conferida campo a campo, à mão, por quem lembrasse.
    func testPatchSilenciosoNaoPerdeNenhumCampo() {
        let c = FleetStateClient()
        c.handle(try! String(
            data: JSONSerialization.data(withJSONObject: ["t": "sessions", "sessions": [frameCompleto]]),
            encoding: .utf8
        )!)
        guard let original = c.lanes.first else { return XCTFail("o quadro cheio tem de popular") }

        // Só `sid` e `state` — o mesmo `state`, para que a igualdade seja exigível INTEIRA.
        c.handle(#"{"t":"state","sid":"loom-1","state":"waiting"}"#)

        XCTAssertEqual(
            c.lanes.first, original,
            "um patch que não fala de um campo não pode apagá-lo. Qualquer diferença aqui é um "
            + "campo cuja política de ausência degrada em vez de preservar."
        )
    }

    /// A contraprova: silêncio preserva, mas `null` EXPLÍCITO degrada. Sem esta distinção o teste
    /// acima seria satisfeito por um `?? antigo` cego, que manteria `GUIAR` numa lane que o servidor
    /// acabou de tornar somente-leitura — e foi exatamente esse o achado da review do `aceita`.
    func testNullExplicitoDegradaEmVezDePreservar() {
        let c = FleetStateClient()
        c.handle(try! String(
            data: JSONSerialization.data(withJSONObject: ["t": "sessions", "sessions": [frameCompleto]]),
            encoding: .utf8
        )!)
        XCTAssertEqual(c.lanes.first?.aceita, .redireciona)

        c.handle(#"{"t":"state","sid":"loom-1","state":"waiting","aceita":null,"loomdKind":null}"#)
        XCTAssertNil(c.lanes.first?.aceita, "`null` é o servidor dizendo que não sabe mais")
        XCTAssertNil(c.lanes.first?.loomdKind, "idem — a evidência volta a ser leitura de máquina")
        XCTAssertEqual(c.lanes.first?.usd, 12.35, "mas `usd` é fato do passado: continua lá")
    }

    /// ✅ A dívida do `isAbsent`, saldada — e a asserção que importa é a TERCEIRA.
    ///
    /// Enquanto a ausência era lida da prosa, a capacidade da tela dependia da redação de uma
    /// string em português. O conserto não é só passar a ler o campo: é o campo VENCER o texto.
    /// Um servidor que declara "esta lane existe" não pode ser contradito por uma frase que ele
    /// mesmo escreveu — senão a dedução continua viva, só que escondida atrás de um `??`.
    func testAusenciaVemDoCampoDeclarado_eOCampoVenceAProsa() {
        let prosa = "sessão não existe no tmux"

        // 1. Sem declaração (cockpit antigo): a prosa ainda serve de ponte.
        let velho = LaneSnapshot(loom: ["sid": "grok-cli2", "state": "exited", "detail": prosa])!
        XCTAssertNil(velho.ausenteDeclarada)
        XCTAssertTrue(velho.isAbsent, "sem o campo, a prosa é a única fonte que resta")

        // 2. Declarado `true`: sem depender de texto nenhum.
        let dito = LaneSnapshot(loom: ["sid": "grok-cli2", "state": "exited", "detail": "", "ausente": true])!
        XCTAssertTrue(dito.isAbsent, "declarado basta — nenhuma frase precisa ser reconhecida")

        // 3. 🚨 Declarado `false` COM a prosa presente: o campo vence.
        let contradito = LaneSnapshot(loom: ["sid": "grok-cli2", "state": "exited", "detail": prosa, "ausente": false])!
        XCTAssertFalse(
            contradito.isAbsent,
            "o servidor disse que a lane EXISTE; a frase é para o operador ler, não para a tela "
            + "contradizer o servidor. Se isto falhar, a dedução por prosa continua viva."
        )
    }
}
