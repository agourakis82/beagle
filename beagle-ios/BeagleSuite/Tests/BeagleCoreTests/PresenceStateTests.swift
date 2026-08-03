//
//  PresenceStateTests.swift
//  BeagleCoreTests — tabela do resolvedor + honestidade da respiração
//

import Testing
import Foundation
@testable import BeagleCore

@Suite("PresenceResolver")
struct PresenceResolverTests {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("fora de .active adormece, mesmo streaming")
    func inactiveSleeps() {
        let r = PresenceResolver(isStreaming: true, isVoiceListening: true,
                                 composerFocused: true, isActive: false)
        #expect(r.state(now: now) == .adormecido)
    }

    @Test("streaming vence entrada do usuário")
    func streamingWins() {
        let r = PresenceResolver(isStreaming: true, isVoiceListening: true, composerFocused: true)
        #expect(r.state(now: now) == .pensando)
    }

    @Test("voz e composer levam a ouvindo")
    func listening() {
        #expect(PresenceResolver(isVoiceListening: true).state(now: now) == .ouvindo)
        #expect(PresenceResolver(composerFocused: true).state(now: now) == .ouvindo)
    }

    @Test("silêncio longo adormece; silêncio curto não")
    func idle() {
        let quiet = PresenceResolver(lastInteraction: now.addingTimeInterval(-600), idleThreshold: 150)
        #expect(quiet.state(now: now) == .adormecido)
        let recent = PresenceResolver(lastInteraction: now.addingTimeInterval(-10), idleThreshold: 150)
        #expect(recent.state(now: now) == .atento)
    }

    @Test("sem interação registrada fica atento, não adormecido")
    func noInteractionYet() {
        #expect(PresenceResolver().state(now: now) == .atento)
    }

    @Test("tabela completa é determinística")
    func table() {
        let cases: [(PresenceResolver, PresenceState)] = [
            (PresenceResolver(isActive: false), .adormecido),
            (PresenceResolver(isStreaming: true), .pensando),
            (PresenceResolver(composerFocused: true), .ouvindo),
            (PresenceResolver(isVoiceListening: true), .ouvindo),
            (PresenceResolver(lastInteraction: now.addingTimeInterval(-1000)), .adormecido),
            (PresenceResolver(lastInteraction: now), .atento),
        ]
        for (r, expected) in cases {
            #expect(r.state(now: now) == expected)
        }
    }

    @Test("todo estado tem um nome de laço distinto")
    func loopNames() {
        let names = Set(PresenceState.allCases.map(\.loopResource))
        #expect(names.count == PresenceState.allCases.count)
        #expect(names.contains("st-atento"))
    }
}

@Suite("PresenceBreath")
struct PresenceBreathTests {

    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("neutro não expõe bpm nem observedAt")
    func neutralIsHonest() {
        #expect(PresenceBreath.neutral.bpm == nil)
        #expect(PresenceBreath.neutral.observedAt == nil)
        #expect(PresenceBreath.neutral.isMeasured == false)
    }

    @Test("neutro respira mais raso que medido — a diferença é visível")
    func neutralAmplitudeIsSmaller() {
        #expect(PresenceBreath.neutral.amplitude < PresenceBreath.measured(bpm: 12, at: now).amplitude)
    }

    @Test("período segue o bpm e é grampeado")
    func period() {
        #expect(abs(PresenceBreath.measured(bpm: 15, at: now).period - 4.0) < 1e-9)
        // absurdos derivados de HR não quebram a animação
        #expect(abs(PresenceBreath.measured(bpm: 200, at: now).period - 3.0) < 1e-9)
        #expect(abs(PresenceBreath.measured(bpm: 0.5, at: now).period - 15.0) < 1e-9)
        #expect(PresenceBreath.neutral.period == PresenceBreath.neutralPeriod)
    }

    @Test("from() exige bpm E observedAt")
    func fromRequiresBoth() {
        #expect(PresenceBreath.from(bpm: 12, observedAt: nil) == .neutral)
        #expect(PresenceBreath.from(bpm: nil, observedAt: now) == .neutral)
        #expect(PresenceBreath.from(bpm: nil, observedAt: nil) == .neutral)
        #expect(PresenceBreath.from(bpm: 12, observedAt: now) == .measured(bpm: 12, at: now))
    }

    @Test("medida velha deixa de ser observação")
    func staleness() {
        let fresh = PresenceBreath.measured(bpm: 12, at: now.addingTimeInterval(-60))
        #expect(fresh.resolved(now: now).isMeasured)
        let stale = PresenceBreath.measured(bpm: 12, at: now.addingTimeInterval(-24 * 3600))
        #expect(stale.resolved(now: now) == .neutral)
    }
}
