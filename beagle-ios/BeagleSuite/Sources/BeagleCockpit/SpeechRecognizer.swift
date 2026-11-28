//
//  SpeechRecognizer.swift
//  BeagleCockpit
//
//  On-device speech-to-text using Apple SpeechAnalyzer (iOS 26+).
//  Two modes:
//    1. Manual: tap to record, tap to stop (thought capture)
//    2. Ambient: continuous background listening, auto-captures insights
//
//  Primary path: SpeechAnalyzer + SpeechTranscriber (iOS 26 Neural Engine).
//  Fallback path: SFSpeechRecognizer (if SpeechAnalyzer assets unavailable).
//
//  All processing on-device. Zero cloud dependency.
//

import SwiftUI
import BeagleCore
@preconcurrency import Speech
@preconcurrency import AVFoundation

@Observable
@MainActor
final class SpeechRecognizer {

    // MARK: - Public state

    var transcript: String = ""
    var isRecording: Bool = false
    var error: String?
    private(set) var isWhisperReady: Bool = false

    /// Ambient capture mode — continuous background listening.
    var isAmbientActive: Bool = false

    /// Captured fragments from ambient mode (new since last check).
    var ambientFragments: [AmbientFragment] = []

    // MARK: - Private state

    var audioEngine: AVAudioEngine?
    var ambientTask: Task<Void, Never>?
    var recordingTask: Task<Void, Never>?
    var analyzerInputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var useLegacyRecognizer: Bool = false

    // MARK: - Voice-acoustic features (natural byproduct of speech already captured for STT)

    /// Raw sample windows accumulated during the current recording, for
    /// VoiceAcousticAnalyzer.summarize() once the turn ends. One window per tap callback
    /// (~4096 frames) — no extra buffering, just retains what the STT path already reads.
    var audioWindows: [[Float]] = []
    private var recordingStartedAt: Date?
    var acousticSampleRate: Double = 16000
    /// Set by the caller before startRecording() so acoustic samples can be tagged back to
    /// the companion conversation they came from.
    var sessionId: String?

    /// Live input loudness, 0…1, published from the audio tap on BOTH paths (analyzer and
    /// legacy). It has to come from the tap, not from `audioWindows`: the legacy tap never
    /// calls extractSamples, so a level derived from the windows would be dead exactly in the
    /// fallback — the bad-network case where the user most needs "estou te ouvindo".
    private(set) var level: Float = 0

    /// Whether this turn's acoustic summary may be uploaded to Physiome. Thinking Aloud keeps
    /// it ON (an explicit, bounded session). The chat voice turn sets it OFF: with voice as a
    /// primary input, every sentence would become prosody inference about his state, which
    /// collides with the companion design's invariant 4 ("emotion reacts, never diagnoses")
    /// and with the anti-creepy `explicit_session_only` policy the code already declares.
    /// Ritmo e pausa do ÚLTIMO turno falado — o sinal de tom que viaja COM a
    /// mensagem, sem áudio. Zerado no cancelamento junto do resto.
    ///
    /// Vai pelo turno e não pelo digest do Physiome porque o digest é média do
    /// dia: para tom, o que importa é como ESTA frase saiu.
    private(set) var sinalDoUltimoTurno: (wpm: Double?, pausa: Double)?

    var uploadsAcoustics: Bool = true

    /// True when SpeechAnalyzer assets are unavailable and we're on SFSpeechRecognizer.
    /// The legacy path has no partial results and re-transcribes a rolling window, so callers
    /// must not offer long hands-free dictation there.
    var isUsingLegacyRecognizer: Bool { useLegacyRecognizer }

    /// How the AVAudioSession is shaped for this turn.
    enum CaptureProfile {
        /// Thinking Aloud: `.record`/`.measurement`, i.e. the rawest signal iOS will give.
        /// The VoiceAcoustic* series already in collection was measured under this profile —
        /// changing it globally would put an artificial step in an N-of-1 time series.
        case measurement
        /// Chat voice turn: `.playAndRecord`/`.voiceChat` (AGC + noise suppression), speaker
        /// and Bluetooth friendly. Only ever used where `uploadsAcoustics == false`, so the
        /// two eras of the acoustic series never mix.
        case conversation
    }

