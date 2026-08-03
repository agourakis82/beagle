//
//  PresenceState.swift
//  BeagleCore — o estado da presença, e o ritmo dela
//
//  Dois tipos e um resolvedor puro. Nenhum deles toca UI, rede ou HealthKit —
//  por isso dá para testar em tabela.
//
//  O ponto do `PresenceBreath` é fechar um furo antigo: AuroraPresence caía em
//  `breathRate ?? 5.5` e CompanionMotion em `4.4`, ou seja, quando o Physiome
//  estava MUDO o companion respirava um ritmo inventado, indistinguível de um
//  ritmo medido. Com um enum de dois casos não existe um `Double?` que possa
//  escorregar para um default silencioso: ou o dado foi observado (e traz
//  QUANDO foi observado), ou o caso é declaradamente `.neutral` — e `.neutral`
//  é visualmente distinto, não só numericamente.
//

import Foundation

// MARK: - Estado

/// Os quatro estados-base da presença. O rawValue é o nome do laço no bundle.
public enum PresenceState: String, Sendable, Equatable, CaseIterable {
    /// Ninguém olhando: app em background, ou parado há bastante tempo.
    case adormecido
    /// Repouso acordado — o estado normal enquanto se lê a conversa.
    case atento
    /// Você está entrando com alguma coisa (voz ou composer com foco).
    case ouvindo
    /// O companion está gerando resposta.
    case pensando

    /// Nome do recurso no bundle (`st-atento.mp4` / `st-atento.png`).
    public var loopResource: String { "st-\(rawValue)" }
}

// MARK: - Respiração

/// O ritmo que anima a presença.
///
/// `.measured` exige bpm **e** o instante da observação: sem `observedAt` o dado
/// não é observado, é palpite. `.neutral` é o caso honesto de "não sei" — e tem
/// amplitude menor de propósito, para que "sem dado" não se pareça com "com dado".
public enum PresenceBreath: Sendable, Equatable {
    case measured(bpm: Double, at: Date)
    case neutral

    /// Período neutro, em segundos. NÃO é uma estimativa do usuário: é um ritmo
    /// declaradamente arbitrário, lento, usado só quando não há medida.
    public static let neutralPeriod: Double = 6.0

    /// Idade máxima padrão de uma medida antes de deixar de valer como observação.
    public static let defaultMaxAge: TimeInterval = 30 * 60

    public var isMeasured: Bool {
        if case .measured = self { return true }
        return false
    }

    /// bpm quando medido; `nil` quando neutro. Nunca inventa.
    public var bpm: Double? {
        if case let .measured(bpm, _) = self { return bpm }
        return nil
    }

    public var observedAt: Date? {
        if case let .measured(_, at) = self { return at }
        return nil
    }

    /// Período do ciclo em segundos. Medidas absurdas (derivadas de HR) são
    /// grampeadas em 4–20 bpm para não quebrar a animação.
    public var period: Double {
        switch self {
        case let .measured(bpm, _):
            return 60.0 / max(4.0, min(20.0, bpm))
        case .neutral:
            return Self.neutralPeriod
        }
    }

    /// Multiplicador de amplitude. O caso neutro respira MENOS fundo — é assim
    /// que "não sei" fica visível sem escrever nada na tela.
    public var amplitude: Double {
        switch self {
        case .measured: return 1.0
        case .neutral:  return 0.45
        }
    }

    /// Constrói a partir de um par opcional. Os DOIS precisam existir.
    public static func from(bpm: Double?, observedAt: Date?) -> PresenceBreath {
        guard let bpm, let observedAt, bpm >= 4 else { return .neutral }
        return .measured(bpm: bpm, at: observedAt)
    }

    /// Uma medida velha demais deixa de ser observação. Sem isto, uma leitura de
    /// ontem continuaria fingindo ser o batimento de agora.
    public func resolved(now: Date, maxAge: TimeInterval = PresenceBreath.defaultMaxAge) -> PresenceBreath {
        guard case let .measured(_, at) = self else { return .neutral }
        return now.timeIntervalSince(at) <= maxAge ? self : .neutral
    }
}

// MARK: - Resolvedor

/// Entradas → `PresenceState`. Puro, `Sendable`, sem relógio interno: quem chama
/// passa `now`, para o teste poder fixar o tempo.
public struct PresenceResolver: Sendable, Equatable {
    /// O companion está gerando resposta.
    public var isStreaming: Bool
    /// Captura de voz aberta.
    public var isVoiceListening: Bool
    /// Composer com foco de teclado (o usuário está compondo).
    public var composerFocused: Bool
    /// `scenePhase == .active`.
    public var isActive: Bool
    /// Última interação do usuário. `nil` → nunca interagiu nesta sessão.
    public var lastInteraction: Date?
    /// Silêncio a partir do qual a presença adormece.
    public var idleThreshold: TimeInterval

    public init(isStreaming: Bool = false,
                isVoiceListening: Bool = false,
                composerFocused: Bool = false,
                isActive: Bool = true,
                lastInteraction: Date? = nil,
                idleThreshold: TimeInterval = 150) {
        self.isStreaming = isStreaming
        self.isVoiceListening = isVoiceListening
        self.composerFocused = composerFocused
        self.isActive = isActive
        self.lastInteraction = lastInteraction
        self.idleThreshold = idleThreshold
    }

    /// Precedência, do mais forte para o mais fraco:
    ///   1. fora de `.active` → adormecido (a tela nem está na frente)
    ///   2. streaming        → pensando  (vence "ouvindo": ele está falando)
    ///   3. voz OU composer  → ouvindo
    ///   4. ocioso demais    → adormecido
    ///   5. resto            → atento
    public func state(now: Date) -> PresenceState {
        if !isActive { return .adormecido }
        if isStreaming { return .pensando }
        if isVoiceListening || composerFocused { return .ouvindo }
        if let last = lastInteraction, now.timeIntervalSince(last) > idleThreshold { return .adormecido }
        return .atento
    }
}
