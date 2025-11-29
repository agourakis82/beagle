//! REST API routes for integrated BEAGLE modules

use crate::state::AppState;
use axum::{
    extract::{Json, Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

// ===== MEMORY/RAG API =====

#[derive(Debug, Deserialize)]
pub struct RagQuery {
    pub query: String,
    pub k: Option<usize>,
    pub use_semantic: Option<bool>,
    pub use_keyword: Option<bool>,
}

#[derive(Debug, Serialize)]
pub struct RagResponse {
    pub documents: Vec<RagDocument>,
    pub total: usize,
    pub query_time_ms: u64,
}

#[derive(Debug, Serialize)]
pub struct RagDocument {
    pub id: String,
    pub content: String,
    pub score: f64,
    pub metadata: serde_json::Value,
}

/// POST /api/memory/documents - Add document to RAG system
pub async fn add_document(
    State(state): State<Arc<AppState>>,
    Json(doc): Json<DocumentInput>,
) -> Result<Response, ApiError> {
    let start = std::time::Instant::now();

    let document = beagle_memory::Document {
        id: doc.id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string()),
        content: doc.content,
        metadata: doc.metadata.unwrap_or_default(),
        embeddings: None,
    };

    state
        .rag_engine
        .write()
        .await
        .add_document(document.clone())
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "id": document.id,
        "message": "Document added successfully",
        "processing_time_ms": start.elapsed().as_millis()
    }))
    .into_response())
}

/// GET /api/memory/query - Query RAG system
pub async fn query_rag(
    State(state): State<Arc<AppState>>,
    Query(params): Query<RagQuery>,
) -> Result<Response, ApiError> {
    let start = std::time::Instant::now();

    let options = beagle_memory::QueryOptions {
        k: params.k.unwrap_or(5),
        use_semantic: params.use_semantic.unwrap_or(true),
        use_keyword: params.use_keyword.unwrap_or(true),
        filters: Default::default(),
    };

    let results = state
        .rag_engine
        .read()
        .await
        .query(&params.query, options)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let documents: Vec<RagDocument> = results
        .into_iter()
        .map(|doc| RagDocument {
            id: doc.id,
            content: doc.content,
            score: doc.score,
            metadata: serde_json::to_value(doc.metadata).unwrap_or_default(),
        })
        .collect();

    let response = RagResponse {
        total: documents.len(),
        documents,
        query_time_ms: start.elapsed().as_millis() as u64,
    };

    Ok(Json(response).into_response())
}

// ===== QUANTUM SIMULATOR API =====

#[derive(Debug, Deserialize)]
pub struct QuantumCircuit {
    pub num_qubits: usize,
    pub operations: Vec<QuantumOperation>,
}

#[derive(Debug, Deserialize)]
pub struct QuantumOperation {
    pub gate: String,
    pub qubit: usize,
    pub control: Option<usize>,
}

#[derive(Debug, Serialize)]
pub struct QuantumResult {
    pub measurements: Vec<u8>,
    pub probabilities: Vec<f64>,
    pub execution_time_ms: u64,
}

/// POST /api/quantum/simulate - Run quantum simulation
pub async fn simulate_quantum(
    State(state): State<Arc<AppState>>,
    Json(circuit): Json<QuantumCircuit>,
) -> Result<Response, ApiError> {
    use beagle_quantum::{QuantumGate, QuantumSimulator};

    let start = std::time::Instant::now();

    let mut sim = QuantumSimulator::new(circuit.num_qubits)
        .map_err(|e| ApiError::BadRequest(e.to_string()))?;

    // Apply operations
    for op in circuit.operations {
        let gate = match op.gate.as_str() {
            "H" => QuantumGate::H,
            "X" => QuantumGate::X,
            "Y" => QuantumGate::Y,
            "Z" => QuantumGate::Z,
            _ => return Err(ApiError::BadRequest(format!("Unknown gate: {}", op.gate))),
        };

        if let Some(control) = op.control {
            sim.apply_controlled_gate(control, op.qubit, gate)
                .map_err(|e| ApiError::Internal(e.to_string()))?;
        } else {
            sim.apply_gate(op.qubit, gate)
                .map_err(|e| ApiError::Internal(e.to_string()))?;
        }
    }

    // Measure all qubits
    let mut measurements = Vec::new();
    for i in 0..circuit.num_qubits {
        measurements.push(
            sim.measure(i)
                .map_err(|e| ApiError::Internal(e.to_string()))?,
        );
}

    let result = QuantumResult {
        measurements,
        probabilities: vec![], // Simplified for now
        execution_time_ms: start.elapsed().as_millis() as u64,
    };

    Ok(Json(result).into_response())
}

