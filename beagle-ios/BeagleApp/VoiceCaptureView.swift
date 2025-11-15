import SwiftUI
import AVFoundation
import Speech

struct VoiceCaptureView: View {
    @EnvironmentObject private var store: NodeStore
    @StateObject private var recorder = VoiceRecorder()
    @State private var transcription: String = ""
    @State private var isAuthorized: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Captura de Voz")
                .font(.largeTitle).bold()

            if recorder.isRecording {
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: "waveform").font(.system(size: 36)).foregroundColor(.white))
                        .scaleEffect(recorder.audioLevel)
                        .animation(.easeInOut(duration: 0.5).repeatForever(), value: recorder.audioLevel)
                    Text("Gravando…").font(.headline)
                    Button("Parar") {
                        recorder.stopRecording { url in
                            transcribeAudio(url: url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Button {
                    Task { await requestPermissionsAndStart() }
                } label: {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: "mic.fill").font(.system(size: 36)).foregroundColor(.white))
                }
                .disabled(!isAuthorized)
                Text(isAuthorized ? "Toque para iniciar" : "Conceda permissões para usar a voz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !transcription.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcrição").font(.headline)
                    ScrollView {
                        Text(transcription)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxHeight: 240)

                    HStack {
                        Button("Descartar") { transcription = "" }
                        Spacer()
                        Button("Salvar nota") {
                            Task { await store.createNode(transcription, type: .audio) }
                            transcription = ""
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding()
        .task { await checkAuthorization() }
    }

    private func requestPermissionsAndStart() async {
        await checkAuthorization()
        if isAuthorized {
            recorder.startRecording()
        }
    }

    private func checkAuthorization() async {
        let mic = await AVAudioApplication.requestRecordPermission()
        let speechAuth = await SFSpeechRecognizer.requestAuthorization(.init())
        isAuthorized = mic && (speechAuth == .authorized)
    }

    private func transcribeAudio(url: URL) {
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: url)
        recognizer?.recognitionTask(with: request) { result, error in
            guard let result = result else { return }
            if result.isFinal {
                transcription = result.bestTranscription.formattedString
            }
        }
    }
}

final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording: Bool = false
    @Published var audioLevel: CGFloat = 1.0
    private var recorder: AVAudioRecorder?
    private var completion: ((URL) -> Void)?

    func startRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("recording.m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record()
            isRecording = true
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard let self = self, self.isRecording else { timer.invalidate(); return }
                self.recorder?.updateMeters()
                let power = self.recorder?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, (power + 160) / 160)
                self.audioLevel = CGFloat(1.0 + normalized * 0.3)
            }
        } catch {
            isRecording = false
        }
    }

    func stopRecording(_ completion: @escaping (URL) -> Void) {
        self.completion = completion
        recorder?.stop()
        isRecording = false
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag { completion?(recorder.url) }
    }
}


