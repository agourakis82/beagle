import Testing
import BeagleCore
import Foundation

// Quando o app deve PARAR e perguntar quando o estado aconteceu.
//
// Os positivos abaixo são frases REAIS do corpus dele, colhidas dos auto-relatos que o funil da
// Fase 2 já classificou com canal. Fixture inventada não provaria nada: o detector existe para
// casar com o jeito que ele escreve, não com o jeito que eu imagino que alguém escreve.
//
// O custo dos dois erros é assimétrico e por isso o detector é generoso:
//   falso positivo  -> um toque a mais numa mensagem que não era relato;
//   falso negativo  -> um relato entra SEM instante, fica inelegível sob a `direcao-v2`, e o
//                      funil continua em zero. É o defeito que isto conserta.

@Test func relatosReaisDoCorpusPedemInstante() {
    // Todas estas produziram auto-relato com canal no banco.
    #expect(RelatoDeEstado.pareceRelato("Estou ansioso hj"))
    #expect(RelatoDeEstado.pareceRelato("acordei com o peito apertado"))
    #expect(RelatoDeEstado.pareceRelato("Hoje passei o dia com vontade de chorar,"))
    #expect(RelatoDeEstado.pareceRelato("Estou meio cansado"))
    #expect(RelatoDeEstado.pareceRelato("Um pouco de angústia"))
    #expect(RelatoDeEstado.pareceRelato("Estou angustiado hoje….peito apertado."))
    #expect(RelatoDeEstado.pareceRelato("Estou ansioso com o Madaros, o compilador."))
}

@Test func acentoNaoDecideNada() {
    // "angústia" e "angustia" são a mesma palavra para quem digita rápido no celular. Um
    // detector sensível a acento perderia metade dos relatos por causa de um til.
    #expect(RelatoDeEstado.pareceRelato("Estou com angustia"))
    #expect(RelatoDeEstado.pareceRelato("Estou com angústia"))
    #expect(RelatoDeEstado.pareceRelato("to exausto"))
    #expect(RelatoDeEstado.pareceRelato("tô exausto"))
}

@Test func conversaNormalNaoEInterrompida() {
    // O preço de errar aqui é atrito em toda mensagem — e app que atrapalha deixa de ser usado.
    // O dado que ele não coleta é o dado que não existe.
    #expect(!RelatoDeEstado.pareceRelato("bom dia"))
    #expect(!RelatoDeEstado.pareceRelato("me mostra o funil"))
    #expect(!RelatoDeEstado.pareceRelato("roda o julgamento agora"))
    #expect(!RelatoDeEstado.pareceRelato("qual o estado do cluster?"))
    #expect(!RelatoDeEstado.pareceRelato(""))
}

@Test func estadoDE_OUTRA_pessoaNaoPedeOInstanteDELE() {
    // A guarda de sujeito do servidor já recusa auto-relato cujo sujeito não é o falante — foram
    // 27 desmarcados por isso. Não faz sentido a interface perguntar quando aconteceu um estado
    // que nem vai virar auto-relato.
    #expect(!RelatoDeEstado.pareceRelato("o paciente estava com dor forte"))
    #expect(!RelatoDeEstado.pareceRelato("ela ficou cansada da viagem"))
}

@Test func oVocabularioTECNICO_dele_naoDisparaNada() {
    // Estes NAO sao hipoteticos: a primeira versao do detector, com busca por substring,
    // disparava em TODOS eles. Ele fala de servidor, computador e cluster o dia inteiro — um app
    // que pergunta "quando esse estado aconteceu?" toda vez que um pod cai seria abandonado na
    // primeira hora, e o dado que ele nao coleta e o dado que nao existe.
    #expect(!RelatoDeEstado.pareceRelato("meu servidor caiu"))        // servi_dor_
    #expect(!RelatoDeEstado.pareceRelato("meu computador travou"))    // computa_dor_
    #expect(!RelatoDeEstado.pareceRelato("meu cluster está normal"))  // nor_mal_
    #expect(!RelatoDeEstado.pareceRelato("eu também acho"))           // tam_bem_
    #expect(!RelatoDeEstado.pareceRelato("minha branch tá com conflito"))
    #expect(!RelatoDeEstado.pareceRelato("sobe o serving na a5000"))
    #expect(!RelatoDeEstado.pareceRelato("o build está lento"))
}

