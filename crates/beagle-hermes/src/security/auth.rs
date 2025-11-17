//! JWT Authentication

use anyhow::Result;
use jsonwebtoken::{encode, decode, Header, Validation, EncodingKey, DecodingKey};
use serde::{Deserialize, Serialize};
use chrono::{Utc, Duration};
use tracing::{info, debug, warn};

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,  // User ID
    pub exp: i64,     // Expiration time
    pub iat: i64,     // Issued at
}

pub struct AuthService {
    encoding_key: EncodingKey,
    decoding_key: DecodingKey,
    secret: String,
}

impl AuthService {
    pub fn new(secret: &str) -> Self {
        Self {
            encoding_key: EncodingKey::from_secret(secret.as_bytes()),
            decoding_key: DecodingKey::from_secret(secret.as_bytes()),
            secret: secret.to_string(),
        }
    }

    /// Generate JWT token
    pub fn generate_token(&self, user_id: &str) -> Result<String> {
        let now = Utc::now();
        let expiration = now + Duration::hours(24);

        let claims = Claims {
            sub: user_id.to_string(),
            exp: expiration.timestamp(),
            iat: now.timestamp(),
        };

        let token = encode(&Header::default(), &claims, &self.encoding_key)?;

        debug!("Generated JWT token for user: {}", user_id);
        Ok(token)
    }

    /// Validate JWT token
    pub fn validate_token(&self, token: &str) -> Result<Claims> {
        let token_data = decode::<Claims>(
            token,
            &self.decoding_key,
            &Validation::default(),
        )?;

        // Check expiration
        let now = Utc::now().timestamp();
        if token_data.claims.exp < now {
            anyhow::bail!("Token expired");
        }

        debug!("Validated JWT token for user: {}", token_data.claims.sub);
        Ok(token_data.claims)
    }

    /// Extract token from Authorization header
    pub fn extract_token(auth_header: &str) -> Option<&str> {
        if auth_header.starts_with("Bearer ") {
            Some(&auth_header[7..])
        } else {
            None
        }
    }
}

/// Axum middleware for JWT authentication
pub async fn auth_middleware(
    req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> Result<axum::response::Response, axum::http::StatusCode> {
    // Extract Authorization header
    let auth_header = req
        .headers()
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .ok_or(axum::http::StatusCode::UNAUTHORIZED)?;

    // Extract token
    let token = AuthService::extract_token(auth_header)
        .ok_or(axum::http::StatusCode::UNAUTHORIZED)?;

    // TODO: Get AuthService from request extensions
    // For now, this is a placeholder
    // let auth_service = req.extensions().get::<AuthService>()
    //     .ok_or(axum::http::StatusCode::INTERNAL_SERVER_ERROR)?;

    // Validate token
    // let claims = auth_service.validate_token(token)
    //     .map_err(|_| axum::http::StatusCode::UNAUTHORIZED)?;

    // Add claims to request extensions for downstream handlers
    // req.extensions_mut().insert(claims);

    Ok(next.run(req).await)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_generation_and_validation() {
        let auth_service = AuthService::new("test_secret_key_min_32_chars_long");

        let user_id = "user123";
        let token = auth_service.generate_token(user_id).unwrap();

        let claims = auth_service.validate_token(&token).unwrap();

        assert_eq!(claims.sub, user_id);
    }

    #[test]
    fn test_token_extraction() {
        let header = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
        let token = AuthService::extract_token(header);

        assert_eq!(token, Some("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"));
    }
}

