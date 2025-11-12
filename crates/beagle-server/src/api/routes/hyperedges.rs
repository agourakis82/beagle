//! Endpoints para gerenciamento de hiperedges.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use beagle_hypergraph::{models::Hyperedge, StorageRepository};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::{
    auth::Claims,
    error::{ApiError, ApiResult},
    state::AppState,
};

fn default_metadata() -> serde_json::Value {
    serde_json::json!({})
}

/// Payload de criação de hiperedges.
#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateHyperedgeRequest {
    #[schema(example = "relates")]
    pub label: String,
    #[schema(value_type = Vec<Uuid>)]
    pub node_ids: Vec<Uuid>,
    #[serde(default = "default_metadata")]
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    #[schema(example = false)]
    pub directed: bool,
}

/// Payload de atualização.
#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateHyperedgeRequest {
    #[schema(example = "relates")]
    pub label: String,
    #[schema(value_type = Vec<Uuid>)]
    pub node_ids: Vec<Uuid>,
    #[serde(default = "default_metadata")]
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    pub directed: bool,
}

/// Representação pública de hiperedges.
#[derive(Debug, Serialize, ToSchema)]
pub struct HyperedgeResponse {
    pub id: Uuid,
    pub label: String,
    #[schema(value_type = Vec<Uuid>)]
    pub node_ids: Vec<Uuid>,
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    pub created_at: String,
    pub updated_at: String,
    pub device_id: String,
    pub directed: bool,
    pub version: i32,
}

impl From<Hyperedge> for HyperedgeResponse {
    fn from(edge: Hyperedge) -> Self {
        Self {
            id: edge.id,
            label: edge.edge_type,
            node_ids: edge.node_ids,
            metadata: edge.metadata,
            created_at: edge.created_at.to_rfc3339(),
            updated_at: edge.updated_at.to_rfc3339(),
            device_id: edge.device_id,
            directed: edge.directed,
            version: edge.version,
        }
    }
}

/// Query de listagem.
#[derive(Debug, Deserialize, IntoParams, ToSchema)]
pub struct ListHyperedgesQuery {
    #[serde(default)]
    #[schema(value_type = Option<Uuid>)]
    pub node_id: Option<Uuid>,
}

/// Roteador de hiperedges.
pub fn router() -> Router<AppState> {
    Router::new()
        .route(
            "/api/v1/hyperedges",
            post(create_hyperedge).get(list_hyperedges),
        )
        .route(
            "/api/v1/hyperedges/:id",
            get(get_hyperedge)
                .put(update_hyperedge)
                .delete(delete_hyperedge),
        )
}

/// Cria novo hiperedge.
#[utoipa::path(
    post,
    path = "/api/v1/hyperedges",
    request_body = CreateHyperedgeRequest,
    responses(
        (status = 201, description = "Hiperedge criado", body = HyperedgeResponse),
        (status = 400, description = "Payload inválido"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn create_hyperedge(
    State(state): State<AppState>,
    claims: Claims,
    Json(payload): Json<CreateHyperedgeRequest>,
) -> ApiResult<(StatusCode, Json<HyperedgeResponse>)> {
    let mut edge = Hyperedge::new(
        payload.label,
        payload.node_ids,
        payload.directed,
        claims.device_id.clone(),
    )
    .map_err(|err| ApiError::BadRequest(format!("Erro de validação: {err}")))?;
    edge.metadata = payload.metadata;

    let created = state
        .storage
        .create_hyperedge(edge)
        .await
        .map_err(ApiError::from)?;

    Ok((StatusCode::CREATED, Json(created.into())))
}

/// Busca hiperedge por ID.
#[utoipa::path(
    get,
    path = "/api/v1/hyperedges/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do hiperedge")
    ),
    responses(
        (status = 200, description = "Hiperedge encontrado", body = HyperedgeResponse),
        (status = 404, description = "Hiperedge não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn get_hyperedge(
    State(state): State<AppState>,
    _claims: Claims,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<HyperedgeResponse>> {
    let edge = state
        .storage
        .get_hyperedge(id)
        .await
        .map_err(ApiError::from)?;

    Ok(Json(edge.into()))
}

/// Atualiza hiperedge.
#[utoipa::path(
    put,
    path = "/api/v1/hyperedges/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do hiperedge")
    ),
    request_body = UpdateHyperedgeRequest,
    responses(
        (status = 200, description = "Hiperedge atualizado", body = HyperedgeResponse),
        (status = 404, description = "Hiperedge não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn update_hyperedge(
    State(state): State<AppState>,
    claims: Claims,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateHyperedgeRequest>,
) -> ApiResult<Json<HyperedgeResponse>> {
    let mut edge = state
        .storage
        .get_hyperedge(id)
        .await
        .map_err(ApiError::from)?;

    edge.edge_type = payload.label;
    edge.node_ids = payload.node_ids;
    edge.metadata = payload.metadata;
    edge.directed = payload.directed;
    edge.device_id = claims.device_id;

    let updated = state
        .storage
        .update_hyperedge(edge)
        .await
        .map_err(ApiError::from)?;

    Ok(Json(updated.into()))
}

/// Remove hiperedge.
#[utoipa::path(
    delete,
    path = "/api/v1/hyperedges/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do hiperedge")
    ),
    responses(
        (status = 204, description = "Hiperedge removido"),
        (status = 404, description = "Hiperedge não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn delete_hyperedge(
    State(state): State<AppState>,
    _claims: Claims,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    state
        .storage
        .delete_hyperedge(id)
        .await
        .map_err(ApiError::from)?;
    Ok(StatusCode::NO_CONTENT)
}

/// Lista hiperedges com filtro opcional.
#[utoipa::path(
    get,
    path = "/api/v1/hyperedges",
    params(ListHyperedgesQuery),
    responses(
        (status = 200, description = "Lista de hiperedges", body = [HyperedgeResponse])
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn list_hyperedges(
    State(state): State<AppState>,
    _claims: Claims,
    Query(query): Query<ListHyperedgesQuery>,
) -> ApiResult<Json<Vec<HyperedgeResponse>>> {
    let mut edges = match query.node_id {
        Some(node_id) => state
            .storage
            .get_edges_for_node(node_id)
            .await
            .map_err(ApiError::from)?,
        None => state
            .storage
            .list_hyperedges(None)
            .await
            .map_err(ApiError::from)?,
    };

    edges.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    Ok(Json(
        edges.into_iter().map(HyperedgeResponse::from).collect(),
    ))
}
