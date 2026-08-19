//
//  RelatoDeEstado.swift
//  BeagleCore — quando o app deve exigir o instante
//
//  ## Por que existe
//
//  A `direcao-v2` só admite ao confronto com a fisiologia o relato cujo instante foi
//  **declarado**. Enquanto declarar era opcional, não acontecia: medido em 18-ago-2026, dos 10
//  auto-relatos que o funil contava como tendo hora, os 10 tinham hora imputada do momento da
//  fala. Zero declarados. O substrato elegível era zero.
//
//  Então o compositor passa a **exigir** a âncora — mas só quando o texto parece um auto-relato
//  de estado. Exigir em toda mensagem transformaria cada "bom dia" numa pergunta sobre quando, e
//  app que atrapalha deixa de ser usado; o dado que ele não coleta é o dado que não existe.
//
//  ## Duas classes de marcador, e o motivo
//
//  A primeira versão disto exigia marcador de estado **e** primeira pessoa, com busca por
//  substring. Validado contra o vocabulário real dele, quebrou dos dois lados:
//
//    "meu servidor caiu"      -> disparava, porque servi**dor** contém "dor"
//    "meu computador travou"  -> idem
//    "meu cluster está normal"-> nor**mal** contém "mal"
//    "eu também acho"         -> tam**bém** contém "bem"
//    "dor de cabeça é sintoma comum" -> **sinto**ma contém "sinto"
//    "Um pouco de angústia"   -> NÃO disparava, por não ter primeira pessoa — e é relato dele
//
//  Ele fala de servidor, computador e cluster o dia inteiro. Um detector que pede o instante do
//  estado toda vez que um pod cai seria abandonado na primeira hora.
//
//  A correção tem duas partes:
//
//  1. **Limite de palavra** em tudo. `dor` casa "dor", não "servidor".
//  2. **Marcadores inequívocos dispensam primeira pessoa.** "angústia", "exausto", "insônia" não
//     aparecem em conversa de infraestrutura; quando aparecem, são sobre ele. Já "dor", "mal",
//     "bem", "sono" são palavras comuns e continuam exigindo a marca de primeira pessoa.
//
//  ## O que este detector NÃO é
//
//  Não é o classificador de auto-relato. Quem decide se um fato é `self_report`, com qual canal e
//  de quem é o sujeito, é o servidor — com as guardas de falante e de sujeito que já existem.
//  Aqui é heurística de INTERFACE: vale a pena perguntar? Errar para mais custa um toque; errar
//  para menos custa um relato sem instante, que é o defeito que isto conserta.
//

import Foundation

public enum RelatoDeEstado {
    /// Estados que, ditos numa conversa com o companion, são sobre ele — mesmo sem "eu".
    /// "Um pouco de angústia" é relato; nenhuma delas aparece falando de cluster.
    static let inequivocos: [String] = [
        "ansios\\w*", "angusti\\w*", "aflit\\w*", "panico",
        "deprimid\\w*", "desanimad\\w*", "chorar", "choro",
        "exaust\\w*", "esgotad\\w*", "insonia", "enxaqueca",
        "plantao", "sobreaviso", "acordei", "madrugada",
        "peito apertad\\w*", "sem energia", "vontade de chorar",
    ]

    /// Palavras que TAMBÉM são do dia a dia técnico ou geral. Só contam com primeira pessoa.
    static let ambiguos: [String] = [
        "dor", "dores", "doi", "doendo",
        "mal", "bem", "triste", "feliz", "content\\w*",
        "cansad\\w*", "moid\\w*", "acabad\\w*",
        "tens\\w*", "nervos\\w*", "agitad\\w*", "acelerad\\w*", "calm\\w*", "relaxad\\w*",
        "irritad\\w*", "raiva", "sozinh\\w*", "solidao", "medo",
        "sono", "dormi", "dormindo", "sonolent\\w*",
    ]

    /// Primeira pessoa FORTE: o falante como sujeito do estado. Verbo conjugado ou "eu".
    static let primeiraPessoaForte: [String] = [
        "estou", "to", "tou", "tava", "sinto", "me sinto",
        "acordei", "dormi", "fiquei", "passei", "ando", "eu", "comigo",
    ]

    /// Possessivos. São primeira pessoa GRAMATICAL e não garantem que o estado é dele:
    /// "meu paciente", "meu servidor", "minha branch". Valem, mas cedem diante de um terceiro.
    static let possessivos: [String] = ["meu", "minha", "meus", "minhas"]

    /// Sujeitos de OUTRA pessoa. Quando aparecem, o estado provavelmente não é dele — e o
    /// servidor já recusaria esse auto-relato pela guarda de sujeito (27 fatos foram desmarcados
    /// por exatamente isso). Perguntar o instante de um estado alheio é atrito pago por nada.
    static let terceiros: [String] = [
        "paciente", "pacientes", "ele", "ela", "eles", "elas",
        "doente", "interno", "residente", "colega", "medico", "enfermeir\\w*",
    ]

    /// Minúsculas e sem acento, com locale fixo em pt-BR.
    ///
    /// Sem o locale explícito o resultado varia com a configuração do aparelho — e um detector
    /// que depende do idioma do sistema falharia justamente no aparelho dele.
    static func normaliza(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "pt_BR"))
    }

    /// Casa `padrao` como PALAVRA inteira. É o que separa "dor" de "servidor".
    static func contemPalavra(_ texto: String, _ padrao: String) -> Bool {
        texto.range(of: "\\b" + padrao + "\\b", options: [.regularExpression]) != nil
    }

    /// Vale a pena perguntar QUANDO este texto aconteceu?
    public static func pareceRelato(_ texto: String) -> Bool {
        let t = normaliza(texto)
        guard t.count >= 3 else { return false }

        let forte = primeiraPessoaForte.contains { contemPalavra(t, $0) }

        // O veto de terceiro vem ANTES de tudo, inclusive dos inequívocos. "O residente estava
        // exausto" não é relato dele por mais inequívoca que a palavra seja — e o servidor
        // recusaria esse auto-relato de qualquer jeito, pela guarda de sujeito. Testar os
        // inequívocos primeiro deixava exatamente esse caso passar.
        if terceiros.contains(where: { contemPalavra(t, $0) }) && !forte { return false }

        if inequivocos.contains(where: { contemPalavra(t, $0) }) { return true }

        guard ambiguos.contains(where: { contemPalavra(t, $0) }) else { return false }
        if forte { return true }
        if possessivos.contains(where: { contemPalavra(t, $0) }) { return true }

        // Relato ELÍPTICO: "mas ainda com sono", "com dor desde cedo". Ele escreve assim, e a
        // frase não tem "eu" nenhum.
        //
        // O gatilho é a construção `com <estado>`, não o tamanho da mensagem. Baixar a régua por
        // tamanho pareceria mais simples e faria "dor de cabeça é sintoma comum" disparar — a
        // preposição é o que distingue quem SENTE de quem explica.
        // `com muita raiva`, `com um pouco de sono`: o modificador entre a preposição e o estado
        // é comum na fala dele, e exigir adjacência perderia a frase inteira.
        return ambiguos.contains { contemPalavra(t, "com (\\w+ ){0,3}" + $0) }
    }
}
