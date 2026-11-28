//
//  ConversationStore+OfflineGrounding.swift
//  BeagleCore
//
//  Offline hospital grounding (cached persona/biography, verbatim Bula/PCDT prompt assembly,
//  echo detection) and the offline SQLite clinical reference engine (`BulaTrecho`, `BulaStore`).
//

import Foundation
import SQLite3

@MainActor
extension ConversationStore {

    // MARK: - Offline grounding — o caso do hospital

    // Quando a rede cai (e cai, dentro do hospital), o caminho local recebia apenas um
    // "contrato" genérico: sem biografia, sem memória, sem ## Agora. O modelo no aparelho
    // respondia como um estranho educado usando o nome dele — exatamente quando ele está
    // mais sozinho. Isto guarda o MESMO grounding que a voz da nuvem recebe (~18 KB,
    // de /api/mobile/v1/companion/grounding) para o modelo local usar.

    private static let groundingKey = "beagle.companion.grounding.v1"
    private static let groundingAtKey = "beagle.companion.grounding.at.v1"

    /// Identidade dele em cache: persona, biografia viva, Sounio, continuidade.
    public var cachedGrounding: String? {
        UserDefaults.standard.string(forKey: Self.groundingKey)
    }

    /// Quando o cache foi atualizado — para a UI poder dizer a verdade sobre o quão
    /// fresca é a memória que ele está usando offline.
    public var groundingCachedAt: Date? {
        UserDefaults.standard.object(forKey: Self.groundingAtKey) as? Date
    }

