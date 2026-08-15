//
//  PresencaSnapshotTests.swift
//  BeagleCoreTests — o plano de dados local que o widget lê
//
//  O widget NÃO faz rede. Ele lê um instantâneo escrito pelo app no App Group.
//  Estes testes cobrem as três formas de esse plano falhar em silêncio:
//  arquivo ausente, arquivo corrompido, e — a pior — fato velho servido como
//  se fosse de agora.
//

import Testing
import Foundation
@testable import BeagleCore

@Suite("PresencaSnapshot")
struct PresencaSnapshotTests {

    private let agora = Date(timeIntervalSinceReferenceDate: 1_000_000)

    // MARK: - Procedência POR FATO

    @Test("fato sem valor é ausência, não zero")
    func semValorEhAusencia() {
        let f = Fato<Double>(valor: nil, observadoEm: agora)
        #expect(f.procedencia(agora: agora) == nil)
        #expect(f.valor == nil)
    }

    @Test("fato medido agora é observado")
    func medidoAgoraEhObservado() {
        let f = Fato(valor: 58.0, observadoEm: agora.addingTimeInterval(-60))
        #expect(f.procedencia(agora: agora) == .observed)
    }

    @Test("fato sem carimbo de tempo é declarado, nunca observado")
    func semCarimboEhDeclarado() {
        let f = Fato(valor: 58.0, observadoEm: nil)
        #expect(f.procedencia(agora: agora) == .declared)
    }

    @Test("fato velho passa a stale — 'não sei' não pode virar 'está assim'")
    func velhoViraStale() {
        let velho = agora.addingTimeInterval(-(PresencaSnapshot.validade + 1))
        let f = Fato(valor: 58.0, observadoEm: velho)
        #expect(f.procedencia(agora: agora) == .stale)
    }

    @Test("a fronteira exata da validade ainda conta como observado")
    func fronteiraEhObservado() {
        let naBorda = agora.addingTimeInterval(-PresencaSnapshot.validade)
        let f = Fato(valor: 58.0, observadoEm: naBorda)
        #expect(f.procedencia(agora: agora) == .observed)
    }

    @Test("cada fato envelhece SOZINHO — o instantâneo não tem uma idade só")
    func cadaFatoEnvelheceSozinho() {
        let s = PresencaSnapshot(
            geradoEm: agora,
            corpo: Fato(valor: 58.0, observadoEm: agora.addingTimeInterval(-4 * 3600)),
            ceu: Fato(valor: "calmo", observadoEm: agora.addingTimeInterval(-60)),
            fluxo: Fato(valor: "FLOW", observadoEm: nil),
            capturasPendentes: 2
        )
        #expect(s.corpo.procedencia(agora: agora) == .stale)
        #expect(s.ceu.procedencia(agora: agora) == .observed)
        #expect(s.fluxo.procedencia(agora: agora) == .declared)
    }

    // MARK: - Ida e volta pelo disco

    @Test("ida e volta preserva valores e carimbos")
    func idaEVolta() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loja = PresencaSnapshotStore(diretorio: dir)

        let original = PresencaSnapshot(
            geradoEm: agora,
            corpo: Fato(valor: 58.0, observadoEm: agora.addingTimeInterval(-120)),
            ceu: Fato(valor: "tempestade", observadoEm: agora),
            fluxo: Fato(valor: "STRESS", observadoEm: nil),
            capturasPendentes: 3
        )
        try loja.escrever(original)
        let lido = loja.ler()

        #expect(lido?.corpo.valor == 58.0)
        #expect(lido?.ceu.valor == "tempestade")
        #expect(lido?.fluxo.valor == "STRESS")
        #expect(lido?.capturasPendentes == 3)
        #expect(lido?.corpo.observadoEm?.timeIntervalSince1970
                == original.corpo.observadoEm?.timeIntervalSince1970)
    }

    @Test("arquivo ausente devolve nil — o widget desenha 'sem notícia', não zero")
    func ausenteDevolveNil() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PresencaSnapshotStore(diretorio: dir).ler() == nil)
    }

    @Test("arquivo corrompido devolve nil em vez de estourar")
    func corrompidoDevolveNil() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loja = PresencaSnapshotStore(diretorio: dir)
        try Data("isto não é json".utf8).write(to: loja.arquivo)
        #expect(loja.ler() == nil)
    }

    @Test("escrita é atômica: nunca existe um arquivo pela metade")
    func escritaAtomica() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loja = PresencaSnapshotStore(diretorio: dir)

        try loja.escrever(PresencaSnapshot(geradoEm: agora, capturasPendentes: 1))
        try loja.escrever(PresencaSnapshot(geradoEm: agora, capturasPendentes: 9))

        // Sobrescrever tem que deixar UM arquivo válido, não dois nem um truncado.
        let restos = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(restos.count == 1)
        #expect(loja.ler()?.capturasPendentes == 9)
    }

    @Test("instantâneo vazio é legítimo — ainda não sei nada NÃO é erro")
    func vazioEhLegitimo() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loja = PresencaSnapshotStore(diretorio: dir)
        try loja.escrever(PresencaSnapshot(geradoEm: agora))
        let lido = loja.ler()
        #expect(lido != nil)
        #expect(lido?.corpo.valor == nil)
        #expect(lido?.capturasPendentes == 0)
    }

    // MARK: - Compatibilidade de formato

    @Test("campo novo desconhecido não invalida um instantâneo antigo")
    func formatoTolerante() throws {
        let dir = try pastaTemporaria()
        defer { try? FileManager.default.removeItem(at: dir) }
        let loja = PresencaSnapshotStore(diretorio: dir)
        // Um app mais NOVO escreveu; um widget mais VELHO lê. Acontece de verdade:
        // o iOS não atualiza app e extensão no mesmo instante.
        let json = """
        {"geradoEm": 1000000, "capturasPendentes": 4, "campoQueAindaNaoExiste": true}
        """
        try Data(json.utf8).write(to: loja.arquivo)
        #expect(loja.ler()?.capturasPendentes == 4)
    }

    private func pastaTemporaria() throws -> URL {
        let d = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("presenca-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}
