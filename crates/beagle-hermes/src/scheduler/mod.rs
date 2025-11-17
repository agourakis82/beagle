//! Background Scheduler for Autonomous Synthesis
//!
//! Runs periodic jobs:
//! - Concept cluster detection (every 6 hours)
//! - Paper synthesis triggering
//! - Cleanup old drafts

pub mod jobs;
pub mod synthesis_scheduler;

pub use synthesis_scheduler::SynthesisScheduler;
