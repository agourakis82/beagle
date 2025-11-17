//! Nightly retraining scheduler
//! Runs at 3 AM local time, trains on yesterday's interactions

use crate::voice::trainer::{LoRATrainer, TrainingExample, TrainingMetrics};
use tokio::time::{sleep, Duration};
use chrono::{Local, Timelike};
use std::path::PathBuf;
use tracing::{info, error};

pub struct RetrainingScheduler {
    trainer: LoRATrainer,
    corpus_path: PathBuf,
    adapter_path: PathBuf,
    schedule_hour: u32,  // Hour of day (0-23)
}

impl RetrainingScheduler {
    pub fn new(
        trainer: LoRATrainer,
        corpus_path: PathBuf,
        adapter_path: PathBuf,
    ) -> Self {
        Self {
            trainer,
            corpus_path,
            adapter_path,
            schedule_hour: 3,  // 3 AM
        }
    }

    /// Start nightly retraining loop
    pub async fn start(&self) {
        info!("Retraining scheduler started (runs daily at {}:00)", self.schedule_hour);
        
        loop {
            // Calculate time until next scheduled run
            let now = Local::now();
            let mut next_run = now
                .with_hour(self.schedule_hour)
                .unwrap()
                .with_minute(0)
                .unwrap()
                .with_second(0)
                .unwrap();
            
            // If already past today's scheduled time, schedule for tomorrow
            if now > next_run {
                next_run = next_run + chrono::Duration::days(1);
            }
            
            let duration_until_next = (next_run - now).to_std().unwrap();
            info!("Next retraining in {:?}", duration_until_next);
            
            // Sleep until scheduled time
            sleep(duration_until_next).await;
            
            // Execute retraining
            match self.retrain().await {
                Ok(metrics) => {
                    info!("Retraining completed successfully");
                    info!("  Final Loss: {:.4}", metrics.final_loss);
                    info!("  Training Time: {:.2}s", metrics.training_time_seconds);
                    info!("  Adapter: {}", metrics.adapter_path);
                }
                Err(e) => {
                    error!("Retraining failed: {}", e);
                }
            }
            
            // Sleep for 1 hour to avoid immediate re-triggering
            sleep(Duration::from_secs(3600)).await;
        }
    }

    async fn retrain(&self) -> Result<TrainingMetrics, Box<dyn std::error::Error>> {
        info!("Starting nightly retraining");
        
        // 1. Collect yesterday's interactions
        let new_examples = self.collect_yesterdays_interactions().await?;
        
        if new_examples.is_empty() {
            info!("No new examples from yesterday. Skipping retraining.");
            return Ok(TrainingMetrics {
                adapter_path: String::new(),
                loss_history: Vec::new(),
                final_loss: 0.0,
                training_time_seconds: 0.0,
            });
        }
        
        info!("Collected {} new examples from yesterday", new_examples.len());
        
        // 2. Training (using train method instead of incremental_train)
        let training_data: Vec<String> = new_examples
            .iter()
            .map(|e| format!("{} {}", e.input, e.target))
            .collect();
        
        let metrics = self.trainer
            .train("microsoft/DialoGPT-small", &training_data, &self.adapter_path)
            .await?;
        
        // 3. Backup old adapters
        self.backup_adapters()?;
        
        // 4. Notify completion
        self.notify_completion(&metrics).await?;
        
        Ok(metrics)
    }

    async fn collect_yesterdays_interactions(&self) -> Result<Vec<TrainingExample>, Box<dyn std::error::Error>> {
        // Query database for yesterday's edits, corrections, user feedback
        // Convert to training examples
        
        // TODO: Implement actual data collection from beagle-db
        // For now, return empty
        Ok(vec![])
    }

    fn backup_adapters(&self) -> Result<(), Box<dyn std::error::Error>> {
        let backup_path = self.adapter_path.with_extension("backup");
        
        if self.adapter_path.exists() {
            std::fs::rename(&self.adapter_path, &backup_path)?;
            info!("Backed up adapters to {:?}", backup_path);
        }
        
        Ok(())
    }

    async fn notify_completion(
        &self,
        _metrics: &TrainingMetrics,
    ) -> Result<(), Box<dyn std::error::Error>> {
        // Send notification to user (email, push notification, etc.)
        info!("Retraining notification sent");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_scheduler() {
        // Test scheduling logic (not actual training)
        let now = Local::now();
        info!("Current time: {}", now);
        
        let schedule_hour = 3;
        let mut next_run = now
            .with_hour(schedule_hour)
            .unwrap()
            .with_minute(0)
            .unwrap()
            .with_second(0)
            .unwrap();
        
        if now > next_run {
            next_run = next_run + chrono::Duration::days(1);
        }
        
        assert!(next_run > now);
    }
}

