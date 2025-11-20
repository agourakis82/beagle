//
//  ContentView.swift
//  BEAGLE Assistant - Tela Bonita
//

import SwiftUI

struct ContentView: View {
    @Environment(BeagleAssistant.self) private var assistant
    
    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: assistant.isListening ? "waveform.path.ecg" : "waveform")
                .font(.system(size: 120))
                .foregroundStyle(assistant.isListening ? .green : .secondary)
            
            // Título
            Text("BEAGLE")
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.cyan)
            
            // Transcrição
            if !assistant.transcription.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu disseste:")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text(assistant.transcription)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
            
            // Resposta
            if !assistant.response.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BEAGLE respondeu:")
                        .font(.title3)
                        .foregroundColor(.cyan)
                    
                    Text(assistant.response)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal)
            }
            
            Button(assistant.isListening ? "Ouvindo..." : "Falar com BEAGLE") {
                assistant.isListening ? assistant.stopListening() : assistant.startListening()
            }
            .font(.title)
            .padding(40)
            .background(assistant.isListening ? Color.red : Color.cyan)
            .foregroundColor(.black)
            .clipShape(Circle())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .environment(BeagleAssistant.shared)
}