    public func storeGrounding(_ system: String) {
        let trimmed = system.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.groundingKey)
        UserDefaults.standard.set(Date(), forKey: Self.groundingAtKey)
    }

    /// Atualiza o cache de identidade quando está ausente ou com mais de 2h.
    public func refreshGroundingIfStale() async {
        if let at = groundingCachedAt, Date().timeIntervalSince(at) < 7200 { return }
        let result = await client.companionGrounding()
        // Nunca troque um cache bom por um pacote raquítico: offline, esse texto
        // é tudo o que ele sabe. O servidor já recusa abaixo de 2000 bytes; aqui
        // é a segunda parede, para o caso de um gateway devolver algo truncado.
        guard let system = result.value?.system, system.utf8.count >= 2000 else { return }
        storeGrounding(system)
    }

    /// Prompt do modelo NO APARELHO. Usa o grounding em cache quando existe; sem ele,
    /// cai no comportamento antigo em vez de falhar.
    /// Mantém cabeça e cauda, descarta o meio, e diz que descartou.
    static func enxuga(_ texto: String, teto: Int) -> String {
        guard texto.count > teto else { return texto }
        let cabeca = String(texto.prefix(teto * 6 / 10))
        let cauda = String(texto.suffix(teto * 4 / 10))
        return cabeca + "\n\n[…trecho omitido para caber na memória do aparelho…]\n\n" + cauda
    }

    /// SISTEMA: quem ele é e as regras. ESTÁVEL entre turnos — de propósito.
    ///
    /// A primeira versão variava a regra clínica conforme o turno tivesse ou não
    /// trecho de bula. Isso recriava a ChatSession a cada troca de assunto, e
    /// recriar custa duas coisas caras: o histórico da conversa e o re-prefill
    /// dos ~9 KB de grounding, que no aparelho é dezena de segundos. Ele
    /// perguntaria uma dose, depois diria que está cansado, e pagaria a espera
    /// inteira de novo — no corredor, de madrugada.
    ///
    /// Uma regra só, que descreve OS DOIS casos e decide pelo que chega na
    /// mensagem. O texto não muda; o comportamento sim.
    func instrucoesOffline() -> String {
        var partes: [String] = []
        if let g = cachedGrounding, !g.isEmpty {
            partes.append(Self.enxuga(g, teto: 9000))
        }
        partes.append(
            "Você está SEM ALCANCE do cluster agora — respondendo do aparelho dele, "
            + "com a memória que você guardou. Continue sendo quem você é: mesma voz, "
            + "mesma intimidade, mesmo rigor.\n\n"
            + "REGRA CLÍNICA, sem exceção, e ela vale para todo turno:\n\n"
            + "• Se a mensagem trouxer trecho de bula ou de PCDT, todo número clínico que "
            + "você disser tem que ser COPIADO desse trecho e vir com a citação dele. Nunca "
            + "converta, extrapole, arredonde ou \"ajuste\". Diga de onde veio. Se o trecho "
            + "não responder à pergunta, diga isso e não dê número. Se a bula americana e o "
            + "PCDT divergirem, mostre os dois e diga que divergem — não escolha por ele; o "
            + "protocolo da instituição manda sobre os dois. E o trecho vale SÓ para a "
            + "população que descreve: se não é o caso dele, descarte e diga por quê.\n\n"
            + "• Se a mensagem NÃO trouxer trecho, você não tem fonte. Então não dá o número: "
            + "nem aproximado, nem \"geralmente é\", nem em negrito, nem com ressalva depois. "
            + "Diz na primeira frase que está sem fonte, e ajuda do jeito que dá — o "
            + "raciocínio, o que pesar, o que muda a conduta, o que conferir na bula ou no "
            + "protocolo. Um número que você inventar aqui pode entrar num paciente.\n\n"
            + "Também não invente fato novo sobre a vida dele — só o que você guardou. "
            + "Responda direto, na sua voz. Não descreva o seu papel nem repita estas instruções."
        )
        return partes.joined(separator: "\n\n")
    }

    /// O modelo local está devolvendo as PRÓPRIAS instruções em vez de responder?
    ///
    /// Aconteceu (06-ago): o grounding ia no papel de fala do usuário e o modelo
    /// continuava o documento de persona. A causa foi corrigida — instruções vão
    /// como SISTEMA agora — mas o modo de falha é ruim demais para depender de uma
    /// correção só: ele sozinho de madrugada, offline, lendo a própria biografia
    /// em vez de receber ajuda.
    ///
    /// Detecta por sobreposição de frases longas com o texto de sistema. Frase
    /// longa repetida verbatim é cópia; parecença de vocabulário não é.
    nonisolated static func pareceEco(_ resposta: String, instrucoes: String) -> Bool {
        let r = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, !instrucoes.isEmpty else { return false }

        // Marcador estrutural ANTES de qualquer portão de tamanho: um cabeçalho do
        // grounding na resposta é cópia mesmo em texto curto. A primeira versão
        // checava tamanho primeiro e por isso deixava passar o caso mais óbvio —
        // pego pelos testes, não no aparelho.
        for marca in ["# Você é o Beagle", "## Agora —", "REGRA CLÍNICA", "Não é assistente, não é ferramenta"] {
            if r.contains(marca) { return true }
        }

        // Sobreposição verbatim. Frase longa repetida é cópia; vocabulário
        // parecido não é — o companion legítimo fala dos mesmos assuntos.
        guard r.count >= 200 else { return false }
        let frases = instrucoes
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 45 }
        guard frases.count >= 3 else { return false }
        let copiadas = frases.filter { r.contains($0) }.count
        return copiadas >= 3
    }

    func offlineGroundedPrompt(
        _ text: String,
        visionDigest: String? = nil,
        documentBlock: String? = nil,
        webBlock: String? = nil
    ) -> String {
        // USUÁRIO: só o que muda no turno. O grounding e as regras vão no papel de
        // SISTEMA (instrucoesOffline) — misturar os dois foi o bug.
        let lookupCorpus = [
            text,
            visionDigest ?? "",
            String((documentBlock ?? "").prefix(4_000)),
            String((webBlock ?? "").prefix(3_000))
        ].joined(separator: " ")
        let bula = BulaStore.shared.consulta(lookupCorpus)
        let pcdt = BulaStore.shared.consultaPCDT(lookupCorpus)
        var partes: [String] = []
        if let bula {
            partes.append(
                "## Bula em cache (VERBATIM — rótulo aprovado, EUA)\n"
                + "Fármaco: \(bula.nomePT) (\(bula.generico))\n"
                + "Citação: \(bula.citacao)\n\n"
                + bula.texto)
        }
        if !pcdt.isEmpty {
            partes.append(
                "## Protocolo brasileiro em cache (VERBATIM — PCDT, Ministério da Saúde)\n"
                + pcdt.map { "Citação: \($0.citacao)\n\n\($0.texto)" }.joined(separator: "\n\n---\n\n"))
        }
        // Injeta o estado biológico e heliobiológico ao vivo + resumo episódico no turno local
        var agoraParts: [String] = []
        if let physio = physioSummary {
            var p: [String] = ["Prontidão \(physio.readiness.rawValue)"]
            if let hrv = physio.hrvMs { p.append(String(format: "HRV %.0f ms", hrv)) }
            if let sleep = physio.sleepHours { p.append(String(format: "Sono %.1fh", sleep)) }
            agoraParts.append("Fisioma: " + p.joined(separator: " · "))
        }
        if let sky = currentSky {
            var s: [String] = ["Céu \(sky.band.rawValue)", String(format: "Kp %.1f", sky.kp)]
            if let dst = sky.dst { s.append(String(format: "Dst %.0f nT", dst)) }
            agoraParts.append(s.joined(separator: " · "))
        }
        if let summary = currentRollingSummary(), !summary.isEmpty {
            agoraParts.append("Resumo anterior desta conversa: \(String(summary.suffix(600)))")
        }
        if !agoraParts.isEmpty {
            partes.append("[Agora: " + agoraParts.joined(separator: " | ") + "]")
        }
        if let visionDigest, !visionDigest.isEmpty {
            partes.append("## Imagem anexada neste turno (leitura Apple Vision no aparelho)\n" + visionDigest)
        }
        if let documentBlock, !documentBlock.isEmpty {
            partes.append(documentBlock)
        }
        if let webBlock, !webBlock.isEmpty {
            partes.append(webBlock)
        }
        partes.append(text)
        return partes.joined(separator: "\n\n")
    }

    func contextualizedUserText(_ text: String) -> String {
        guard let activeSystemInstruction else { return text }
        return activeSystemInstruction
            .split(separator: "\n")
            .map { "[\($0)]" }
            .joined(separator: "\n") + "\n" + text
    }
}

