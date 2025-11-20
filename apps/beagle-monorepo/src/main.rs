//! BEAGLE MONOREPO — Orquestrador Principal
//! Integra todos os projetos: Darwin, KEC, PBPK, PCS, Heliobiology, etc.

use beagle_smart_router::query_smart;
use beagle_darwin::DarwinCore;
use beagle_workspace::{PBPKPlatform, HeliobiologyPlatform, Kec3Engine};
use beagle_whisper::BeagleVoiceAssistant;
use tracing::{info, error};
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Inicializa tracing
    tracing_subscriber::fmt::init();
    
    println!("╔════════════════════════════════════════════════════════════╗");
    println!("║  BEAGLE MONOREPO — TUDO JUNTO — 2025-11-19                ║");
    println!("║  Darwin + KEC + PBPK + PCS + Heliobiology + Scaffold     ║");
    println!("╚════════════════════════════════════════════════════════════╝");
    println!();
    
    info!("🚀 Inicializando componentes do BEAGLE...");
    
    // Inicializa Darwin Core
    let darwin = DarwinCore::new();
    info!("✅ Darwin Core inicializado");
    
    // Inicializa PBPK Platform
    let pbpk = PBPKPlatform::new();
    info!("✅ PBPK Platform inicializado");
    
    // Inicializa Heliobiology
    let helio = HeliobiologyPlatform::new();
    info!("✅ Heliobiology Platform inicializado");
    
    // Inicializa KEC 3.0
    let kec = Kec3Engine::new();
    info!("✅ KEC 3.0 Engine inicializado");
    
    // Inicializa Whisper (opcional - só se whisper.cpp estiver instalado)
    let whisper_assistant = BeagleVoiceAssistant::new().ok();
    if whisper_assistant.is_some() {
        info!("✅ Whisper Voice Assistant inicializado");
    } else {
        info!("ℹ️  Whisper não disponível (whisper.cpp não instalado)");
    }
    
    println!();
    println!("🎯 BEAGLE MONOREPO — Todos os sistemas operacionais");
    println!("   - Darwin Core (GraphRAG + Self-RAG)");
    println!("   - KEC 3.0 GPU (Julia)");
    println!("   - PBPK Platform (Multimodal Encoders + PINN)");
    println!("   - Heliobiology (Kairos + HRV Mood)");
    println!("   - Embeddings SOTA (Nomic, Jina, GTE-Qwen2)");
    println!("   - Vector Search Híbrido");
    println!("   - Workflows Agentic (ReAct + Reflexion)");
    if whisper_assistant.is_some() {
        println!("   - Whisper Voice Assistant (transcrição local)");
    }
    println!();
    
    // Loop principal
    let mut cycle = 0;
    loop {
        cycle += 1;
        info!("🔄 Ciclo BEAGLE #{}", cycle);
        
        // Query integrada
        let prompt = format!(
            "Estado atual do BEAGLE (ciclo {}). \
            Gera hipótese integrada sobre: \
            KEC 3.0 + Heliobiology + Psiquiatria Simbólica + PBPK. \
            Usa GraphRAG + Self-RAG para buscar conhecimento relevante.",
            cycle
        );
        
        match query_smart(&prompt, 100000).await {
            Ok(response) => {
                println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                println!("BEAGLE Response (Ciclo {}):", cycle);
                println!("{}", response);
                println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            }
            Err(e) => {
                error!("❌ Erro na query: {}", e);
            }
        }
        
        println!();
        
        // Testa componentes
        if cycle % 5 == 0 {
            info!("🧪 Testando componentes...");
            
            // Testa PBPK
            if let Err(e) = pbpk.encode_multimodal("CCO").await {
                error!("❌ Erro PBPK: {}", e);
            } else {
                info!("✅ PBPK OK");
            }
            
            // Testa Heliobiology
            let history = vec![1.0f32; 72];
            if let Err(e) = helio.forecast_kairos(&history).await {
                error!("❌ Erro Heliobiology: {}", e);
            } else {
                info!("✅ Heliobiology OK");
            }
        }
        
        // Aguarda próximo ciclo
        tokio::time::sleep(Duration::from_secs(300)).await;
    }
}

