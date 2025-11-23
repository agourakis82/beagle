use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::neurosymbolic::{Fact, LogicRule, NeuralExtractor, Predicate, HybridReasoner};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct NeuroSymbolicRequest {
    /// Query or instruction for reasoning
    pub query: String,
    /// Text to analyze and extract knowledge from
    pub text: String,
    /// Whether to run forward chaining
    #[serde(default)]
    pub enable_forward_chain: bool,
}

#[derive(Debug, Serialize)]
pub struct NeuroSymbolicResponse {
    pub extracted_facts: Vec<FactDto>,
    pub extracted_rules: Vec<RuleDto>,
    pub derived_facts: Vec<PredicateDto>,
    pub is_consistent: bool,
    pub confidence_score: f64,
    pub hallucinations: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct FactDto {
    pub predicate: String,
    pub args: Vec<String>,
    pub confidence: f64,
    pub source: String,
}

#[derive(Debug, Serialize)]
pub struct RuleDto {
    pub premises: Vec<PredicateDto>,
    pub conclusion: PredicateDto,
    pub confidence: f64,
}

#[derive(Debug, Serialize)]
pub struct PredicateDto {
    pub name: String,
    pub args: Vec<String>,
}

pub async fn neurosymbolic_reason(
    State(state): State<AppState>,
    Json(req): Json<NeuroSymbolicRequest>,
) -> Result<Json<NeuroSymbolicResponse>, (StatusCode, String)> {
    info!("🔬 /dev/neurosymbolic - Analyzing text ({} chars)", req.text.len());

    // Create hybrid reasoner
    let neural_extractor = Arc::new(NeuralExtractor::new(state.anthropic.clone()));
    let mut hybrid = HybridReasoner::new(neural_extractor);

    // Run hybrid reasoning
    let result = hybrid
        .reason(&req.text)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, format!("Reasoning failed: {}", e)))?;

    // Detect hallucinations
    let hallucinations = hybrid.detect_hallucinations(&result.extracted_facts);

    info!(
        "✅ Extracted {} facts, {} rules, derived {} facts",
        result.extracted_facts.len(),
        result.extracted_rules.len(),
        result.derived_facts.len()
    );

    // Convert to DTOs
    let response = NeuroSymbolicResponse {
        extracted_facts: result.extracted_facts.iter().map(fact_to_dto).collect(),
        extracted_rules: result.extracted_rules.iter().map(rule_to_dto).collect(),
        derived_facts: result.derived_facts.iter().map(pred_to_dto).collect(),
        is_consistent: result.is_consistent,
        confidence_score: result.confidence_score,
        hallucinations,
    };

    Ok(Json(response))
}

// Conversion helpers

fn fact_to_dto(fact: &Fact) -> FactDto {
    FactDto {
        predicate: fact.predicate.name.clone(),
        args: fact.predicate.args.iter().map(term_to_string).collect(),
        confidence: fact.confidence,
        source: fact.source.clone(),
    }
}

fn rule_to_dto(rule: &LogicRule) -> RuleDto {
    RuleDto {
        premises: rule.premises.iter().map(pred_to_dto).collect(),
        conclusion: pred_to_dto(&rule.conclusion),
        confidence: rule.confidence,
    }
}

fn pred_to_dto(pred: &Predicate) -> PredicateDto {
    PredicateDto {
        name: pred.name.clone(),
        args: pred.args.iter().map(term_to_string).collect(),
    }
}

fn term_to_string(term: &beagle_agents::neurosymbolic::Term) -> String {
    use beagle_agents::neurosymbolic::Term;
    match term {
        Term::Constant(c) => c.clone(),
        Term::Variable(v) => format!("?{}", v),
        Term::Function(f, args) => {
            format!("{}({})", f, args.iter().map(term_to_string).collect::<Vec<_>>().join(", "))
        }
    }
}
