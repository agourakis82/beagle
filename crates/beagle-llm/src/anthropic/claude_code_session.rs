//! Módulo para leitura de sessões OAuth do Claude Code.
//!
//! Permite que BEAGLE reutilize a autenticação do Claude Code extension
//! ao invés de gerenciar API keys separadas.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::{debug, info, warn};

/// Estrutura da sessão OAuth armazenada pelo Claude Code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaudeCodeSession {
    #[serde(rename = "claudeAiOauth")]
    pub claude_ai_oauth: OAuthCredentials,
}

/// Credenciais OAuth do Claude Code.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OAuthCredentials {
    #[serde(rename = "accessToken")]
    pub access_token: String,

    #[serde(rename = "refreshToken")]
    pub refresh_token: String,

    #[serde(rename = "expiresAt")]
    pub expires_at: u64,

    pub scopes: Vec<String>,

    #[serde(rename = "subscriptionType")]
    pub subscription_type: String,

    #[serde(rename = "rateLimitTier")]
    pub rate_limit_tier: String,
}

impl OAuthCredentials {
    /// Verifica se o token de acesso está expirado.
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        now >= self.expires_at
    }

    /// Verifica se tem permissão de inferência (necessário para chamadas de API).
    pub fn has_inference_scope(&self) -> bool {
        self.scopes.contains(&"user:inference".to_string())
    }

    /// Retorna true se o usuário tem MAX subscription.
    pub fn is_max_subscription(&self) -> bool {
        self.subscription_type.to_lowercase() == "max"
    }
}

/// Leitor de sessões do Claude Code.
pub struct ClaudeCodeSessionReader {
    credentials_path: PathBuf,
}

impl ClaudeCodeSessionReader {
    /// Cria um novo leitor usando o caminho padrão do Claude Code.
    pub fn new() -> Self {
        Self {
            credentials_path: Self::default_credentials_path(),
        }
    }

    /// Cria um leitor com caminho customizado (útil para testes).
    #[allow(dead_code)]
    pub fn with_path(path: PathBuf) -> Self {
        Self {
            credentials_path: path,
        }
    }

    /// Retorna o caminho padrão das credenciais do Claude Code.
    fn default_credentials_path() -> PathBuf {
        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .unwrap_or_else(|_| ".".to_string());

        PathBuf::from(home)
            .join(".claude")
            .join(".credentials.json")
    }

    /// Lê a sessão do Claude Code.
    pub fn read_session(&self) -> Result<ClaudeCodeSession> {
        debug!(
            path = %self.credentials_path.display(),
            "Lendo sessão do Claude Code"
        );

        if !self.credentials_path.exists() {
            anyhow::bail!(
                "Arquivo de credenciais do Claude Code não encontrado em: {}\n\
                 Certifique-se de que o Claude Code extension está instalado e autenticado.",
                self.credentials_path.display()
            );
        }

        let content = std::fs::read_to_string(&self.credentials_path)
            .context("Falha ao ler arquivo de credenciais")?;

        let session: ClaudeCodeSession = serde_json::from_str(&content)
            .context("Falha ao parsear credenciais do Claude Code")?;

        // Validações
        if session.claude_ai_oauth.is_expired() {
            warn!("Token de acesso do Claude Code está expirado");
            // Nota: ainda retornamos a sessão pois o refresh token pode ser válido
        }

        if !session.claude_ai_oauth.has_inference_scope() {
            anyhow::bail!(
                "Sessão do Claude Code não tem permissão 'user:inference'.\n\
                 Scopes disponíveis: {:?}",
                session.claude_ai_oauth.scopes
            );
        }

        info!(
            subscription = %session.claude_ai_oauth.subscription_type,
            rate_limit = %session.claude_ai_oauth.rate_limit_tier,
            expired = session.claude_ai_oauth.is_expired(),
            "Sessão do Claude Code carregada"
        );

        Ok(session)
    }

    /// Tenta ler a sessão, retornando None se não existir ou estiver inválida.
    #[allow(dead_code)]
    pub fn try_read_session(&self) -> Option<ClaudeCodeSession> {
        self.read_session().ok()
    }
}

impl Default for ClaudeCodeSessionReader {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oauth_credentials_expiration() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        let expired = OAuthCredentials {
            access_token: "test".to_string(),
            refresh_token: "test".to_string(),
            expires_at: now - 1000, // 1 segundo atrás
            scopes: vec!["user:inference".to_string()],
            subscription_type: "max".to_string(),
            rate_limit_tier: "default_claude_max_5x".to_string(),
        };

        assert!(expired.is_expired());

        let valid = OAuthCredentials {
            expires_at: now + 3600000, // 1 hora no futuro
            ..expired.clone()
        };

        assert!(!valid.is_expired());
    }

    #[test]
    fn test_inference_scope_check() {
        let with_scope = OAuthCredentials {
            access_token: "test".to_string(),
            refresh_token: "test".to_string(),
            expires_at: 0,
            scopes: vec!["user:inference".to_string(), "user:profile".to_string()],
            subscription_type: "max".to_string(),
            rate_limit_tier: "default_claude_max_5x".to_string(),
        };

        assert!(with_scope.has_inference_scope());

        let without_scope = OAuthCredentials {
            scopes: vec!["user:profile".to_string()],
            ..with_scope.clone()
        };

        assert!(!without_scope.has_inference_scope());
    }

    #[test]
    fn test_max_subscription_detection() {
        let max_user = OAuthCredentials {
            access_token: "test".to_string(),
            refresh_token: "test".to_string(),
            expires_at: 0,
            scopes: vec!["user:inference".to_string()],
            subscription_type: "max".to_string(),
            rate_limit_tier: "default_claude_max_5x".to_string(),
        };

        assert!(max_user.is_max_subscription());

        let standard_user = OAuthCredentials {
            subscription_type: "standard".to_string(),
            ..max_user.clone()
        };

        assert!(!standard_user.is_max_subscription());
    }
}
