//! BEAGLE HERMES - Editorial Assistant Core
//!
//! HERMES provides:
//! - Voice preservation via LoRA fine-tuning
//! - Continuous learning (nightly retraining)
//! - Multi-level editing (grammar → style → academic → journal)
//! - Citation management (auto-generation + verification)

pub mod editor;
pub mod citations;
pub mod voice;
pub mod integration;

pub use voice::analyzer::{VoiceAnalyzer, VoiceProfile};