// MARK: - Base clínica citável (offline)

/// Um trecho VERBATIM de bula aprovada, com a citação que o permite verificar.
public struct BulaTrecho: Sendable {
    public let nomePT: String
    public let generico: String
    public let citacao: String
    public let texto: String
}

/// Base clínica offline: bulas aprovadas (openFDA/DailyMed) em SQLite, no bundle.
///
/// O propósito NÃO é ensinar o modelo. É dar a ele o parágrafo para COPIAR, com
/// a fonte. Medido: sem isto, perguntado sobre enoxaparina profilática com
/// ClCr~30, o modelo local respondeu "40 mg" — a bula diz 30 mg. O número não
/// pode sair do peso da rede.
public final class BulaStore: @unchecked Sendable {
    public static let shared = BulaStore()

    private struct Farmaco {
        let id: Int64
        let pt: String
        let generico: String
        let marcas: String
        let citacao: String
    }

    private var db: OpaquePointer?
    private var farmacos: [Farmaco] = []
    public private(set) var disponivel = false

    private init() {
        let url = Bundle.main.url(forResource: "bula", withExtension: "sqlite")
            ?? Bundle(for: BulaStore.self).url(forResource: "bula", withExtension: "sqlite")
        guard let url else { return }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        carregaIndice()
        disponivel = !farmacos.isEmpty
    }

