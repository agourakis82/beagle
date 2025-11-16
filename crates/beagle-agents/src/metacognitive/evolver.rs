use super::{
    analyzer::FailurePattern,
    specialized::SpecializedAgentFactory,
};
use anyhow::Result;
use tracing::info;

pub struct ArchitectureEvolver {
    agent_factory: SpecializedAgentFactory,
    evolution_threshold: f64,
}

impl ArchitectureEvolver {
    pub fn new(agent_factory: SpecializedAgentFactory) -> Self {
        Self {
            agent_factory,
            evolution_threshold: 0.3, // Evolve if failure rate > 30%
        }
    }
    
    pub async fn evolve(&mut self, patterns: &[FailurePattern]) -> Result<EvolutionResult> {
        info!("🧬 Evolution triggered: {} patterns detected", patterns.len());
        
        let mut created_agents = Vec::new();
        
        for pattern in patterns {
            // Create specialized agent for this pattern
            let agent_spec = self.agent_factory.create_for_pattern(pattern).await?;
            created_agents.push(agent_spec);
        }
        
        let count = created_agents.len();
        let architecture_changed = !created_agents.is_empty();
        info!("✅ Created {} specialized agents", count);
        
        Ok(EvolutionResult {
            new_agents: created_agents,
            architecture_changed,
        })
    }
    
    pub fn should_evolve(&self, failure_rate: f64) -> bool {
        failure_rate > self.evolution_threshold
    }
}

#[derive(Debug, Clone)]
pub struct EvolutionResult {
    pub new_agents: Vec<AgentSpecification>,
    pub architecture_changed: bool,
}

#[derive(Debug, Clone)]
pub struct AgentSpecification {
    pub name: String,
    pub capability: String,
    pub system_prompt: String,
    pub model_type: String,
}
