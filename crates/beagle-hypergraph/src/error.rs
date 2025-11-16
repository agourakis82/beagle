//! Definições abrangentes de erros para operações do hipergrafo Beagle.

use thiserror::Error;
use uuid::Uuid;

use crate::models::ValidationError;

/// Resultado padrão da crate para operações que podem falhar com [`HypergraphError`].
pub type Result<T> = std::result::Result<T, HypergraphError>;

/// Enumeração de erros que cobre falhas de domínio, infraestrutura e validação.
#[derive(Debug, Error)]
pub enum HypergraphError {
    /// Nó consultado não foi localizado.
    #[error("Node not found: {0}")]
    NodeNotFound(Uuid),

    /// Hiperedge consultado não foi localizado.
    #[error("Hyperedge not found: {0}")]
    HyperedgeNotFound(Uuid),

    /// Erro de banco de dados propagado pela camada SQLx.
    #[error("Database error: {0}")]
    DatabaseError(#[from] sqlx::Error),

    /// Erro de validação da camada de domínio.
    #[error("Validation error: {0}")]
    ValidationError(#[from] ValidationError),

    /// Falha na serialização ou desserialização JSON.
    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    /// UUID inválido fornecido pelo chamador.
    #[error("Invalid UUID: {0}")]
    InvalidUuid(#[from] uuid::Error),

    /// Erro relacionado ao pool de conexões.
    #[error("Connection pool error: {0}")]
    PoolError(String),

    /// Falha ocorrida durante transação.
    #[error("Transaction error: {0}")]
    TransactionError(String),

    /// Detecção de conflito de versão em atualização concorrente.
    #[error("Concurrent modification detected (version mismatch)")]
    VersionConflict { expected: i32, found: i32 },

    /// Operação negada por restrição de negócio.
    #[error("Operation not permitted: {reason}")]
    OperationNotPermitted { reason: String },

    /// Falha ao interagir com camadas de cache.
    #[error("Cache error: {0}")]
    CacheError(String),

    /// Erro interno genérico.
    #[error("Internal error: {0}")]
    InternalError(String),
}

impl HypergraphError {
    /// Indica se a falha é transitória, recomendando tentativa de repetição.
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            HypergraphError::PoolError(_)
                | HypergraphError::TransactionError(_)
                | HypergraphError::DatabaseError(_)
                | HypergraphError::CacheError(_)
        )
    }

    /// Indica se a falha é atribuída a erro do cliente (classe 4xx).
    pub fn is_client_error(&self) -> bool {
        matches!(
            self,
            HypergraphError::NodeNotFound(_)
                | HypergraphError::HyperedgeNotFound(_)
                | HypergraphError::ValidationError(_)
                | HypergraphError::InvalidUuid(_)
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let node_id = Uuid::nil();
        let err = HypergraphError::NodeNotFound(node_id);
        assert_eq!(format!("{err}"), format!("Node not found: {node_id}"));

        let validation_err = ValidationError::EmptyContent;
        let err = HypergraphError::from(validation_err);
        assert_eq!(
            format!("{err}"),
            "Validation error: Content cannot be empty"
        );
    }

    #[test]
    fn test_error_from_conversions() {
        let sqlx_error = sqlx::Error::PoolClosed;
        let err: HypergraphError = sqlx_error.into();
        assert!(matches!(err, HypergraphError::DatabaseError(_)));

        let json_error = serde_json::from_str::<serde_json::Value>("invalid json").unwrap_err();
        let err: HypergraphError = json_error.into();
        assert!(matches!(err, HypergraphError::SerializationError(_)));

        let err: HypergraphError = Uuid::parse_str("invalid-uuid").unwrap_err().into();
        assert!(matches!(err, HypergraphError::InvalidUuid(_)));
    }

    #[test]
    fn test_is_transient() {
        let transient_errors = [
            HypergraphError::PoolError("timeout".into()),
            HypergraphError::TransactionError("deadlock".into()),
            HypergraphError::DatabaseError(sqlx::Error::PoolTimedOut),
        ];

        for err in transient_errors {
            assert!(err.is_transient());
        }

        let non_transient = HypergraphError::NodeNotFound(Uuid::nil());
        assert!(!non_transient.is_transient());
    }

    #[test]
    fn test_is_client_error() {
        let client_errors = [
            HypergraphError::NodeNotFound(Uuid::nil()),
            HypergraphError::HyperedgeNotFound(Uuid::nil()),
            HypergraphError::ValidationError(ValidationError::EmptyContent),
            HypergraphError::from(Uuid::parse_str("not-a-uuid").unwrap_err()),
        ];

        for err in client_errors {
            assert!(err.is_client_error());
        }

        let server_error = HypergraphError::InternalError("boom".into());
        assert!(!server_error.is_client_error());
    }
}
