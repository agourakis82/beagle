//
//  PisoTests.swift
//  O chão do aparelho e o portão da última milha.
//
//  O teste que mais importa continua sendo o NEGATIVO: fala legítima dele SOBRE
//  um erro não pode ser censurada. Quando algo quebra, admitir a quebra é a coisa
//  mais honesta que ele faz — e seria exatamente o que um portão ingênuo apagaria.
//

import Testing
import Foundation
@testable import BeagleCore

@Test("string de erro NÃO é fala")
func erroNaoEhFala() {
    #expect(!PisoLocal.ehFala("Failed to authenticate. API Error: 401 Invalid bearer token"))
    #expect(!PisoLocal.ehFala("Local model error: The operation couldn't be completed"))
    #expect(!PisoLocal.ehFala("No response received."))
    #expect(!PisoLocal.ehFala("<html><title>502 Bad Gateway</title></html>"))
    #expect(!PisoLocal.ehFala(""))
    #expect(!PisoLocal.ehFala(nil))
}

@Test("fala legítima dele SOBRE um erro passa")
func falaSobreErroPassa() {
    let t = "Aquilo que você viu na tela ontem, o 401, era eu mandando um texto de guarda "
        + "no lugar da credencial. O servidor recusou e o erro virou a minha fala. "
        + "A culpa é minha, não sua, e já está consertado."
    #expect(PisoLocal.ehFala(t))
}

@Test("fala curta e humana passa")
func falaCurtaPassa() {
    #expect(PisoLocal.ehFala("Estou aqui com você."))
}

@Test("sem rede tem frase própria, e ela não promete voltar já")
func semRede() {
    let f = PisoLocal.frase(.semRede)
    #expect(f.contains("sem alcance"))
    #expect(!f.lowercased().contains("já volto"))
}

@Test("cada motivo tem frase distinta — dizer a coisa certa importa")
func motivosDistintos() {
    let fs = [PisoLocal.frase(.semRede), PisoLocal.frase(.servidorMudo),
              PisoLocal.frase(.modeloLocal), PisoLocal.frase(.desconhecido)]
    #expect(Set(fs).count == 4)
    for f in fs { #expect(f.count > 60) }        // presença, não bilhete seco
}

@Test("sem rede vence qualquer erro na classificação")
func semRedeVence() {
    let erro = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
    #expect(PisoLocal.motivo(de: erro, temRede: false) == .semRede)
    #expect(PisoLocal.motivo(de: erro, temRede: true) == .servidorMudo)
}

@Test("nenhuma frase do chão é reprovada pelo próprio portão")
func chaoPassaNoPortao() {
    for m in [PisoLocal.Motivo.semRede, .servidorMudo, .modeloLocal, .desconhecido] {
        #expect(PisoLocal.ehFala(PisoLocal.frase(m)), "o chão não pode se autocensurar")
    }
}
