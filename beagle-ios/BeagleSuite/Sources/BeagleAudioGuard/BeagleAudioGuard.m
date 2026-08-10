#import "BeagleAudioGuard.h"

NSString * const BeagleAudioGuardDominio = @"dev.sounio.audio";

BOOL BeagleExecutarProtegido(void (^bloco)(void), NSError * _Nullable * _Nullable erro) {
    @try {
        bloco();
        return YES;
    }
    @catch (NSException *e) {
        if (erro) {
            NSString *descricao = [NSString stringWithFormat:@"%@ — %@",
                                   e.name ?: @"NSException",
                                   e.reason ?: @"(sem motivo)"];
            // A pilha é o que faltava: sem o log do aparelho, ela é a única
            // forma de saber QUAL chamada lançou.
            NSArray<NSString *> *pilha = e.callStackSymbols ?: @[];
            *erro = [NSError errorWithDomain:BeagleAudioGuardDominio
                                        code:1
                                    userInfo:@{
                NSLocalizedDescriptionKey: descricao,
                @"pilha": [pilha subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)8, pilha.count))]
            }];
        }
        return NO;
    }
}
