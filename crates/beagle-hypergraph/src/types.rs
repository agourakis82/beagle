//! Tipos de domínio especializados que encapsulam integrações externas (pgvector, sqlx).
#[cfg(feature = "database")]
use std::ops::Deref;

#[cfg(feature = "database")]
use pgvector::Vector;
use serde::{Deserialize, Serialize};
#[cfg(feature = "database")]
use sqlx::encode::IsNull;
#[cfg(feature = "database")]
use sqlx::postgres::{PgArgumentBuffer, PgTypeInfo, PgValueRef};
#[cfg(feature = "database")]
use sqlx::{error::BoxDynError, Decode, Postgres, Type};

/// Número padrão de dimensões para embeddings (compatível com modelos OpenAI `text-embedding-ada-002`).
pub const EMBEDDING_DIMENSION: usize = 1536;

/// Wrapper newtype para o tipo `vector` do PostgreSQL (pgvector).
///
/// Garante validação de dimensionalidade e integração transparente com `sqlx`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Embedding(pub Vec<f32>);

impl Embedding {
    /// Cria um embedding validando dimensionalidade.
    pub fn new(values: Vec<f32>) -> Result<Self, String> {
        if values.len() != EMBEDDING_DIMENSION {
            return Err(format!(
                "Invalid embedding dimension: {} (expected {EMBEDDING_DIMENSION})",
                values.len()
            ));
        }
        Ok(Self(values))
    }

    /// Cria embedding sem validação (uso interno/controlado).
    pub fn new_unchecked(values: Vec<f32>) -> Self {
        Self(values)
    }

    /// Retorna a dimensionalidade.
    pub fn dimension(&self) -> usize {
        self.0.len()
    }

    /// Converte para `pgvector::Vector` (útil em operações de banco).
    #[cfg(feature = "database")]
    pub fn to_pgvector(&self) -> Vector {
        Vector::from(self.0.clone())
    }

    /// Retorna o vetor de embedding (offline mode).
    #[cfg(not(feature = "database"))]
    pub fn to_vec(&self) -> Vec<f32> {
        self.0.clone()
    }

    /// Cria embedding a partir de `pgvector::Vector`.
    #[cfg(feature = "database")]
    pub fn from_pgvector(vector: Vector) -> Self {
        Self(vector.to_vec())
    }

    /// Cria embedding a partir de vetor (offline mode).
    #[cfg(not(feature = "database"))]
    pub fn from_vec(vec: Vec<f32>) -> Self {
        Self(vec)
    }
}

#[cfg(feature = "database")]
impl Deref for Embedding {
    type Target = Vec<f32>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

#[cfg(not(feature = "database"))]
impl std::ops::Deref for Embedding {
    type Target = Vec<f32>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl From<Vec<f32>> for Embedding {
    fn from(values: Vec<f32>) -> Self {
        Self(values)
    }
}

impl From<Embedding> for Vec<f32> {
    fn from(embedding: Embedding) -> Self {
        embedding.0
    }
}

#[cfg(feature = "database")]
impl From<Vector> for Embedding {
    fn from(vector: Vector) -> Self {
        Self::from_pgvector(vector)
    }
}

#[cfg(feature = "database")]
impl From<Embedding> for Vector {
    fn from(embedding: Embedding) -> Self {
        embedding.to_pgvector()
    }
}

#[cfg(feature = "database")]
impl From<&Embedding> for Vector {
    fn from(embedding: &Embedding) -> Self {
        embedding.to_pgvector()
    }
}

#[cfg(feature = "database")]
impl Type<Postgres> for Embedding {
    fn type_info() -> PgTypeInfo {
        Vector::type_info()
    }
}

#[cfg(feature = "database")]
impl<'q> sqlx::Encode<'q, Postgres> for Embedding {
    fn encode_by_ref(
        &self,
        buf: &mut PgArgumentBuffer,
    ) -> std::result::Result<IsNull, BoxDynError> {
        let vector = self.to_pgvector();
        vector.encode_by_ref(buf)
    }

    fn size_hint(&self) -> usize {
        self.0.len() * std::mem::size_of::<f32>()
    }
}

#[cfg(feature = "database")]
impl<'r> Decode<'r, Postgres> for Embedding {
    fn decode(value: PgValueRef<'r>) -> Result<Self, sqlx::error::BoxDynError> {
        let vector = Vector::decode(value)?;
        Ok(Self::from_pgvector(vector))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_embedding_creation() {
        let values = vec![0.1; EMBEDDING_DIMENSION];
        let embedding = Embedding::new(values.clone()).unwrap();
        assert_eq!(embedding.dimension(), EMBEDDING_DIMENSION);
        assert_eq!(*embedding, values);
    }

    #[test]
    fn test_embedding_validation() {
        let wrong_dimension = vec![0.1; 512];
        let result = Embedding::new(wrong_dimension);
        assert!(result.is_err());
    }

    #[test]
    fn test_embedding_conversion() {
        let values = vec![0.1; EMBEDDING_DIMENSION];
        let embedding = Embedding::from(values.clone());
        let back: Vec<f32> = embedding.into();
        assert_eq!(back, values);
    }
}