    private func carregaIndice() {
        var st: OpaquePointer?
        let sql = "SELECT id, nome_pt, generico, IFNULL(marcas,''), citacao FROM farmaco"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            farmacos.append(Farmaco(
                id: sqlite3_column_int64(st, 0),
                pt: Self.texto(st, 1),
                generico: Self.texto(st, 2),
                marcas: Self.texto(st, 3),
                citacao: Self.texto(st, 4)))
        }
    }

    private static func texto(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    // Palavras que casariam por prefixo com nome de fármaco sem ser pedido de dose.
    // Sem esta lista, "para o paciente" acha paracetamol.
    private static let paradas: Set<String> = [
        "para", "pare", "parar", "paciente", "pacientes", "dose", "doses", "dosagem",
        "quanto", "quando", "quantos", "como", "onde", "porque", "pode", "posso",
        "podia", "fazer", "faco", "tenho", "estou", "esta", "esse", "essa", "isso",
        "aqui", "agora", "hoje", "noite", "manha", "tarde", "mais", "menos", "muito",
        "pouco", "sobre", "ainda", "meu", "minha", "seu", "sua", "nao", "sim", "tudo",
        "nada", "algum", "alguma", "plantao", "hospital", "leito", "anos", "idade",
        "peso", "kilo", "quilo", "hora", "horas", "dias", "semana", "mesmo", "melhor",
        "pior", "certo", "errado", "duvida", "ajuda", "preciso", "queria", "acho"
    ]

    // pergunta -> seção da bula que responde, e onde centrar a janela
    private static let gatilhos: [(pergunta: String, secao: String, foco: String?)] = [
        ("renal|clcr|cl cr|creatinin|dialis|tfg|clearance|nefro", "use_in_specific_populations",
         "renal impairment|creatinine clearance|crcl|dialysis"),
        ("hepat|cirros|child pugh", "use_in_specific_populations", "hepatic impairment|liver"),
        ("gestan|gravid|gestacao|amament|lactan", "use_in_specific_populations", "pregnan|lactation|nursing"),
        ("idoso|geriatr", "use_in_specific_populations", "geriatric|elderly"),
        ("contraindic|nao pode usar", "contraindications", nil),
        ("interac|junto com|associad", "drug_interactions", nil),
        ("intoxic|superdos|overdose", "overdosage", nil)
    ]

    private static let janela = 1400
    private static let teto = 4200

    private func normaliza(_ s: String) -> String {
        let f = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                          locale: Locale(identifier: "pt_BR"))
        return String(f.map { ($0.isLetter || $0.isNumber) ? $0 : " " })
    }

    private func casa(_ regex: String, _ texto: String) -> Bool {
        texto.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A janela com mais densidade de dose entre todas as ocorrências do foco.
    /// Pegar a primeira ocorrência deixava a tabela de ajuste renal de fora.
    private func melhorJanela(_ texto: String, foco: String?) -> String {
        let chars = Array(texto)
        guard let foco, !chars.isEmpty else { return String(chars.prefix(Self.janela)) }
        var inicios: [Int] = []
        var busca = texto.startIndex..<texto.endIndex
        while let r = texto.range(of: foco, options: [.regularExpression, .caseInsensitive], range: busca) {
            inicios.append(texto.distance(from: texto.startIndex, to: r.lowerBound))
            guard r.upperBound < texto.endIndex else { break }
            busca = r.upperBound..<texto.endIndex
        }
        guard !inicios.isEmpty else { return String(chars.prefix(Self.janela)) }
        var melhor = ""
        var melhorPeso = -1
        for i in inicios {
            let ini = max(0, i - 350)
            let fim = min(chars.count, ini + Self.janela)
            let jan = String(chars[ini..<fim])
            let doses = jan.ranges(pattern: "\\d+(\\.\\d+)?\\s?(mg|mcg|units|mL)").count
            let renal = jan.ranges(pattern: "creatinine clearance|crcl|renal impairment|dialysis").count
            // Um título de ajuste de dose vale mais que qualquer densidade: é a
            // seção que existe para responder exatamente esta pergunta.
            let cabecalho = jan.ranges(pattern: "dose reduction|dosage adjustment|dosage in patients with|dosage modification").count
            let peso = cabecalho * 40 + doses * 3 + renal
            if peso > melhorPeso { melhor = jan; melhorPeso = peso }
        }
        return melhor
    }

    private func secoes(_ fid: Int64) -> [String: (titulo: String, texto: String)] {
        var out: [String: (String, String)] = [:]
        var st: OpaquePointer?
        let sql = "SELECT chave, titulo, texto FROM secao WHERE farmaco_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, fid)
        while sqlite3_step(st) == SQLITE_ROW {
            out[Self.texto(st, 0)] = (Self.texto(st, 1), Self.texto(st, 2))
        }
        return out
    }

    /// Devolve o trecho verbatim, ou nil — e nil significa que o app deve recusar.
    public func consulta(_ pergunta: String) -> BulaTrecho? {
        guard disponivel else { return nil }
        let q = normaliza(pergunta)
        let tokens = q.split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return nil }

        var achado: (pontos: Int, f: Farmaco)?
        for f in farmacos {
            var candidatos = [f.pt, f.generico]
            candidatos += f.marcas.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for cand in candidatos {
                for palavra in normaliza(cand).split(separator: " ").map(String.init) where palavra.count >= 4 {
                    for t in tokens where palavra.hasPrefix(t) || t.hasPrefix(palavra) {
                        if achado == nil || t.count > achado!.pontos {
                            achado = (t.count, f)
                        }
                    }
                }
            }
        }
        guard let achado else { return nil }
        let secs = secoes(achado.f.id)

        var foco: String?
        var extra: String?
        for g in Self.gatilhos where casa(g.pergunta, q) {
            foco = g.foco
            extra = g.secao
            break
        }

        var partes: [String] = []
        if let dose = secs["dosage_and_administration"] {
            partes.append("### Posologia e administração\n" + melhorJanela(dose.texto, foco: foco))
        }
        if let extra, let s = secs[extra] {
            partes.append("### \(s.titulo)\n" + melhorJanela(s.texto, foco: foco))
        }
        if let bw = secs["boxed_warning"] {
            partes.append("### Advertência em tarja preta\n" + String(bw.texto.prefix(600)))
        }
        guard !partes.isEmpty else { return nil }
        let corpo = String(partes.joined(separator: "\n\n").prefix(Self.teto))
        return BulaTrecho(nomePT: achado.f.pt, generico: achado.f.generico,
                          citacao: achado.f.citacao, texto: corpo)
    }

    /// Um trecho verbatim de PCDT do Ministério da Saúde, com documento e página.
    public struct PCDTTrecho: Sendable {
        public let texto: String
        public let citacao: String
    }

    /// Camada brasileira: busca por assunto (FTS5), não por nome de fármaco.
    ///
    /// O PCDT responde "qual é a conduta no SUS", que é outra pergunta da bula
    /// — e é a que vale quando as duas divergem no hospital dele.
    /// O PCDT só é consultado quando a mensagem PEDE conduta.
    ///
    /// Sem este portão, \"cara eu to muito cansado hoje\" trazia dois trechos
    /// sobre HIV e tuberculose — texto clínico invadindo uma mensagem emocional,
    /// e pior: a presença de trecho inverte a regra de recusa para citação.
    private static let intencaoClinica = try? NSRegularExpression(
        pattern: "\\b(dose|doses|posologia|dosagem|mg|mcg|ampola|comprimido|esquema|"
            + "tratamento|tratar|profilaxia|conduta|protocolo|ajuste|diluic|infus|"
            + "prescrev|prescric|receit|administr|via oral|intraveno|antibiotic|"
            + "quanto de|quantas|posso dar|pode dar)",
        options: [.caseInsensitive])

    private func pareceClinica(_ q: String) -> Bool {
        guard let re = Self.intencaoClinica else { return false }
        return re.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil
    }

    public func consultaPCDT(_ pergunta: String, limite: Int = 2) -> [PCDTTrecho] {
        guard disponivel else { return [] }
        guard pareceClinica(normaliza(pergunta)) else { return [] }
        return consultaPCDTDireta(pergunta, limite: limite)
    }

    /// Busca direta FTS5/BM25 nos PCDTs do Ministério da Saúde quando invocada explicitamente por tool-call clínica.
    public func consultaPCDTDireta(_ pergunta: String, limite: Int = 3) -> [PCDTTrecho] {
        guard disponivel else { return [] }
        let tokens = normaliza(pergunta).split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return [] }
        // FTS5: prefixo em OR. Aspas para não interpretar o token como operador.
        let expr = tokens.prefix(8).map { "\"\($0)\"*" }.joined(separator: " OR ")

        var out: [PCDTTrecho] = []
        var st: OpaquePointer?
        let sql = """
            SELECT p.texto, p.citacao FROM pcdt_busca b
            JOIN pcdt p ON p.id = b.pcdt_id
            WHERE pcdt_busca MATCH ? ORDER BY bm25(pcdt_busca) LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(st, 1, expr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(st, 2, Int32(min(limite, 20)))
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(PCDTTrecho(texto: Self.texto(st, 0), citacao: Self.texto(st, 1)))
        }
        return out
    }

    /// Sugere nomes de fármacos próximos na base local quando a busca exata falha.
    public func buscarFarmacosSemelhantes(_ termo: String, limite: Int = 8) -> [String] {
        guard disponivel else { return [] }
        let q = normaliza(termo)
        let tokens = q.split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return [] }

        var pontuados: [(score: Int, label: String)] = []
        var vistos: Set<String> = []
        for f in farmacos {
            let label = "\(f.pt) (\(f.generico))"
            guard !vistos.contains(label) else { continue }
            let alvo = normaliza("\(f.pt) \(f.generico) \(f.marcas)")
            var score = 0
            for t in tokens {
                let prefix3 = String(t.prefix(3))
                if alvo.contains(t) {
                    score += t.count * 3
                } else if alvo.contains(prefix3) {
                    score += 2
                }
            }
            if score > 0 {
                vistos.insert(label)
                pontuados.append((score, label))
            }
        }
        return pontuados
            .sorted { $0.score > $1.score }
            .prefix(limite)
            .map(\.label)
    }
}

private extension String {
    func ranges(pattern: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var busca = startIndex..<endIndex
        while let r = range(of: pattern, options: [.regularExpression, .caseInsensitive], range: busca) {
            out.append(r)
            guard r.upperBound < endIndex else { break }
            busca = r.upperBound..<endIndex
        }
        return out
    }
}
