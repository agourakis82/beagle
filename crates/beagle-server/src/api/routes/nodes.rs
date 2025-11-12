//! Endpoints de CRUD para nós do hipergrafo.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use beagle_hypergraph::{
    models::{ContentType, Node},
    types::Embedding,
    StorageRepository,
};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::{
    auth::Claims,
    error::{ApiError, ApiResult},
    state::AppState,
};

fn empty_metadata() -> serde_json::Value {
    serde_json::json!({})
}

/// Payload de criação de nó.
#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateNodeRequest {
    #[schema(example = "Insight sobre grafos hiperbólicos")]
    pub content: String,
    #[schema(value_type = String, example = "Thought")]
    pub content_type: ContentType,
    #[serde(default = "empty_metadata")]
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    #[schema(value_type = Vec<f32>, example = json!([0.12, 0.42, 0.98]))]
    pub embedding: Option<Vec<f32>>,
}

/// Payload de atualização.
#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateNodeRequest {
    #[schema(example = "Insight revisado sobre grafos hiperbólicos")]
    pub content: String,
    #[schema(value_type = String, example = "Memory")]
    pub content_type: ContentType,
    #[serde(default = "empty_metadata")]
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    #[schema(value_type = Vec<f32>)]
    pub embedding: Option<Vec<f32>>,
}

/// Representação de nó retornada pela API.
#[derive(Debug, Serialize, ToSchema)]
pub struct NodeResponse {
    pub id: Uuid,
    pub content: String,
    #[schema(value_type = String)]
    pub content_type: String,
    #[schema(value_type = Object)]
    pub metadata: serde_json::Value,
    pub created_at: String,
    pub updated_at: String,
    pub device_id: String,
    #[schema(nullable = true)]
    pub embedding: Option<Vec<f32>>,
    pub version: i32,
}

impl From<Node> for NodeResponse {
    fn from(node: Node) -> Self {
        Self {
            id: node.id,
            content: node.content,
            content_type: node.content_type.to_string(),
            metadata: node.metadata,
            created_at: node.created_at.to_rfc3339(),
            updated_at: node.updated_at.to_rfc3339(),
            device_id: node.device_id,
            embedding: node.embedding.map(Into::into),
            version: node.version,
        }
    }
}

/// Consulta com paginação.
#[derive(Debug, Deserialize, IntoParams)]
pub struct ListNodesQuery {
    #[serde(default = "default_limit")]
    #[param(example = 20)]
    pub limit: usize,
    #[serde(default)]
    #[param(example = 0)]
    pub offset: usize,
    #[serde(default)]
    #[param(value_type = Option<String>, example = "Thought")]
    pub content_type: Option<ContentType>,
    #[serde(default)]
    #[param(example = "device-alpha")]
    pub device_id: Option<String>,
}

const fn default_limit() -> usize {
    20
}

/// Roteador dos endpoints de nós.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/nodes", post(create_node).get(list_nodes))
        .route(
            "/api/v1/nodes/:id",
            get(get_node).put(update_node).delete(delete_node),
        )
}

/// Cria novo nó.
#[utoipa::path(
    post,
    path = "/api/v1/nodes",
    request_body = CreateNodeRequest,
    responses(
        (status = 201, description = "Nó criado", body = NodeResponse),
        (status = 400, description = "Payload inválido"),
        (status = 401, description = "Não autorizado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn create_node(
    State(state): State<AppState>,
    claims: Claims,
    Json(payload): Json<CreateNodeRequest>,
) -> ApiResult<(StatusCode, Json<NodeResponse>)> {
    let mut builder = Node::builder()
        .content(payload.content)
        .content_type(payload.content_type)
        .metadata(payload.metadata)
        .device_id(claims.device_id.clone());

    if let Some(embedding) = payload.embedding {
        builder = builder.embedding(embedding);
    }

    let node = builder
        .build()
        .map_err(|err| ApiError::BadRequest(format!("Erro de validação: {err}")))?;

    let created = state
        .storage
        .create_node(node)
        .await
        .map_err(ApiError::from)?;

    Ok((StatusCode::CREATED, Json(created.into())))
}

/// Recupera nó por ID.
#[utoipa::path(
    get,
    path = "/api/v1/nodes/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do nó")
    ),
    responses(
        (status = 200, description = "Nó encontrado", body = NodeResponse),
        (status = 404, description = "Nó não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn get_node(
    State(state): State<AppState>,
    _claims: Claims,
    Path(id): Path<Uuid>,
) -> ApiResult<Json<NodeResponse>> {
    let node = state.storage.get_node(id).await.map_err(ApiError::from)?;

    Ok(Json(node.into()))
}

/// Atualiza nó existente.
#[utoipa::path(
    put,
    path = "/api/v1/nodes/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do nó")
    ),
    request_body = UpdateNodeRequest,
    responses(
        (status = 200, description = "Nó atualizado", body = NodeResponse),
        (status = 404, description = "Nó não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn update_node(
    State(state): State<AppState>,
    claims: Claims,
    Path(id): Path<Uuid>,
    Json(payload): Json<UpdateNodeRequest>,
) -> ApiResult<Json<NodeResponse>> {
    let mut node = state.storage.get_node(id).await.map_err(ApiError::from)?;

    node.content = payload.content;
    node.content_type = payload.content_type;
    node.metadata = payload.metadata;
    node.device_id = claims.device_id;
    node.embedding = payload.embedding.map(Embedding::from);

    let updated = state
        .storage
        .update_node(node)
        .await
        .map_err(ApiError::from)?;

    Ok(Json(updated.into()))
}

/// Remove nó.
#[utoipa::path(
    delete,
    path = "/api/v1/nodes/{id}",
    params(
        ("id" = Uuid, Path, description = "Identificador do nó")
    ),
    responses(
        (status = 204, description = "Nó removido"),
        (status = 404, description = "Nó não encontrado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn delete_node(
    State(state): State<AppState>,
    _claims: Claims,
    Path(id): Path<Uuid>,
) -> ApiResult<StatusCode> {
    state
        .storage
        .delete_node(id)
        .await
        .map_err(ApiError::from)?;
    Ok(StatusCode::NO_CONTENT)
}

/// Lista nós com filtros opcionais.
#[utoipa::path(
    get,
    path = "/api/v1/nodes",
    params(ListNodesQuery),
    responses(
        (status = 200, description = "Lista de nós", body = [NodeResponse])
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn list_nodes(
    State(state): State<AppState>,
    _claims: Claims,
    Query(query): Query<ListNodesQuery>,
) -> ApiResult<Json<Vec<NodeResponse>>> {
    let mut nodes = state
        .storage
        .list_nodes(None)
        .await
        .map_err(ApiError::from)?;

    if let Some(content_type) = query.content_type {
        nodes.retain(|node| node.content_type == content_type);
    }

    if let Some(device_id) = query.device_id {
        nodes.retain(|node| node.device_id == device_id);
    }

    nodes.sort_by(|a, b| b.created_at.cmp(&a.created_at));

    let slice = nodes
        .into_iter()
        .skip(query.offset)
        .take(query.limit)
        .map(NodeResponse::from)
        .collect();

    Ok(Json(slice))
}







