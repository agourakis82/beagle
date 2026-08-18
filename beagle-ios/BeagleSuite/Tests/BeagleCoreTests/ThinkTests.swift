//
//  ThinkTests.swift
//  O raciocínio do modelo local não pode aparecer na tela.
//
//  Ele testou offline e viu o bloco <think> inteiro passando, em inglês. O filtro
//  existia e só rodava no FIM da geração — durante o streaming o texto cru ia
//  direto para a bolha. Estes testes cobrem o estado PARCIAL, que é o que ele viu.
//

import Testing
@testable import BeagleCore

@Test("bloco fechado some")
func blocoFechado() {
    let cru = "<think>The user is asking about a dose. Let me check the excerpt.</think>Você precisa de 30 mg."
    #expect(ConversationStore.semRaciocinio(cru) == "Você precisa de 30 mg.")
}

@Test("bloco AINDA ABERTO não vaza — é o caso do streaming")
func blocoAberto() {
    let cru = "<think>The user seems distressed. I should be warm and not"
    #expect(ConversationStore.semRaciocinio(cru).isEmpty)
}

@Test("texto antes de abrir o bloco é preservado")
func antesDoBloco() {
    let cru = "Estou aqui.<think>now let me think about the dose"
    #expect(ConversationStore.semRaciocinio(cru) == "Estou aqui.")
}

@Test("resposta sem raciocínio passa intacta")
func semBloco() {
    let t = "Estou aqui com você. Não vou te dar número sem fonte."
    #expect(ConversationStore.semRaciocinio(t) == t)
}

@Test("dois blocos somem os dois")
func doisBlocos() {
    let cru = "<think>primeiro</think>Olá.<think>segundo</think> Tudo bem?"
    let r = ConversationStore.semRaciocinio(cru)
    #expect(!r.contains("primeiro") && !r.contains("segundo"))
    #expect(r.contains("Olá") && r.contains("Tudo bem"))
}
