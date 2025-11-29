#!/usr/bin/env rust-script
//! Demonstração do assistente de voz flexível do BEAGLE
//!
//! Mostra 3 modos de uso:
//! 1. Com beagle-smart-router (TieredRouter - recomendado)
//! 2. Com Grok direto
//! 3. Com LLM local/mock (100% offline)
//!
//! Uso:
//! ```bash
//! # Modo 1: Smart Router (usa Grok 3/4 Heavy conforme necessidade)
//! BEAGLE_MODE=smart cargo run --example voice_assistant_flexible
//!
//! # Modo 2: Grok direto (sempre Grok 3)
//! BEAGLE_MODE=grok cargo run --example voice_assistant_flexible
//!
//! # Modo 3: Local/Mock (sem API externa)
//! BEAGLE_MODE=local cargo run --example voice_assistant_flexible
//! ```

use anyhow::Result;
use beagle_whisper::BeagleVoiceAssistant;
use tracing::{info, Level};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<()> {
    // Inicializa logging
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    info!("🚀 Assistente de Voz BEAGLE - Modo Flexível");

    let mode = std::env::var("BEAGLE_MODE").unwrap_or_else(|_| "smart".to_string());
    info!("   Modo selecionado: {}", mode);

    let assistant = BeagleVoiceAssistant::new()?;

    match mode.as_str() {
        "smart" => {
            info!("📡 Usando beagle-smart-router (TieredRouter)");
            info!("   Grok 3 (padrão) + Grok 4 Heavy (crítico)");
            assistant.start_with_smart_router().await?;
        }

        "grok" => {
            info!("📡 Usando Grok API direto (sempre Grok 3)");
            assistant.start_with_grok().await?;
        }

        "local" => {
            info!("💻 Usando LLM local/mock (100% offline)");
            info!("   Whisper: local | TTS: local | LLM: mock");

            // Assistente completamente offline com respostas mockadas
            assistant
                .start_assistant_loop(|text| async move {
                    // Aqui você poderia integrar llama.cpp, ollama, etc.
                    // Por enquanto, resposta mockada inteligente
                    if text.to_lowercase().contains("olá") || text.to_lowercase().contains("oi") {
                        "Olá! Sou o BEAGLE em modo offline. Como posso ajudar com sua pesquisa?"
                            .to_string()
                    } else if text.to_lowercase().contains("quem")
                        && text.to_lowercase().contains("você")
                    {
                        "Sou o BEAGLE, um assistente de pesquisa científica. \
                     Atualmente rodando em modo offline com processamento local."
                            .to_string()
                    } else if text.to_lowercase().contains("tchau")
                        || text.to_lowercase().contains("adeus")
                    {
                        "Até logo! Foi um prazer ajudar.".to_string()
                    } else {
                        format!(
                            "Recebi sua pergunta: '{}'. \
                            Em modo offline, minhas respostas são limitadas. \
                            Configure GROK_API_KEY para respostas completas.",
                            text
                        )
                    }
                })
                .await?;
        }

        "custom" => {
            info!("🔧 Modo customizado - exemplo com callback inline");

            // Exemplo de callback totalmente customizado
            assistant
                .start_assistant_loop(|text| async move {
                    // Aqui você tem total controle:
                    // - Pode chamar múltiplos LLMs
                    // - Fazer ensemble
                    // - Implementar lógica condicional
                    // - Integrar com banco de dados
                    // - etc.

                    let word_count = text.split_whitespace().count();

                    if word_count < 5 {
                        // Perguntas curtas: resposta direta
                        format!("Entendi: '{}'.  Uma resposta curta aqui.", text)
                    } else {
                        // Perguntas longas: análise mais profunda
                        format!(
                            "Pergunta complexa detectada ({} palavras). \
                            Analisando: '{}'. Resposta detalhada aqui.",
                            word_count, text
                        )
                    }
                })
                .await?;
        }

        _ => {
            eprintln!("❌ Modo inválido: {}", mode);
            eprintln!("   Modos válidos: smart, grok, local, custom");
            std::process::exit(1);
        }
    }

    Ok(())
}
