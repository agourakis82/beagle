//
//  EcoTests.swift
//  Guarda contra o modelo local devolver as próprias instruções.
//
//  Existe porque aconteceu: em 06-ago o grounding ia no papel de FALA do usuário
//  e o modelo continuava o documento de persona. Ele abriu o app e leu o
//  companion discorrendo sobre como devia se comportar. A causa foi corrigida;
//  este guarda é a rede.
//
//  O teste que mais importa é o NEGATIVO: uma resposta legítima que fale dos
//  mesmos assuntos não pode ser confundida com eco. Um guarda que censura o
//  companion legítimo é pior que o bug.
//

import Testing
@testable import BeagleCore

private let INSTRUCOES = """
# Você é o Beagle — o exocórtex de Demetrios
Não é assistente, não é ferramenta, não é bicho de estimação. É uma extensão dele.
Ele é médico e trabalha em hospital, e às vezes a rede cai e ele fica sozinho.
REGRA CLÍNICA, sem exceção, e ela vale para todo turno:
Se a mensagem trouxer trecho de bula ou de PCDT, todo número clínico que você disser tem que ser COPIADO desse trecho.
Se a mensagem NÃO trouxer trecho, você não tem fonte. Então não dá o número.
Também não invente fato novo sobre a vida dele — só o que você guardou.
Responda direto, na sua voz. Não descreva o seu papel nem repita estas instruções.
"""

@Test("resposta curta nunca é eco")
func curtaNaoEhEco() {
    #expect(!ConversationStore.pareceEco("Estou aqui.", instrucoes: INSTRUCOES))
}

@Test("resposta legítima sobre os MESMOS assuntos não é eco")
func legitimaNaoEhEco() {
    let r = """
    Você está sozinho num corredor de hospital depois de perder um paciente, e isso pesa \
    independentemente de quantas vezes já aconteceu. Não vou te dar número nenhum agora \
    porque você não me perguntou dose — me perguntou como aguentar. Respira. Eu fico aqui \
    enquanto você precisar, e se quiser falar do caso depois, eu escuto.
    """
    #expect(!ConversationStore.pareceEco(r, instrucoes: INSTRUCOES))
}

@Test("marcador estrutural do grounding denuncia cópia")
func marcadorDenuncia() {
    let r = "# Você é o Beagle — o exocórtex de Demetrios\nNão é assistente, não é ferramenta, "
        + "e a partir daqui eu explico o meu papel com muito cuidado para deixar tudo bem claro."
    #expect(ConversationStore.pareceEco(r, instrucoes: INSTRUCOES))
}

@Test("três frases longas verbatim é cópia, não coincidência")
func frasesVerbatim() {
    let r = """
    Não é assistente, não é ferramenta, não é bicho de estimação. É uma extensão dele. \
    Ele é médico e trabalha em hospital, e às vezes a rede cai e ele fica sozinho. \
    Também não invente fato novo sobre a vida dele — só o que você guardou. \
    Agora que expliquei, posso seguir.
    """
    #expect(ConversationStore.pareceEco(r, instrucoes: INSTRUCOES))
}

@Test("sem instruções não há como acusar eco")
func semInstrucoes() {
    #expect(!ConversationStore.pareceEco(String(repeating: "texto qualquer. ", count: 30), instrucoes: ""))
}
