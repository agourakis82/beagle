//
//  MotorLocal.swift
//  BeagleCore — a fronteira entre o núcleo e o runtime de LLM local
//
//  POR QUE ESTA FRONTEIRA EXISTE
//
//  O alvo dos WIDGETS linka BeagleCore. Enquanto o LocalLLMEngine morava aqui, o
//  BeagleCore arrastava MLX, Hub e Tokenizers — e o widget herdava tudo: um
//  `BeagleWidgets.debug.dylib` de 80 MB para mostrar três linhas de texto, mais
//  três bundles de recurso aninhados que o Xcode NÃO assina dentro de extensões,
//  o que fazia a instalação no aparelho ser recusada com
//  ApplicationVerificationFailed.
//
//  Ou seja: não era só gordura. Era a causa de o app não instalar.
//
//  A inversão: o BeagleCore declara o que PRECISA (quatro membros); quem sabe
//  fazer LLM local vive noutro alvo e se REGISTRA no arranque. Assim o widget
//  linka um núcleo magro e o app continua com tudo.
//

import Foundation

/// O que o núcleo precisa de um runtime de LLM local — nada além disto.
///
/// A superfície foi medida, não inventada: é exatamente o que ConversationStore e
/// GoDeepStore chamavam. Qualquer membro a mais aqui volta a amarrar o núcleo ao
/// runtime, que é o problema que esta fronteira existe para desfazer.
@MainActor
public protocol MotorLocal: AnyObject {
    /// Há modelo carregado e pronto para responder.
    var isReady: Bool { get }
    /// Uma resposta completa. Lança se o modelo não estiver pronto ou falhar.
    func respond(to prompt: String) async throws -> String
    /// Devolve a memória. Chamado quando o app perde o primeiro plano.
    func unload()
    /// Recarrega o último modelo escolhido pelo usuário, se houver.
    func restaurarUltimoModelo() async
}

/// Onde o app deixa o motor para o núcleo encontrar.
///
/// `nil` é um estado LEGÍTIMO, não um erro: no widget, no relógio e no macOS não
/// existe runtime local, e o núcleo tem que continuar funcionando sem ele. Todo
/// consumidor trata a ausência como "não tenho modelo aqui", nunca como falha.
@MainActor
public enum MotoresLocais {
    public private(set) static weak var motor: MotorLocal?

    /// Chamado UMA vez, no arranque do app. `weak` de propósito: o registro não
    /// pode ser o dono do motor nem mantê-lo vivo depois de descarregado.
    public static func registrar(_ m: MotorLocal) { motor = m }

    /// RAM física do aparelho, em GB. Mora aqui, e não no motor, porque é
    /// `Foundation` puro — arrastar o runtime inteiro só para ler isto foi parte
    /// de como o núcleo engordou.
    public static var ramGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }
}
