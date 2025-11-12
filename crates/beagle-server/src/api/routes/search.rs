//! Endpoints de busca semântica e vizinhança.

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use beagle_hypergraph::StorageRepository;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::{
    auth::Claims,
    error::{ApiError, ApiResult},
    state::AppState,
};

/// Payload para busca semântica.
#[derive(Debug, Deserialize, ToSchema)]
pub struct SemanticSearchRequest {
    #[schema(value_type = Vec<f32>)]
    pub embedding: Vec<f32>,
    #[serde(default = "default_limit")]
    #[schema(example = 10)]
    pub limit: usize,
    #[serde(default = "default_threshold")]
    #[schema(example = 0.75)]
    pub threshold: f32,
}

const fn default_limit() -> usize {
    10
}

const fn default_threshold() -> f32 {
    0.7
}

/// Item de resposta da busca semântica.
#[derive(Debug, Serialize, ToSchema)]
pub struct SemanticMatch {
    pub score: f32,
    pub node: super::nodes::NodeResponse,
}

/// Parâmetros de vizinhança.
#[derive(Debug, Deserialize, IntoParams, ToSchema)]
pub struct NeighborhoodQuery {
    #[serde(default = "default_depth")]
    #[schema(example = 2)]
    pub depth: i32,
}

const fn default_depth() -> i32 {
    2
}

/// Resposta de vizinhança agrupada.
#[derive(Debug, Serialize, ToSchema)]
pub struct NeighborhoodResponse {
    pub node: super::nodes::NodeResponse,
    pub depth: i32,
}

/// Roteador dos endpoints de busca.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/search/semantic", post(semantic_search))
        .route("/api/v1/search/neighbors/:id", get(neighborhood))
}

/// Busca semântica por embedding.
#[utoipa::path(
    post,
    path = "/api/v1/search/semantic",
    request_body = SemanticSearchRequest,
    responses(
        (status = 200, description = "Resultados ranqueados", body = [SemanticMatch]),
        (status = 400, description = "Payload inválido"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn semantic_search(
    State(state): State<AppState>,
    _claims: Claims,
    Json(payload): Json<SemanticSearchRequest>,
) -> ApiResult<Json<Vec<SemanticMatch>>> {
    if payload.embedding.is_empty() {
        return Err(ApiError::BadRequest(
            "Embedding da consulta não pode ser vazio".into(),
        ));
    }

    let matches = state
        .storage
        .semantic_search(payload.embedding, payload.limit, payload.threshold)
        .await
        .map_err(ApiError::from)?;

    let response = matches
        .into_iter()
        .map(|(node, score)| SemanticMatch {
            score,
            node: node.into(),
        })
        .collect();

    Ok(Json(response))
}

/// Vizualização de vizinhança BFS.
#[utoipa::path(
    get,
    path = "/api/v1/search/neighbors/{id}",
    params(
        ("id" = Uuid, Path, description = "Nó de partida"),
        NeighborhoodQuery
    ),
    responses(
        (status = 200, description = "Nós alcançáveis", body = [NeighborhoodResponse]),
        (status = 404, description = "Nó não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn neighborhood(
    State(state): State<AppState>,
    _claims: Claims,
    Path(node_id): Path<Uuid>,
    Query(query): Query<NeighborhoodQuery>,
) -> ApiResult<Json<Vec<NeighborhoodResponse>>> {
    let depth = query.depth.max(1);

    let neighbors = state
        .storage
        .query_neighborhood(node_id, depth)
        .await
        .map_err(ApiError::from)?;

    let response = neighbors
        .into_iter()
        .map(|(node, depth)| NeighborhoodResponse {
            node: node.into(),
            depth,
        })
        .collect();

    Ok(Json(response))
}







