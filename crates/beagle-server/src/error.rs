//! Definições de erro HTTP da camada de API.

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use beagle_hypergraph::error::HypergraphError;
use serde::Serialize;

/// Resultado padrão da API.
pub type ApiResult<T> = Result<T, ApiError>;

/// Enum coerente com códigos HTTP apropriados.
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    Unauthorized(String),
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Conflict(String),
    #[error("{0}")]
    TooManyRequests(String),
    #[error("{0}")]
    Internal(String),
}

#[derive(Serialize)]
struct ErrorResponse<'a> {
    error: &'a str,
    message: String,
}

impl ApiError {
    fn status_code(&self) -> StatusCode {
        match self {
            ApiError::BadRequest(_) => StatusCode::BAD_REQUEST,
            ApiError::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            ApiError::NotFound(_) => StatusCode::NOT_FOUND,
            ApiError::Conflict(_) => StatusCode::CONFLICT,
            ApiError::TooManyRequests(_) => StatusCode::TOO_MANY_REQUESTS,
            ApiError::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }

    fn label(&self) -> &'static str {
        match self {
            ApiError::BadRequest(_) => "BadRequest",
            ApiError::Unauthorized(_) => "Unauthorized",
            ApiError::NotFound(_) => "NotFound",
            ApiError::Conflict(_) => "Conflict",
            ApiError::TooManyRequests(_) => "TooManyRequests",
            ApiError::Internal(_) => "InternalServerError",
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = self.status_code();
        let body = Json(ErrorResponse {
            error: self.label(),
            message: self.to_string(),
        });
        (status, body).into_response()
    }
}

impl From<HypergraphError> for ApiError {
    fn from(error: HypergraphError) -> Self {
        if error.is_client_error() {
            match error {
                HypergraphError::NodeNotFound(id) => {
                    ApiError::NotFound(format!("Node {id} não encontrado"))
                }
                HypergraphError::HyperedgeNotFound(id) => {
                    ApiError::NotFound(format!("Hyperedge {id} não encontrado"))
                }
                HypergraphError::ValidationError(err) => {
                    ApiError::BadRequest(format!("Erro de validação: {err}"))
                }
                HypergraphError::InvalidUuid(err) => {
                    ApiError::BadRequest(format!("UUID inválido: {err}"))
                }
                other => ApiError::BadRequest(other.to_string()),
            }
        } else {
            ApiError::Internal(error.to_string())
        }
    }
}

impl From<anyhow::Error> for ApiError {
    fn from(value: anyhow::Error) -> Self {
        ApiError::Internal(value.to_string())
    }
}







