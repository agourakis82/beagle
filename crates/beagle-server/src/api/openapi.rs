//! Especificação OpenAPI gerada via `utoipa`.

use utoipa::OpenApi;

use crate::api::routes::{auth, health, hyperedges, nodes, search};

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
        (name = "nodes", description = "Gestão de nós do hipergrafo"),
        (name = "hyperedges", description = "Gestão de hiperedges"),
        (name = "search", description = "Busca semântica e navegação"),
    )
)]
pub struct ApiDoc;







