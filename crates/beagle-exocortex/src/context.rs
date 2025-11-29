//! Context Manager - Situational Awareness Integration
//!
//! Integrates the World Model with real-time context to provide
//! situational awareness for decision-making.
//!
//! Supports integration with beagle-observer for real HRV data.

use chrono::{DateTime, Timelike, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;

#[cfg(feature = "observer")]
use beagle_observer::{PhysioState as ObserverPhysioState, UserContext as ObserverUserContext};

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for the context manager
#[derive(Debug, Clone)]
pub struct ContextManagerConfig {
    /// Enable world model integration
    pub enable_world_model: bool,
    /// Enable physiological tracking
    pub enable_physio_tracking: bool,
    /// Enable environment sensing
    pub enable_environment_sensing: bool,
    /// Adaptation sensitivity (0-1)
    pub adaptation_sensitivity: f32,
}

impl Default for ContextManagerConfig {
    fn default() -> Self {
        Self {
            enable_world_model: true,
            enable_physio_tracking: true,
            enable_environment_sensing: true,
            adaptation_sensitivity: 0.5,
        }
    }
}

// ============================================================================
// Situational Context
// ============================================================================

/// Full situational context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SituationalContext {
    /// World state summary
    pub world_state: WorldStateSummary,
    /// Physiological state (if available)
    pub physio_state: Option<PhysioContext>,
    /// Environmental context
    pub environment: EnvironmentContext,
    /// Timestamp
    pub timestamp: DateTime<Utc>,
}

impl Default for SituationalContext {
    fn default() -> Self {
        Self {
            world_state: WorldStateSummary::default(),
            physio_state: None,
            environment: EnvironmentContext::default(),
            timestamp: Utc::now(),
        }
    }
}

/// World state summary
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WorldStateSummary {
    /// Current topic focus
    pub current_topic: Option<String>,
    /// Active goals
    pub active_goals: Vec<String>,
    /// Recent events
    pub recent_events: Vec<String>,
}

/// Physiological context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysioContext {
    /// HRV-derived state
    pub hrv_state: HrvState,
    /// Stress level (0-1)
    pub stress_level: f32,
    /// Energy level (0-1)
    pub energy_level: f32,
    /// Focus level (0-1)
    pub focus_level: f32,
}

impl Default for PhysioContext {
    fn default() -> Self {
        Self {
            hrv_state: HrvState::Unknown,
            stress_level: 0.3,
            energy_level: 0.7,
            focus_level: 0.5,
        }
    }
}

/// HRV-derived mental state
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum HrvState {
    /// High HRV, low stress - optimal for complex tasks
    Flow,
    /// Normal HRV - regular state
    Normal,
    /// Low HRV, elevated stress
    Stressed,
    /// Very low HRV - fatigue
    Fatigued,
    /// No data available
    Unknown,
}

impl HrvState {
    /// Should simplify responses for this state?
    pub fn should_simplify(&self) -> bool {
        matches!(self, HrvState::Stressed | HrvState::Fatigued)
    }

    /// Response length modifier
    pub fn length_modifier(&self) -> f32 {
        match self {
            HrvState::Flow => 1.2,
            HrvState::Normal => 1.0,
            HrvState::Stressed => 0.7,
            HrvState::Fatigued => 0.6,
            HrvState::Unknown => 1.0,
        }
    }
}

/// Environmental context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvironmentContext {
    /// Time of day
    pub time_of_day: TimeOfDay,
    /// Day of week
    pub day_of_week: String,
    /// Timezone
    pub timezone: String,
}

impl Default for EnvironmentContext {
    fn default() -> Self {
        let now = Utc::now();
        Self {
            time_of_day: TimeOfDay::from_hour(now.hour() as u8),
            day_of_week: now.format("%A").to_string(),
            timezone: "UTC".to_string(),
        }
    }
}

/// Time of day classification
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum TimeOfDay {
    EarlyMorning,
    Morning,
    Afternoon,
    Evening,
    Night,
}

impl TimeOfDay {
    pub fn from_hour(hour: u8) -> Self {
        match hour {
            5..=7 => TimeOfDay::EarlyMorning,
            8..=11 => TimeOfDay::Morning,
            12..=16 => TimeOfDay::Afternoon,
            17..=20 => TimeOfDay::Evening,
            _ => TimeOfDay::Night,
        }
    }

