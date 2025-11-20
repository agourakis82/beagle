//! Exemplo de uso do BEAGLE Bilingual

use beagle_bilingual::{auto_bilingual, generate_bilingual_thread, to_bilingual, BeagleTwitter};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    println!("🌐 BEAGLE Bilingual - Exemplo de Uso\n");

    // 1. Tradução básica
    println!("1. Tradução básica:");
    let text_pt = "Este é um paper sobre KEC 3.0 e sua aplicação em biomateriais.";
    let bilingual = to_bilingual(text_pt).await?;
    println!("   PT: {}", bilingual.pt);
    println!("   EN: {}\n", bilingual.en);

    // 2. Detecção automática
    println!("2. Detecção automática:");
    let text_en = "This is a paper about KEC 3.0 and its application in biomaterials.";
    let bilingual_auto = auto_bilingual(text_en).await?;
    println!("   PT: {}", bilingual_auto.pt);
    println!("   EN: {}\n", bilingual_auto.en);

    // 3. Geração de thread bilíngue
    println!("3. Geração de thread bilíngue:");
    let title_pt = "KEC 3.0: Uma Nova Métrica para Análise de Biomateriais";
    let abstract_pt = "Este trabalho apresenta KEC 3.0, uma métrica inovadora...";
    let paper_url = "https://arxiv.org/abs/2024.12345";

    let thread = generate_bilingual_thread(title_pt, abstract_pt, paper_url).await?;
    for (i, tweet) in thread.iter().enumerate() {
        println!("   Tweet {}: {}", i + 1, &tweet[..tweet.len().min(80)]);
    }

    // 4. Postar no Twitter (se token configurado)
    if let Ok(token) = std::env::var("TWITTER_BEARER_TOKEN") {
        println!("\n4. Postando no Twitter...");
        let twitter = BeagleTwitter::new(&token);
        match twitter.thread_paper(title_pt, abstract_pt, paper_url).await {
            Ok(_) => println!("   ✅ Thread postada com sucesso!"),
            Err(e) => println!("   ❌ Erro: {}", e),
        }
    } else {
        println!("\n4. Twitter não configurado (TWITTER_BEARER_TOKEN não definido)");
    }

    println!("\n✅ Exemplo concluído!");
    Ok(())
}
