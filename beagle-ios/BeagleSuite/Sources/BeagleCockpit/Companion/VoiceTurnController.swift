//
//  VoiceTurnController.swift
//  BeagleCockpit — Companion chat
//
//  The three metres of cable between the speech engine and the conversation.
//
//  SpeechRecognizer already knew how to listen; the chat's mic button was a no-op. This
//  class owns ONE turn of voice: arm → listen → commit (or cancel), with haptics as the
//  only feedback channel that works with the phone face-down. It holds zero networking —
//  it produces a String and hands it back.
//
//  Two modes, deliberately asymmetric:
//    • push-to-talk (hold) is primary — the finger IS the endpoint detector.
//    • hands-free (tap to latch) is an explicit, per-turn opt-in with silence endpointing.
//  That asymmetry is a hospital decision: silence endpointing assumes silence exists, and
//  in a corridor it does not. It is also the privacy line — holding to speak keeps the
//  `explicit_session_only` promise that continuous listening would break.
//
//  Acoustic upload is OFF on this path (see SpeechRecognizer.uploadsAcoustics): voice as a
//  primary input must not turn every sentence into prosody inference about his state.
//

import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class VoiceTurnController {

    enum Phase: Equatable {
        /// Nothing happening. The mic is just a glyph.
        case idle
        /// Permission / engine spinning up. Sub-second, but it must be visible: the user has
        /// already started talking by now.
        case arming
        /// Push-to-talk: the finger is down. Releasing commits.
        case listening
        /// Hands-free: latched for this turn only. Silence endpointing is live.
        case latched
        /// The finger drifted past the cancel threshold — release now and nothing is sent.
        case cancelArmed
        /// Permission refused. The UI should say so instead of failing mute.
        case denied
    }

    // MARK: - Published state

    private(set) var phase: Phase = .idle
    /// Live partial transcript. Empty until the recognizer produces something.
    var transcript: String { recognizer.transcript }
    /// Por que a voz não abriu. Era gravado e ninguém lia — o usuário segurava o
    /// microfone e não acontecia nada, sem uma palavra na tela.
    var erro: String? { recognizer.error }

    /// Por que o TOQUE não fez nada. Havia duas saídas mudas — sem mãos-livres e
    /// fora do estado ocioso — e as duas só vibravam. Vibração não é explicação:
    /// quem aperta e não vê nada conclui que apertou errado.
    private(set) var motivoDaRecusa: String?
    /// Ritmo e pausa do último turno FALADO. Nulo quando ele digitou, e nulo
    /// depois de um cancelamento — cancelar promete que nada daquele turno sai.
    var sinalDoUltimoTurno: (wpm: Double?, pausa: Double)? { recognizer.sinalDoUltimoTurno }
    /// Input loudness 0…1 for the level bar.
    var level: Float { recognizer.level }
    /// True whenever the mic is actually open (either mode).
    var isListening: Bool { phase == .listening || phase == .latched || phase == .cancelArmed }
    /// Hands-free is not offered on the SFSpeechRecognizer fallback: no partial results and a
    /// rolling re-transcription window make long dictation there a lie.
    var supportsHandsFree: Bool { !recognizer.isUsingLegacyRecognizer }
    /// Set once, by the composer. Receives the finished utterance.
    var onCommit: ((String) -> Void)?

    // MARK: - Private

    private let recognizer = SpeechRecognizer()
    private var setupTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var startedAt: Date?
    private var lastVoiceAt: Date?

    /// Hard ceiling on a single turn. If the release event is ever lost — an incoming call,
    /// a notification, the app backgrounding mid-hold — the mic must not stay open.
    private static let maxTurnSeconds: TimeInterval = 120
    /// Silence that ends a latched turn. Only ever applied in `.latched`.
    private static let endpointSilenceSeconds: TimeInterval = 1.8
    /// Below this the input counts as silence for endpointing.
    private static let silenceLevel: Float = 0.12
    /// Vertical drag, in points, that arms cancel during a hold.
    static let cancelDragThreshold: CGFloat = 60

    // MARK: - Lifecycle

    /// Kick off asset warm-up so the first hold doesn't eat the first three words. Fire and
    /// forget — never awaited directly, because `SpeechRecognizer.setup()` downloads assets
    /// with no timeout of its own and hospital wifi would hang whatever awaited it.
    func prewarm() {
        guard setupTask == nil else { return }
        setupTask = Task { [weak self] in await self?.recognizer.setup() }
    }

    /// Wait for warm-up, but only for so long. Whichever finishes first wins; a still-running
    /// download is left to finish in the background instead of blocking the turn.
    private func awaitSetup(timeout seconds: Double) async {
        prewarm()
        guard let setupTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await setupTask.value }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Current permission state, without prompting. This is the first thing to read when the
    /// mic "doesn't work": nothing in the speech stack ever asked for authorization before
    /// this class existed, so a never-prompted install is indistinguishable from a broken one.
    var authorization: SpeechRecognizer.AuthorizationSnapshot {
        SpeechRecognizer.authorizationSnapshot()
    }

    // MARK: - Push-to-talk

    /// Finger down. Returns as soon as the mic is open — the haptic fires first so the "go"
    /// signal reaches the hand before he starts the sentence.
    func beginHold() async {
        guard phase == .idle || phase == .denied else { return }
        await start(latched: false)
    }

    /// Finger moved while holding. `translation` is negative upward.
    func updateHold(translation: CGFloat) {
        guard phase == .listening || phase == .cancelArmed else { return }
        let shouldCancel = translation < -Self.cancelDragThreshold
        if shouldCancel, phase == .listening {
            phase = .cancelArmed
            haptic(.warning)
        } else if !shouldCancel, phase == .cancelArmed {
            phase = .listening
            impact(.soft)
        }
    }

    /// Finger up. Commits, or discards if cancel was armed.
    func endHold() {
        switch phase {
        case .cancelArmed: cancel()
        case .listening: commit()
        default: break
        }
    }

    // MARK: - Hands-free

    /// Short tap on the mic: latch for THIS turn. Tapping again forces the commit — the escape
    /// hatch has to exist, because silence endpointing will sometimes never fire.
    func toggleLatched() async {
        switch phase {
        case .latched:
            commit()
        case .idle, .denied:
            guard supportsHandsFree else {
                motivoDaRecusa = "Ditado contínuo indisponível neste aparelho — SEGURE o microfone para falar."
                haptic(.error)
                return
            }
            motivoDaRecusa = nil
            await start(latched: true)
        default:
            break
        }
    }

    // MARK: - Core transitions

    private func start(latched: Bool) async {
        phase = .arming
        let auth = await SpeechRecognizer.requestAuthorization()
        guard auth.isReady else {
            phase = .denied
            haptic(.error)
            return
        }
        await awaitSetup(timeout: 6)
        // Chat turns never upload prosody, and use the voice-optimized session so AirPods and
        // walking around work. Thinking Aloud keeps its raw `.measurement` profile untouched.
        await recognizer.startRecording(profile: .conversation, uploadsAcoustics: false)
        guard recognizer.isRecording else {
            phase = .idle
            haptic(.error)
            return
        }
        startedAt = Date()
        lastVoiceAt = Date()
        phase = latched ? .latched : .listening
        impact(.soft)
        startWatchdog()
    }

    private func commit() {
        guard isListening || phase == .arming else { return }
        stopWatchdog()
        recognizer.stopRecording()
        let text = recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .idle
        startedAt = nil
        guard !text.isEmpty else {
            // Nothing heard. This MUST be felt, not merely absent — the whole point of the
            // gesture is that he is not looking at the screen.
            haptic(.error)
            return
        }
        haptic(.success)
        onCommit?(text)
    }

    /// Discard the turn: no transcript, no acoustic sample, no message.
    func cancel() {
        guard phase != .idle else { return }
        stopWatchdog()
        recognizer.cancelRecording()
        phase = .idle
        startedAt = nil
        haptic(.warning)
    }

    /// Called when the app leaves the foreground. A hold whose release event never arrives is
    /// an open microphone; force the turn closed rather than trusting the gesture.
    func handleResignActive() {
        guard isListening else { return }
        if phase == .latched {
            commit()
        } else {
            cancel()
        }
    }

    // MARK: - Watchdog + endpointing

    private func startWatchdog() {
        stopWatchdog()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.isListening else { return }
                self.tick()
            }
        }
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func tick() {
        if let startedAt, Date().timeIntervalSince(startedAt) > Self.maxTurnSeconds {
            commit()
            return
        }
        if recognizer.level > Self.silenceLevel { lastVoiceAt = Date() }
        // Endpointing ONLY when latched. In push-to-talk the finger is the endpoint, which is
        // the only endpoint detector that works in a noisy corridor.
        guard phase == .latched,
              !recognizer.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let lastVoiceAt,
              Date().timeIntervalSince(lastVoiceAt) > Self.endpointSilenceSeconds else { return }
        commit()
    }

    // MARK: - Haptics (the only feedback channel that works face-down)

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    private func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(type)
    }
}
