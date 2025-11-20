//! Bilingual Integration - Integra tradução bilíngue no loop adversarial

use beagle_bilingual::{to_bilingual, BeagleTwitter, generate_bilingual_thread};
use tracing::{info, warn};

/// Integra publicação bilíngue quando score > 98
pub async fn integrate_bilingual_publish(
    title_pt: &str,
    abstract_pt: &str,
    paper_url: &str,
    score: f64,
) -> anyhow::Result<()> {
    if score > 98.0 {
        info!("🌐 Score > 98. Publicando bilíngue automaticamente...");
        
        // Gera thread bilíngue
        let thread = match generate_bilingual_thread(title_pt, abstract_pt, paper_url).await {
            Ok(t) => t,
            Err(e) => {
                warn!("⚠️  Falha ao gerar thread bilíngue: {}. Continuando...", e);
                return Ok(());
            }
        };
        
        // Posta no Twitter se token configurado
        if let Ok(token) = std::env::var("TWITTER_BEARER_TOKEN") {
            match BeagleTwitter::new(&token).thread(thread).await {
                Ok(_) => {
                    info!("✅ Thread bilíngue postada no Twitter");
                }
                Err(e) => {
                    warn!("⚠️  Falha ao postar no Twitter: {}. Continuando...", e);
                }
            }
        } else {
            info!("ℹ️  TWITTER_BEARER_TOKEN não configurado. Thread gerada mas não postada.");
            for (i, tweet) in thread.iter().enumerate() {
                info!("🐦 Tweet {}: {}", i + 1, tweet);
            }
        }
    }
    
    Ok(())
}

/// Converte qualquer resposta do BEAGLE para bilíngue
pub async fn make_response_bilingual(text: &str) -> anyhow::Result<(String, String)> {
    let bilingual = to_bilingual(text).await?;
    Ok((bilingual.pt, bilingual.en))
}

