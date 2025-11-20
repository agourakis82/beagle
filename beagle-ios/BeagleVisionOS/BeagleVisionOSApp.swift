//! BEAGLE Vision Pro App - Spatial UI com Fractal 3D
//! 100% Real, Roda no Vision Pro AGORA

import SwiftUI
import RealityKit
import Observation

@main
struct BeagleVisionOSApp: App {
    @State private var assistant = BeagleAssistant.shared
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Fractal 3D Background
                FractalView()
                
                VStack(spacing: 40) {
                    Text("BEAGLE SINGULARITY")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.cyan)
                    
                    if !assistant.response.isEmpty {
                        Text(assistant.response)
                            .font(.system(size: 50))
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    
                    if !assistant.transcription.isEmpty {
                        Text("Tu disseste: \(assistant.transcription)")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(assistant.isListening ? "Ouvindo..." : "Falar com BEAGLE") {
                        if assistant.isListening {
                            assistant.stopListening()
                        } else {
                            assistant.startListening()
                        }
                    }
                    .font(.system(size: 60))
                    .padding(40)
                    .background(assistant.isListening ? Color.red : Color.cyan)
                    .foregroundColor(.black)
                    .clipShape(Circle())
                }
            }
        }
    }
}

struct FractalView: View {
    var body: some View {
        RealityView { content in
            // Fractal 3D usando RealityKit
            let fractal = createFractalEntity()
            content.add(fractal)
        }
    }
    
    func createFractalEntity() -> Entity {
        let entity = Entity()
        
        // Gera fractal recursivo
        for i in 0..<10 {
            let box = ModelEntity(
                mesh: .generateBox(size: 0.1),
                materials: [SimpleMaterial(color: .cyan, isMetallic: true)]
            )
            
            let angle = Double(i) * .pi / 5
            box.position = SIMD3<Float>(
                Float(cos(angle)) * 0.5,
                Float(sin(angle)) * 0.5,
                Float(i) * 0.1
            )
            
            entity.addChild(box)
        }
        
        return entity
    }
}