    /// Cognitive load tolerance at this time
    pub fn cognitive_tolerance(&self) -> f32 {
        match self {
            TimeOfDay::EarlyMorning => 0.6,
            TimeOfDay::Morning => 1.0,
            TimeOfDay::Afternoon => 0.9,
            TimeOfDay::Evening => 0.7,
            TimeOfDay::Night => 0.5,
        }
    }
}

// ============================================================================
// Context Adaptations
// ============================================================================

/// Adaptations to apply based on context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextAdaptations {
    /// Description of this adaptation
    pub description: String,
    /// Simplify responses
    pub simplify_responses: bool,
    /// Response length modifier (1.0 = normal)
    pub length_modifier: f32,
    /// Reduce cognitive load
    pub reduce_cognitive_load: bool,
    /// Add more structure
    pub add_structure: bool,
    /// Increase empathy in tone
    pub increase_empathy: bool,
}

impl Default for ContextAdaptations {
    fn default() -> Self {
        Self {
            description: "Default adaptations".to_string(),
            simplify_responses: false,
            length_modifier: 1.0,
            reduce_cognitive_load: false,
            add_structure: false,
            increase_empathy: false,
        }
    }
}

// ============================================================================
// Context Manager
// ============================================================================

/// Context manager for situational awareness
pub struct ContextManager {
    /// Configuration
    config: ContextManagerConfig,
    /// Current situational context
    context: Arc<RwLock<SituationalContext>>,
}

impl ContextManager {
    /// Create new context manager
    pub fn new(config: ContextManagerConfig) -> Self {
        Self {
            config,
            context: Arc::new(RwLock::new(SituationalContext::default())),
        }
    }

    /// Get current situational context
    pub async fn get_context(&self) -> SituationalContext {
        self.context.read().await.clone()
    }

    /// Update physiological state
    pub fn update_physio(&mut self, stress_level: f32, energy_level: f32, focus_level: f32) {
        // Determine HRV state from levels
        let hrv_state = if focus_level > 0.8 && stress_level < 0.3 {
            HrvState::Flow
        } else if stress_level > 0.7 {
            HrvState::Stressed
        } else if energy_level < 0.3 {
            HrvState::Fatigued
        } else {
            HrvState::Normal
        };

        let physio = PhysioContext {
            hrv_state,
            stress_level,
            energy_level,
            focus_level,
        };

        // Update synchronously using try_write
        if let Ok(mut ctx) = self.context.try_write() {
            ctx.physio_state = Some(physio);
            ctx.timestamp = Utc::now();
        }
    }

    /// Get adaptation recommendations based on context
    pub fn get_adaptations(&self, context: &SituationalContext) -> Vec<ContextAdaptations> {
        let mut adaptations = Vec::new();

        // Adapt based on physiological state
        if let Some(ref physio) = context.physio_state {
            if physio.hrv_state.should_simplify() {
                adaptations.push(ContextAdaptations {
                    description: format!("Simplifying for {:?} state", physio.hrv_state),
                    simplify_responses: true,
                    length_modifier: physio.hrv_state.length_modifier(),
                    reduce_cognitive_load: true,
                    add_structure: false,
                    increase_empathy: physio.stress_level > 0.5,
                });
            }

            if physio.focus_level < 0.3 {
                adaptations.push(ContextAdaptations {
                    description: "Adding structure for low focus".to_string(),
                    simplify_responses: false,
                    length_modifier: 1.0,
                    reduce_cognitive_load: false,
                    add_structure: true,
                    increase_empathy: false,
                });
            }
        }

        // Adapt based on time of day
        let cognitive_tolerance = context.environment.time_of_day.cognitive_tolerance();
        if cognitive_tolerance < 0.7 {
            adaptations.push(ContextAdaptations {
                description: format!("Adapting for {:?}", context.environment.time_of_day),
                simplify_responses: true,
                length_modifier: cognitive_tolerance,
                reduce_cognitive_load: true,
                add_structure: false,
                increase_empathy: false,
            });
        }

        adaptations
    }

    /// Check if current context suggests deep work mode
    pub async fn is_deep_work_mode(&self) -> bool {
        let ctx = self.context.read().await;

        if let Some(ref physio) = ctx.physio_state {
            if physio.hrv_state == HrvState::Flow && physio.focus_level > 0.7 {
                return true;
            }
        }

        matches!(
            ctx.environment.time_of_day,
            TimeOfDay::Morning | TimeOfDay::EarlyMorning
        )
    }

