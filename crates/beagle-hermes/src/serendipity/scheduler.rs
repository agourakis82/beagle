//! Synthesis Scheduler: Background task orchestration

use super::cluster_monitor::InsightCluster;
use super::priority_queue::{PriorityQueue, SynthesisTask};
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::{Mutex, Semaphore};
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};

/// Maximum concurrent syntheses
const MAX_CONCURRENT: usize = 2;

/// Retry attempts for failed syntheses
const MAX_RETRIES: usize = 3;

/// Backoff duration between retries (seconds)
const RETRY_BACKOFF_SECS: u64 = 60;

pub struct SynthesisScheduler {
    queue: Arc<Mutex<PriorityQueue>>,
    semaphore: Arc<Semaphore>,
    is_running: Arc<Mutex<bool>>,
}

impl SynthesisScheduler {
    pub fn new() -> Self {
        Self {
            queue: Arc::new(Mutex::new(PriorityQueue::new(100))),
            semaphore: Arc::new(Semaphore::new(MAX_CONCURRENT)),
            is_running: Arc::new(Mutex::new(false)),
        }
    }

    /// Start background scheduler
    pub async fn start(&self) -> Result<()> {
        let mut running = self.is_running.lock().await;
        if *running {
            return Ok(());
        }
        *running = true;
        drop(running);

        info!("🚀 Starting synthesis scheduler (max {} concurrent)", MAX_CONCURRENT);

        let queue = self.queue.clone();
        let semaphore = self.semaphore.clone();
        let is_running = self.is_running.clone();

        tokio::spawn(async move {
            loop {
                // Check if still running
                if !*is_running.lock().await {
                    info!("⏸️  Scheduler stopped");
                    break;
                }

                // Process queue
                if let Err(e) = Self::process_queue_static(queue.clone(), semaphore.clone()).await {
                    error!("❌ Error processing queue: {}", e);
                }

                // Sleep before next iteration
                sleep(Duration::from_secs(10)).await;
            }
        });

        Ok(())
    }

    /// Stop scheduler
    pub async fn stop(&self) {
        let mut running = self.is_running.lock().await;
        *running = false;
        info!("🛑 Stopping synthesis scheduler");
    }

    /// Process synthesis queue
    async fn process_queue_static(
        queue: Arc<Mutex<PriorityQueue>>,
        semaphore: Arc<Semaphore>,
    ) -> Result<()> {
        loop {
            // Get next task
            let task = {
                let mut q = queue.lock().await;
                q.pop()
            };

            match task {
                Some(task) => {
                    info!(
                        "📝 Processing task: {} (priority: {:.2})",
                        task.cluster_id, task.priority
                    );

                    // Acquire semaphore (wait if at max concurrent)
                    let permit = semaphore.clone().acquire_owned().await?;

                    // Spawn synthesis task
                    let task_clone = task.clone();
                    tokio::spawn(async move {
                        if let Err(e) = Self::spawn_synthesis_static(task_clone).await {
                            error!("❌ Synthesis failed: {}", e);
                        }
                        drop(permit); // Release semaphore
                    });
                }
                None => {
                    // Queue empty, exit loop
                    break;
                }
            }
        }

        Ok(())
    }

    /// Add cluster to synthesis queue
    pub async fn enqueue(&self, cluster: InsightCluster) -> Result<()> {
        let task = SynthesisTask {
            cluster_id: cluster.cluster_id.clone(),
            topic: cluster.topic,
            insight_count: cluster.insight_count,
            priority: cluster.calculate_priority(),
            retries: 0,
            created_at: chrono::Utc::now(),
        };

        let mut queue = self.queue.lock().await;
        queue.push(task)?;

        info!(
            "➕ Added cluster '{}' to synthesis queue (priority: {:.2})",
            cluster.cluster_id,
            cluster.calculate_priority()
        );

        Ok(())
    }

    /// Spawn synthesis using MultiAgentOrchestrator
    async fn spawn_synthesis_static(task: SynthesisTask) -> Result<()> {
        info!("🎯 Starting synthesis for cluster: {}", task.cluster_id);

        // Simulate synthesis (in reality, would call MultiAgentOrchestrator)
        match Self::simulate_synthesis(&task).await {
            Ok(_) => {
                info!("✅ Synthesis completed: {}", task.cluster_id);
                Ok(())
            }
            Err(e) => {
                warn!("⚠️  Synthesis attempt failed: {} (retry {}/{})", e, task.retries, MAX_RETRIES);

                if task.retries < MAX_RETRIES {
                    Self::handle_error_static(task).await?;
                } else {
                    error!("❌ Max retries reached for cluster: {}", task.cluster_id);
                }

                Err(e)
            }
        }
    }

    /// Simulate synthesis (placeholder)
    async fn simulate_synthesis(task: &SynthesisTask) -> Result<()> {
        // TODO: Replace with actual MultiAgentOrchestrator call
        // For now, simulate work
        sleep(Duration::from_secs(2)).await;

        // Simulate random failures for testing
        if task.insight_count % 7 == 0 {
            anyhow::bail!("Simulated synthesis failure");
        }

        info!("📄 Generated synthesis paper for topic: {}", task.topic);
        Ok(())
    }

    /// Handle synthesis errors with retry logic
    async fn handle_error_static(mut task: SynthesisTask) -> Result<()> {
        task.retries += 1;

        info!(
            "🔄 Retrying synthesis for {} (attempt {}/{})",
            task.cluster_id,
            task.retries,
            MAX_RETRIES
        );

        // Exponential backoff
        let backoff_duration = RETRY_BACKOFF_SECS * 2u64.pow(task.retries as u32 - 1);
        sleep(Duration::from_secs(backoff_duration)).await;

        // Re-attempt synthesis
        Self::spawn_synthesis_static(task).await
    }

    /// Get queue status
    pub async fn get_status(&self) -> SchedulerStatus {
        let queue = self.queue.lock().await;
        let is_running = *self.is_running.lock().await;

        SchedulerStatus {
            is_running,
            queue_size: queue.len(),
            available_slots: self.semaphore.available_permits(),
        }
    }
}

impl Default for SynthesisScheduler {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, serde::Serialize)]
pub struct SchedulerStatus {
    pub is_running: bool,
    pub queue_size: usize,
    pub available_slots: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scheduler_start_stop() {
        let scheduler = SynthesisScheduler::new();

        scheduler.start().await.unwrap();
        assert!(scheduler.get_status().await.is_running);

        scheduler.stop().await;
        sleep(Duration::from_millis(100)).await;
        assert!(!scheduler.get_status().await.is_running);
    }

    #[tokio::test]
    async fn test_enqueue() {
        let scheduler = SynthesisScheduler::new();

        let cluster = InsightCluster {
            cluster_id: "test_cluster".to_string(),
            topic: "quantum computing".to_string(),
            insight_count: 25,
            novelty_score: 0.9,
            first_insight_time: chrono::Utc::now(),
            last_insight_time: chrono::Utc::now(),
            is_synthesized: false,
            priority: 0.0,
        };

        scheduler.enqueue(cluster).await.unwrap();

        let status = scheduler.get_status().await;
        assert_eq!(status.queue_size, 1);
    }
}
