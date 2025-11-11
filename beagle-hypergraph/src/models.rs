//! Modelos de domínio que representam os nós (`Node`) e hiperarcos (`Hyperedge`)
//! manipulados pelo orquestrador Beagle.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fmt;
use uuid::Uuid;

/// Tipos semânticos possíveis para o conteúdo de um [`Node`].
///
/// ```
/// use beagle_hypergraph::models::ContentType;
///
/// assert_eq!(ContentType::Thought.to_string(), "Thought");
/// ```
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContentType {
    Thought,
    Memory,
    Context,
    Task,
    Note,
}

impl fmt::Display for ContentType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let label = match self {
            ContentType::Thought => "Thought",
            ContentType::Memory => "Memory",
            ContentType::Context => "Context",
            ContentType::Task => "Task",
            ContentType::Note => "Note",
        };
        f.write_str(label)
    }
}

/// Erros de validação estruturados que descrevem causas específicas de falha.
#[derive(Debug, thiserror::Error)]
pub enum ValidationError {
    /// Conteúdo não pode ser vazio.
    #[error("Content cannot be empty")]
    EmptyContent,

    /// Conteúdo excedeu o comprimento máximo permitido.
    #[error("Content exceeds maximum length of {max}")]
    ContentTooLong { max: usize },

    /// Metadados precisam ser representados como objeto JSON.
    #[error("Metadata must be a JSON object")]
    InvalidMetadata,

    /// Hiperarco precisa conectar pelo menos dois nós distintos.
    #[error("Hyperedge must connect at least 2 nodes")]
    InsufficientNodes,

    /// Versão inválida para controle de concorrência.
    #[error("Invalid version number: {0}")]
    InvalidVersion(i32),

    /// Etiqueta de hiperedge não pode ser vazia.
    #[error("Hyperedge label cannot be empty")]
    EmptyLabel,

    /// Lista de nós do hiperedge possui duplicatas.
    #[error("Hyperedge contains duplicate node id: {0}")]
    DuplicateNodeId(Uuid),

    /// Ordem temporal inconsistente entre criação e atualização.
    #[error("created_at cannot be later than updated_at")]
    TimestampOrder,

    /// Identificador do dispositivo não pode ser vazio.
    #[error("device_id cannot be empty")]
    EmptyDeviceId,
}

/// Representa um nó cognitivo do hipergrafo, contendo conteúdo semântico,
/// metadados e vetor de embedding opcional.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Node {
    /// Identificador global único do nó.
    pub id: Uuid,
    /// Conteúdo textual associado ao nó.
    pub content: String,
    /// Classificação semântica do conteúdo.
    pub content_type: ContentType,
    /// Metadados arbitrários em formato JSON (deve ser objeto).
    #[serde(default)]
    pub metadata: serde_json::Value,
    /// Vetor de embedding opcional usado para busca semântica.
    pub embedding: Option<Vec<f32>>,
    /// Timestamp de criação.
    pub created_at: DateTime<Utc>,
    /// Timestamp da última atualização.
    pub updated_at: DateTime<Utc>,
    /// Timestamp de deleção lógica, quando aplicável.
    pub deleted_at: Option<DateTime<Utc>>,
    /// Identificador do dispositivo responsável pela última mutação.
    pub device_id: String,
    /// Versão do nó para controle de concorrência (vector clock).
    pub version: i32,
}

impl Node {
    /// Comprimento máximo permitido para o conteúdo textual.
    pub const MAX_CONTENT_LENGTH: usize = 100_000;

    /// Cria um novo [`Node`] a partir de conteúdo, tipo e dispositivo.
    ///
    /// ```
    /// use beagle_hypergraph::models::{ContentType, Node};
    ///
    /// let node = Node::new("Insight", ContentType::Thought, "device-alpha")
    ///     .expect("valid node");
    /// assert_eq!(node.version, 0);
    /// ```
    pub fn new<S, D>(
        content: S,
        content_type: ContentType,
        device_id: D,
    ) -> Result<Self, ValidationError>
    where
        S: Into<String>,
        D: Into<String>,
    {
        NodeBuilder::default()
            .content(content)
            .content_type(content_type)
            .device_id(device_id)
            .build()
    }

