//! BEAGLE iOS App - Assistente Pessoal Completo

import SwiftUI

@main
struct BeagleApp: App {
    @StateObject private var assistant = BeagleAssistant.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // Header
                    VStack {
                        Text("BEAGLE SINGULARITY")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.cyan)
                        
                        Text("Exocórtex Pessoal")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                    
                    // HRV Status
                    VStack(spacing: 12) {
                        Text("HRV: \(Int(assistant.hrvValue))ms")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(assistant.flowState == "FLOW" ? .green : .red)
                        
                        Text(assistant.flowState)
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color(white: 0.1))
                    .cornerRadius(20)
                    
                    // Response
                    ScrollView {
                        Text(assistant.lastResponse)
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    .background(Color(white: 0.1))
                    .cornerRadius(20)
                    
                    // Voice Button
                    Button(action: {
                        assistant.toggleListening()
                    }) {
                        Image(systemName: assistant.isListening ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .frame(width: 120, height: 120)
                            .background(assistant.isListening ? Color.red : Color.green)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
}