@Test func relatoELIPTICO_semEu_tambemConta() {
    // Ele escreve assim, e a frase nao tem "eu" nenhum. A construcao `com <estado>` e o que
    // distingue quem SENTE de quem explica — baixar a regua por tamanho da mensagem seria mais
    // simples e faria "dor de cabeca e sintoma comum" disparar.
    #expect(RelatoDeEstado.pareceRelato("Melhorou hoje… mas ainda com sono"))
    #expect(RelatoDeEstado.pareceRelato("Hoje está pior, com muita raiva"))
    #expect(RelatoDeEstado.pareceRelato("Um pouco de angústia"))
}

@Test func terceiroVETA_mesmoComPalavraInequivoca() {
    // O veto de terceiro vem ANTES dos inequivocos. Testar os inequivocos primeiro deixava
    // "o residente estava exausto" passar — e o servidor recusaria esse auto-relato de qualquer
    // jeito, pela guarda de sujeito. Perguntar o instante de um estado alheio e atrito por nada.
    #expect(!RelatoDeEstado.pareceRelato("o residente estava exausto"))
    #expect(!RelatoDeEstado.pareceRelato("meu paciente estava com dor"))
    // Mas se ELE tambem esta na frase, com verbo proprio, volta a valer.
    #expect(RelatoDeEstado.pareceRelato("o paciente piorou e eu fiquei exausto"))
}

@Test func precisaDasDUAScoisas() {
    // Marcador de estado SEM primeira pessoa não basta, e vice-versa. Exigir as duas é o que
    // separa "estou com dor" de "dor de cabeça é sintoma comum".
    #expect(!RelatoDeEstado.pareceRelato("dor de cabeça é sintoma comum de desidratação"))
    #expect(!RelatoDeEstado.pareceRelato("eu vou ao mercado depois"))
}

@Test func canaisDaFase2estaoTodosCobertos() {
    // O vocabulário espelha os canais fechados que a extração reconhece. Um canal sem marcador
    // aqui seria um canal cujos relatos nunca ganham instante — e portanto nunca entram no
    // confronto, por mais que a fila drene.
    #expect(RelatoDeEstado.pareceRelato("estou agitado"))       // arousal
    #expect(RelatoDeEstado.pareceRelato("me sinto triste"))      // valence
    #expect(RelatoDeEstado.pareceRelato("estou com dor"))        // pain
    #expect(RelatoDeEstado.pareceRelato("estou exausto"))        // fatigue
    #expect(RelatoDeEstado.pareceRelato("dormi mal"))            // sleep
    #expect(RelatoDeEstado.pareceRelato("estou de plantao"))     // oncall
}

@Test func relatoDeSONO_eReconhecido() {
    // Relato de sono e RETROSPECTIVO: o estado foi na noite anterior, nunca no instante da fala.
    // Isto existe por um veredito real — "Dormi sim, estava cansado ontem" foi declarado com a
    // ancora "agora" (11h10 da manha, o padrao mais facil de tocar), o join perguntou ao corpo
    // naquela janela e achou n_samples = 0: as 11h ele estava acordado. INELEGIVEL por falta de
    // medida, com o instante tecnicamente honesto e semanticamente errado.
    #expect(RelatoDeEstado.pareceSono("Dormi sim, estava cansado ontem"))
    #expect(RelatoDeEstado.pareceSono("acordei com o peito apertado"))
    #expect(RelatoDeEstado.pareceSono("não consegui dormir, insônia de novo"))
    #expect(RelatoDeEstado.pareceSono("passei a madrugada acordado"))
}

@Test func oQueNAOeSonoNaoGanhaAncoraDeNoite() {
    // Oferecer "ontem a noite" num relato de dor de agora seria empurrar a hora errada.
    #expect(!RelatoDeEstado.pareceSono("estou com dor de cabeça"))
    #expect(!RelatoDeEstado.pareceSono("estou ansioso com o compilador"))
}
