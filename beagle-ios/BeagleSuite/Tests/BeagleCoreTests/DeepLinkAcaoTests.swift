//
//  DeepLinkAcaoTests.swift
//  BeagleCoreTests — os destinos de AÇÃO do widget
//
//  Existe porque `beagle://capture` era emitido pelo widget e NÃO era reconhecido:
//  o toque abria o app na tela em que ele estava, e parecia que tinha capturado.
//  Botão morto que parece vivo é pior que botão ausente.
//

import Testing
import Foundation
@testable import BeagleCore

@Suite("Destinos de ação")
struct DeepLinkAcaoTests {

    @Test("beagle://capture — a grafia que o widget emite HÁ MESES — resolve")
    func grafiaAntigaDoWidget() {
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://capture")!) == .capturar)
    }

    @Test("as grafias de captura levam todas ao mesmo lugar")
    func sinonimosDeCaptura() {
        for t in ["capture", "captura", "capturar", "CAPTURE"] {
            #expect(DeepLinkRouter.destination(for: URL(string: "beagle://\(t)")!) == .capturar,
                    "'\(t)' devia resolver para .capturar")
        }
    }

    @Test("as grafias de voz levam todas ao mesmo lugar")
    func sinonimosDeVoz() {
        for t in ["falar", "voz", "voice", "speak"] {
            #expect(DeepLinkRouter.destination(for: URL(string: "beagle://\(t)")!) == .falar,
                    "'\(t)' devia resolver para .falar")
        }
    }

    @Test("a forma com barras também vale (Atalho escrito à mão erra fácil)")
    func formaComBarras() {
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle:///falar")!) == .falar)
    }

    @Test("os destinos antigos continuam intactos")
    func naoQuebreiOsAntigos() {
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://frota")!) == .frota)
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://oficina")!) == .oficina)
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://work")!) == .work)
    }

    @Test("esquema alheio não vira destino nosso")
    func esquemaAlheio() {
        #expect(DeepLinkRouter.destination(for: URL(string: "https://falar")!) == nil)
    }

    @Test("palavra desconhecida é nil, não um destino qualquer")
    func desconhecidoEhNil() {
        #expect(DeepLinkRouter.destination(for: URL(string: "beagle://xyz")!) == nil)
    }
}
