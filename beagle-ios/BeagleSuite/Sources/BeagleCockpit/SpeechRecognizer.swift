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

    func startRecording() async {
        error = nil
        transcript = ""
        audioWindows.removeAll()
        recordingStartedAt = Date()

        if useLegacyRecognizer {
            await startRecordingLegacy()
        } else {
            await startRecordingAnalyzer()
        }
    }

    func stopRecording() {
        // Signal the analyzer input stream to finish
        analyzerInputContinuation?.finish()
        analyzerInputContinuation = nil

        // Cancel the recording task
        recordingTask?.cancel()
        recordingTask = nil

        stopAudioEngine()
        uploadAcousticSummaryForCompletedTurn()
    }

    /// Computes the turn's voice-acoustic summary from windows accumulated during the tap
    /// (see extractSamples/audioWindows above) and uploads it like any other health metric.
    /// Best-effort, fire-and-forget — never blocks stopRecording() or the caller's UI flow.
    private func uploadAcousticSummaryForCompletedTurn() {
        guard !audioWindows.isEmpty else { return }
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
            guard self != nil else { return }

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

    private func startRecordingLegacy() async {
        #if canImport(AVFoundation) && os(iOS)
        await startAudioEngine()
        guard isRecording else { return }

        let bufferRef = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
        bufferRef.initialize(to: [])

        audioEngine?.inputNode.installTap(onBus: 0, bufferSize: 4096, format: audioEngine!.inputNode.outputFormat(forBus: 0)) { buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let channelData, frameLength > 0 {
                bufferRef.pointee.append(contentsOf: Array(UnsafeBufferPointer(start: channelData, count: frameLength)))
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
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
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

    private func transcribeRawLegacy(_ samples: [Float]) async -> String? {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format!, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let audioData = buffer.floatChannelData![0]
        audioData.initialize(from: samples, count: samples.count)

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
