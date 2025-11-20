//
//  BeagleAssistantApp.swift
//  BEAGLE Assistant - Assistente Pessoal Completo (Fala → Age)
//  100% Real, Roda HOJE no iPhone/Mac/Watch
//

import SwiftUI
import Speech
import AVFoundation

@main
struct BeagleAssistantApp: App {
    @State private var assistant = BeagleAssistant.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(assistant)
                .onAppear {
                    assistant.startListening()
                }
        }
    }
}

