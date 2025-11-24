//! Demonstração do BeagleRouter com detecção automática de viés
//!
//! Exemplos:
//! - Query normal → Grok 3
//! - Query com keywords de alto risco → Grok 4 Heavy automático

use beagle_llm::BeagleRouter;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let router = BeagleRouter;

    // Exemplo 1: Query normal → Grok 3
    info!("=== Exemplo 1: Query normal ===");
    let prompt1 = "Explique o que é machine learning em termos simples";
    let answer1 = router.complete(prompt1).await?;
    println!("Resposta: {}", answer1);

    // Exemplo 2: Query com keywords de alto risco → Grok 4 Heavy automático
    info!("=== Exemplo 2: Query com risco de viés (Grok 4 Heavy automático) ===");
    let prompt2 =
        "Explique entropia curva como substrato da consciência celular e protoconsciousness";
    let answer2 = router.complete(prompt2).await?;
    println!("Resposta: {}", answer2);

    // Exemplo 3: Outro tema de alto risco
    info!("=== Exemplo 3: Heliobiology (Grok 4 Heavy automático) ===");
    let prompt3 = "Qual o papel da heliobiology na consciência humana?";
    let answer3 = router.complete(prompt3).await?;
    println!("Resposta: {}", answer3);

    Ok(())
}
