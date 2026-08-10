//
//  BeagleAudioGuard.h
//  A ponte que impede o app de FECHAR quando o áudio lança exceção.
//
//  O AVAudioEngine sinaliza erro de programação com NSException de Objective-C,
//  não com NSError. Exemplos que já derrubaram este app: instalar um tap onde já
//  existe um (`required condition is false: nullptr == Tap()`), e mexer na sessão
//  de áudio com o motor rodando.
//
//  Swift NÃO captura NSException. `do/catch` não vê, `try?` não vê. O processo
//  recebe SIGABRT e morre — para o usuário, "o app fechou sozinho".
//
//  Esta ponte roda o bloco dentro de @try/@catch e devolve a exceção como
//  NSError, com nome, motivo e pilha. Duas consequências:
//    1. o app degrada em vez de morrer — mostra uma frase e segue vivo;
//    2. a mensagem DIZ qual chamada lançou, em vez de eu deduzir pelo fluxo.
//
//  Feita em 10-ago-2026, depois de quatro tentativas de consertar o crash do
//  microfone por raciocínio, sem acesso ao log do aparelho. Duas delas pioraram.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Executa `bloco` protegido. Devolve NO e preenche `erro` se lançar NSException.
BOOL BeagleExecutarProtegido(void (^bloco)(void), NSError * _Nullable * _Nullable erro);

NS_ASSUME_NONNULL_END