    /// Obtém um builder para configurar e criar um [`Node`] validado.
    pub fn builder() -> NodeBuilder {
        NodeBuilder::default()
    }

    /// Atualiza o conteúdo textual após validar as invariantes.
    pub fn update_content(&mut self, content: String) -> Result<(), ValidationError> {
        if content.is_empty() {
            return Err(ValidationError::EmptyContent);
        }
        if content.len() > Self::MAX_CONTENT_LENGTH {
            return Err(ValidationError::ContentTooLong {
                max: Self::MAX_CONTENT_LENGTH,
            });
        }
        self.content = content;
        self.updated_at = Utc::now();
        self.validate()
    }

    /// Marca o nó como deletado logicamente.
    pub fn soft_delete(&mut self) {
        self.deleted_at = Some(Utc::now());
        self.updated_at = self.deleted_at.unwrap();
    }

    /// Retorna `true` se o nó estiver marcado como deletado.
    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }

    /// Valida as invariantes do nó.
    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.content.is_empty() {
            return Err(ValidationError::EmptyContent);
        }
        if self.content.len() > Self::MAX_CONTENT_LENGTH {
            return Err(ValidationError::ContentTooLong {
                max: Self::MAX_CONTENT_LENGTH,
            });
        }
        if let Some(deleted_at) = self.deleted_at {
            if deleted_at < self.created_at {
                return Err(ValidationError::TimestampOrder);
            }
        }
        if self.created_at > self.updated_at {
            return Err(ValidationError::TimestampOrder);
        }
        if self.version < 0 {
            return Err(ValidationError::InvalidVersion(self.version));
        }
        if self.device_id.trim().is_empty() {
            return Err(ValidationError::EmptyDeviceId);
        }
        if !(self.metadata.is_null() || self.metadata.is_object()) {
            return Err(ValidationError::InvalidMetadata);
        }
        Ok(())
    }
}

/// Builder para criação segura de [`Node`]s com validação final.
#[derive(Debug, Default)]
pub struct NodeBuilder {
    id: Option<Uuid>,
    content: Option<String>,
    content_type: Option<ContentType>,
    metadata: serde_json::Value,
    embedding: Option<Vec<f32>>,
    created_at: Option<DateTime<Utc>>,
    updated_at: Option<DateTime<Utc>>,
    deleted_at: Option<DateTime<Utc>>,
    device_id: Option<String>,
    version: Option<i32>,
}

impl NodeBuilder {
    /// Define um identificador específico para o nó.
    pub fn id(mut self, id: Uuid) -> Self {
        self.id = Some(id);
        self
    }

    /// Define o conteúdo textual.
    pub fn content<S: Into<String>>(mut self, content: S) -> Self {
        self.content = Some(content.into());
        self
    }

    /// Define o tipo semântico do conteúdo.
    pub fn content_type(mut self, content_type: ContentType) -> Self {
        self.content_type = Some(content_type);
        self
    }

    /// Define os metadados a partir de um objeto JSON.
    pub fn metadata(mut self, metadata: serde_json::Value) -> Self {
        self.metadata = metadata;
        self
    }

    /// Define metadados a partir de um mapa chave-valor.
    pub fn metadata_map(mut self, map: HashMap<String, serde_json::Value>) -> Self {
        self.metadata = serde_json::Value::Object(map.into_iter().collect());
        self
    }

    /// Define o vetor de embedding.
    pub fn embedding(mut self, embedding: Vec<f32>) -> Self {
        self.embedding = Some(embedding);
        self
    }

    /// Define o timestamp de criação.
    pub fn created_at(mut self, created_at: DateTime<Utc>) -> Self {
        self.created_at = Some(created_at);
        self
    }

    /// Define o timestamp de atualização.
    pub fn updated_at(mut self, updated_at: DateTime<Utc>) -> Self {
        self.updated_at = Some(updated_at);
        self
    }

    /// Define o timestamp de deleção lógica.
    pub fn deleted_at(mut self, deleted_at: DateTime<Utc>) -> Self {
        self.deleted_at = Some(deleted_at);
        self
    }

    /// Define o identificador do dispositivo.
    pub fn device_id<S: Into<String>>(mut self, device_id: S) -> Self {
        self.device_id = Some(device_id.into());
        self
    }

