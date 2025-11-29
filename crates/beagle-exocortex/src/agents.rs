//! Agent Mesh - Coordinated Agent Team
//!
//! Provides intelligent agent selection and coordination:
//! - Task-appropriate agent selection
//! - User expertise-aware delegation
//! - Specialization learning over time

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::orchestrator::ExocortexInput;

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for the agent mesh
#[derive(Debug, Clone)]
pub struct AgentMeshConfig {
    /// Enable proactive suggestions
    pub enable_proactive: bool,
    /// Enable specialization learning
    pub enable_specialization_learning: bool,
    /// Maximum team size
    pub max_team_size: usize,
    /// Collaboration threshold
    pub collaboration_threshold: f32,
}

impl Default for AgentMeshConfig {
    fn default() -> Self {
        Self {
            enable_proactive: true,
            enable_specialization_learning: true,
            max_team_size: 5,
            collaboration_threshold: 0.6,
        }
    }
}

// ============================================================================
// Agent Capabilities
// ============================================================================

/// Agent capability classification
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum AgentCapability {
    /// Research and information retrieval
    Research,
    /// Writing and content generation
    Writing,
    /// Analysis and reasoning
    Analysis,
    /// Code generation and debugging
    Coding,
    /// Mathematical reasoning
    Mathematics,
    /// Creative tasks
    Creative,
    /// Fact-checking and validation
    Validation,
    /// Coordination of other agents
    Coordination,
    /// Debate and critical review
    Debate,
    /// Synthesis of multiple sources
    Synthesis,
    /// Planning and strategy
    Strategy,
}

impl AgentCapability {
    /// All capabilities
    pub fn all() -> Vec<Self> {
        vec![
            Self::Research,
            Self::Writing,
            Self::Analysis,
            Self::Coding,
            Self::Mathematics,
            Self::Creative,
            Self::Validation,
            Self::Coordination,
            Self::Debate,
            Self::Synthesis,
            Self::Strategy,
        ]
    }
}

// ============================================================================
// Agent Team
// ============================================================================

/// An agent team member
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMember {
    /// Agent name/identifier
    pub name: String,
    /// Primary capability
    pub capability: AgentCapability,
    /// Role in team
    pub role: AgentRole,
}

/// Role in an agent team
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum AgentRole {
    /// Lead agent
    Primary,
    /// Supporting agent
    Support,
    /// Validation/review
    Reviewer,
}

/// Agent team for a task
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentTeam {
    /// Team members
    pub members: Vec<AgentMember>,
    /// Team complexity score
    pub complexity: u8,
    /// Recommended LLM tier
    pub llm_tier: String,
}

impl Default for AgentTeam {
    fn default() -> Self {
        Self {
            members: vec![AgentMember {
                name: "Analyst".to_string(),
                capability: AgentCapability::Analysis,
                role: AgentRole::Primary,
            }],
            complexity: 1,
            llm_tier: "tier1".to_string(),
        }
    }
}

/// Task context for agent selection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskContext {
    /// The question or task
    pub question: String,
    /// Inferred domain
    pub domain: Option<String>,
    /// User's expertise in this domain
    pub user_expertise: f32,
    /// Required capabilities
    pub required_capabilities: Vec<AgentCapability>,
}

// ============================================================================
// Agent Mesh
// ============================================================================

/// Agent mesh - coordinates agent selection and execution
pub struct AgentMesh {
    /// Configuration
    config: AgentMeshConfig,
    /// Agent performance metrics
    metrics: Arc<RwLock<HashMap<AgentCapability, AgentMetrics>>>,
    /// Specialization scores per domain
    specialization: Arc<RwLock<HashMap<String, HashMap<AgentCapability, f32>>>>,
}

/// Agent performance metrics
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AgentMetrics {
    /// Total tasks completed
    pub tasks_completed: u32,
    /// Average satisfaction rating
    pub avg_satisfaction: Option<f32>,
    /// Success rate (0.0 - 1.0)
    pub success_rate: f32,
}