// ===== NEURAL ENGINE API =====

#[derive(Debug, Deserialize)]
pub struct NeuralInput {
    pub text: String,
    pub max_tokens: Option<usize>,
    pub temperature: Option<f32>,
}

#[derive(Debug, Serialize)]
pub struct NeuralOutput {
    pub generated_text: String,
    pub tokens: usize,
    pub processing_time_ms: u64,
}

/// POST /api/neural/generate - Generate text with transformer
pub async fn generate_text(
    State(state): State<Arc<AppState>>,
    Json(input): Json<NeuralInput>,
) -> Result<Response, ApiError> {
    let start = std::time::Instant::now();

    let max_tokens = input.max_tokens.unwrap_or(50);
    let temperature = input.temperature.unwrap_or(0.9);

    let generated = state
        .transformer
        .generate(&input.text, max_tokens, temperature)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let output = NeuralOutput {
        generated_text: generated,
        tokens: max_tokens,
        processing_time_ms: start.elapsed().as_millis() as u64,
    };

    Ok(Json(output).into_response())
}

// ===== SYMBOLIC REASONING API =====

#[derive(Debug, Deserialize)]
pub struct ReasoningInput {
    pub facts: Vec<FactInput>,
    pub rules: Vec<RuleInput>,
    pub query: FactInput,
}

#[derive(Debug, Deserialize)]
pub struct FactInput {
    pub predicate: String,
    pub terms: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct RuleInput {
    pub conditions: Vec<FactInput>,
    pub conclusion: FactInput,
}

#[derive(Debug, Serialize)]
pub struct ReasoningResult {
    pub proven: bool,
    pub proof_steps: Vec<String>,
    pub inference_time_ms: u64,
}

/// POST /api/symbolic/reason - Perform symbolic reasoning
pub async fn symbolic_reasoning(
    State(_state): State<Arc<AppState>>,
    Json(input): Json<ReasoningInput>,
) -> Result<Response, ApiError> {
    use beagle_symbolic::{Fact, InferenceEngine, KnowledgeBase, Rule};

    let start = std::time::Instant::now();

    let mut kb = KnowledgeBase::new();

    // Add facts
    for fact_input in input.facts {
        kb.add_fact(Fact::new(&fact_input.predicate, fact_input.terms));
    }

    // Add rules
    for rule_input in input.rules {
        let conditions: Vec<Fact> = rule_input
            .conditions
            .into_iter()
            .map(|f| Fact::new(&f.predicate, f.terms))
            .collect();
        let conclusion = Fact::new(
            &rule_input.conclusion.predicate,
            rule_input.conclusion.terms,
        );
        kb.add_rule(Rule::new(conditions, conclusion));
    }

    // Create engine and prove
    let mut engine = InferenceEngine::new(kb);
    let query = Fact::new(&input.query.predicate, input.query.terms);

    let proven = engine
        .prove(&query)
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let result = ReasoningResult {
        proven,
        proof_steps: engine.get_proof_trace(),
        inference_time_ms: start.elapsed().as_millis() as u64,
    };

    Ok(Json(result).into_response())
}

// ===== SEARCH ENGINE API =====

#[derive(Debug, Deserialize)]
pub struct SearchInput {
    pub query: String,
    pub limit: Option<usize>,
    pub filters: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct SearchResponse {
    pub results: Vec<SearchResult>,
    pub total: usize,
    pub facets: serde_json::Value,
    pub search_time_ms: u64,
}

#[derive(Debug, Serialize)]
pub struct SearchResult {
    pub id: String,
    pub content: String,
    pub score: f64,
    pub snippet: String,
    pub metadata: serde_json::Value,
}

/// POST /api/search/index - Index a document
pub async fn index_document(
    State(state): State<Arc<AppState>>,
    Json(doc): Json<DocumentInput>,
) -> Result<Response, ApiError> {
    let mut document = beagle_search::Document::new(&doc.content);
    document.id = doc.id.unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    if let Some(metadata) = doc.metadata {
        if let Some(obj) = metadata.as_object() {
            for (key, value) in obj {
                if let Some(val_str) = value.as_str() {
                    document.add_metadata(key, val_str);
                }
            }
        }
    }

    state
        .search_engine
        .write()
        .await
        .index_document(document.clone())
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "id": document.id,
        "message": "Document indexed successfully"
    }))
    .into_response())
}

