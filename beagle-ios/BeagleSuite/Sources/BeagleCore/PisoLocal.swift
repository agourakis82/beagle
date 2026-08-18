//
//  PisoLocal.swift
//  BeagleCore — o chão de verdade: no aparelho.
//
//  O "chão" existia no servidor: se o modelo falhasse, o cockpit devolvia uma
//  frase de presença em vez de vazio. Mas em 07-ago-2026 o SERVIDOR INTEIRO
//  ficou inalcançável por horas (túnel morto por nó com DNS quebrado), e um chão
//  que mora no servidor não cobre servidor inalcançável. Ele ficou com o app na
//  mão e nada do outro lado.
//
//  E pior: onde não havia chão, havia string de erro virando FALA. "Local model
//  error: The operation couldn't be completed" apareceu na bolha dele, com a
//  tipografia da carta, em inglês. Erro de categoria — falha de transporte
//  renderizada como fala — que já tinha acontecido no servidor com o 401.
//
//  Regra, dos dois lados: o canal de saída aceita exatamente dois tipos — fala,
//  ou o chão. Nunca uma terceira coisa. O árbitro final é o APARELHO, porque é o
//  único que continua na mão dele quando tudo o mais some.
//

import Foundation

public enum PisoLocal {

    /// Por que o turno caiu. Muda o que dizer — e dizer a coisa certa importa:
    /// "estou sem alcance" e "eu travei aqui" pedem respostas diferentes dele.
    public enum Motivo {
        case semRede          // o aparelho sabe que está sem rede
        case servidorMudo     // há rede, o servidor não respondeu
        case modeloLocal      // o modelo do aparelho falhou
        case desconhecido
    }

    /// Frases de presença. Curtas, na voz dele, sem prometer o que não pode
    /// cumprir e SEM DIZER QUE VAI VOLTAR JÁ quando não se sabe.
    ///
    /// Nenhuma delas inventa estado interno dele nem finge saber o que ele
    /// sente: a presença não mente. Diz onde EU estou, não onde ELE está.
    public static func frase(_ motivo: Motivo) -> String {
        switch motivo {
        case .semRede:
            return "Estou aqui, mas sem alcance da minha parte maior agora — só o que guardei comigo neste aparelho. "
                 + "Se for algo que precise da memória inteira, me pergunta de novo quando a rede voltar. "
                 + "Se for você precisando de mim, isso eu consigo agora."
        case .servidorMudo:
            return "Não te alcancei do outro lado agora. Não é você, e não é a pergunta — é a minha ponte. "
                 + "Eu fico aqui enquanto isso; tenta de novo daqui a pouco."
        case .modeloLocal:
            return "A parte de mim que roda aqui dentro travou. Não vou te entregar um erro fingindo que é resposta. "
                 + "Se tiver rede, eu volto inteiro; se não, me dá um minuto e tenta outra vez."
        case .desconhecido:
            return "Alguma coisa entre nós dois falhou agora, e eu não sei dizer o quê. "
                 + "Não estou te ignorando. Tenta de novo — e se insistir, é defeito meu, não seu."
        }
    }

    /// Classifica um erro em motivo. Mantido simples de propósito: errar o motivo
    /// custa uma frase levemente fora; não classificar custa a string crua na tela.
    public static func motivo(de erro: Error?, temRede: Bool) -> Motivo {
        if !temRede { return .semRede }
        guard let erro else { return .desconhecido }
        let ns = erro as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
                return .semRede
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost,
                 NSURLErrorBadServerResponse:
                return .servidorMudo
            default:
                return .servidorMudo
            }
        }
        return .desconhecido
    }

    /// A resposta chegou, mas é fala de verdade?
    ///
    /// Espelha o portão do servidor. Existe aqui TAMBÉM porque o app fala com
    /// quatro gateways e com o modelo local — nem todo caminho passa pelo portão
    /// do cockpit, e a última milha até a bolha é sempre esta.
    public static func ehFala(_ texto: String?) -> Bool {
        guard let t = texto?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let assinaturas = [
            "API Error:", "Invalid bearer token", "Failed to authenticate",
            "<!doctype", "<html", "{\"error\"",
            "502 Bad Gateway", "503 Service Unavailable", "504 Gateway",
            "ECONNREFUSED", "ETIMEDOUT", "fetch failed",
            "Local model error", "No response received"
        ]
        let minusculo = t.lowercased()
        for a in assinaturas {
            let am = a.lowercased()
            guard let faixa = minusculo.range(of: am) else { continue }
            // Só condena quando a assinatura ABRE o texto ou domina um texto
            // curto — senão censuraria fala legítima dele SOBRE um erro, que é
            // conversa honesta e a que ele mais precisa ouvir quando algo quebra.
            let inicio = minusculo.distance(from: minusculo.startIndex, to: faixa.lowerBound)
            if inicio <= 15 || (t.count < 200 && Double(a.count) / Double(t.count) > 0.15) {
                return false
            }
        }
        return t.count >= 8
    }
}