impl AgentMesh {
    /// Create new agent mesh
    pub fn new(config: AgentMeshConfig) -> Self {
        let mut metrics = HashMap::new();
        for cap in AgentCapability::all() {
            metrics.insert(cap, AgentMetrics::default());
        }

        Self {
            config,
            metrics: Arc::new(RwLock::new(metrics)),
            specialization: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Select team for given capabilities
    pub fn select_team(&self, capabilities: &[AgentCapability], _threshold: f32) -> AgentTeam {
        if capabilities.is_empty() {
            return AgentTeam::default();
        }

        let mut members = Vec::new();

        // First capability is primary
        let primary = capabilities[0];
        members.push(AgentMember {
            name: format!("{:?}Agent", primary),
            capability: primary,
            role: AgentRole::Primary,
        });

        // Rest are support
        for (i, &cap) in capabilities.iter().skip(1).enumerate() {
            if i >= self.config.max_team_size - 1 {
                break;
            }
            members.push(AgentMember {
                name: format!("{:?}Agent", cap),
                capability: cap,
                role: AgentRole::Support,
            });
        }

        // Determine complexity
        let complexity = (capabilities.len() as u8).clamp(1, 5);

        // Determine LLM tier
        let llm_tier = if complexity >= 3 {
            "tier2".to_string()
        } else {
            "tier1".to_string()
        };

        AgentTeam {
            members,
            complexity,
            llm_tier,
        }
    }

    /// Get proactive suggestions based on input
    pub fn get_proactive_suggestions(&self, input: &ExocortexInput) -> Vec<(String, f32)> {
        if !self.config.enable_proactive {
            return Vec::new();
        }

        let mut suggestions = Vec::new();
        let query_lower = input.query.to_lowercase();

        // Research suggestions
        if query_lower.contains("research") || query_lower.contains("paper") {
            suggestions.push((
                "Consider using TRIAD debate for research synthesis".to_string(),
                0.6,
            ));
        }

        // Code suggestions
        if query_lower.contains("code") || query_lower.contains("implement") {
            suggestions.push((
                "Would you like me to also write tests for this code?".to_string(),
                0.7,
            ));
        }

        // Writing suggestions
        if query_lower.contains("write") || query_lower.contains("draft") {
            suggestions.push((
                "I can help refine the tone and style if you share your preferences".to_string(),
                0.5,
            ));
        }

        suggestions
    }

    /// Record task completion for learning
    pub async fn record_completion(
        &self,
        capability: AgentCapability,
        domain: &str,
        success: bool,
        satisfaction: Option<f32>,
    ) {
        // Update metrics
        let mut metrics = self.metrics.write().await;
        if let Some(m) = metrics.get_mut(&capability) {
            m.tasks_completed += 1;

            let n = m.tasks_completed as f32;
            let old_rate = m.success_rate;
            m.success_rate = (old_rate * (n - 1.0) + if success { 1.0 } else { 0.0 }) / n;

            if let Some(sat) = satisfaction {
                let old_sat = m.avg_satisfaction.unwrap_or(0.5);
                m.avg_satisfaction = Some((old_sat * (n - 1.0) + sat) / n);
            }
        }

        // Update domain specialization
        if self.config.enable_specialization_learning {
            let mut spec = self.specialization.write().await;
            let domain_spec = spec.entry(domain.to_string()).or_default();

            let current = domain_spec.get(&capability).copied().unwrap_or(0.5);
            let update = if success { 0.1 } else { -0.05 };
            domain_spec.insert(capability, (current + update).clamp(0.0, 1.0));
        }
    }

    /// Get metrics for a capability
    pub async fn metrics_for(&self, capability: AgentCapability) -> AgentMetrics {
        let metrics = self.metrics.read().await;
        metrics.get(&capability).cloned().unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_team_selection() {
        let config = AgentMeshConfig::default();
        let mesh = AgentMesh::new(config);

        let caps = vec![AgentCapability::Research, AgentCapability::Writing];
        let team = mesh.select_team(&caps, 0.6);

        assert_eq!(team.members.len(), 2);
        assert_eq!(team.members[0].role, AgentRole::Primary);
        assert_eq!(team.members[1].role, AgentRole::Support);
    }

    #[test]
    fn test_empty_capabilities() {
        let config = AgentMeshConfig::default();
        let mesh = AgentMesh::new(config);

        let team = mesh.select_team(&[], 0.6);
        assert!(!team.members.is_empty()); // Should have default
    }
}
