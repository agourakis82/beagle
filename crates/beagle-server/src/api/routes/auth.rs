//! Endpoints de autenticação JWT.

use argon2::{password_hash::PasswordHash, Argon2, PasswordVerifier};
use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    auth::Claims,
    error::{ApiError, ApiResult},
    state::AppState,
};

/// Payload para autenticação via senha.
#[derive(Debug, Deserialize, ToSchema)]
pub struct LoginRequest {
    #[schema(example = "admin")]
    pub username: String,
    #[schema(example = "test")]
    pub password: String,
    #[serde(default)]
    #[schema(example = "device-alpha")]
    pub device_id: Option<String>,
}

/// Resposta contendo token JWT.
#[derive(Debug, Serialize, ToSchema)]
pub struct LoginResponse {
    pub token: String,
    pub token_type: String,
    pub expires_in: i64,
}

/// Informações do usuário autenticado.
#[derive(Debug, Serialize, ToSchema)]
pub struct MeResponse {
    pub subject: String,
    pub device_id: String,
    pub issued_at: usize,
    pub expires_at: usize,
}

/// Roteador dos endpoints de autenticação.
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/auth/login", post(login))
        .route("/api/v1/auth/me", get(me))
}

/// Realiza autenticação e gera JWT.
#[utoipa::path(
    post,
    path = "/api/v1/auth/login",
    request_body = LoginRequest,
    responses(
        (status = 200, description = "Autenticado com sucesso", body = LoginResponse),
        (status = 401, description = "Credenciais inválidas"),
        (status = 400, description = "Requisição inválida"),
    )
)]
pub async fn login(
    State(state): State<AppState>,
    Json(payload): Json<LoginRequest>,
) -> ApiResult<Json<LoginResponse>> {
    if payload.username.trim().is_empty() || payload.password.is_empty() {
        return Err(ApiError::BadRequest(
            "Usuário e senha são obrigatórios".into(),
        ));
    }

    if payload.username != state.admin_username() {
        return Err(ApiError::Unauthorized("Credenciais inválidas".into()));
    }

    let parsed_hash = PasswordHash::new(state.admin_password_hash())
        .map_err(|_| ApiError::Internal("Hash de senha inválido".into()))?;

    Argon2::default()
        .verify_password(payload.password.as_bytes(), &parsed_hash)
        .map_err(|_| ApiError::Unauthorized("Credenciais inválidas".into()))?;

    let device_id = payload
        .device_id
        .unwrap_or_else(|| payload.username.clone());

    let claims = Claims::new(
        payload.username.clone(),
        device_id.clone(),
        state.jwt_expiration_hours(),
    );

    let token = claims.encode(state.jwt_secret())?;

    let response = LoginResponse {
        token,
        token_type: "Bearer".into(),
        expires_in: state.jwt_expiration_hours() * 3600,
    };

    Ok(Json(response))
}

/// Retorna claims do usuário autenticado.
#[utoipa::path(
    get,
    path = "/api/v1/auth/me",
    responses(
        (status = 200, description = "Informações do token", body = MeResponse),
        (status = 401, description = "Token inválido ou expirado"),
    ),
    security(
        ("bearer_auth" = [])
    )
)]
pub async fn me(claims: Claims) -> Json<MeResponse> {
    Json(MeResponse {
        subject: claims.sub,
        device_id: claims.device_id,
        issued_at: claims.iat,
        expires_at: claims.exp,
    })
}







