use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use std::time::Instant;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Configurar logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    // Ler API key
    let api_key = std::env::var("ANTHROPIC_API_KEY")
        .expect("❌ ANTHROPIC_API_KEY não encontrada no ambiente");

    println!("🔑 Inicializando Anthropic client...");
    println!("📋 API Key: {}...", &api_key[..20]);

    let client = AnthropicClient::new(api_key)?;
    println!("✅ Cliente inicializado com sucesso\n");

    // ========================================
    // TEST 1: Claude Haiku 4.5 (Rápido)
    // ========================================
    println!("╔══════════════════════════════════════╗");
    println!("║  TEST 1: Claude Haiku 4.5 (Fast)    ║");
    println!("╚══════════════════════════════════════╝");

    let request = CompletionRequest {
        model: ModelType::ClaudeHaiku45,
        messages: vec![Message {
            role: "user".to_string(),
            content: "Diga olá em português e explique o que você é em uma frase.".to_string(),
        }],
        max_tokens: 100,
        temperature: 1.0,
        system: None,
    };

    print!("⏳ Aguardando resposta... ");
    let start = Instant::now();
    let response = client.complete(request).await?;
    let elapsed = start.elapsed();
    println!("✅\n");

    println!("📝 Response:\n{}\n", response.content);
    println!("⏱️  Latency: {:?}", elapsed);
    println!("🏷️  Model: {}", response.model);
    println!(
        "📊 Usage: {}\n",
        serde_json::to_string_pretty(&response.usage)?
    );

    // ========================================
    // TEST 2: Claude Sonnet 4.5 (Premium)
    // ========================================
    println!("╔══════════════════════════════════════╗");
    println!("║  TEST 2: Claude Sonnet 4.5 (Premium)║");
    println!("╚══════════════════════════════════════╝");

    let request = CompletionRequest {
        model: ModelType::ClaudeSonnet45,
        messages: vec![Message {
            role: "user".to_string(),
            content: "Explique o conceito de entropia em uma frase filosófica profunda."
                .to_string(),
        }],
        max_tokens: 150,
        temperature: 1.0,
        system: None,
    };

    print!("⏳ Aguardando resposta... ");
    let start = Instant::now();
    match client.complete(request).await {
        Ok(response) => {
            let elapsed = start.elapsed();
            println!("✅\n");

            println!("📝 Response:\n{}\n", response.content);
            println!("⏱️  Latency: {:?}", elapsed);
            println!("🏷️  Model: {}", response.model);
            println!(
                "📊 Usage: {}\n",
                serde_json::to_string_pretty(&response.usage)?
            );
        }
        Err(err) => {
            println!("❌ Erro ao chamar Claude Sonnet 4.5: {err:?}");
            println!("⚠️  Continuando sem testar o modelo premium.\n");
        }
    }

    // ========================================
    // TEST 3: Múltiplas Requisições Sequenciais
    // ========================================
    println!("╔══════════════════════════════════════╗");
    println!("║  TEST 3: Sequential Requests (3x)   ║");
    println!("╚══════════════════════════════════════╝\n");

    for i in 1..=3 {
        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message {
                role: "user".to_string(),
                content: format!(
                    "Em uma palavra: qual é a capital número {} mais populosa do mundo?",
                    i
                ),
            }],
            max_tokens: 20,
            temperature: 1.0,
            system: None,
        };

        print!("  Request {}/3... ", i);
        let start = Instant::now();
        let response = client.complete(request).await?;
        let elapsed = start.elapsed();

        println!("✅ ({:?}) → {}", elapsed, response.content.trim());
    }

    println!("\n╔══════════════════════════════════════╗");
    println!("║  🎉 ALL TESTS PASSED                ║");
    println!("╚══════════════════════════════════════╝");

    Ok(())
}