    var captureProfile: CaptureProfile = .measurement

    /// Called from the audio tap (any thread): smooth and publish the loudness.
    nonisolated func publishLevel(_ value: Float) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.level = self.level * 0.7 + value * 0.3
        }
    }

    /// Normalized loudness of a buffer: RMS in dBFS mapped from a −50 dB floor to 0…1.
    nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float? {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return min(max((db + 50) / 50, 0), 1)
    }

    static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
    }

    // MARK: - Setup

    func setup() async {
        // Check if SpeechAnalyzer transcription assets are available
        do {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
                // Current locale not supported by SpeechAnalyzer — fall back
                useLegacyRecognizer = true
                isWhisperReady = true
                return
            }

            let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])

            // Ensure on-device assets are installed
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installationRequest.downloadAndInstall()
            }

            useLegacyRecognizer = false
            isWhisperReady = true
        } catch {
            // Asset download failed — fall back to SFSpeechRecognizer
            useLegacyRecognizer = true
            isWhisperReady = true
        }
    }

    // MARK: - Manual recording (tap to start/stop)

    func startRecording(profile: CaptureProfile = .measurement, uploadsAcoustics: Bool = true) async {
        error = nil
        transcript = ""
        level = 0
        audioWindows.removeAll()
        recordingStartedAt = Date()
        captureProfile = profile
        self.uploadsAcoustics = uploadsAcoustics

        if useLegacyRecognizer {
            await startRecordingLegacy()
        } else {
            await startRecordingAnalyzer()
        }
    }

    func stopRecording() {
        teardownCapture()
        uploadAcousticSummaryForCompletedTurn()
    }

    /// Abort the turn: the user dragged up / walked away. Everything captured is dropped —
    /// no transcript, and above all no acoustic sample, because uploading prosody from an
    /// utterance he explicitly discarded is exactly the behaviour the cancel gesture promises
    /// not to have.
    func cancelRecording() {
        sinalDoUltimoTurno = nil
        audioWindows.removeAll()
        recordingStartedAt = nil
        teardownCapture()
        transcript = ""
    }

    private func teardownCapture() {
        // Signal the analyzer input stream to finish
        analyzerInputContinuation?.finish()
        analyzerInputContinuation = nil

        // Cancel the recording task
        recordingTask?.cancel()
        recordingTask = nil

        stopAudioEngine()
        level = 0
    }

    /// Computes the turn's voice-acoustic summary from windows accumulated during the tap
    /// (see extractSamples/audioWindows above) and uploads it like any other health metric.
    /// Best-effort, fire-and-forget — never blocks stopRecording() or the caller's UI flow.
    private func uploadAcousticSummaryForCompletedTurn() {
        // SINAL DO TURNO x MÉTRICA DE SAÚDE — duas coisas diferentes, duas travas.
        //
        // `uploadsAcoustics` foi criado para impedir que turno de chat vire linha de
        // prosódia no Physiome, e isso continua valendo. Mas o sinal de TOM que
        // acompanha a mensagem (ritmo e pausa) é outra coisa: ele foi pedido
        // explicitamente, viaja como dois números no corpo do turno, e nunca vira
        // série histórica. Calcular antes da trava é o que faz o recurso existir no
        // chat — que é justamente onde ele importa.
        //
        // O áudio segue descartado aqui, nos dois caminhos.
        guard !audioWindows.isEmpty else { audioWindows.removeAll(); return }
        let vaiParaPhysiome = uploadsAcoustics
        let windows = audioWindows
        audioWindows.removeAll()
        let turnDuration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let wordCount = transcript.split(separator: " ").count
        let sid = sessionId
        let sampleRate = acousticSampleRate

        Task {
            let summary = VoiceAcousticAnalyzer.summarize(
                windows: windows,
                sampleRate: sampleRate,
                transcriptWordCount: wordCount > 0 ? wordCount : nil,
                turnDurationSeconds: turnDuration
            )
            await MainActor.run { [weak self] in
                self?.sinalDoUltimoTurno = (wpm: summary.speechRateWpm, pausa: summary.pauseRatio)
            }
            guard vaiParaPhysiome else { return }
            let now = ISO8601DateFormatter()
            now.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let ts = now.string(from: Date())
            let metadata: [String: String]? = sid.map { ["session_id": $0] }

            var samples: [PhysioHealthSample] = [
                PhysioHealthSample(uuid: UUID().uuidString, ts: ts, endTs: ts, type: "VoiceAcousticRmsDb", value: summary.rmsDb, unit: "dBFS", source: "com.beagle.cockpit", device: nil, metadata: metadata),
                PhysioHealthSample(uuid: UUID().uuidString, ts: ts, endTs: ts, type: "VoiceAcousticPauseRatio", value: summary.pauseRatio, unit: "ratio", source: "com.beagle.cockpit", device: nil, metadata: metadata),
            ]
            if let f0Mean = summary.f0MeanHz {
                samples.append(PhysioHealthSample(uuid: UUID().uuidString, ts: ts, endTs: ts, type: "VoiceAcousticF0MeanHz", value: f0Mean, unit: "Hz", source: "com.beagle.cockpit", device: nil, metadata: metadata))
            }
            if let f0Variance = summary.f0VarianceHz {
                samples.append(PhysioHealthSample(uuid: UUID().uuidString, ts: ts, endTs: ts, type: "VoiceAcousticF0VarianceHz", value: f0Variance, unit: "Hz^2", source: "com.beagle.cockpit", device: nil, metadata: metadata))
            }
            if let wpm = summary.speechRateWpm {
                samples.append(PhysioHealthSample(uuid: UUID().uuidString, ts: ts, endTs: ts, type: "VoiceAcousticSpeechRateWpm", value: wpm, unit: "wpm", source: "com.beagle.cockpit", device: nil, metadata: metadata))
            }

            await PhysiomeUploader.shared.enqueue(healthSamples: samples)
            await PhysiomeUploader.shared.flush()
        }
    }

    // MARK: - Ambient capture mode

    /// Toggle ambient listening on/off.
    func toggleAmbient() async {
        if isAmbientActive {
            stopAmbient()
        } else {
            await startAmbient()
        }
    }

    func startAmbient() async {
        guard !isAmbientActive else { return }
        error = nil

        if useLegacyRecognizer {
            await startAmbientLegacy()
        } else {
            await startAmbientAnalyzer()
        }
    }

    func stopAmbient() {
        analyzerInputContinuation?.finish()
        analyzerInputContinuation = nil
        ambientTask?.cancel()
        ambientTask = nil
        isAmbientActive = false
        stopAudioEngine()
    }

    /// Consume and clear captured fragments (called by CognitiveStore).
    func consumeFragments() -> [AmbientFragment] {
        let fragments = ambientFragments
        ambientFragments.removeAll()
        return fragments
    }


    // MARK: - Authorization

    /// What the system currently grants. Read this BEFORE blaming asset installation: nothing
    /// in this class ever requested speech or microphone permission, so an un-prompted install
    /// looks exactly like "assets failed".
    struct AuthorizationSnapshot: Sendable {
        var speech: SFSpeechRecognizerAuthorizationStatus
        var microphoneGranted: Bool
        var isReady: Bool { speech == .authorized && microphoneGranted }
    }

    static func authorizationSnapshot() -> AuthorizationSnapshot {
        #if os(iOS)
        let mic = AVAudioApplication.shared.recordPermission == .granted
        #else
        let mic = true
        #endif
        return AuthorizationSnapshot(speech: SFSpeechRecognizer.authorizationStatus(), microphoneGranted: mic)
    }

    /// Requests microphone + speech authorization. Idempotent; returns whether capture is
    /// allowed to proceed.
    static func requestAuthorization() async -> AuthorizationSnapshot {
        #if os(iOS)
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
            }
        }
        #endif
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
        }
        return authorizationSnapshot()
    }

}

// MARK: - Ambient fragment model

struct AmbientFragment: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let timestamp: Date
}
