//
//  SpeechRecognizer+Engines.swift
//  BeagleCockpit
//
//  On-device SpeechAnalyzer (iOS 26+) and SFSpeechRecognizer fallback capture
//  pipelines plus AVAudioEngine lifecycle management for SpeechRecognizer.
//

import SwiftUI
import BeagleCore
@preconcurrency import Speech
@preconcurrency import AVFoundation

extension SpeechRecognizer {
    // MARK: - SpeechAnalyzer path (iOS 26+)

    func startRecordingAnalyzer() async {
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

    func startAmbientAnalyzer() async {
        #if canImport(AVFoundation) && os(iOS)
        do {
            try await BeagleAudioSessionCoordinator.shared.activateSpeechRecording(
                measurementProfile: true,
                allowBluetoothForMeasurement: true
            )
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

    func startRecordingLegacy() async {
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

    func startAmbientLegacy() async {
        #if canImport(AVFoundation) && os(iOS)
        do {
            try await BeagleAudioSessionCoordinator.shared.activateSpeechRecording(
                measurementProfile: true,
                allowBluetoothForMeasurement: true
            )
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
        do {
            try await BeagleAudioSessionCoordinator.shared.activateSpeechRecording(
                measurementProfile: captureProfile == .measurement,
                allowBluetoothForMeasurement: false
            )
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
            Task.detached(priority: .utility) {
                await BeagleAudioSessionCoordinator.shared.deactivate()
            }
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

    func stopAudioEngine() {
        let wasActive = audioEngine != nil || isRecording
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        if wasActive {
            Task.detached(priority: .utility) {
                await BeagleAudioSessionCoordinator.shared.deactivate()
            }
        }
    }
    #else
    private func startAudioEngine() async {
        error = "Speech capture requires iOS"
    }

    func stopAudioEngine() {
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
