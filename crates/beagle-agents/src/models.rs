use beagle_personality::Domain;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Etapa individual registrada durante a pesquisa.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResearchStep {
    pub step_number: usize,
    pub action: String,
    pub result: String,
    pub duration_ms: u64,
}

/// Métricas consolidadas da execução.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResearchMetrics {
    pub total_duration_ms: u64,
    pub llm_calls: usize,
    pub context_chunks_retrieved: usize,
    pub refinement_iterations: usize,
    pub quality_score: f32,
}

/// Resultado padronizado devolvido ao servidor.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResearchResult {
    pub answer: String,
    pub domain: Domain,
    pub steps: Vec<ResearchStep>,
    pub metrics: ResearchMetrics,
    pub session_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sources: Option<Vec<String>>,
}


