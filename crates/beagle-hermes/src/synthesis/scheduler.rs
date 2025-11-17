//! Background scheduler for autonomous synthesis

use super::{SynthesisEngine, SynthesisRequest};
use crate::{Result, HermesConfig, knowledge::KnowledgeGraph};
use tokio_cron_scheduler::{JobScheduler, Job};
use uuid::Uuid;
use tracing::{info, error, debug};

pub struct SynthesisScheduler {
    scheduler: JobScheduler,
    engine: SynthesisEngine,
    knowledge_graph: KnowledgeGraph,
    config: SchedulerConfig,
}

#[derive(Debug, Clone)]
pub struct SchedulerConfig {
    pub cron_schedule: String, // e.g., "0 0 */6 * * *" (every 6h)
    pub min_insights: usize,   // e.g., 20
    pub cooldown_hours: i64,   // e.g., 24
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            cron_schedule: "0 0 */6 * * *".to_string(),
            min_insights: 20,
            cooldown_hours: 24,
        }
    }
}

impl SynthesisScheduler {
    pub async fn new(
        hermes_config: &HermesConfig,
        engine: SynthesisEngine,
        knowledge_graph: KnowledgeGraph,
    ) -> Result<Self> {
        let scheduler = JobScheduler::new().await
            .map_err(|e| crate::HermesError::ConfigError(format!("Failed to create scheduler: {}", e)))?;
        let config = SchedulerConfig::default();

        Ok(Self {
            scheduler,
            engine,
            knowledge_graph,
            config,
        })
    }

    pub async fn start(&self) -> Result<()> {
        let engine = self.engine.clone();
        let kg = self.knowledge_graph.clone();
        let config = self.config.clone();

        // Schedule synthesis check job
        let schedule = config.cron_schedule.clone();
        self.scheduler.add(
            Job::new_async(schedule.as_str(), move |_uuid, _lock| {
                let engine = engine.clone();
                let kg = kg.clone();
                let config = config.clone();

                Box::pin(async move {
                    info!("Running synthesis trigger check");

                    match check_synthesis_triggers(&engine, &kg, &config).await {
                        Ok(count) => info!("Triggered {} synthesis jobs", count),
                        Err(e) => error!("Synthesis check failed: {}", e),
                    }
                })
            }).map_err(|e| crate::HermesError::ConfigError(format!("Failed to create job: {}", e)))?
        ).await
            .map_err(|e| crate::HermesError::ConfigError(format!("Failed to add job: {}", e)))?;

        self.scheduler.start().await
            .map_err(|e| crate::HermesError::ConfigError(format!("Failed to start scheduler: {}", e)))?;

        info!("Synthesis scheduler started with schedule: {}", self.config.cron_schedule);

        Ok(())
    }
}

async fn check_synthesis_triggers(
    engine: &SynthesisEngine,
    kg: &KnowledgeGraph,
    config: &SchedulerConfig,
) -> Result<usize> {
    // 1. Query knowledge graph for concept clusters
    let clusters = kg.find_concept_clusters(config.min_insights).await?;

    info!("Found {} concept clusters", clusters.len());

    let mut triggered = 0;

    // 2. Check if each cluster is ready for synthesis
    for cluster in clusters {
        if cluster.is_ready_for_synthesis(config.min_insights, config.cooldown_hours) {
            info!("Triggering synthesis for cluster: {}", cluster.concept_name);

            // 3. Spawn synthesis job (async)
            let request = SynthesisRequest {
                cluster,
                section_type: crate::SectionType::Introduction,
                target_words: 500,
                voice_profile: super::VoiceProfile::default(),
            };

            let engine_clone = engine.clone();
            tokio::spawn(async move {
                match engine_clone.synthesize(request).await {
                    Ok(result) => info!("Synthesis completed: {} words", result.word_count),
                    Err(e) => error!("Synthesis failed: {}", e),
                }
            });

            triggered += 1;
        }
    }

    Ok(triggered)
}

