//! Brain Connector - Consciousness Integration Layer
//!
//! Bridges the consciousness substrate (IIT 4.0, Global Workspace Theory)
//! with decision-making and response generation.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for the brain connector
#[derive(Debug, Clone)]
pub struct BrainConnectorConfig {
    /// Enable IIT 4.0 consciousness calculation
    pub enable_iit: bool,
    /// Enable Global Workspace Theory attention
    pub enable_gwt: bool,
    /// Enable metacognitive monitoring
    pub enable_metacognition: bool,
    /// Phi threshold for escalation
    pub phi_threshold: f32,
    /// Maximum attention capacity
    pub attention_capacity: usize,
}

impl Default for BrainConnectorConfig {
    fn default() -> Self {
        Self {
            enable_iit: true,
            enable_gwt: true,
            enable_metacognition: true,
            phi_threshold: 0.5,
            attention_capacity: 7,
        }
    }
}

// ============================================================================
// Consciousness State
// ============================================================================

/// Consciousness state snapshot
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessState {
    /// Integrated Information (Φ) - IIT 4.0
    pub phi: f32,
    /// Awareness level classification
    pub awareness_level: AwarenessLevel,
    /// Current attention spotlight contents
    pub attention_spotlight: Vec<String>,
    /// Metacognitive confidence
    pub metacognitive_confidence: f32,
    /// Timestamp
    pub timestamp: DateTime<Utc>,
}

impl Default for ConsciousnessState {
    fn default() -> Self {
        Self {
            phi: 0.5,
            awareness_level: AwarenessLevel::Normal,
            attention_spotlight: Vec::new(),
            metacognitive_confidence: 0.5,
            timestamp: Utc::now(),
        }
    }
}

/// Awareness level classification
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum AwarenessLevel {
    /// Low - routine processing
    Automatic,
    /// Medium - normal conscious processing
    Normal,
    /// High - focused attention
    Focused,
    /// Very high - flow state
    Flow,
    /// Elevated with uncertainty - needs deliberation
    Deliberative,
}

impl AwarenessLevel {
    /// Create from phi value
    pub fn from_phi(phi: f32) -> Self {
        match phi {
            p if p < 0.2 => AwarenessLevel::Automatic,
            p if p < 0.5 => AwarenessLevel::Normal,
            p if p < 0.7 => AwarenessLevel::Focused,
            p if p < 0.9 => AwarenessLevel::Flow,
            _ => AwarenessLevel::Deliberative,
        }
    }
}

// ============================================================================
// Brain Connector
// ============================================================================

/// Brain connector - bridges consciousness with cognition
pub struct BrainConnector {
    /// Configuration
    config: BrainConnectorConfig,
    /// Current consciousness state
    state: ConsciousnessState,
    /// Domain-specific confidence calibration
    calibration: HashMap<String, f32>,
}

impl BrainConnector {
    /// Create new brain connector
    pub fn new(config: BrainConnectorConfig) -> Self {
        Self {
            config,
            state: ConsciousnessState::default(),
            calibration: HashMap::new(),
        }
    }

    /// Get current consciousness state
    pub fn get_state(&self) -> ConsciousnessState {
        self.state.clone()
    }

    /// Set awareness level
    pub fn set_awareness_level(&mut self, level: AwarenessLevel) {
        self.state.awareness_level = level;
        self.state.timestamp = Utc::now();

        // Update phi based on awareness level
        self.state.phi = match level {
            AwarenessLevel::Automatic => 0.1,
            AwarenessLevel::Normal => 0.4,
            AwarenessLevel::Focused => 0.6,
            AwarenessLevel::Flow => 0.8,
            AwarenessLevel::Deliberative => 0.9,
        };
    }

    /// Update phi value
    pub fn update_phi(&mut self, phi: f32) {
        self.state.phi = phi;
        self.state.awareness_level = AwarenessLevel::from_phi(phi);
        self.state.timestamp = Utc::now();
    }

    /// Add item to attention spotlight
    pub fn attend(&mut self, item: String) {
        self.state.attention_spotlight.push(item);

        // Limit to capacity
        if self.state.attention_spotlight.len() > self.config.attention_capacity {
            self.state.attention_spotlight.remove(0);
        }
    }

    /// Clear attention spotlight
    pub fn clear_spotlight(&mut self) {
        self.state.attention_spotlight.clear();
    }

    /// Get attention spotlight
    pub fn spotlight(&self) -> &[String] {
        &self.state.attention_spotlight
    }

    /// Update metacognitive confidence
    pub fn set_confidence(&mut self, confidence: f32) {
        self.state.metacognitive_confidence = confidence.clamp(0.0, 1.0);
    }

    /// Get calibrated confidence for a domain
    pub fn get_confidence(&self, domain: Option<&str>) -> f32 {
        let base = self.state.metacognitive_confidence;

        if let Some(d) = domain {
            if let Some(&cal) = self.calibration.get(d) {
                return (base * cal).clamp(0.0, 1.0);
            }
        }

        base
    }

    /// Calibrate confidence for a domain
    pub fn calibrate(&mut self, domain: &str, factor: f32) {
        self.calibration
            .insert(domain.to_string(), factor.clamp(0.5, 1.5));
    }

    /// Should escalate to deeper reasoning?
    pub fn should_escalate(&self) -> bool {
        self.state.phi >= self.config.phi_threshold
            || matches!(
                self.state.awareness_level,
                AwarenessLevel::Deliberative | AwarenessLevel::Focused
            )
    }

    /// Get recommended LLM tier
    pub fn recommended_tier(&self) -> &'static str {
        match self.state.awareness_level {
            AwarenessLevel::Automatic | AwarenessLevel::Normal => "tier1",
            AwarenessLevel::Focused | AwarenessLevel::Flow | AwarenessLevel::Deliberative => {
                "tier2"
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_awareness_from_phi() {
        assert_eq!(AwarenessLevel::from_phi(0.1), AwarenessLevel::Automatic);
        assert_eq!(AwarenessLevel::from_phi(0.4), AwarenessLevel::Normal);
        assert_eq!(AwarenessLevel::from_phi(0.6), AwarenessLevel::Focused);
    }

    #[test]
    fn test_brain_connector() {
        let config = BrainConnectorConfig::default();
        let mut brain = BrainConnector::new(config);

        brain.set_awareness_level(AwarenessLevel::Focused);
        let state = brain.get_state();
        assert_eq!(state.awareness_level, AwarenessLevel::Focused);

        brain.attend("Test item".to_string());
        assert_eq!(brain.spotlight().len(), 1);
    }
}
