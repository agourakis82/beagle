//
//  VetorDeEmocaoTests.swift
//  BeagleCoreTests — o vetor que dirige a voz
//
//  O risco aqui não é errar uma conta: é FABRICAR emoção. Um vetor montado pela
//  metade faria o companion encenar um estado que ninguém mediu, com a voz dele.
//

import Testing
import Foundation
@testable import BeagleCore

@Suite("VetorDeEmocao")
struct VetorDeEmocaoTests {

    private let quando = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("faltando QUALQUER eixo não há vetor — meia medida não vira emoção")
    func meiaMedidaNaoVira() {
        #expect(VetorDeEmocao.de(valencia: nil, readiness: 0.8, medidoEm: quando) == nil)
        #expect(VetorDeEmocao.de(valencia: -0.5, readiness: nil, medidoEm: quando) == nil)
        #expect(VetorDeEmocao.de(valencia: -0.5, readiness: 0.8, medidoEm: nil) == nil)
    }

    @Test("ativação é o INVERSO da prontidão: recuperado é calmo, tensionado é aceso")
    func ativacaoEhInversoDaProntidao() {
        let calmo = VetorDeEmocao.de(valencia: 0.2, readiness: 0.9, medidoEm: quando)
        let aceso = VetorDeEmocao.de(valencia: 0.2, readiness: 0.1, medidoEm: quando)
        // Comparar por PROXIMIDADE: 1.0 - 0.9 dá 0.09999999999999998 em ponto
        // flutuante. Igualdade exata de decimal aqui testaria a IEEE-754, não a
        // regra — e reprovaria um código correto.
        #expect(abs((calmo?.ativacao ?? -1) - 0.1) < 1e-9)
        #expect(abs((aceso?.ativacao ?? -1) - 0.9) < 1e-9)
    }

    @Test("os eixos são aparados na faixa — nada de valência 7")
    func eixosAparados() {
        let v = VetorDeEmocao(valencia: 7, ativacao: -3, medidoEm: quando)
        #expect(v.valencia == 1)
        #expect(v.ativacao == 0)
    }

    @Test("o corpo JSON leva os três campos que o servidor espera")
    func corpoJSON() {
        let v = VetorDeEmocao(valencia: -0.6, ativacao: 0.8, medidoEm: quando)
        let c = v.corpoJSON
        #expect(c["valencia"] as? Double == -0.6)
        #expect(c["ativacao"] as? Double == 0.8)
        #expect((c["medido_em"] as? String)?.isEmpty == false)
    }

    @Test("o carimbo é preservado — é ele que o servidor usa para recusar medida vencida")
    func carimboPreservado() {
        let v = VetorDeEmocao.de(valencia: 0.1, readiness: 0.5, medidoEm: quando)
        #expect(v?.medidoEm == quando)
    }
}
