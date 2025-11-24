use beagle_grok_api::{GrokClient, GrokModel};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let api_key = std::env::var("GROK_API_KEY")
        .or_else(|_| std::env::var("XAI_API_KEY"))
        .expect("GROK_API_KEY or XAI_API_KEY not set");

    println!("Testing Grok 3...");
    let client = GrokClient::with_model(&api_key, GrokModel::Grok3);
    let response = client.chat("Say 'Grok 3 works!'", None).await?;
    println!("✅ Grok 3: {}", response);

    println!("\nTesting Grok 4...");
    let client4 = GrokClient::with_model(&api_key, GrokModel::Grok4);
    let response4 = client4.chat("Say 'Grok 4 works!'", None).await?;
    println!("✅ Grok 4: {}", response4);

    Ok(())
}
