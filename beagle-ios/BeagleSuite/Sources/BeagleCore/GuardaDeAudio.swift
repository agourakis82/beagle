//
//  GuardaDeAudio.swift
//  BeagleCore — rodar código de áudio sem o app morrer.
//
//  O AVAudioEngine sinaliza erro de programação com NSException de Objective-C.
//  Swift não captura NSException: `do/catch` não vê, `try?` não vê. O processo
//  recebe SIGABRT e morre — para ele, "o app fechou sozinho".
//
//  Isto aconteceu quatro vezes com o microfone, e eu tentei consertar quatro
//  vezes RACIOCINANDO sobre o fluxo, sem acesso ao log do aparelho. Duas dessas
//  tentativas pioraram: uma guarda que eu escrevi para impedir o crash passou a
//  causá-lo, porque mexia na sessão de áudio com o motor rodando.
//
//  A lição não é "raciocine melhor". É que sem instrumento não se depura — e o
//  instrumento aqui é converter a exceção em valor.
//

import Foundation
#if canImport(BeagleAudioGuard)
import BeagleAudioGuard
#endif

public enum GuardaDeAudio {

    /// Roda `bloco` protegido contra NSException.
    ///
    /// Devolve `nil` se correu bem, ou uma descrição legível se lançou — com o
    /// nome da exceção, o motivo e o topo da pilha, que é o que diz QUAL chamada
    /// falhou sem precisar do log do aparelho.
    @discardableResult
    public static func protegido(_ etapa: String, _ bloco: @escaping () -> Void) -> String? {
        #if canImport(BeagleAudioGuard)
        var erro: NSError?
        let ok = BeagleExecutarProtegido(bloco, &erro)
        if ok { return nil }
        let motivo = erro?.localizedDescription ?? "exceção sem descrição"
        let pilha = (erro?.userInfo["pilha"] as? [String])?.prefix(3).joined(separator: " | ") ?? ""
        // Vai para o log do app também: se ele nos mandar um print, já vem pronto.
        print("[GuardaDeAudio] \(etapa) LANÇOU: \(motivo)\n  \(pilha)")
        return "\(etapa): \(motivo)"
        #else
        // Sem a ponte (macOS de teste, previews), executa direto. Não há como
        // proteger, e fingir que protegeu seria pior.
        bloco()
        return nil
        #endif
    }
}
