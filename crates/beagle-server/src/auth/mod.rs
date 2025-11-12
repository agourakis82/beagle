//! Autenticação baseada em JWT com extração via Axum.

use axum::{async_trait, extract::FromRequestParts, http::request::Parts, RequestPartsExt};
use axum_extra::{
    headers::{authorization::Bearer, Authorization},
    typed_header::TypedHeader,
};
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::{error::ApiError, state::AppState};

/// Claims padrão utilizados nos JWTs da API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,
    pub device_id: String,
    pub exp: usize,
    pub iat: usize,
}

impl Claims {
    /// Cria novo conjunto de claims com expiração futura.
    pub fn new(user_id: String, device_id: String, expiration_hours: i64) -> Self {
        let now = Utc::now();
        let expires_at = now + Duration::hours(expiration_hours);
        Self {
            sub: user_id,
            device_id,
            exp: expires_at.timestamp() as usize,
            iat: now.timestamp() as usize,
        }
    }

    /// Serializa claims em JWT assinado.
    pub fn encode(&self, secret: &str) -> Result<String, ApiError> {
        encode(
            &Header::default(),
            self,
            &EncodingKey::from_secret(secret.as_bytes()),
        )
        .map_err(|err| ApiError::Internal(format!("Falha ao assinar JWT: {err}")))
    }

    /// Desserializa claims a partir de token JWT.
    pub fn decode(token: &str, secret: &str) -> Result<Self, ApiError> {
        decode::<Claims>(
            token,
            &DecodingKey::from_secret(secret.as_bytes()),
            &Validation::default(),
        )
        .map(|data| data.claims)
        .map_err(|err| ApiError::Unauthorized(format!("Token inválido: {err}")))
    }
}

/// Extractor de JWT para handlers protegidos.
#[async_trait]
impl FromRequestParts<AppState> for Claims {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let TypedHeader(Authorization(bearer)) = parts
            .extract::<TypedHeader<Authorization<Bearer>>>()
            .await
            .map_err(|_| ApiError::Unauthorized("Cabeçalho Authorization ausente".into()))?;

        Claims::decode(bearer.token(), state.jwt_secret())
    }
}







