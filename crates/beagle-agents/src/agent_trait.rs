use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Trait base para agentes especializados executados em paralelo.
#[async_trait]
pub trait Agent: Send + Sync {
    /// Identificador único do agente.
    fn id(&self) -> &str;

    /// Competência principal do agente.
    fn capability(&self) -> AgentCapability;

    /// Executa a tarefa do agente.
    async fn execute(&self, input: AgentInput) -> Result<AgentOutput>;

    /// Permite health-checks customizados.
    async fn health_check(&self) -> AgentHealth {
        AgentHealth::Healthy
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AgentCapability {
    ContextRetrieval,
    FactChecking,
    QualityAssessment,
    ResponseGeneration,
    Coordination,
    Synthesis,
}

#[derive(Debug, Clone)]
pub struct AgentInput {
    pub query: String,
    pub context: Vec<String>,
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentOutput {
    pub agent_id: String,
    pub result: Value,
    pub confidence: f32,
    pub duration_ms: u64,
    pub metadata: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentHealth {
    Healthy,
    Degraded,
    Unhealthy,
}

impl AgentInput {
    pub fn new(query: String) -> Self {
        Self {
            query,
            context: vec![],
            metadata: serde_json::json!({}),
        }
    }

    pub fn with_context(mut self, context: Vec<String>) -> Self {
        self.context = context;
        self
    }

    pub fn with_metadata(mut self, metadata: Value) -> Self {
        self.metadata = metadata;
        self
    }
}