    /// Define explicitamente a versão.
    pub fn version(mut self, version: i32) -> Self {
        self.version = Some(version);
        self
    }

    /// Constrói o [`Node`] e garante que as invariantes sejam satisfeitas.
    pub fn build(mut self) -> Result<Node, ValidationError> {
        let now = Utc::now();
        let metadata = if self.metadata.is_null() {
            serde_json::Value::Object(serde_json::Map::new())
        } else {
            self.metadata
        };

        let node = Node {
            id: self.id.unwrap_or_else(Uuid::new_v4),
            content: self.content.unwrap_or_default(),
            content_type: self.content_type.unwrap_or(ContentType::Thought),
            metadata,
            embedding: self.embedding.take(),
            created_at: self.created_at.unwrap_or(now),
            updated_at: self.updated_at.unwrap_or(now),
            deleted_at: self.deleted_at,
            device_id: self.device_id.unwrap_or_default(),
            version: self.version.unwrap_or(0),
        };
        node.validate()?;
        Ok(node)
    }
}

/// Hiperarco conectando múltiplos nós, com suporte a direção e metadados.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hyperedge {
    /// Identificador global único do hiperedge.
    pub id: Uuid,
    /// Etiqueta semântica que descreve a relação.
    pub label: String,
    /// Conjunto de nós conectados por este hiperedge.
    pub node_ids: Vec<Uuid>,
    /// Metadados adicionais (deve ser objeto JSON).
    pub metadata: serde_json::Value,
    /// Timestamp de criação.
    pub created_at: DateTime<Utc>,
    /// Timestamp da última atualização.
    pub updated_at: DateTime<Utc>,
    /// Timestamp de deleção lógica.
    pub deleted_at: Option<DateTime<Utc>>,
    /// Dispositivo responsável pela última mutação.
    pub device_id: String,
    /// Versão utilizada em protocolos de sincronização.
    pub version: i32,
    /// Indica se a relação é dirigida.
    pub is_directed: bool,
}

impl Hyperedge {
    /// Cria um novo [`Hyperedge`] validado.
    ///
    /// ```
    /// use beagle_hypergraph::models::{Hyperedge, ContentType, Node};
    /// use uuid::Uuid;
    ///
    /// let nodes = vec![Uuid::new_v4(), Uuid::new_v4()];
    /// let edge = Hyperedge::new("relates", nodes.clone(), false, "device-alpha")
    ///     .expect("valid edge");
    /// assert_eq!(edge.node_ids.len(), 2);
    /// ```
    pub fn new<S: Into<String>>(
        label: S,
        node_ids: Vec<Uuid>,
        is_directed: bool,
        device_id: S,
    ) -> Result<Self, ValidationError> {
        let now = Utc::now();
        let hyperedge = Hyperedge {
            id: Uuid::new_v4(),
            label: label.into(),
            node_ids,
            metadata: serde_json::Value::Object(serde_json::Map::new()),
            created_at: now,
            updated_at: now,
            deleted_at: None,
            device_id: device_id.into(),
            version: 0,
            is_directed,
        };
        hyperedge.validate()?;
        Ok(hyperedge)
    }

    /// Adiciona um nó ao hiperedge se ainda não estiver presente.
    pub fn add_node(&mut self, node_id: Uuid) -> Result<bool, ValidationError> {
        if self.node_ids.contains(&node_id) {
            return Err(ValidationError::DuplicateNodeId(node_id));
        }
        self.node_ids.push(node_id);
        self.updated_at = Utc::now();
        self.validate()?;
        Ok(true)
    }

    /// Remove um nó, retornando `true` se o nó existia.
    pub fn remove_node(&mut self, node_id: Uuid) -> bool {
        if let Some(pos) = self.node_ids.iter().position(|id| *id == node_id) {
            self.node_ids.remove(pos);
            self.updated_at = Utc::now();
            true
        } else {
            false
        }
    }

    /// Verifica se o nó informado está conectado pelo hiperedge.
    pub fn contains_node(&self, node_id: Uuid) -> bool {
        self.node_ids.contains(&node_id)
    }

    /// Marca o hiperedge como deletado logicamente.
    pub fn soft_delete(&mut self) {
        let timestamp = Utc::now();
        self.deleted_at = Some(timestamp);
        self.updated_at = timestamp;
    }

