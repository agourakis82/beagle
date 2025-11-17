//! Example: Capture a thought and process it

use beagle_hermes::{HermesConfig, HermesEngine, ThoughtInput, ThoughtContext};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create HERMES config
    let config = HermesConfig::default();

    // Initialize HERMES engine
    let hermes = HermesEngine::new(config).await?;

    // Capture a text thought
    let input = ThoughtInput::Text {
        content: "The scaffold entropy model suggests that biomaterial degradation follows a power-law distribution with exponent α=0.75.".to_string(),
        context: ThoughtContext::Hypothesis,
    };

    println!("Capturing thought...");
    let insight_id = hermes.capture_thought(input).await?;
    println!("✅ Thought captured with ID: {}", insight_id);

    Ok(())
}

