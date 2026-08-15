//
//  PresencaSnapshot.swift
//  BeagleCore — o plano de dados LOCAL que o widget lê
//
//  POR QUE ISTO EXISTE
//
//  Os widgets faziam rede DE DENTRO do processo do widget (CockpitClient.catalog()
//  a cada 5 min). Duas consequências, ambas ruins no plantão:
//
//    1. Fora do alcance do cluster — que é a regra no hospital, não a exceção —
//       o widget não mostra nada.
//    2. O WidgetKit corta orçamento de refresh de quem faz I/O lento. O widget
//       que tenta ser fresco acaba MAIS velho.
//
//  Aqui a inversão: o APP escreve um instantâneo pequeno no contêiner do App
//  Group; o WIDGET só lê, local, sem rede. Sempre desenha, e desenha depressa.
//
//  ARQUIVO, NÃO UserDefaults. O UserDefaults do grupo já é usado como FILA pela
//  extensão de compartilhamento (`pendingSharedThoughts`). Misturar fila com
//  estado no mesmo mecanismo é como se perde uma das duas.
//
//  UM ESCRITOR, UM LEITOR. Só o app escreve; só o widget lê. Sem escrita
//  concorrente, não há coordenação a acertar.
//

import Foundation

/// Um valor COM a sua procedência. A unidade é o fato, não o instantâneo:
/// o coração pode ser de 4h atrás enquanto o céu é de agora, e a tela tem que
/// poder dizer isso. Um instantâneo com uma idade só mentiria sobre metade dele.
public struct Fato<T: Codable & Sendable>: Codable, Sendable {
    public let valor: T?
    /// Quando foi MEDIDO. `nil` = não veio de medição (declarado).
    public let observadoEm: Date?

    public init(valor: T? = nil, observadoEm: Date? = nil) {
        self.valor = valor
        self.observadoEm = observadoEm
    }

    /// `nil` quando não há valor — ausência não é um modo de verdade, é ausência.
    /// Sem carimbo → `.declared`. Com carimbo dentro da validade → `.observed`.
    /// Fora dela → `.stale`, porque "não sei mais" jamais pode ser servido como
    /// "está assim".
    public func procedencia(agora: Date = Date()) -> TruthMode? {
        guard valor != nil else { return nil }
        guard let observadoEm else { return .declared }
        return agora.timeIntervalSince(observadoEm) <= PresencaSnapshot.validade
            ? .observed : .stale
    }
}

/// O que o companion sabe agora, na forma que cabe num widget.
///
/// Deliberadamente pequeno: tempo · corpo · céu (a mesma tríade da Faixa de
/// Estado, mesmo vocabulário nas duas superfícies) mais o fluxo e a fila de
/// capturas. Nada aqui é dado clínico bruto — é o que dá para ler de relance.
public struct PresencaSnapshot: Codable, Sendable {
    /// Mesma validade que a presença já usa (30 min). Um segundo conceito de
    /// "fresco" seria uma segunda verdade sobre a mesma coisa.
    public static let validade: TimeInterval = PresenceBreath.defaultMaxAge

    /// Quando o app escreveu. Não é a idade dos fatos — cada um tem a sua.
    public let geradoEm: Date
    /// Batimento em bpm.
    public let corpo: Fato<Double>
    /// Banda do céu, já em palavra (`SkyBand.rawValue`).
    public let ceu: Fato<String>
    /// Estado de fluxo declarado pelo servidor/HRV.
    public let fluxo: Fato<String>
    /// Capturas esperando envio. Número REAL — nunca um zero de enfeite.
    public let capturasPendentes: Int

    public init(geradoEm: Date,
                corpo: Fato<Double> = .init(),
                ceu: Fato<String> = .init(),
                fluxo: Fato<String> = .init(),
                capturasPendentes: Int = 0) {
        self.geradoEm = geradoEm
        self.corpo = corpo
        self.ceu = ceu
        self.fluxo = fluxo
        self.capturasPendentes = capturasPendentes
    }

    /// TOLERANTE A CAMPO FALTANDO, de propósito.
    ///
    /// O iOS não atualiza app e extensão no mesmo instante: um app novo escreve
    /// um instantâneo que um widget velho vai ler, e vice-versa. Se um campo
    /// novo derrubasse a decodificação inteira, o widget ficaria mudo no meio de
    /// toda atualização — falha invisível e periódica, a pior espécie.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        geradoEm = (try? c.decode(Date.self, forKey: .geradoEm)) ?? Date()
        corpo = (try? c.decode(Fato<Double>.self, forKey: .corpo)) ?? .init()
        ceu = (try? c.decode(Fato<String>.self, forKey: .ceu)) ?? .init()
        fluxo = (try? c.decode(Fato<String>.self, forKey: .fluxo)) ?? .init()
        capturasPendentes = (try? c.decode(Int.self, forKey: .capturasPendentes)) ?? 0
    }
}

/// Lê e escreve o instantâneo no contêiner do App Group.
///
/// `diretorio` é injetável para os testes rodarem em pasta temporária — sem isso
/// o teste dependeria de entitlement de App Group, que não existe em teste.
public struct PresencaSnapshotStore: Sendable {
    public static let appGroup = "group.dev.sounio.cockpit"
    private static let nomeDoArquivo = "presenca.json"

    private let diretorio: URL

    public init(diretorio: URL) { self.diretorio = diretorio }

    /// `nil` quando o App Group não está disponível — melhor não escrever do que
    /// escrever num lugar que o widget nunca vai ler.
    public init?(appGroup: String = PresencaSnapshotStore.appGroup) {
        guard let d = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        self.diretorio = d
    }

    public var arquivo: URL { diretorio.appendingPathComponent(Self.nomeDoArquivo) }

    private static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    /// Escrita ATÔMICA: o widget pode ler no meio da escrita do app, e um arquivo
    /// truncado decodifica como nada. `.atomic` troca por rename, então o leitor
    /// vê o anterior ou o novo, nunca um pedaço.
    public func escrever(_ s: PresencaSnapshot) throws {
        try Self.codificador.encode(s).write(to: arquivo, options: .atomic)
    }

    /// Nunca lança. Ausente ou corrompido devolve `nil`, e cabe a quem desenha
    /// dizer "sem notícia" — jamais um zero que pareça medida.
    public func ler() -> PresencaSnapshot? {
        guard let d = try? Data(contentsOf: arquivo) else { return nil }
        return try? Self.decodificador.decode(PresencaSnapshot.self, from: d)
    }
}
