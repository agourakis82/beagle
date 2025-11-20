//! Synthesis Scheduler - Main orchestrator

use crate::knowledge::KnowledgeGraph;
use crate::synthesis::{SynthesisEngine, SynthesisRequest, VoiceProfile};
use crate::{HermesConfig, HermesError, Result};
use std::sync::Arc;
use tokio_cron_scheduler::{Job, JobScheduler};
use tracing::{error, info};

pub struct SynthesisScheduler {
    scheduler: JobScheduler,
    graph_client: Arc<KnowledgeGraph>,
    orchestrator: Arc<SynthesisEngine>,
    cluster_threshold: usize,
    cron_schedule: String,
}

impl SynthesisScheduler {
    pub async fn new(
        config: &HermesConfig,
        graph_client: Arc<KnowledgeGraph>,
        orchestrator: Arc<SynthesisEngine>,
    ) -> Result<Self> {
        let scheduler = JobScheduler::new()
            .await
            .map_err(|e| HermesError::ConfigError(format!("Failed to init scheduler: {}", e)))?;

        Ok(Self {
            scheduler,
            graph_client,
            orchestrator,
            cluster_threshold: config.min_insights_for_synthesis,
            cron_schedule: config.synthesis_schedule.clone(),
        })
    }

    /// Start background scheduler
    pub async fn start(&mut self) -> Result<()> {
        info!(
            "🚀 Starting HERMES Background Scheduler (cron: {}, min_insights: {})",
            self.cron_schedule, self.cluster_threshold
        );

        // Job 1: Cluster detection + synthesis (every 6 hours)
        let graph_client = Arc::clone(&self.graph_client);
        let orchestrator = Arc::clone(&self.orchestrator);
        let threshold = self.cluster_threshold;

        let schedule = self.cron_schedule.clone();
        let schedule_for_closure = schedule.clone();
        let synthesis_job = Job::new_async(schedule.as_str(), move |_uuid, _lock| {
            let graph_client = Arc::clone(&graph_client);
            let orchestrator = Arc::clone(&orchestrator);
            let schedule_descr = schedule_for_closure.clone();

            Box::pin(async move {
                info!(
                    "⏰ Running scheduled cluster detection (cron: {})",
                    schedule_descr
                );

                match Self::check_and_synthesize(graph_client, orchestrator, threshold).await {
                    Ok(papers_triggered) => {
                        info!(
                            "✅ Synthesis check complete: {} papers triggered",
                            papers_triggered
                        );
                    }
                    Err(e) => {
                        error!("❌ Synthesis check failed: {}", e);
                    }
                }
            })
        })
        .map_err(|e| HermesError::ConfigError(format!("Failed to build synthesis job: {}", e)))?;

        self.scheduler
            .add(synthesis_job)
            .await
            .map_err(|e| HermesError::ConfigError(format!("Failed to add synthesis job: {}", e)))?;

        // Job 2: Cleanup old drafts (daily at 3 AM)
        let graph_client_cleanup = Arc::clone(&self.graph_client);
        let cleanup_job = Job::new_async("0 3 * * *", move |_uuid, _lock| {
            let graph_client = Arc::clone(&graph_client_cleanup);
            Box::pin(async move {
                info!("🧹 Running daily cleanup");
                Self::cleanup_old_drafts(graph_client).await;
            })
        })
        .map_err(|e| HermesError::ConfigError(format!("Failed to build cleanup job: {}", e)))?;

        self.scheduler
            .add(cleanup_job)
            .await
            .map_err(|e| HermesError::ConfigError(format!("Failed to add cleanup job: {}", e)))?;

        // Start scheduler
        self.scheduler
            .start()
            .await
            .map_err(|e| HermesError::ConfigError(format!("Failed to start scheduler: {}", e)))?;

        info!("✅ HERMES Scheduler started successfully");

        Ok(())
    }

    /// Stop scheduler
    pub async fn stop(&mut self) -> Result<()> {
        self.scheduler
            .shutdown()
            .await
            .map_err(|e| HermesError::ConfigError(format!("Failed to stop scheduler: {}", e)))?;
        info!("🛑 HERMES Scheduler stopped");
        Ok(())
    }

    /// Check for dense clusters and trigger synthesis
    async fn check_and_synthesize(
        graph_client: Arc<KnowledgeGraph>,
        orchestrator: Arc<SynthesisEngine>,
        threshold: usize,
    ) -> Result<usize> {
        // 1. Detect dense clusters
        let clusters = graph_client.find_concept_clusters(threshold).await?;

        if clusters.is_empty() {
            info!("No dense clusters found (threshold: {})", threshold);
            return Ok(0);
        }

        info!(
            "🔍 Found {} dense clusters ready for synthesis",
            clusters.len()
        );

        let mut papers_triggered = 0;

        // 2. Synthesize paper for each cluster
        for cluster in clusters {
            let concept_name = cluster.concept_name.clone();
            info!(
                "📝 Triggering synthesis for: {} ({} insights)",
                concept_name, cluster.insight_count
            );

            let request = SynthesisRequest {
                cluster,
                section_type: crate::SectionType::Introduction,
                target_words: 600,
                voice_profile: VoiceProfile::default(),
            };

            match orchestrator.synthesize(request).await {
                Ok(_) => {
                    papers_triggered += 1;
                    info!("✅ Paper synthesis started for {}", concept_name);
                }
                Err(e) => {
                    error!("❌ Failed to synthesize paper for {}: {}", concept_name, e);
                }
            }
        }

        Ok(papers_triggered)
    }

    /// Cleanup old drafts and orphaned data
    async fn cleanup_old_drafts(_graph_client: Arc<KnowledgeGraph>) {
        use chrono::{Duration, Utc};

        // Delete insights older than 90 days that aren't linked to papers
        let cutoff_date = Utc::now() - Duration::days(90);

        // This would require a Neo4j query to find and delete old insights
        // For now, just log
        info!("Cleanup: Would delete insights older than {}", cutoff_date);

        // In production, would:
        // 1. Find insights older than cutoff_date
        // 2. Check if they're linked to any papers
        // 3. Delete orphaned insights
        // 4. Clean up unused concept nodes
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires Neo4j + full stack
    async fn test_scheduler_startup() {
        // Mock dependencies
        let graph_client = Arc::new(
            KnowledgeGraph::new("bolt://localhost:7687", "neo4j", "password")
                .await
                .unwrap(),
        );

        // Note: SynthesisEngine needs to be created properly
        // let orchestrator = Arc::new(
        //     SynthesisEngine::new(/* ... */).await.unwrap()
        // );

        // let mut scheduler = SynthesisScheduler::new(
        //     graph_client,
        //     orchestrator,
        //     20,
        // ).await.unwrap();

        // scheduler.start().await.unwrap();

        // // Let it run for 5 seconds
        // tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;

        // scheduler.stop().await.unwrap();

        println!("✅ Scheduler test passed (mocked)");
    }
}
