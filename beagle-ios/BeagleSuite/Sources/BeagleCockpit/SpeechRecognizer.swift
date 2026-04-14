//
//  SpeechRecognizer.swift
//  BeagleCockpit
//
//  On-device speech-to-text using WhisperKit (OpenAI Whisper on Neural Engine).
//  Two modes:
//    1. Manual: tap to record, tap to stop (thought capture)
//    2. Ambient: continuous background listening, auto-captures insights
//
//  All processing on-device. Zero cloud dependency.
//

import SwiftUI
import BeagleCore

#if canImport(WhisperKit) && os(iOS)
@preconcurrency import WhisperKit
#endif

#if canImport(AVFoundation) && os(iOS)
import AVFoundation
#endif

#if canImport(Speech) && os(iOS)
import Speech
#endif

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

    #if canImport(WhisperKit) && os(iOS)
    nonisolated(unsafe) private var whisperKit: WhisperKit?
    #endif

    #if canImport(AVFoundation) && os(iOS)
    private var audioEngine: AVAudioEngine?
    #endif

    private var ambientTask: Task<Void, Never>?

    // MARK: - Setup

    func setup() async {
        #if canImport(WhisperKit) && os(iOS)
        do {
            whisperKit = try await WhisperKit(
                model: "openai_whisper-tiny",
                downloadBase: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                verbose: false
            )
            isWhisperReady = true
        } catch {
            self.error = "Whisper setup failed: \(error.localizedDescription)"
            isWhisperReady = false
        }
        #endif
    }

    // MARK: - Manual recording (tap to start/stop)

    func startRecording() async {
        error = nil
        transcript = ""
        await startAudioEngine()

        #if canImport(AVFoundation) && os(iOS)
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

        Task {
            while isRecording {
                try? await Task.sleep(for: .seconds(2))
                guard isRecording else { break }
                let samples = bufferRef.pointee
                if !samples.isEmpty {
                    await transcribeAndUpdate(samples)
                }
            }
            bufferRef.deallocate()
        }
        #endif
    }

    func stopRecording() {
        stopAudioEngine()
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

        #if canImport(AVFoundation) && os(iOS)
        // Configure for background audio
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Sliding window: accumulate 30s chunks, transcribe, slide
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
                // Keep only last 60s of audio (2 chunks)
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

        // Background transcription loop
        ambientTask = Task {
            var lastTranscript = ""

            while !Task.isCancelled && isAmbientActive {
                try? await Task.sleep(for: .seconds(chunkDuration))
                guard isAmbientActive else { break }

                let samples = bufferRef.pointee
                guard samples.count > Int(sampleRate * 2) else { continue } // at least 2s of audio

                // Transcribe the chunk
                let text = await transcribeRaw(Array(samples.suffix(chunkSamples)))

                // Only capture if there's meaningful new content
                if let text, !text.isEmpty, text != lastTranscript {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Filter out silence/noise (very short fragments or repeated)
                    if trimmed.count > 10 {
                        let fragment = AmbientFragment(
                            text: trimmed,
                            timestamp: Date()
                        )
                        ambientFragments.append(fragment)

                        // Keep last 50 fragments
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

    func stopAmbient() {
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
    #endif

    // MARK: - Private: transcription

    private func transcribeAndUpdate(_ samples: [Float]) async {
        if let text = await transcribeRaw(samples), !text.isEmpty {
            transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func transcribeRaw(_ samples: [Float]) async -> String? {
        #if canImport(WhisperKit) && os(iOS)
        guard let whisper = whisperKit else { return nil }
        do {
            let results = try await whisper.transcribe(audioArray: samples)
            return results.first?.text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

// MARK: - Ambient fragment model

struct AmbientFragment: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let timestamp: Date
}
