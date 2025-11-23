//! Serendipity Engine: Autonomous background paper synthesis
//!
//! This module implements the complete serendipity pipeline:
//! 1. ClusterMonitor: Polls Neo4j for insight clusters
//! 2. PriorityQueue: Manages synthesis tasks by priority
//! 3. Scheduler: Orchestrates concurrent syntheses
//! 4. Notifications: Alerts users when papers are ready

pub mod cluster_monitor;
pub mod engine;
pub mod notifications;
pub mod priority_queue;
pub mod scheduler;

// Re-export main types
pub use cluster_monitor::{ClusterMonitor, InsightCluster};
pub use engine::{Discovery, Hypothesis, SerendipityEngine};
pub use notifications::{NotificationChannel, NotificationPreferences, NotificationService};
pub use priority_queue::{PriorityQueue, SynthesisTask};
pub use scheduler::{SchedulerStatus, SynthesisScheduler};

// Placeholder for domain_classifier
pub mod domain_classifier {
    pub struct DomainClassifier;

    impl DomainClassifier {
        pub fn new() -> Self {
            Self
        }
    }

    impl Default for DomainClassifier {
        fn default() -> Self {
            Self::new()
        }
    }
}