    /// Retorna `true` se o hiperedge estiver deletado.
    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }

    /// Valida invariantes estruturais e semânticas.
    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.label.trim().is_empty() {
            return Err(ValidationError::EmptyLabel);
        }
        if self.node_ids.len() < 2 {
            return Err(ValidationError::InsufficientNodes);
        }
        let mut seen = HashSet::with_capacity(self.node_ids.len());
        for node_id in &self.node_ids {
            if !seen.insert(*node_id) {
                return Err(ValidationError::DuplicateNodeId(*node_id));
            }
        }
        if self.version < 0 {
            return Err(ValidationError::InvalidVersion(self.version));
        }
        if !(self.metadata.is_null() || self.metadata.is_object()) {
            return Err(ValidationError::InvalidMetadata);
        }
        if self.created_at > self.updated_at {
            return Err(ValidationError::TimestampOrder);
        }
        if self.device_id.trim().is_empty() {
            return Err(ValidationError::EmptyDeviceId);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_node_creation() {
        let node = Node::new("Insight", ContentType::Thought, "device-alpha").unwrap();
        assert_eq!(node.version, 0);
        assert_eq!(node.content, "Insight");
        assert_eq!(node.device_id, "device-alpha");
        assert!(node.metadata.is_object());
        assert!(node.validate().is_ok());
    }

    #[test]
    fn test_node_validation_empty_content() {
        let result = Node::new("", ContentType::Note, "device-alpha");
        assert!(matches!(result, Err(ValidationError::EmptyContent)));
    }

    #[test]
    fn test_node_validation_content_too_long() {
        let long_content = "a".repeat(Node::MAX_CONTENT_LENGTH + 1);
        let mut builder = Node::builder();
        builder = builder
            .content(long_content)
            .content_type(ContentType::Note)
            .device_id("device-alpha");
        let result = builder.build();
        assert!(matches!(
            result,
            Err(ValidationError::ContentTooLong { max }) if max == Node::MAX_CONTENT_LENGTH
        ));
    }

    #[test]
    fn test_node_soft_delete() {
        let mut node = Node::new("Persist", ContentType::Task, "device-alpha").unwrap();
        assert!(!node.is_deleted());
        node.soft_delete();
        assert!(node.is_deleted());
        assert!(node.deleted_at.is_some());
    }

    #[test]
    fn test_hyperedge_creation() {
        let nodes = vec![Uuid::new_v4(), Uuid::new_v4()];
        let edge = Hyperedge::new("relates", nodes.clone(), false, "device-alpha").unwrap();
        assert_eq!(edge.node_ids, nodes);
        assert!(!edge.is_directed);
        assert!(edge.metadata.is_object());
    }

    #[test]
    fn test_hyperedge_add_remove_nodes() {
        let mut edge = Hyperedge::new(
            "relates",
            vec![Uuid::new_v4(), Uuid::new_v4()],
            true,
            "device-alpha",
        )
        .unwrap();

        let new_node = Uuid::new_v4();
        assert!(edge.add_node(new_node).is_ok());
        assert!(edge.contains_node(new_node));

        assert!(edge.remove_node(new_node));
        assert!(!edge.contains_node(new_node));
    }

    #[test]
    fn test_hyperedge_validation_insufficient_nodes() {
        let result = Hyperedge::new("relates", vec![Uuid::new_v4()], false, "device-alpha");
        assert!(matches!(result, Err(ValidationError::InsufficientNodes)));
    }

    #[test]
    fn test_metadata_must_be_object() {
        let mut builder = Node::builder();
        builder = builder
            .content("Valid")
            .content_type(ContentType::Context)
            .device_id("device-alpha")
            .metadata(serde_json::json!(["invalid"]));
        let result = builder.build();
        assert!(matches!(result, Err(ValidationError::InvalidMetadata)));
    }

    #[test]
    fn test_hyperedge_duplicate_nodes_error() {
        let node_id = Uuid::new_v4();
        let result = Hyperedge::new("relates", vec![node_id, node_id], false, "device-alpha");
        assert!(matches!(result, Err(ValidationError::DuplicateNodeId(_))));
    }
}
