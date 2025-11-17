//! Example: Multi-agent synthesis orchestration

use beagle_hermes::agents::MultiAgentOrchestrator;
use beagle_hermes::knowledge::{ConceptCluster, ClusteredInsight};
use beagle_hermes::synthesis::VoiceProfile;
use chrono::Utc;
use uuid::Uuid;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    // Create voice profile
    let voice_profile = VoiceProfile::default();

    // Initialize orchestrator
    let orchestrator = MultiAgentOrchestrator::new(voice_profile).await?;

    // Create a test concept cluster
    let cluster = ConceptCluster {
        concept_name: "scaffold_entropy".to_string(),
        insight_count: 25,
        insights: vec![
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Biomaterial degradation follows power-law distribution".to_string(),
                timestamp: Utc::now(),
            },
            ClusteredInsight {
                id: Uuid::new_v4(),
                content: "Entropy increases with scaffold complexity".to_string(),
                timestamp: Utc::now(),
            },
        ],
        last_synthesis: None,
    };

    println!("🚀 Starting multi-agent synthesis...");

    // Synthesize section
    let result = orchestrator
        .synthesize_section(
            &cluster,
            "Introduction".to_string(),
            500,
        )
        .await?;

    println!("✅ Synthesis complete!");
    println!("   Word count: {}", result.word_count);
    println!("   Papers cited: {}", result.papers_cited);
    println!("   Quality score: {:.1}%", result.quality_score * 100.0);
    println!("   Status: {}", if result.validation.approved { "APPROVED" } else { "NEEDS REFINEMENT" });

    Ok(())
}

