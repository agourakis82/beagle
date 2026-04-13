//
//  SpeechRecognizer.swift
//  BeagleCockpit
//
//  Real-time speech recognition using SFSpeechRecognizer + AVAudioEngine.
//  Streams partial transcription results as they arrive.
//  Used by ThoughtCaptureView for voice-to-text thought capture.
//

#if canImport(Speech) && canImport(AVFoundation) && os(iOS)
import Speech
import AVFoundation
import Observation

@Observable
@MainActor
final class SpeechRecognizer {

    private(set) var transcript: String = ""
    private(set) var isRecording: Bool = false
    private(set) var error: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Start

    func startRecording() async {
        error = nil
        transcript = ""

        // Check authorization
        let authorized = await Self.requestAuthorization()
        guard authorized else {
            error = "Speech recognition not authorized. Enable in Settings → Privacy → Speech Recognition."
            return
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Could not configure audio session: \(error.localizedDescription)"
            return
        }

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition not available on this device."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap to feed audio to recognizer
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Could not start audio engine: \(error.localizedDescription)"
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isRecording = true

        // Start recognition
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    // Ignore cancellation errors (normal when stopping)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.error = error.localizedDescription
                    }
                    self.stopRecording()
                }

                if result?.isFinal == true {
                    self.stopRecording()
                }
            }
        }
    }

    // MARK: - Stop

    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

#endif
