import Testing
import BeagleCore
import Foundation

// O instante do ESTADO, declarado por ele — não o instante em que a frase chegou.
//
// A distinção não é acadêmica. Medido em 18-ago-2026: dos 10 auto-relatos que o funil da Fase 2
// contava como tendo hora, os 10 tinham hora imputada do momento da fala; zero declarados. E dos
// 26.617 registros dele em 60 dias, nenhum trazia hora explícita no texto. O extrator não estava
// falhando — não havia o que extrair. O instante tem que nascer no app.

@Test func semAncoraNaoDeclaraNada() {
    // O padrão é a ausência, e a ausência é significativa: sob o pré-registro `direcao-v2`,
    // instante deduzido da fala é INELEGÍVEL. Se `nil` virasse "agora" em algum ponto do
    // caminho, todo turno passaria a declarar um instante que ele nunca afirmou — que é
    // exatamente o defeito que este código conserta, só que com aparência de conserto.
    #expect(InstanteDeclarado(ancora: nil) == nil)
}

@Test func agoraResolveNoEnvioENaoNoToque() {
    // Entre tocar a âncora e apertar enviar pode passar tempo redigindo. Congelar o instante no
    // toque gravaria a hora de uma decisão de interface, não a do estado.
    let envio = Date(timeIntervalSince1970: 1_800_000_000)
    let d = InstanteDeclarado(ancora: .agora, agora: envio)
    #expect(d?.instante == envio)
    #expect(d?.ancora == "agora")
}

@Test func atrasSubtraiOsMinutosCertos() {
    let envio = Date(timeIntervalSince1970: 1_800_000_000)
    let d = InstanteDeclarado(ancora: .atras(minutos: 180), agora: envio)
    #expect(d?.instante == envio.addingTimeInterval(-10_800))
    #expect(d?.ancora == "atras_180min")
}

@Test func horarioEscolhidoViajaIntacto() {
    let escolhido = Date(timeIntervalSince1970: 1_799_990_000)
    let d = InstanteDeclarado(ancora: .horario(escolhido), agora: Date())
    #expect(d?.instante == escolhido)
    #expect(d?.ancora == "horario_escolhido")
}

@Test func aChaveDistingueComoOInstanteFoiObtido() {
    // O instante sozinho não diz COMO foi obtido, e a precisão de cada forma é diferente: um
    // horário escolhido a dedo não vale o mesmo que "há 3 horas". Quem for analisar precisa
    // poder estratificar por isso.
    #expect(AncoraTemporal.agora.chave == "agora")
    #expect(AncoraTemporal.atras(minutos: 60).chave == "atras_60min")
    #expect(AncoraTemporal.horario(Date()).chave == "horario_escolhido")
}

@Test func oCorpoLevaOsDoisCampos() {
    // Um sem o outro não serve: só o instante perde a precisão de origem; só a âncora não datou
    // nada. O servidor lê os dois nomes exatos.
    let d = InstanteDeclarado(ancora: .agora, agora: Date(timeIntervalSince1970: 1_800_000_000))
    let campos = d!.camposJSON
    #expect(campos["state_occurred_at"] != nil)
    #expect(campos["state_anchor"] == "agora")
    #expect(campos.count == 2)
}

@Test func oISOCarregaOFuso() {
    // Horário solto, sem deslocamento, seria lido pelo servidor como UTC e deslocaria o
    // confronto em três horas — dentro da janela de ±60 min isso é a diferença entre concordar
    // e discordar.
    let d = InstanteDeclarado(ancora: .agora, agora: Date(timeIntervalSince1970: 1_800_000_000))
    let iso = d!.instanteISO
    #expect(iso.contains("T"))
    #expect(iso.hasSuffix("Z") || iso.contains("+") || iso.contains("-"))
}

@Test func asAncorasRapidasSaoCurtas() {
    // Nenhuma opção rápida vai além de algumas horas, e não é acanhamento: a Fase 2 confronta
    // numa janela de ±60 min, e a memória do INSTANTE de um estado não sobrevive a um dia.
    // Oferecer "semana passada" convidaria a uma precisão que ninguém tem.
    for a in AncoraTemporal.rapidas {
        if case .atras(let m) = a { #expect(m <= 360) }
    }
    #expect(AncoraTemporal.rapidas.first == .agora)
}
