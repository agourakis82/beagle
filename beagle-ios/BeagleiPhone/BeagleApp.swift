//
//  BeagleApp.swift
//  BeagleiPhone
//
//  iPhone App - Interface principal do BEAGLE
//

import SwiftUI

@main
struct BeagleApp: App {
    @StateObject private var beagle = BeagleCore.shared
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(beagle)
        }
    }
}

struct MainView: View {
    @EnvironmentObject var beagle: BeagleCore
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("BEAGLE")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.cyan)
                
                // Status
                HStack {
                    Circle()
                        .fill(beagle.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(beagle.isConnected ? "Conectado" : "Desconectado")
                        .font(.headline)
                }
                
                // Input
                TextField("Digite sua pergunta...", text: $beagle.inputText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                // Botão de envio
                Button("Enviar") {
                    beagle.sendQuery()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!beagle.isConnected)
                
                // Resposta
                ScrollView {
                    Text(beagle.lastResponse)
                        .padding()
                }
                .frame(maxHeight: 400)
                
                Spacer()
            }
            .padding()
            .navigationTitle("BEAGLE")
        }
    }
}

class BeagleCore: ObservableObject {
    static let shared = BeagleCore()
    
    @Published var isConnected = false
    @Published var inputText = ""
    @Published var lastResponse = "Aguardando conexão..."
    
    private let baseURL = "http://localhost:8080" // TODO: Configurar
    
    init() {
        checkConnection()
    }
    
    func checkConnection() {
        // TODO: Verificar conexão com backend
        isConnected = true
    }
    
    func sendQuery() {
        guard !inputText.isEmpty else { return }
        
        // TODO: Enviar para backend Rust
        Task {
            let response = await queryBackend(inputText)
            await MainActor.run {
                lastResponse = response
                inputText = ""
            }
        }
    }
    
    private func queryBackend(_ text: String) async -> String {
        // TODO: Implementar chamada HTTP real
        return "Resposta do BEAGLE para: \(text)"
    }
}

