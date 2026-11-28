//
//  OpenAILiveVoiceSession+AudioEngine.swift
//  BeagleCore — Captura thread-safe e grafo de áudio full-duplex (`AVAudioEngine`)
//

import Foundation
#if canImport(AVFoundation)
@preconcurrency import AVFoundation
#endif

// MARK: - Captura de Microfone Thread-Safe para PCM16LE 24kHz (Fora do MainActor)

#if os(iOS) || os(visionOS) || os(macOS)
final class LiveAudioCaptureTapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let continuation: AsyncStream<(Data, Float)>.Continuation
    private var accumulatedPCM = Data()
    /// Envia pacotes de ~60 ms (1.440 amostras × 2 bytes = 2.880 bytes) para baixa latência de voz.
    private let flushThresholdBytes = 2_880

    init(
        inputFormat: AVAudioFormat,
        continuation: AsyncStream<(Data, Float)>.Continuation
    ) {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(OpenAILiveProtocol.sampleRateHz),
            channels: 1,
            interleaved: true
        )!
        self.targetFormat = target
        self.converter = AVAudioConverter(from: inputFormat, to: target)
        self.continuation = continuation
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.computeNormalizedRMS(buffer)
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / max(1.0, buffer.format.sampleRate)
        let outCapacity = AVAudioFrameCount(max(64, Int(ceil(Double(buffer.frameLength) * ratio)) + 32))
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        final class OneShotBox: @unchecked Sendable {
            var consumed = false
            let source: AVAudioPCMBuffer
            init(_ source: AVAudioPCMBuffer) { self.source = source }
        }
        let box = OneShotBox(buffer)
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
            if box.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            box.consumed = true
            outStatus.pointee = .haveData
            return box.source
        }

        guard status != .error, convError == nil, outBuffer.frameLength > 0,
              let int16Ptr = outBuffer.int16ChannelData?[0] else {
            return
        }

        let byteCount = Int(outBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Ptr, count: byteCount)
        accumulatedPCM.append(data)

        if accumulatedPCM.count >= flushThresholdBytes {
            let chunk = accumulatedPCM
            accumulatedPCM.removeAll(keepingCapacity: true)
            continuation.yield((chunk, rms))
        }
    }

    func finish() {
        if !accumulatedPCM.isEmpty {
            continuation.yield((accumulatedPCM, 0))
            accumulatedPCM.removeAll()
        }
        continuation.finish()
    }

    private static func computeNormalizedRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        if let f32 = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count {
                let s = f32[i]
                sum += s * s
            }
            let rms = (sum / Float(count)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            return min(max((db + 50) / 50, 0), 1)
        }
        return 0
    }
}
#endif

// MARK: - Grafo de Áudio Full-Duplex (`AVAudioEngine` + Cancelamento de Eco `.voiceChat`)

extension OpenAILiveVoiceSession {
    #if os(iOS) || os(visionOS) || os(macOS)
    static func requestMicrophonePermission() async -> Bool {
        #if os(iOS) || os(visionOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
        #endif
    }

    func startFullDuplexAudioEngine() async throws {
        teardownAudioEngineNodes()

        #if os(iOS) || os(visionOS)
        try await BeagleAudioSessionCoordinator.shared.activateFullDuplexVoiceChat(
            preferredSampleRate: Double(OpenAILiveProtocol.sampleRateHz),
            preferredIOBufferDuration: 0.02,
            duckOthers: true
        )
        audioSessionActive = true
        #endif

        guard isActive else {
            stopFullDuplexAudioEngine()
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(OpenAILiveProtocol.sampleRateHz),
            channels: 1,
            interleaved: false
        )!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFormat)

        let inputNode = engine.inputNode
        let hwInputFormat = inputNode.outputFormat(forBus: 0)

        var streamContinuation: AsyncStream<(Data, Float)>.Continuation!
        let captureStream = AsyncStream<(Data, Float)> { continuation in
            streamContinuation = continuation
        }

