//! Example: Paradoxical Self-Modification Engine
//!
//! Demonstra auto-modificação de código via paradoxos autorreferentes.

use beagle_paradox::{ParadoxEngine, SelfModifier};
use std::path::PathBuf;
use tracing::{info, Level};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();

    info!("🔬 PARADOXICAL SELF-MODIFICATION ENGINE: Exemplo completo");

    // Exemplo 1: Paradoxo de perfeição
    info!("💀 EXEMPLO 1: Paradoxo de perfeição");
    let paradox = ParadoxEngine::new();
    
    // NOTA: Este exemplo modifica um arquivo real - use com cuidado!
    // Descomente apenas se quiser testar em um arquivo específico
    /*
    let result = paradox
        .run_paradox(
            PathBuf::from("crates/beagle-quantum/src/superposition.rs"),
            "Melhore este código até que ele seja perfeito. Quando for perfeito, ele deve se auto-deletar.",
            8,
        )
        .await?;

    info!("✅ Paradoxo executado:");
    info!("  - Iterações: {}", result.iterations_completed);
    info!("  - Paradoxo resolvido: {}", if result.paradox_resolved { "SIM" } else { "NÃO" });
    info!("  - Código final: {} caracteres", result.final_code_length);
    
    if let Some(strategy) = &result.resolution_strategy {
        info!("  - Estratégia de resolução: {}", strategy);
    }

    for (i, modification) in result.modifications_made.iter().enumerate() {
        info!("  Modificação {}: {}", i + 1, modification);
    }
    */

    // Exemplo 2: Paradoxo de melhoria infinita
    info!("💀 EXEMPLO 2: Paradoxo de melhoria infinita");
    let paradox2 = ParadoxEngine::new();
    
    // Este exemplo mostra como usar sem modificar arquivos reais
    info!("Paradoxo: 'Melhore este arquivo até que ele prove que não pode ser melhorado'");
    info!("(Exemplo desabilitado para segurança - descomente para testar)");

    // Exemplo 3: Validação de código
    info!("✅ EXEMPLO 3: Validação de código");
    let modifier = SelfModifier::new();
    
    let valid_code = r#"
        pub fn example() -> i32 {
            42
        }
    "#;

    let invalid_code = "";

    info!("Código válido: {}", modifier.validate_rust_code(valid_code));
    info!("Código inválido: {}", modifier.validate_rust_code(invalid_code));

    info!("🎯 PARADOXICAL SELF-MODIFICATION COMPLETA");
    info!("⚠️  NOTA: Use com cuidado - este módulo modifica código real!");

    Ok(())
}




