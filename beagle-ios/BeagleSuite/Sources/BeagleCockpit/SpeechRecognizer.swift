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

    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false
    private(set) var error: String?
    private(set) var isWhisperReady: Bool = false

    /// Ambient capture mode — continuous background listening.
    private(set) var isAmbientActive: Bool = false

    /// Captured fragments from ambient mode (new since last check).
    private(set) var ambientFragments: [AmbientFragment] = []

    // MARK: - Private state

    private var audioEngine: AVAudioEngine?
    private var ambientTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var analyzerInputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var useLegacyRecognizer: Bool = false

    // MARK: - Voice-acoustic features (natural byproduct of speech already captured for STT)

    /// Raw sample windows accumulated during the current recording, for
    /// VoiceAcousticAnalyzer.summarize() once the turn ends. One window per tap callback
    /// (~4096 frames) — no extra buffering, just retains what the STT path already reads.
    private var audioWindows: [[Float]] = []
    private var recordingStartedAt: Date?
    private var acousticSampleRate: Double = 16000
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

    private var captureProfile: CaptureProfile = .measurement

    /// Called from the audio tap (any thread): smooth and publish the loudness.
    nonisolated private func publishLevel(_ value: Float) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.level = self.level * 0.7 + value * 0.3
        }
    }

    /// Normalized loudness of a buffer: RMS in dBFS mapped from a −50 dB floor to 0…1.
    nonisolated private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float? {
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

    private static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
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

    // MARK: - SpeechAnalyzer path (iOS 26+)

    private func startRecordingAnalyzer() async {
        #if canImport(AVFoundation) && os(iOS)
        await startAudioEngine()
        guard isRecording, let audioEngine else { return }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            error = "Speech language not supported"
            stopAudioEngine()
            return
        }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])

        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            error = "Could not determine audio format"
            stopAudioEngine()
            return
        }
        acousticSampleRate = audioFormat.sampleRate

        let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.analyzerInputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Install converter if needed
        let converter = AVAudioConverter(from: hardwareFormat, to: audioFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Loudness comes from the hardware buffer (pre-conversion) so it is identical on
            // both capture paths and never depends on the converter succeeding.
            if let lvl = Self.normalizedLevel(of: buffer) { self.publishLevel(lvl) }

            if let converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * audioFormat.sampleRate / hardwareFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }

                var outError: NSError?
                converter.convert(to: convertedBuffer, error: &outError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if outError == nil {
                    let input = AnalyzerInput(buffer: convertedBuffer)
                    continuation.yield(input)
                    if let samples = Self.extractSamples(from: convertedBuffer) {
                        Task { @MainActor [weak self] in self?.audioWindows.append(samples) }
                    }
                }
            } else {
                // Formats already match
                let input = AnalyzerInput(buffer: buffer)
                continuation.yield(input)
                if let samples = Self.extractSamples(from: buffer) {
                    Task { @MainActor [weak self] in self?.audioWindows.append(samples) }
                }
            }
        }

        // Process results in background
        recordingTask = Task { [weak self] in
            // Stream transcription results
            let resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        await MainActor.run { [weak self] in
                            if !text.isEmpty {
                                self?.transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.error = "Transcription error: \(error.localizedDescription)"
                    }
                }
            }

            // Feed audio to the analyzer
            do {
                let lastSampleTime = try await analyzer.analyzeSequence(inputStream)
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                // Analysis cancelled or failed — not necessarily an error
                if !Task.isCancelled {
                    await MainActor.run { [weak self] in
                        self?.error = "Analysis error: \(error.localizedDescription)"
                    }
                }
            }

            resultsTask.cancel()
        }
        #endif
    }

    private func startAmbientAnalyzer() async {
        #if canImport(AVFoundation) && os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            self.error = "Speech language not supported for ambient"
            return
        }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])

        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            self.error = "Could not determine audio format for ambient"
            return
        }

        let (inputStream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.analyzerInputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let converter = AVAudioConverter(from: hardwareFormat, to: audioFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            if let converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * audioFormat.sampleRate / hardwareFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else { return }

                var outError: NSError?
                converter.convert(to: convertedBuffer, error: &outError) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if outError == nil {
                    continuation.yield(AnalyzerInput(buffer: convertedBuffer))
                }
            } else {
                continuation.yield(AnalyzerInput(buffer: buffer))
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Could not start ambient audio: \(error.localizedDescription)"
            continuation.finish()
            return
        }

        self.audioEngine = engine
        self.isAmbientActive = true

        ambientTask = Task { [weak self] in
            // Track last captured text to detect new content
            var lastCapturedText = ""

            // Stream transcription results continuously
            let resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)

                        guard !text.isEmpty, text != lastCapturedText, text.count > 10 else { continue }

                        lastCapturedText = text
                        let fragment = AmbientFragment(text: text, timestamp: Date())

                        await MainActor.run { [weak self] in
                            self?.ambientFragments.append(fragment)

                            // Keep last 50 fragments
                            if let count = self?.ambientFragments.count, count > 50 {
                                self?.ambientFragments.removeFirst(count - 50)
                            }
                        }
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        if self?.isAmbientActive == true {
                            self?.error = "Ambient transcription error: \(error.localizedDescription)"
                        }
                    }
                }
            }

            // Feed audio to analyzer (blocks until stream finishes)
            do {
                let lastSampleTime = try await analyzer.analyzeSequence(inputStream)
                if let lastSampleTime {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                // Cancelled — expected on stopAmbient()
            }

            resultsTask.cancel()
        }
        #else
        error = "Ambient capture requires iOS"
        #endif
    }

    // MARK: - Legacy SFSpeechRecognizer path (fallback)

    /// Hard ceiling on audio retained by the legacy re-transcription loop.
    private static let legacyMaxRetainedSeconds: Double = 45

    private func startRecordingLegacy() async {
        #if canImport(AVFoundation) && os(iOS)
        await startAudioEngine()
        guard isRecording else { return }

        let bufferRef = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
        bufferRef.initialize(to: [])

        let legacyFormat = audioEngine!.inputNode.outputFormat(forBus: 0)
        // The legacy path re-transcribes the WHOLE accumulated buffer every 2 s, so an
        // untruncated buffer makes long dictation cost O(n²) and eventually stall. Cap the
        // retained audio; callers are told (isUsingLegacyRecognizer) not to offer hands-free
        // dictation on this path at all.
        let legacyCapSamples = Int(legacyFormat.sampleRate * Self.legacyMaxRetainedSeconds)

        audioEngine?.inputNode.installTap(onBus: 0, bufferSize: 4096, format: legacyFormat) { [weak self] buffer, _ in
            if let lvl = Self.normalizedLevel(of: buffer) { self?.publishLevel(lvl) }
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let channelData, frameLength > 0 {
                bufferRef.pointee.append(contentsOf: Array(UnsafeBufferPointer(start: channelData, count: frameLength)))
                if bufferRef.pointee.count > legacyCapSamples {
                    bufferRef.pointee.removeFirst(bufferRef.pointee.count - legacyCapSamples)
                }
            }
        }

        recordingTask = Task {
            while isRecording {
                try? await Task.sleep(for: .seconds(2))
                guard isRecording else { break }
                let samples = bufferRef.pointee
                if !samples.isEmpty {
                    await transcribeAndUpdateLegacy(samples)
                }
            }
            bufferRef.deallocate()
        }
        #endif
    }

    private func startAmbientLegacy() async {
        #if canImport(AVFoundation) && os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let chunkDuration: TimeInterval = 30
        let sampleRate = recordingFormat.sampleRate
        let chunkSamples = Int(sampleRate * chunkDuration)

        let bufferRef = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
        bufferRef.initialize(to: [])

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let channelData, frameLength > 0 {
                bufferRef.pointee.append(contentsOf: Array(UnsafeBufferPointer(start: channelData, count: frameLength)))
                if bufferRef.pointee.count > chunkSamples * 2 {
                    bufferRef.pointee.removeFirst(bufferRef.pointee.count - chunkSamples * 2)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Could not start ambient audio: \(error.localizedDescription)"
            bufferRef.deallocate()
            return
        }

        self.audioEngine = engine
        self.isAmbientActive = true

        ambientTask = Task {
            var lastTranscript = ""

            while !Task.isCancelled && isAmbientActive {
                try? await Task.sleep(for: .seconds(chunkDuration))
                guard isAmbientActive else { break }

                let samples = bufferRef.pointee
                guard samples.count > Int(sampleRate * 2) else { continue }

                let text = await transcribeRawLegacy(Array(samples.suffix(chunkSamples)))

                if let text, !text.isEmpty, text != lastTranscript {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 10 {
                        let fragment = AmbientFragment(
                            text: trimmed,
                            timestamp: Date()
                        )
                        ambientFragments.append(fragment)

                        if ambientFragments.count > 50 {
                            ambientFragments.removeFirst(ambientFragments.count - 50)
                        }
                    }
                    lastTranscript = text
                }
            }

            bufferRef.deallocate()
        }
        #else
        error = "Ambient capture requires iOS"
        #endif
    }

    // MARK: - Private: audio engine

    #if canImport(AVFoundation) && os(iOS)
    private func startAudioEngine() async {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            switch captureProfile {
            case .measurement:
                // Unchanged on purpose: the VoiceAcoustic* series in collection was measured
                // here. `.voiceChat` would switch on AGC + noise suppression and silently put
                // a step change in rmsDb / f0 / pauseRatio.
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            case .conversation:
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat,
                                             options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker])
            }
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()

        // O `catch` abaixo só pega erro SWIFT. `prepare()` levanta exceção
        // OBJECTIVE-C quando o grafo é inválido, e exceção ObjC não é capturável
        // em Swift: ela chama abort() e o app MORRE.
        //
        // Medido no aparelho dele (BeagleCockpit-2026-08-04-170839.ips):
        //   AVAudioEngine.prepare -> AVAudioEngineGraph::Initialize -> NSException
        //   -> SIGABRT, saindo de startAudioEngine().
        //
        // A causa é o formato do nó de entrada vir inválido (0 Hz ou 0 canais) —
        // acontece quando a rota de áudio ainda não assentou depois de ativar a
        // sessão, o que é a regra com Bluetooth, não a exceção.
        //
        // Tocar em `inputNode` força o grafo a resolver a entrada; validar ANTES de
        // `prepare()` troca um crash por uma mensagem. Nunca chame prepare() sem
        // esta checagem.
        let formatoDeEntrada = engine.inputNode.inputFormat(forBus: 0)
        let formatoDeEntradaValido = formatoDeEntrada.sampleRate > 0 && formatoDeEntrada.channelCount > 0
        guard formatoDeEntradaValido else {
            self.error = "O microfone não abriu (rota de áudio indisponível). Tente de novo; se estiver com fone, desconecte e repita."
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            return
        }

        self.audioEngine = engine
        self.isRecording = true
    }

    private func stopAudioEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    #else
    private func startAudioEngine() async {
        error = "Speech capture requires iOS"
    }

    private func stopAudioEngine() {
        isRecording = false
    }
    #endif

    // MARK: - Private: legacy transcription (SFSpeechRecognizer)

    private func transcribeAndUpdateLegacy(_ samples: [Float]) async {
        if let text = await transcribeRawLegacy(samples), !text.isEmpty {
            transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Best available on-device recognizer for the user's language.
    nonisolated private static func legacyRecognizer() -> SFSpeechRecognizer? {
        let supported = SFSpeechRecognizer.supportedLocales()
        for candidate in [Locale.current, Locale(identifier: "pt-BR"), Locale(identifier: "pt_BR")] {
            if supported.contains(where: { $0.identifier == candidate.identifier }),
               let r = SFSpeechRecognizer(locale: candidate) {
                return r
            }
        }
        let lang = Locale.current.language.languageCode?.identifier ?? "pt"
        if let near = supported.first(where: { $0.language.languageCode?.identifier == lang }),
           let r = SFSpeechRecognizer(locale: near) {
            return r
        }
        return SFSpeechRecognizer()
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

    private func transcribeRawLegacy(_ samples: [Float]) async -> String? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let audioData = buffer.floatChannelData![0]
        audioData.initialize(from: samples, count: samples.count)

        // Was hard-coded en-US: on the fallback path that meant transcribing pt-BR speech with
        // an English recognizer — a silent, blame-the-model failure. Prefer the device locale,
        // then pt-BR, then whatever the system offers.
        let recognizer = Self.legacyRecognizer()
        guard recognizer?.isAvailable == true else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = true

            var finalTranscription: String?
            var didResume = false

            let task = recognizer!.recognitionTask(with: request) { result, error in
                if didResume { return }

                if error != nil {
                    didResume = true
                    continuation.resume(returning: nil)
                    return
                }

                if let result = result, result.isFinal {
                    finalTranscription = result.bestTranscription.formattedString
                    didResume = true
                    continuation.resume(returning: finalTranscription)
                }
            }

            request.append(buffer)
            request.endAudio()

            Task {
                try? await Task.sleep(for: .seconds(5))
                if !didResume {
                    task.cancel()
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Ambient fragment model

struct AmbientFragment: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let timestamp: Date
}
