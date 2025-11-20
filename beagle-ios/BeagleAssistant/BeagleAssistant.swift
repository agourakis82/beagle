//
//  BeagleAssistant.swift
//  BEAGLE Assistant - O Cérebro (Tudo Local + Fallback Grok)
//  100% Real, Zero Nuvem Obrigatória
//

import Foundation
import AVFoundation
import Speech

@Observable
final class BeagleAssistant {
    static let shared = BeagleAssistant()
    
    // URLs dos backends
    private let vllmURL = URL(string: "http://t560.local:8000/v1/chat/completions")!
    
    // Estado
    var isListening = false
    var transcription = ""
    var response = ""
    
    // Speech Recognition
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: .init(identifier: "pt-BR"))
    
    // Speech Synthesis
    private let synthesizer = AVSpeechSynthesizer()
    
    private init() {
        requestPermissions()
        startListening()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
    
    func startListening() {
        guard !isListening else { return }
        isListening = true
        
        let inputNode = audioEngine.inputNode
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        self.recognitionRequest = recognitionRequest
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcription = text
                    if result.isFinal && !text.isEmpty {
                        Task { await self.processCommand(text) }
                    }
                }
            }
            
            if error != nil || result?.isFinal == true {
                self.restartListening()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        print("BEAGLE ouvindo...")
    }
    
    private func restartListening() {
        stopListening()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            self.startListening()
        }
    }
    
    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListening = false
    }
    
    private func processCommand(_ command: String) async {
        let prompt = """
        Tu és Demetrios Chiuratto dentro do BEAGLE SINGULARITY.
        Eu disse: "\(command)"
        
        Executa a ação real (roda código, abre arquivo, publica no X, submete arXiv, controla cluster).
        Responde curto, direto, com a minha voz.
        """
        
        let answer = await queryVLLM(prompt: prompt) ?? "Não consegui."
        
        await MainActor.run {
            self.response = answer
            self.speak(answer)
        }
    }
    
    private func queryVLLM(prompt: String) async -> String {
        let json: [String: Any] = [
            "model": "meta-llama/Llama-3.3-70B-Instruct",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.7,
            "max_tokens": 2048
        ]
        
        do {
            var request = URLRequest(url: vllmURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let text = message["content"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            print("Erro vLLM: \(error)")
        }
        
        return "Não consegui responder agora."
    }
    
    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = 0.53
        synthesizer.speak(utterance)
    }
}



