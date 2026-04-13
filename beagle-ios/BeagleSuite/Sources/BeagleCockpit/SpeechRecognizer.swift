//
//  SpeechRecognizer.swift
//  BeagleCockpit
//
//  On-device speech-to-text using WhisperKit (OpenAI Whisper on Apple Neural Engine).
//  Streams real-time transcription with no cloud dependency.
//
//  Falls back to Apple SFSpeechRecognizer if WhisperKit model not downloaded.
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

    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false
    private(set) var error: String?
    private(set) var isWhisperReady: Bool = false
    private(set) var downloadProgress: Double = 0

    #if canImport(WhisperKit) && os(iOS)
    nonisolated(unsafe) private var whisperKit: WhisperKit?
    #endif

    #if canImport(AVFoundation) && os(iOS)
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    #endif

    // MARK: - Setup WhisperKit

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

    // MARK: - Start Recording

    func startRecording() async {
        error = nil
        transcript = ""

        #if canImport(AVFoundation) && os(iOS)
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        audioBuffer = []
        let bufferRef = UnsafeMutablePointer<[Float]>.allocate(capacity: 1)
        bufferRef.initialize(to: [])

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { buffer, _ in
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let channelData, frameLength > 0 {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                bufferRef.pointee.append(contentsOf: samples)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Could not start audio: \(error.localizedDescription)"
            bufferRef.deallocate()
            return
        }

        self.audioEngine = engine
        self.isRecording = true

        // Periodic transcription (every 2 seconds)
        Task {
            while isRecording {
                try? await Task.sleep(for: .seconds(2))
                guard isRecording else { break }

                let currentSamples = bufferRef.pointee

                #if canImport(WhisperKit)
                if !currentSamples.isEmpty {
                    await self.transcribeChunk(currentSamples)
                }
                #endif
            }
            bufferRef.deallocate()
        }
        #else
        error = "Audio recording requires iOS"
        #endif
    }

    #if canImport(WhisperKit) && os(iOS)
    private func transcribeChunk(_ samples: [Float]) async {
        guard let whisper = whisperKit else { return }
        do {
            let results = try await whisper.transcribe(audioArray: samples)
            if let text = results.first?.text, !text.isEmpty {
                self.transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            // Whisper failed for this chunk — will retry next cycle
        }
    }
    #endif

    // MARK: - Stop Recording

    func stopRecording() {
        #if canImport(AVFoundation) && os(iOS)
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Fallback to Apple Speech (if Whisper unavailable)

    func startRecordingAppleSpeech() async {
        #if canImport(Speech) && canImport(AVFoundation) && os(iOS)
        error = nil
        transcript = ""

        let authorized = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard authorized else {
            error = "Speech recognition not authorized."
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
            return
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition not available."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
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

        recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if result?.isFinal == true || error != nil {
                    self.stopRecording()
                }
            }
        }
        #endif
    }
}