/// GET /api/search - Search documents
pub async fn search_documents(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SearchInput>,
) -> Result<Response, ApiError> {
    let start = std::time::Instant::now();

    let mut query = beagle_search::SearchQuery::new(&params.query);
    if let Some(limit) = params.limit {
        query = query.with_limit(limit);
    }

    let results = state
        .search_engine
        .read()
        .await
        .search(&query)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let search_results: Vec<SearchResult> = results
        .into_iter()
        .map(|r| SearchResult {
            id: r.id,
            content: r.content.clone(),
            score: r.score,
            snippet: r
                .snippet
                .unwrap_or_else(|| r.content[..100.min(r.content.len())].to_string()),
            metadata: serde_json::to_value(r.metadata).unwrap_or_default(),
        })
        .collect();

    let response = SearchResponse {
        total: search_results.len(),
        results: search_results,
        facets: serde_json::json!({}),
        search_time_ms: start.elapsed().as_millis() as u64,
    };

    Ok(Json(response).into_response())
}

// ===== OBSERVER/METRICS API =====

#[derive(Debug, Deserialize)]
pub struct MetricInput {
    pub name: String,
    pub value: f64,
    pub metric_type: String,
    pub labels: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
pub struct MetricsResponse {
    pub total_metrics: usize,
    pub top_metrics: Vec<MetricData>,
    pub anomalies: Vec<AnomalyData>,
}

#[derive(Debug, Serialize)]
pub struct MetricData {
    pub name: String,
    pub value: f64,
    pub timestamp: String,
}

#[derive(Debug, Serialize)]
pub struct AnomalyData {
    pub metric_name: String,
    pub score: f64,
    pub description: String,
}

/// POST /api/metrics - Record a metric
pub async fn record_metric(
    State(state): State<Arc<AppState>>,
    Json(input): Json<MetricInput>,
) -> Result<Response, ApiError> {
    use beagle_observer::{Metric, MetricType};

    let metric = match input.metric_type.as_str() {
        "counter" => Metric::counter(&input.name, input.value),
        "gauge" => Metric::gauge(&input.name, input.value),
        "histogram" => Metric::histogram(&input.name, vec![input.value]),
        _ => return Err(ApiError::BadRequest("Invalid metric type".to_string())),
    };

    state
        .observer
        .record_metric(metric)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(serde_json::json!({
        "message": "Metric recorded successfully"
    }))
    .into_response())
}

/// GET /api/metrics/summary - Get metrics summary
pub async fn get_metrics_summary(State(state): State<Arc<AppState>>) -> Result<Response, ApiError> {
    use beagle_observer::TimeWindow;

    let summary = state
        .observer
        .get_metrics_summary(TimeWindow::Minutes(5))
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let response = MetricsResponse {
        total_metrics: summary.total_metrics,
        top_metrics: summary
            .top_metrics
            .into_iter()
            .take(10)
            .map(|m| MetricData {
                name: m.name,
                value: m.value,
                timestamp: m.timestamp.to_rfc3339(),
            })
            .collect(),
        anomalies: summary
            .anomalies
            .into_iter()
            .map(|a| AnomalyData {
                metric_name: a.metric_name,
                score: a.score,
                description: a.description,
            })
            .collect(),
    };

    Ok(Json(response).into_response())
}

/// GET /api/health - Get system health status
pub async fn get_health(State(state): State<Arc<AppState>>) -> Result<Response, ApiError> {
    let health = state
        .observer
        .get_health()
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    Ok(Json(health).into_response())
}

// ===== COMMON TYPES =====

#[derive(Debug, Deserialize)]
pub struct DocumentInput {
    pub id: Option<String>,
    pub content: String,
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug)]
pub enum ApiError {
    BadRequest(String),
    NotFound(String),
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            ApiError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            ApiError::NotFound(msg) => (StatusCode::NOT_FOUND, msg),
            ApiError::Internal(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };

        let body = Json(serde_json::json!({
            "error": error_message,
            "status": status.as_u16(),
        }));

        (status, body).into_response()
    }
}

// ===== ROUTE CONFIGURATION =====

use axum::routing::{get, post};
use axum::Router;

/// Configure all integrated module routes
pub fn configure_routes() -> Router<Arc<AppState>> {
    Router::new()
        // Memory/RAG routes
        .route("/api/memory/documents", post(add_document))
        .route("/api/memory/query", get(query_rag))
        // Quantum simulator routes
        .route("/api/quantum/simulate", post(simulate_quantum))
        // Neural engine routes
        .route("/api/neural/generate", post(generate_text))
        // Symbolic reasoning routes
        .route("/api/symbolic/reason", post(symbolic_reasoning))
        // Search engine routes
        .route("/api/search/index", post(index_document))
        .route("/api/search", get(search_documents))
        // Observer/metrics routes
        .route("/api/metrics", post(record_metric))
        .route("/api/metrics/summary", get(get_metrics_summary))
        .route("/api/health", get(get_health))
}