    /// Update physiological context from Observer's PhysioState
    /// This bridges the real HRV data from beagle-observer to the exocortex
    #[cfg(feature = "observer")]
    pub async fn update_from_observer_physio(&self, observer_physio: &ObserverPhysioState) {
        // Convert Observer's HRV level string to our HrvState enum
        let hrv_state = match observer_physio.hrv_level.as_deref() {
            Some("high") => HrvState::Flow,
            Some("normal") => HrvState::Normal,
            Some("low") => {
                // Distinguish between stressed and fatigued based on stress index
                if observer_physio.stress_index.unwrap_or(0.0) > 0.6 {
                    HrvState::Stressed
                } else {
                    HrvState::Fatigued
                }
            }
            _ => HrvState::Unknown,
        };

        // Calculate stress and energy levels from Observer data
        let stress_level = observer_physio.stress_index.unwrap_or(0.3) as f32;
        let energy_level = 1.0_f32 - stress_level; // Simple inverse

        // Estimate focus from HRV state
        let focus_level = match hrv_state {
            HrvState::Flow => 0.9,
            HrvState::Normal => 0.6,
            HrvState::Stressed => 0.4,
            HrvState::Fatigued => 0.3,
            HrvState::Unknown => 0.5,
        };

        let physio = PhysioContext {
            hrv_state,
            stress_level,
            energy_level,
            focus_level,
        };

        // Update context
        if let Ok(mut ctx) = self.context.try_write() {
            ctx.physio_state = Some(physio);
            ctx.timestamp = Utc::now();
        }
    }

    /// Update full context from Observer's UserContext
    /// This bridges all physiological, environmental, and space weather data
    #[cfg(feature = "observer")]
    pub async fn update_from_observer_user_context(&self, user_ctx: &ObserverUserContext) {
        // Update physiological context
        self.update_from_observer_physio(&user_ctx.physio).await;

        // Update world state summary with environmental info
        if let Ok(mut ctx) = self.context.try_write() {
            // Add environmental context to world state
            if let Some(ref summary) = user_ctx.env.summary {
                ctx.world_state
                    .recent_events
                    .push(format!("Environment: {}", summary));
            }

            // Add space weather context
            if let Some(ref risk_level) = user_ctx.space.heliobio_risk_level {
                ctx.world_state.recent_events.push(format!(
                    "Space weather: {} (Kp: {})",
                    risk_level,
                    user_ctx
                        .space
                        .kp_index
                        .map(|k| format!("{:.1}", k))
                        .unwrap_or_else(|| "N/A".to_string())
                ));
            }

            // Keep only last 5 events
            if ctx.world_state.recent_events.len() > 5 {
                ctx.world_state.recent_events = ctx
                    .world_state
                    .recent_events
                    .iter()
                    .rev()
                    .take(5)
                    .cloned()
                    .collect::<Vec<_>>()
                    .into_iter()
                    .rev()
                    .collect();
            }
        }
    }

    /// Get current HRV state (convenience method)
    pub async fn get_hrv_state(&self) -> HrvState {
        self.context
            .read()
            .await
            .physio_state
            .as_ref()
            .map(|p| p.hrv_state)
            .unwrap_or(HrvState::Unknown)
    }

    /// Check if user is in a high-stress state
    pub async fn is_high_stress(&self) -> bool {
        self.context
            .read()
            .await
            .physio_state
            .as_ref()
            .map(|p| p.stress_level > 0.7)
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_time_of_day() {
        assert_eq!(TimeOfDay::from_hour(9), TimeOfDay::Morning);
        assert_eq!(TimeOfDay::from_hour(14), TimeOfDay::Afternoon);
        assert_eq!(TimeOfDay::from_hour(22), TimeOfDay::Night);
    }

    #[test]
    fn test_hrv_state() {
        assert!(HrvState::Stressed.should_simplify());
        assert!(!HrvState::Flow.should_simplify());
        assert!(HrvState::Flow.length_modifier() > 1.0);
    }

    #[tokio::test]
    async fn test_context_manager() {
        let config = ContextManagerConfig::default();
        let manager = ContextManager::new(config);

        let context = manager.get_context().await;
        assert!(context.physio_state.is_none());
    }
}