        let processor = LiveAudioCaptureTapProcessor(
            inputFormat: hwInputFormat,
            continuation: streamContinuation
        )
        self.tapProcessor = processor

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: hwInputFormat) { buffer, _ in
            processor.process(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.playbackFormat = outFormat
        self.scheduledOutputBuffers = 0

        audioSendTask = Task { @MainActor [weak self] in
            for await (pcm16Chunk, rms) in captureStream {
                guard let self, self.isActive else { break }
                self.updateInputLevel(self.inputLevel * 0.65 + rms * 0.35)
                guard self.isConnected, !self.isPaused else { continue }
                if let payload = OpenAILiveProtocol.buildInputAudioAppendPayload(
                    chunk: pcm16Chunk,
                    carryoverByte: &self.carryoverByte
                ) {
                    _ = await self.sendJSON(payload)
                }
            }
        }
    }

    func scheduleOutputPCM16(_ pcm16Data: Data) {
        guard let player = playerNode,
              let format = playbackFormat,
              let engine = audioEngine,
              engine.isRunning else {
            return
        }

        let sampleCount = pcm16Data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)),
              let dst = pcmBuffer.floatChannelData?[0] else {
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)
        var sumSquares: Float = 0
        pcm16Data.withUnsafeBytes { rawBuf in
            guard let int16Base = rawBuf.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: int16Base[i])
                let normalized = Float(sample) / 32768.0
                dst[i] = normalized
                sumSquares += normalized * normalized
            }
        }

        let rms = (sumSquares / Float(sampleCount)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        updateOutputLevel(min(max((db + 50) / 50, 0), 1))

        speakingDecayTask?.cancel()
        scheduledOutputBuffers += 1
        if !player.isPlaying {
            player.play()
        }
        if !isPaused && activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emitPhaseUpdate(.speaking, line: CompanionLiveVoicePhase.speaking.defaultLinePtBR)
        }

        player.scheduleBuffer(pcmBuffer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleScheduledOutputBufferFinished()
            }
        }
    }

    private func handleScheduledOutputBufferFinished() {
        scheduledOutputBuffers = max(0, scheduledOutputBuffers - 1)
        guard scheduledOutputBuffers == 0 else { return }
        updateOutputLevel(0)
        speakingDecayTask?.cancel()
        speakingDecayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self,
                  !Task.isCancelled,
                  self.isActive,
                  !self.isPaused,
                  self.scheduledOutputBuffers == 0 else { return }
            if self.activeDelegationCount > 0 {
                self.emitPhaseUpdate(.thinking, line: "MoE · consultando exocórtex, Bula & ferramentas…")
            } else {
                self.emitPhaseUpdate(.listening, line: CompanionLiveVoicePhase.listening.defaultLinePtBR)
            }
        }
    }

    func flushLocalPlayback() {
        speakingDecayTask?.cancel()
        speakingDecayTask = nil
        scheduledOutputBuffers = 0
        updateOutputLevel(0)
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }
        player.stop()
        player.play()
    }

    func stopFullDuplexAudioEngine() {
        let hadEngine = teardownAudioEngineNodes()

        #if os(iOS) || os(visionOS)
        if audioSessionActive || hadEngine {
            audioSessionActive = false
            Task.detached(priority: .utility) {
                await BeagleAudioSessionCoordinator.shared.deactivate()
            }
        }
        #else
        _ = hadEngine
        #endif
    }

    @discardableResult
    private func teardownAudioEngineNodes() -> Bool {
        speakingDecayTask?.cancel()
        speakingDecayTask = nil
        scheduledOutputBuffers = 0
        tapProcessor?.finish()
        tapProcessor = nil

        let hadEngine = audioEngine != nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            playerNode?.stop()
            engine.stop()
        }
        playerNode = nil
        playbackFormat = nil
        audioEngine = nil
        return hadEngine
    }
    #else
    func scheduleOutputPCM16(_ pcm16Data: Data) {}
    func flushLocalPlayback() {}
    #endif
}
