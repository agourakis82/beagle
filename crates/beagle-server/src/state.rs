//! Estado compartilhado da aplicação Axum.

use std::sync::Arc;

use anyhow::Context;
use beagle_hypergraph::storage::CachedPostgresStorage;

use crate::config::Config;

/// Estado imutável compartilhado entre os handlers.
#[derive(Clone)]
pub struct AppState {
    pub storage: Arc<CachedPostgresStorage>,
    jwt_secret: Arc<String>,
    jwt_expiration_hours: i64,
    admin_username: Arc<String>,
    admin_password_hash: Arc<String>,
}

impl AppState {
    /// Inicializa estado a partir da configuração carregada.
    pub async fn new(config: &Config) -> anyhow::Result<Self> {
        let storage = CachedPostgresStorage::new(config.database_url(), config.redis_url())
            .await
            .with_context(|| "Falha ao inicializar camada de armazenamento (Postgres + Redis)")?;

        Ok(Self {
            storage: Arc::new(storage),
            jwt_secret: Arc::new(config.jwt_secret().to_owned()),
            jwt_expiration_hours: config.jwt_expiration_hours(),
            admin_username: Arc::new(config.admin_username().to_owned()),
            admin_password_hash: Arc::new(config.admin_password_hash().to_owned()),
        })
    }

    /// Segredo usado para assinar tokens JWT.
    pub fn jwt_secret(&self) -> &str {
        &self.jwt_secret
    }

    /// Janelas de expiração em horas para tokens JWT.
    pub fn jwt_expiration_hours(&self) -> i64 {
        self.jwt_expiration_hours
    }

    /// Usuário administrador canônico.
    pub fn admin_username(&self) -> &str {
        &self.admin_username
    }

    /// Hash Argon2 da senha administrativa.
    pub fn admin_password_hash(&self) -> &str {
        &self.admin_password_hash
    }
}







