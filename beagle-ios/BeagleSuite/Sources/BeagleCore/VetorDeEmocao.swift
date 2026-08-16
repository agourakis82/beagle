//
//  VetorDeEmocao.swift
//  BeagleCore — os dois eixos que dirigem COMO ele fala
//
//  O companion passa a dirigir a própria fala a partir de emoção MEDIDA, não
//  inferida. Dois eixos, o circumplexo clássico:
//
//    · valência  −1…+1  — HKStateOfMind, registrada por ELE. É dele.
//    · ativação    0…1  — derivada do corpo.
//
//  ATIVAÇÃO É REÚSO, NÃO INVENÇÃO. Ela sai de `readiness`, que o app já calcula e
//  já usa para o flowState (readiness alta = recuperado; baixa = tensionado).
//  Derivar um segundo "arousal" a partir de HRV cru criaria uma SEGUNDA verdade
//  sobre a mesma coisa, e aí as duas discordariam em algum plantão.
//
//  E a regra do projeto vale aqui: o que não foi medido não vira afirmação. Sem
//  os dois eixos, ou com medida vencida, não há vetor — e o servidor cai na
//  direção neutra em vez de encenar uma emoção que ninguém mediu.
//

import Foundation

public struct VetorDeEmocao: Sendable, Equatable {
    /// −1…+1. Como ELE disse que estava.
    public let valencia: Double
    /// 0…1. Quanto o corpo está ativado.
    public let ativacao: Double
    /// Quando os eixos foram medidos. O servidor recusa medida vencida.
    public let medidoEm: Date

    public init(valencia: Double, ativacao: Double, medidoEm: Date) {
        self.valencia = max(-1, min(1, valencia))
        self.ativacao = max(0, min(1, ativacao))
        self.medidoEm = medidoEm
    }

    /// `nil` quando falta qualquer eixo — ausência é ausência, e completar um
    /// vetor pela metade seria exatamente a fabricação que queremos evitar.
    public static func de(valencia: Double?, readiness: Double?, medidoEm: Date?) -> VetorDeEmocao? {
        guard let valencia, let readiness, let medidoEm else { return nil }
        // Ativação é o INVERSO da prontidão: recuperado = calmo, tensionado = aceso.
        return VetorDeEmocao(valencia: valencia, ativacao: 1.0 - readiness, medidoEm: medidoEm)
    }

    /// O corpo que vai no POST da voz. Nomes em português como o resto da rota.
    public var corpoJSON: [String: Any] {
        let iso = ISO8601DateFormatter()
        return ["valencia": valencia, "ativacao": ativacao, "medido_em": iso.string(from: medidoEm)]
    }
}
