// WebSocket authentication and session management
//
// References:
// - Jones, M., et al. (2015). JSON Web Token (JWT). RFC 7519.
// - OWASP Authentication Cheat Sheet

use crate::{Result, WebSocketError};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use dashmap::DashMap;
use uuid::Uuid;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::{rand_core::OsRng, SaltString};
use tracing::{debug, info, warn, instrument};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    pub sub: String,  // Subject (user ID)
    pub exp: u64,     // Expiration time
    pub iat: u64,     // Issued at
    pub jti: String,  // JWT ID
    pub roles: Vec<String>,
    pub permissions: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct Session {
    pub id: String,
    pub user_id: String,
    pub created_at: u64,
    pub expires_at: u64,
    pub roles: Vec<String>,
    pub permissions: Vec<String>,
    pub metadata: HashMap<String, String>,
}

pub struct AuthProvider {
    jwt_secret: String,
    sessions: Arc<DashMap<String, Session>>,
    token_expiry: Duration,
}

impl AuthProvider {
    pub fn new(jwt_secret: String, token_expiry: Duration) -> Self {
        Self {
            jwt_secret,
            sessions: Arc::new(DashMap::new()),
            token_expiry,
        }
    }

    #[instrument(skip(self, password))]
    pub fn hash_password(&self, password: &str) -> Result<String> {
        let salt = SaltString::generate(&mut OsRng);
        let argon2 = Argon2::default();

        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)
            .map_err(|e| WebSocketError::AuthenticationError(e.to_string()))?;

        Ok(password_hash.to_string())
    }

    #[instrument(skip(self, password, hash))]
    pub fn verify_password(&self, password: &str, hash: &str) -> Result<bool> {
        let parsed_hash = PasswordHash::new(hash)
            .map_err(|e| WebSocketError::AuthenticationError(e.to_string()))?;

        let argon2 = Argon2::default();
        Ok(argon2.verify_password(password.as_bytes(), &parsed_hash).is_ok())
    }

    #[instrument(skip(self))]
    pub fn generate_token(&self, user_id: &str, roles: Vec<String>, permissions: Vec<String>) -> Result<String> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let claims = Claims {
            sub: user_id.to_string(),
            exp: now + self.token_expiry.as_secs(),
            iat: now,
            jti: Uuid::new_v4().to_string(),
            roles,
            permissions,
        };

        let token = encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.jwt_secret.as_bytes()),
        ).map_err(|e| WebSocketError::AuthenticationError(e.to_string()))?;

        Ok(token)
    }

    #[instrument(skip(self, token))]
    pub fn validate_token(&self, token: &str) -> Result<Claims> {
        let token_data = decode::<Claims>(
            token,
            &DecodingKey::from_secret(self.jwt_secret.as_bytes()),
            &Validation::default(),
        ).map_err(|e| WebSocketError::AuthenticationError(e.to_string()))?;

        Ok(token_data.claims)
    }

    #[instrument(skip(self))]
    pub fn create_session(&self, user_id: &str, roles: Vec<String>, permissions: Vec<String>) -> String {
        let session_id = Uuid::new_v4().to_string();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let session = Session {
            id: session_id.clone(),
            user_id: user_id.to_string(),
            created_at: now,
            expires_at: now + self.token_expiry.as_secs(),
            roles,
            permissions,
            metadata: HashMap::new(),
        };

        self.sessions.insert(session_id.clone(), session);
        session_id
    }

    #[instrument(skip(self))]
    pub fn get_session(&self, session_id: &str) -> Option<Session> {
        self.sessions.get(session_id).map(|s| s.clone())
    }

    #[instrument(skip(self))]
    pub fn invalidate_session(&self, session_id: &str) {
        self.sessions.remove(session_id);
    }

    #[instrument(skip(self))]
    pub fn cleanup_expired_sessions(&self) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        self.sessions.retain(|_, session| session.expires_at > now);
    }

    pub fn has_permission(&self, claims: &Claims, permission: &str) -> bool {
        claims.permissions.contains(&permission.to_string())
    }

    pub fn has_role(&self, claims: &Claims, role: &str) -> bool {
        claims.roles.contains(&role.to_string())
    }
}

pub struct TokenValidator {
    provider: Arc<AuthProvider>,
}

impl TokenValidator {
    pub fn new(provider: Arc<AuthProvider>) -> Self {
        Self { provider }
    }

    pub async fn validate(&self, token: &str) -> Result<Claims> {
        self.provider.validate_token(token)
    }
}

pub struct SessionManager {
    provider: Arc<AuthProvider>,
}

impl SessionManager {
    pub fn new(provider: Arc<AuthProvider>) -> Self {
        // Start cleanup task
        let provider_clone = provider.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(300));
            loop {
                interval.tick().await;
                provider_clone.cleanup_expired_sessions();
            }
        });

        Self { provider }
    }

    pub async fn create(&self, user_id: &str, roles: Vec<String>, permissions: Vec<String>) -> String {
        self.provider.create_session(user_id, roles, permissions)
    }

    pub async fn get(&self, session_id: &str) -> Option<Session> {
        self.provider.get_session(session_id)
    }

    pub async fn invalidate(&self, session_id: &str) {
        self.provider.invalidate_session(session_id);
    }
}

use std::collections::HashMap;
