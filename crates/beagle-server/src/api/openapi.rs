//! Especificação OpenAPI gerada via `utoipa`.

use utoipa::OpenApi;

use crate::api::routes::{auth, chat, health, hyperedges, nodes, search};

/// Documento OpenAPI 3.1 do Beagle Server.
#[derive(OpenApi)]
#[openapi(
    info(
        title = "Beagle Hypergraph API",
        version = "1.0.0",
        description = "REST API para manipulação do hipergrafo cognitivo Beagle.",
        contact(
            name = "Equipe Beagle",
            email = "api@beagle.dev"
        )
    ),
    paths(
        health::health_check,
        health::readiness_check,
        health::liveness_check,
        chat::chat_completion,
        auth::login,
        auth::me,
        nodes::create_node,
        nodes::get_node,
        nodes::update_node,
        nodes::delete_node,
        nodes::list_nodes,
        hyperedges::create_hyperedge,
        hyperedges::get_hyperedge,
        hyperedges::update_hyperedge,
        hyperedges::delete_hyperedge,
        hyperedges::list_hyperedges,
        search::semantic_search,
        search::neighborhood
    ),
    components(
        schemas(
            auth::LoginRequest,
            auth::LoginResponse,
            auth::MeResponse,
            chat::ChatRequest,
            chat::ChatResponse,
            nodes::CreateNodeRequest,
            nodes::UpdateNodeRequest,
            nodes::NodeResponse,
            hyperedges::CreateHyperedgeRequest,
            hyperedges::UpdateHyperedgeRequest,
            hyperedges::HyperedgeResponse,
            health::HealthResponse,
            search::SemanticSearchRequest,
            search::SemanticMatch,
            search::NeighborhoodQuery,
            search::NeighborhoodResponse
        )
    ),
    tags(
        (name = "health", description = "Monitoramento e prontidão"),
        (name = "auth", description = "Autenticação e identidade"),
        (name = "chat", description = "Integração LLM via Vertex AI"),
        (name = "nodes", description = "Gestão de nós do hipergrafo"),
        (name = "hyperedges", description = "Gestão de hiperedges"),
        (name = "search", description = "Busca semântica e navegação"),
        (name = "dev", description = "🚀 Revolutionary AI Features (Weeks 1-14)"),
        (name = "quantum", description = "Quantum-Inspired Reasoning (Week 1-2)"),
        (name = "adversarial", description = "Adversarial Self-Play (Week 3-4)"),
        (name = "metacognitive", description = "Metacognitive Evolution (Week 5-7)"),
        (name = "neurosymbolic", description = "Neuro-Symbolic Hybrid (Week 8-10)"),
        (name = "temporal", description = "Temporal Multi-Scale Reasoning (Week 13)"),
    )
)]
pub struct ApiDoc;

/// Revolutionary Features API Documentation (v2.0)
///
/// BEAGLE v2.0 exposes cutting-edge AI capabilities through /dev endpoints:
///
/// ## Quantum-Inspired Reasoning (Week 1-2)
/// - `/dev/quantum-reasoning` - Superposition states, interference patterns, measurement collapse
///
/// ## Adversarial Self-Play (Week 3-4)
/// - `/dev/adversarial-compete` - Tournament-based competition, ELO ratings, strategy evolution
///
/// ## Metacognitive Evolution (Week 5-7)
/// - `/dev/metacognitive/analyze-performance` - Performance bottleneck analysis
/// - `/dev/metacognitive/analyze-failures` - Failure pattern detection
///
/// ## Neuro-Symbolic Hybrid (Week 8-10)
/// - `/dev/neurosymbolic` - First-order logic, hallucination detection, symbolic reasoning
///
/// ## Temporal Multi-Scale (Week 13)
/// - `/dev/temporal` - Multi-scale causality (µs → years), pattern mining, anomaly detection
///
/// ## Advanced Research
/// - `/dev/deep-research` - MCTS-based deep exploration
/// - `/dev/swarm` - Swarm intelligence coordination
/// - `/dev/reasoning` - General hybrid reasoning
/// - `/dev/debate` - Multi-agent debate orchestration
///
/// All endpoints require Anthropic API key configuration.
