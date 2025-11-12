//! Modelos de domínio que representam os nós (`Node`) e hiperarcos (`Hyperedge`)
//! manipulados pelo orquestrador Beagle.

use crate::{
    serde_helpers::{
        deserialize_datetime, deserialize_optional_datetime, deserialize_uuid_vec,
        serialize_datetime, serialize_optional_datetime, serialize_optional_embedding,
        serialize_uuid_vec,
    },
    types::{Embedding, EMBEDDING_DIMENSION},
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashSet;
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

    /// Inserção criaria duplicata explícita em hiperedge.
    #[error("Duplicate node in hyperedge")]
    DuplicateNode,

    /// Ordem temporal inconsistente entre criação e atualização.
    #[error("created_at cannot be later than updated_at")]
    TimestampOrder,

    /// Identificador do dispositivo não pode ser vazio.
    #[error("device_id cannot be empty")]
    EmptyDeviceId,

    /// Campo obrigatório ausente.
    #[error("Missing required field: {0}")]
    MissingField(String),

    /// Dimensionalidade inválida do vetor de embedding.
    #[error("Invalid embedding dimension: expected {expected}, got {got}")]
    InvalidEmbeddingDimension { expected: usize, got: usize },
}

/// Representa um nó cognitivo do hipergrafo, contendo conteúdo semântico,
/// metadados e vetor de embedding opcional.
///
/// # JSON Serialization
///
/// A serialização via Serde aplica otimizações de tamanho:
///
/// - Renomeia chaves (`content_type` → `type`, `device_id` → `device`)
/// - Omite metadados vazios e versões em zero
/// - Usa UUIDs compactos para hiperarcos relacionados
/// - Serializa `DateTime` em ISO 8601 e embeddings apenas quando presentes
///
/// Exemplo de payload mínimo:
///
/// ```json
/// {
///   "id": "a1b2c3d4e5f67890a1b2c3d4e5f67890",
///   "content": "My thought",
///   "type": "Thought",
///   "created_at": "2025-11-10T19:30:00Z",
///   "updated_at": "2025-11-10T19:30:00Z",
///   "device": "macbook-m3"
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Node {
    /// Identificador global único do nó.
    pub id: Uuid,
    /// Conteúdo textual associado ao nó.
    pub content: String,
    /// Classificação semântica do conteúdo.
    #[serde(rename = "type")]
    pub content_type: ContentType,
    /// Metadados arbitrários em formato JSON (deve ser objeto).
    #[serde(
        default = "default_metadata",
        skip_serializing_if = "is_default_metadata"
    )]
    pub metadata: serde_json::Value,
    /// Vetor de embedding opcional usado para busca semântica.
    #[serde(
        skip_serializing_if = "Option::is_none",
        serialize_with = "serialize_optional_embedding",
        default
    )]
    pub embedding: Option<Embedding>,
    /// Timestamp de criação.
    #[serde(
        serialize_with = "serialize_datetime",
        deserialize_with = "deserialize_datetime"
    )]
    pub created_at: DateTime<Utc>,
    /// Timestamp da última atualização.
    #[serde(
        serialize_with = "serialize_datetime",
        deserialize_with = "deserialize_datetime"
    )]
    pub updated_at: DateTime<Utc>,
    /// Timestamp de deleção lógica, quando aplicável.
    #[serde(
        skip_serializing_if = "Option::is_none",
        serialize_with = "serialize_optional_datetime",
        deserialize_with = "deserialize_optional_datetime",
        default
    )]
    pub deleted_at: Option<DateTime<Utc>>,
    /// Identificador do dispositivo responsável pela última mutação.
    #[serde(rename = "device")]
    pub device_id: String,
    /// Versão do nó para controle de concorrência (vector clock).
    #[serde(default, skip_serializing_if = "is_zero_i32")]
    pub version: i32,
}

fn default_metadata() -> serde_json::Value {
    json!({})
}

fn is_default_metadata(value: &serde_json::Value) -> bool {
    if let Some(obj) = value.as_object() {
        obj.is_empty()
    } else {
        value.is_null()
    }
}

fn is_zero_i32(value: &i32) -> bool {
    *value == 0
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
        NodeBuilder::new()
            .content(content)
            .content_type(content_type)
            .device_id(device_id)
            .build()
    }

    /// Obtém um builder para configurar e criar um [`Node`] validado.
    pub fn builder() -> NodeBuilder {
        NodeBuilder::new()
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

/// Builder para construção de instâncias de [`Node`] com validação.
///
/// O padrão builder garante o fornecimento de campos obrigatórios
/// e valida as restrições antes de criar um `Node`.
///
/// # Exemplos
///
/// ```
/// use beagle_hypergraph::models::{Node, ContentType};
/// use serde_json::json;
///
/// let node = Node::builder()
///     .content("Important insight about hypergraphs")
///     .content_type(ContentType::Thought)
///     .metadata(json!({"priority": 5}))
///     .device_id("workstation-001")
///     .build()?;
///
/// assert_eq!(node.content, "Important insight about hypergraphs");
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
///
/// # Campos obrigatórios
///
/// - `content`: string não vazia (1-100_000 caracteres)
/// - `content_type`: tipo semântico (Thought, Memory, Context, etc.)
/// - `device_id`: identificador do dispositivo criador do nó
///
/// # Campos opcionais
///
/// - `metadata`: objeto JSON (padrão `{}`)
/// - `embedding`: vetor de embedding (deve possuir 1536 dimensões se fornecido)
///
/// # Erros
///
/// Retorna [`ValidationError`] se:
/// - Campos obrigatórios estiverem ausentes
/// - Conteúdo for vazio ou exceder 100_000 caracteres
/// - Metadados não forem um objeto JSON
/// - Embedding não possuir dimensão 1536
#[derive(Debug, Default)]
pub struct NodeBuilder {
    id: Option<Uuid>,
    content: Option<String>,
    content_type: Option<ContentType>,
    metadata: Option<serde_json::Value>,
    embedding: Option<Embedding>,
    device_id: Option<String>,
}

impl NodeBuilder {
    /// Cria um novo builder com estado vazio.
    pub fn new() -> Self {
        Self::default()
    }

    /// Força o identificador do nó.
    pub fn id(mut self, id: Uuid) -> Self {
        self.id = Some(id);
        self
    }

    /// Define o conteúdo textual.
    pub fn content(mut self, content: impl Into<String>) -> Self {
        self.content = Some(content.into());
        self
    }

    /// Define o tipo semântico do conteúdo.
    pub fn content_type(mut self, content_type: ContentType) -> Self {
        self.content_type = Some(content_type);
        self
    }

    /// Define o objeto de metadados.
    pub fn metadata(mut self, metadata: serde_json::Value) -> Self {
        self.metadata = Some(metadata);
        self
    }

    /// Define o vetor de embedding semântico.
    pub fn embedding(mut self, embedding: Vec<f32>) -> Self {
        self.embedding = Some(Embedding::from(embedding));
        self
    }

    /// Define o identificador do dispositivo que produz o nó.
    pub fn device_id(mut self, device_id: impl Into<String>) -> Self {
        self.device_id = Some(device_id.into());
        self
    }

    /// Constrói o [`Node`] validando pré-condições invariantes.
    pub fn build(self) -> Result<Node, ValidationError> {
        let content = self.content.ok_or(ValidationError::EmptyContent)?;
        if content.is_empty() {
            return Err(ValidationError::EmptyContent);
        }
        if content.len() > Node::MAX_CONTENT_LENGTH {
            return Err(ValidationError::ContentTooLong {
                max: Node::MAX_CONTENT_LENGTH,
            });
        }

        let content_type = self
            .content_type
            .ok_or_else(|| ValidationError::MissingField("content_type".into()))?;

        let device_id = self
            .device_id
            .ok_or_else(|| ValidationError::MissingField("device_id".into()))?;
        if device_id.trim().is_empty() {
            return Err(ValidationError::EmptyDeviceId);
        }

        if let Some(ref metadata) = self.metadata {
            if !metadata.is_object() {
                return Err(ValidationError::InvalidMetadata);
            }
        }

        if let Some(ref embedding) = self.embedding {
            if embedding.dimension() != EMBEDDING_DIMENSION {
                return Err(ValidationError::InvalidEmbeddingDimension {
                    expected: EMBEDDING_DIMENSION,
                    got: embedding.dimension(),
                });
            }
        }

        let id = self.id.unwrap_or_else(Uuid::new_v4);
        let metadata = self.metadata.unwrap_or_else(|| json!({}));
        let now = Utc::now();

        let node = Node {
            id,
            content,
            content_type,
            metadata,
            embedding: self.embedding,
            created_at: now,
            updated_at: now,
            deleted_at: None,
            device_id,
            version: 0,
        };

        node.validate()?;
        Ok(node)
    }
}

/// Hiperarco conectando múltiplos nós, com suporte a direção e metadados.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Hyperedge {
    /// Identificador global único do hiperedge.
    pub id: Uuid,
    /// Etiqueta semântica que descreve a relação.
    #[serde(rename = "label")]
    pub edge_type: String,
    /// Conjunto de nós conectados por este hiperedge.
    #[serde(
        rename = "nodes",
        serialize_with = "serialize_uuid_vec",
        deserialize_with = "deserialize_uuid_vec"
    )]
    pub node_ids: Vec<Uuid>,
    /// Metadados adicionais (deve ser objeto JSON).
    #[serde(
        default = "default_metadata",
        skip_serializing_if = "is_default_metadata"
    )]
    pub metadata: serde_json::Value,
    /// Timestamp de criação.
    #[serde(
        serialize_with = "serialize_datetime",
        deserialize_with = "deserialize_datetime"
    )]
    pub created_at: DateTime<Utc>,
    /// Timestamp da última atualização.
    #[serde(
        serialize_with = "serialize_datetime",
        deserialize_with = "deserialize_datetime"
    )]
    pub updated_at: DateTime<Utc>,
    /// Timestamp de deleção lógica.
    #[serde(
        skip_serializing_if = "Option::is_none",
        serialize_with = "serialize_optional_datetime",
        deserialize_with = "deserialize_optional_datetime",
        default
    )]
    pub deleted_at: Option<DateTime<Utc>>,
    /// Dispositivo responsável pela última mutação.
    #[serde(rename = "device")]
    pub device_id: String,
    /// Versão utilizada em protocolos de sincronização.
    #[serde(default, skip_serializing_if = "is_zero_i32")]
    pub version: i32,
    /// Indica se a relação é dirigida.
    #[serde(default)]
    pub directed: bool,
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
        edge_type: S,
        node_ids: Vec<Uuid>,
        is_directed: bool,
        device_id: S,
    ) -> Result<Self, ValidationError> {
        let now = Utc::now();
        let hyperedge = Hyperedge {
            id: Uuid::new_v4(),
            edge_type: edge_type.into(),
            node_ids,
            metadata: serde_json::Value::Object(serde_json::Map::new()),
            created_at: now,
            updated_at: now,
            deleted_at: None,
            device_id: device_id.into(),
            version: 0,
            directed: is_directed,
        };
        hyperedge.validate()?;
        Ok(hyperedge)
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
        if self.edge_type.trim().is_empty() {
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

    /// Obtém todos os identificadores dos nós conectados por este hiperedge.
    ///
    /// A ordem preserva a sequência de inserção configurada no hiperedge.
    pub fn nodes(&self) -> &[Uuid] {
        &self.node_ids
    }

    /// Retorna a cardinalidade do hiperedge (quantidade de nós conectados).
    pub fn node_count(&self) -> usize {
        self.node_ids.len()
    }

    /// Indica se o hiperedge conecta exatamente dois nós.
    pub fn is_binary(&self) -> bool {
        self.node_ids.len() == 2
    }

    /// Indica se o hiperedge conecta mais de dois nós.
    pub fn is_nary(&self) -> bool {
        self.node_ids.len() > 2
    }

    /// Verifica se determinado nó participa deste hiperedge.
    pub fn contains_node(&self, node_id: Uuid) -> bool {
        self.node_ids.contains(&node_id)
    }

    /// Avalia se todos os nós informados estão presentes no hiperedge.
    pub fn contains_all_nodes(&self, node_ids: &[Uuid]) -> bool {
        node_ids.iter().all(|id| self.node_ids.contains(id))
    }

    /// Avalia se ao menos um dos nós informados participa do hiperedge.
    pub fn contains_any_node(&self, node_ids: &[Uuid]) -> bool {
        node_ids.iter().any(|id| self.node_ids.contains(id))
    }

    /// Adiciona um nó ao hiperedge.
    ///
    /// Retorna `true` quando um novo nó é inserido e `false` se já existia.
    pub fn add_node(&mut self, node_id: Uuid) -> bool {
        if self.node_ids.contains(&node_id) {
            return false;
        }
        self.node_ids.push(node_id);
        self.updated_at = Utc::now();
        true
    }

    /// Adiciona múltiplos nós ao hiperedge, ignorando duplicatas.
    ///
    /// Retorna a quantidade de nós efetivamente adicionados.
    pub fn add_nodes(&mut self, node_ids: impl IntoIterator<Item = Uuid>) -> usize {
        let mut added = 0;
        for node_id in node_ids {
            if self.add_node(node_id) {
                added += 1;
            }
        }
        added
    }

    /// Remove um nó do hiperedge.
    ///
    /// Retorna `Ok(true)` quando o nó estava presente, `Ok(false)` caso contrário.
    /// Retorna [`ValidationError::InsufficientNodes`] se a remoção violar a
    /// cardinalidade mínima (>= 2 nós).
    pub fn remove_node(&mut self, node_id: Uuid) -> Result<bool, ValidationError> {
        if self.node_ids.len() <= 2 {
            return Err(ValidationError::InsufficientNodes);
        }

        if let Some(pos) = self.node_ids.iter().position(|id| *id == node_id) {
            self.node_ids.remove(pos);
            self.updated_at = Utc::now();
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Substitui um nó existente por outro identificador.
    ///
    /// Retorna `Ok(true)` se a substituição ocorrer, `Ok(false)` caso o nó original
    /// não esteja presente. Retorna [`ValidationError::DuplicateNode`] quando o nó
    /// de destino já pertence ao hiperedge.
    pub fn replace_node(
        &mut self,
        old_node: Uuid,
        new_node: Uuid,
    ) -> Result<bool, ValidationError> {
        if let Some(pos) = self.node_ids.iter().position(|id| *id == old_node) {
            if self.node_ids.contains(&new_node) {
                return Err(ValidationError::DuplicateNode);
            }
            self.node_ids[pos] = new_node;
            self.updated_at = Utc::now();
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Retorna os nós que estão simultaneamente neste hiperedge e no `other`.
    pub fn intersection(&self, other: &Hyperedge) -> Vec<Uuid> {
        self.node_ids
            .iter()
            .filter(|id| other.node_ids.contains(id))
            .copied()
            .collect()
    }

    /// Retorna a união dos nós pertencentes a ambos os hiperarcos, sem duplicatas.
    pub fn union(&self, other: &Hyperedge) -> Vec<Uuid> {
        let mut nodes = self.node_ids.clone();
        for id in &other.node_ids {
            if !nodes.contains(id) {
                nodes.push(*id);
            }
        }
        nodes
    }

    /// Retorna os nós presentes neste hiperedge e ausentes em `other`.
    pub fn difference(&self, other: &Hyperedge) -> Vec<Uuid> {
        self.node_ids
            .iter()
            .filter(|id| !other.node_ids.contains(id))
            .copied()
            .collect()
    }

    /// Retorna os nós que pertencem a apenas um dos hiperarcos.
    pub fn symmetric_difference(&self, other: &Hyperedge) -> Vec<Uuid> {
        let mut diff = self.difference(other);
        diff.extend(other.difference(self));
        diff
    }

    /// Verifica se este hiperedge compartilha ao menos um nó com `other`.
    pub fn overlaps_with(&self, other: &Hyperedge) -> bool {
        !self.intersection(other).is_empty()
    }

    /// Verifica se este hiperedge é subconjunto de `other` (todos os nós estão contidos).
    pub fn is_subset_of(&self, other: &Hyperedge) -> bool {
        self.node_ids.iter().all(|id| other.node_ids.contains(id))
    }

    /// Verifica se este hiperedge é superconjunto de `other`.
    pub fn is_superset_of(&self, other: &Hyperedge) -> bool {
        other.is_subset_of(self)
    }

    /// Quantifica o grau de sobreposição (número de nós partilhados) com `other`.
    pub fn overlap_degree(&self, other: &Hyperedge) -> usize {
        self.intersection(other).len()
    }
}

#[cfg(test)]
/// # Property-Based Testing
///
/// Este módulo utiliza [proptest](https://docs.rs/proptest/) para validar invariantes
/// fundamentais do domínio mediante geração de milhares de entradas aleatórias.
/// A abordagem orientada a propriedades amplia a cobertura semântica ao verificar
/// comportamentos estruturais sob variabilidade extrema.
///
/// ## Propriedades Principais
///
/// - **Roundtrip de serialização**: nós e hiperarcos válidos preservam identidade após
///   serialização e desserialização.
/// - **Consistência de validação**: restrições de comprimento de conteúdo, dimensão de
///   embeddings e cardinalidade mínima são rigidamente impostas.
/// - **Correção de operações de conjuntos**: união, interseção, diferença e diferença
///   simétrica obedecem às propriedades matemáticas esperadas.
/// - **Idempotência estrutural**: inserir nós duplicados não altera estado nem cardinalidade.
/// - **Ordem temporal**: timestamps preservam relações causais (`created_at ≤ updated_at ≤ deleted_at`).
///
/// ## Execução dos Testes
///
/// ```bash
/// # Executa apenas as propriedades (prefixo `prop_`)
/// cargo test prop_
///
/// # Amplia o número de casos para 10.000 (mais lento, porém mais abrangente)
/// PROPTEST_CASES=10000 cargo test prop_
/// ```
mod proptests {
    use super::*;
    use proptest::collection::hash_map;
    use proptest::prelude::*;
    use serde_json::json;
    use uuid::Uuid;

    // ====== CUSTOM STRATEGIES ======

    /// Estratégia para strings de conteúdo válidas (1-100_000 caracteres alfanuméricos + espaço).
    fn content_strategy() -> impl Strategy<Value = String> {
        prop::string::string_regex("[a-zA-Z0-9 ]{1,100000}")
            .expect("regex de conteúdo precisa ser válida")
    }

    /// Estratégia para geração de `ContentType`.
    fn content_type_strategy() -> impl Strategy<Value = ContentType> {
        prop_oneof![
            Just(ContentType::Thought),
            Just(ContentType::Memory),
            Just(ContentType::Task),
            Just(ContentType::Note),
            Just(ContentType::Context),
        ]
    }

    /// Estratégia para identifiers de dispositivos.
    fn device_id_strategy() -> impl Strategy<Value = String> {
        prop::string::string_regex("[a-z0-9-]{5,50}")
            .expect("regex de device_id precisa ser válida")
    }

    /// Estratégia para metadados válidos (objetos JSON rasos).
    fn metadata_strategy() -> impl Strategy<Value = serde_json::Value> {
        hash_map(
            prop::string::string_regex("[a-z]{3,10}").expect("regex de chave precisa ser válida"),
            prop_oneof![
                any::<i64>().prop_map(serde_json::Value::from),
                any::<f64>().prop_map(serde_json::Value::from),
                prop::string::string_regex("[a-zA-Z0-9 ]{0,100}")
                    .expect("regex de valor precisa ser válida")
                    .prop_map(serde_json::Value::from),
            ],
            0..10,
        )
        .prop_map(|map| json!(map))
    }

    /// Estratégia para embeddings válidas (1536 dimensões).
    fn embedding_strategy() -> impl Strategy<Value = Vec<f32>> {
        prop::collection::vec(any::<f32>(), 1536..=1536)
    }

    /// Estratégia para vetores de UUIDs únicos (≥ 2) destinados a hiperarcos.
    fn unique_uuid_vec_strategy() -> impl Strategy<Value = Vec<Uuid>> {
        prop::collection::btree_set(any::<[u8; 16]>(), 2..12)
            .prop_map(|set| set.into_iter().map(Uuid::from_bytes).collect::<Vec<Uuid>>())
    }

    /// Estratégia completa para `Node` válido (embedding opcional).
    fn node_strategy() -> impl Strategy<Value = Node> {
        (
            content_strategy(),
            content_type_strategy(),
            metadata_strategy(),
            prop::option::of(embedding_strategy()),
            device_id_strategy(),
        )
            .prop_map(|(content, content_type, metadata, embedding, device_id)| {
                let builder = Node::builder()
                    .content(content)
                    .content_type(content_type)
                    .metadata(metadata)
                    .device_id(device_id);

                let builder = if let Some(embedding) = embedding {
                    builder.embedding(embedding)
                } else {
                    builder
                };

                builder
                    .build()
                    .expect("estratégia deve produzir nós devidamente validados")
            })
    }

    /// Estratégia completa para `Hyperedge` válido.
    fn hyperedge_strategy() -> impl Strategy<Value = Hyperedge> {
        (
            prop::string::string_regex("[a-z-]{3,30}")
                .expect("regex de tipo de hiperedge precisa ser válida"),
            unique_uuid_vec_strategy(),
            any::<bool>(),
            device_id_strategy(),
        )
            .prop_map(|(edge_type, node_ids, directed, device_id)| {
                Hyperedge::new(edge_type, node_ids, directed, device_id)
                    .expect("estratégia deve produzir hiperarcos válidos")
            })
    }

    proptest! {
        #![proptest_config(ProptestConfig {
            cases: 1000,
            max_shrink_iters: 1000,
            ..ProptestConfig::default()
        })]

        /// Propriedade: serialização/desserialização preserva invariantes fundamentais.
        #[test]
        fn prop_node_serialization_roundtrip(node in node_strategy()) {
            let json = serde_json::to_string(&node).expect("serialização deve funcionar");
            let deserialized: Node = serde_json::from_str(&json).expect("desserialização deve ser válida");

            prop_assert_eq!(node.id, deserialized.id);
            prop_assert_eq!(node.content, deserialized.content);
            prop_assert_eq!(node.content_type, deserialized.content_type);
            prop_assert_eq!(node.device_id, deserialized.device_id);
            prop_assert_eq!(node.metadata, deserialized.metadata);
            prop_assert_eq!(node.embedding, deserialized.embedding);
        }

        /// Propriedade: builder gera UUIDs não nulos e distintivos.
        #[test]
        fn prop_node_id_is_valid_uuid(
            content in content_strategy(),
            content_type in content_type_strategy(),
            device_id in device_id_strategy(),
        ) {
            let node = Node::builder()
                .content(content)
                .content_type(content_type)
                .device_id(device_id)
                .build()
                .expect("builder deve produzir nó válido");

            prop_assert_ne!(node.id, Uuid::nil());

            let node2 = Node::builder()
                .content("Different content")
                .content_type(ContentType::Thought)
                .device_id("device-aux")
                .build()
                .expect("segundo nó deve ser válido");

            prop_assert_ne!(node.id, node2.id);
        }

        /// Propriedade: timestamps satisfazem `created_at ≤ updated_at ≤ deleted_at`.
        #[test]
        fn prop_node_timestamps_ordered(node in node_strategy()) {
            prop_assert!(node.created_at <= node.updated_at);
            if let Some(deleted) = node.deleted_at {
                prop_assert!(deleted >= node.created_at);
            }
        }

        /// Propriedade: validação de conteúdo respeita limites mínimos/máximos.
        #[test]
        fn prop_content_validation_enforced(
            valid_content in content_strategy(),
            content_type in content_type_strategy(),
            device_id in device_id_strategy(),
        ) {
            let result = Node::builder()
                .content(valid_content.clone())
                .content_type(content_type)
                .device_id(device_id.clone())
                .build();
            prop_assert!(result.is_ok());

            let empty_result = Node::builder()
                .content("")
                .content_type(content_type)
                .device_id(device_id.clone())
                .build();
            prop_assert!(empty_result.is_err());

            let long_result = Node::builder()
                .content("a".repeat(100_001))
                .content_type(content_type)
                .device_id(device_id)
                .build();
            prop_assert!(long_result.is_err());
        }

        /// Propriedade: validação de dimensões de embedding é estrita.
        #[test]
        fn prop_embedding_dimension_validation(
            content in content_strategy(),
            device_id in device_id_strategy(),
            dimension in 0_usize..3000_usize,
        ) {
            let embedding = vec![0.1_f32; dimension];
            let result = Node::builder()
                .content(content)
                .content_type(ContentType::Context)
                .device_id(device_id)
                .embedding(embedding)
                .build();

            if dimension == EMBEDDING_DIMENSION {
                prop_assert!(result.is_ok());
            } else {
                prop_assert!(result.is_err());
            }
        }

        /// Propriedade: builder aplica metadados somente quando são objetos JSON.
        #[test]
        fn prop_metadata_must_be_object(
            content in content_strategy(),
            content_type in content_type_strategy(),
            device_id in device_id_strategy(),
            metadata in metadata_strategy(),
        ) {
            let result = Node::builder()
                .content(content)
                .content_type(content_type)
                .device_id(device_id)
                .metadata(metadata)
                .build();

            prop_assert!(result.is_ok());
        }

        /// Propriedade (com shrinking individualizado): comprimento de conteúdo determina validade.
        #[test]
        fn prop_node_content_validation_with_shrinking(
            content in prop::string::string_regex(".{0,150000}")
                .expect("regex de shrinking precisa ser válida"),
            content_type in content_type_strategy(),
            device_id in device_id_strategy(),
        ) {
            let result = Node::builder()
                .content(content.clone())
                .content_type(content_type)
                .device_id(device_id)
                .build();

            if content.is_empty() || content.len() > 100_000 {
                prop_assert!(result.is_err());
            } else {
                prop_assert!(result.is_ok());
            }
        }

        /// Propriedade: hiperarcos sempre possuem pelo menos dois nós.
        #[test]
        fn prop_hyperedge_min_nodes(edge in hyperedge_strategy()) {
            prop_assert!(edge.node_count() >= 2);
        }

        /// Propriedade: inserção de nó duplicado é idempotente.
        #[test]
        fn prop_hyperedge_add_duplicate_idempotent(mut edge in hyperedge_strategy()) {
            let existing_node = edge.nodes()[0];
            let initial_count = edge.node_count();

            prop_assert!(!edge.add_node(existing_node));
            prop_assert_eq!(edge.node_count(), initial_count);

            prop_assert!(!edge.add_node(existing_node));
            prop_assert_eq!(edge.node_count(), initial_count);
        }

        /// Propriedade: interseção é comutativa.
        #[test]
        fn prop_hyperedge_intersection_commutative(
            edge1 in hyperedge_strategy(),
            edge2 in hyperedge_strategy(),
        ) {
            let mut intersection1 = edge1.intersection(&edge2);
            let mut intersection2 = edge2.intersection(&edge1);
            intersection1.sort();
            intersection2.sort();

            prop_assert_eq!(intersection1, intersection2);
        }

        /// Propriedade: união contém todos os nós presentes em ambos hiperarcos.
        #[test]
        fn prop_hyperedge_union_completeness(
            edge1 in hyperedge_strategy(),
            edge2 in hyperedge_strategy(),
        ) {
            let union = edge1.union(&edge2);

            for node in edge1.nodes() {
                prop_assert!(union.contains(node));
            }
            for node in edge2.nodes() {
                prop_assert!(union.contains(node));
            }
        }

        /// Propriedade: diferença é subconjunto do primeiro hiperedge e disjunta do segundo.
        #[test]
        fn prop_hyperedge_difference_properties(
            edge1 in hyperedge_strategy(),
            edge2 in hyperedge_strategy(),
        ) {
            let difference = edge1.difference(&edge2);

            for node in &difference {
                prop_assert!(edge1.contains_node(*node));
                prop_assert!(!edge2.contains_node(*node));
            }
        }

        /// Propriedade: diferença simétrica corresponde a união menos interseção.
        #[test]
        fn prop_hyperedge_symmetric_difference_matches_definition(
            edge1 in hyperedge_strategy(),
            edge2 in hyperedge_strategy(),
        ) {
            let symmetric = edge1.symmetric_difference(&edge2);
            let union = edge1.union(&edge2);
            let mut intersection = edge1.intersection(&edge2);
            intersection.sort();

            for node in &symmetric {
                let in_edge1 = edge1.contains_node(*node);
                let in_edge2 = edge2.contains_node(*node);
                prop_assert_ne!(in_edge1, in_edge2);
            }

            for node in union {
                let in_symmetric = symmetric.contains(&node);
                let in_intersection = intersection.contains(&node);
                prop_assert!(!(in_symmetric && in_intersection));
            }
        }

        /// Propriedade: roundtrip de serialização de hiperarco preserva campos essenciais.
        #[test]
        fn prop_hyperedge_serialization_roundtrip(edge in hyperedge_strategy()) {
            let json = serde_json::to_string(&edge).expect("serialização deve funcionar");
            let deserialized: Hyperedge = serde_json::from_str(&json)
                .expect("desserialização deve ser válida");

            prop_assert_eq!(edge.id, deserialized.id);
            prop_assert_eq!(edge.edge_type, deserialized.edge_type);
            prop_assert_eq!(edge.node_ids, deserialized.node_ids);
            prop_assert_eq!(edge.directed, deserialized.directed);
        }

        /// Propriedade: sobreposição implica interseção não vazia.
        #[test]
        fn prop_hyperedge_overlap_consistency(
            edge1 in hyperedge_strategy(),
            edge2 in hyperedge_strategy(),
        ) {
            let overlaps = edge1.overlaps_with(&edge2);
            let intersection = edge1.intersection(&edge2);

            prop_assert_eq!(overlaps, !intersection.is_empty());
        }
    }
}

#[cfg(test)]
mod hyperedge_tests {
    use super::*;
    use std::collections::HashSet;
    use uuid::Uuid;

    fn create_test_hyperedge(node_count: usize) -> Hyperedge {
        let nodes: Vec<Uuid> = (0..node_count).map(|_| Uuid::new_v4()).collect();
        Hyperedge::new("test-edge", nodes.clone(), false, "device-alpha").unwrap()
    }

    #[test]
    fn test_nodes_accessor() {
        let edge = create_test_hyperedge(3);
        assert_eq!(edge.nodes().len(), 3);
        assert_eq!(edge.nodes(), &edge.node_ids);
    }

    #[test]
    fn test_node_count_and_arity_flags() {
        let binary_edge = create_test_hyperedge(2);
        assert_eq!(binary_edge.node_count(), 2);
        assert!(binary_edge.is_binary());
        assert!(!binary_edge.is_nary());

        let mut nary_edge = create_test_hyperedge(3);
        assert_eq!(nary_edge.node_count(), 3);
        assert!(!nary_edge.is_binary());
        assert!(nary_edge.is_nary());

        let new_node = Uuid::new_v4();
        assert!(nary_edge.add_node(new_node));
        assert_eq!(nary_edge.node_count(), 4);
        assert!(nary_edge.is_nary());
    }

    #[test]
    fn test_contains_all_and_any_nodes() {
        let edge = create_test_hyperedge(3);
        let nodes = edge.nodes().to_vec();

        assert!(edge.contains_all_nodes(&nodes));
        assert!(edge.contains_all_nodes(&nodes[..2]));
        assert!(edge.contains_any_node(&nodes[..2]));
        let absent = Uuid::new_v4();
        assert!(!edge.contains_any_node(&[absent]));
        let mut mixed = nodes[..2].to_vec();
        mixed.push(absent);
        assert!(!edge.contains_all_nodes(&mixed));
    }

    #[test]
    fn test_add_node() {
        let mut edge = create_test_hyperedge(2);
        let new_node = Uuid::new_v4();

        assert!(edge.add_node(new_node));
        assert_eq!(edge.node_count(), 3);
        assert!(edge.contains_node(new_node));
    }

    #[test]
    fn test_add_node_duplicate() {
        let mut edge = create_test_hyperedge(2);
        let existing = edge.nodes()[0];

        assert!(!edge.add_node(existing));
        assert_eq!(edge.node_count(), 2);
    }

    #[test]
    fn test_add_nodes_bulk() {
        let mut edge = create_test_hyperedge(2);
        let nodes: Vec<Uuid> = vec![Uuid::new_v4(), edge.nodes()[0], Uuid::new_v4()];
        let added = edge.add_nodes(nodes.clone());

        assert_eq!(added, 2);
        assert_eq!(edge.node_count(), 4);
        assert!(edge.contains_node(nodes[0]));
        assert!(edge.contains_node(nodes[2]));
    }

    #[test]
    fn test_remove_node() {
        let mut edge = create_test_hyperedge(3);
        let node_to_remove = edge.nodes()[0];

        assert!(edge.remove_node(node_to_remove).unwrap());
        assert_eq!(edge.node_count(), 2);
        assert!(!edge.contains_node(node_to_remove));
    }

    #[test]
    fn test_remove_node_insufficient() {
        let mut edge = create_test_hyperedge(2);
        let node_to_remove = edge.nodes()[0];

        let result = edge.remove_node(node_to_remove);
        assert!(matches!(result, Err(ValidationError::InsufficientNodes)));
    }

    #[test]
    fn test_replace_node_success() {
        let mut edge = create_test_hyperedge(3);
        let old_node = edge.nodes()[0];
        let new_node = Uuid::new_v4();

        let replaced = edge.replace_node(old_node, new_node).unwrap();
        assert!(replaced);
        assert!(!edge.contains_node(old_node));
        assert!(edge.contains_node(new_node));
    }

    #[test]
    fn test_replace_node_duplicate_error() {
        let mut edge = create_test_hyperedge(3);
        let old_node = edge.nodes()[0];
        let duplicate_target = edge.nodes()[1];

        let err = edge.replace_node(old_node, duplicate_target).unwrap_err();
        assert!(matches!(err, ValidationError::DuplicateNode));
    }

    #[test]
    fn test_intersection() {
        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();
        let node4 = Uuid::new_v4();

        let edge1 = Hyperedge::new("e1", vec![node1, node2, node3], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![node2, node3, node4], false, "d").unwrap();

        let intersection = edge1.intersection(&edge2);
        assert_eq!(intersection.len(), 2);
        assert!(intersection.contains(&node2));
        assert!(intersection.contains(&node3));
    }

    #[test]
    fn test_union() {
        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();

        let edge1 = Hyperedge::new("e1", vec![node1, node2], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![node2, node3], false, "d").unwrap();

        let union = edge1.union(&edge2);
        let set: HashSet<_> = union.iter().cloned().collect();
        assert_eq!(union.len(), 3);
        assert!(set.contains(&node1));
        assert!(set.contains(&node2));
        assert!(set.contains(&node3));
    }

    #[test]
    fn test_difference_and_symmetric_difference() {
        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();
        let node4 = Uuid::new_v4();

        let edge1 = Hyperedge::new("e1", vec![node1, node2, node3], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![node2, node3, node4], false, "d").unwrap();

        let difference = edge1.difference(&edge2);
        assert_eq!(difference, vec![node1]);

        let symmetric = edge1.symmetric_difference(&edge2);
        let set: HashSet<_> = symmetric.iter().cloned().collect();
        assert_eq!(symmetric.len(), 2);
        assert!(set.contains(&node1));
        assert!(set.contains(&node4));
    }

    #[test]
    fn test_overlap_predicates() {
        let shared_node = Uuid::new_v4();
        let edge1 = Hyperedge::new("e1", vec![shared_node, Uuid::new_v4()], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![shared_node, Uuid::new_v4()], false, "d").unwrap();
        let edge3 = Hyperedge::new("e3", vec![Uuid::new_v4(), Uuid::new_v4()], false, "d").unwrap();

        assert!(edge1.overlaps_with(&edge2));
        assert!(!edge1.overlaps_with(&edge3));

        let union_edge = Hyperedge::new("union", edge1.union(&edge2), false, "d").unwrap();
        assert!(edge1.is_subset_of(&union_edge));
    }

    #[test]
    fn test_subset_and_superset() {
        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();

        let edge1 = Hyperedge::new("e1", vec![node1, node2], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![node1, node2, node3], false, "d").unwrap();

        assert!(edge1.is_subset_of(&edge2));
        assert!(edge2.is_superset_of(&edge1));
        assert!(!edge2.is_subset_of(&edge1));
    }

    #[test]
    fn test_overlap_degree() {
        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();
        let node4 = Uuid::new_v4();

        let edge1 = Hyperedge::new("e1", vec![node1, node2, node3], false, "d").unwrap();
        let edge2 = Hyperedge::new("e2", vec![node2, node3, node4], false, "d").unwrap();

        assert_eq!(edge1.overlap_degree(&edge2), 2);
    }
}

#[cfg(test)]
mod serialization_tests {
    use super::*;
    use serde_json::{json, Value};

    #[test]
    fn test_node_json_size_optimized() {
        let node = Node::builder()
            .content("Test content for size benchmark")
            .content_type(ContentType::Thought)
            .device_id("test-device-id")
            .build()
            .unwrap();

        let json = serde_json::to_string(&node).unwrap();

        assert!(json.contains(r#""type":"#));
        assert!(json.contains(r#""device":"#));
        assert!(!json.contains(r#""content_type""#));
        assert!(!json.contains(r#""device_id""#));

        if super::is_default_metadata(&node.metadata) {
            assert!(!json.contains(r#""metadata""#));
        }
        if super::is_zero_i32(&node.version) {
            assert!(!json.contains(r#""version""#));
        }

        println!("Optimized JSON size: {} bytes", json.len());
        println!("JSON: {}", json);
    }

    #[test]
    fn test_node_roundtrip() {
        let original = Node::builder()
            .content("Roundtrip test")
            .content_type(ContentType::Memory)
            .metadata(json!({"key": "value"}))
            .device_id("device-123")
            .build()
            .unwrap();

        let json = serde_json::to_string(&original).unwrap();
        let deserialized: Node = serde_json::from_str(&json).unwrap();

        assert_eq!(original.id, deserialized.id);
        assert_eq!(original.content, deserialized.content);
        assert_eq!(original.content_type, deserialized.content_type);
        assert_eq!(original.metadata, deserialized.metadata);
        assert_eq!(original.device_id, deserialized.device_id);
    }

    #[test]
    fn test_hyperedge_uuid_compact() {
        let node_ids = vec![Uuid::new_v4(), Uuid::new_v4()];
        let edge = Hyperedge::new("test-edge", node_ids.clone(), false, "device").unwrap();

        let json = serde_json::to_string(&edge).unwrap();
        let value: Value = serde_json::from_str(&json).unwrap();
        let nodes = value
            .get("nodes")
            .and_then(Value::as_array)
            .expect("nodes array present");

        assert_eq!(nodes.len(), node_ids.len());
        for entry in nodes {
            let uuid_str = entry.as_str().expect("each node id is string");
            assert_eq!(uuid_str.len(), 32);
            assert!(!uuid_str.contains('-'));
        }

        let deserialized: Hyperedge = serde_json::from_str(&json).unwrap();
        assert_eq!(edge.node_ids, deserialized.node_ids);
        assert_eq!(edge.edge_type, deserialized.edge_type);

        println!("Hyperedge JSON size: {} bytes", json.len());
    }

    #[test]
    fn test_embedding_serialization() {
        let embedding = vec![0.1; EMBEDDING_DIMENSION];
        let node = Node::builder()
            .content("With embedding")
            .content_type(ContentType::Context)
            .embedding(embedding.clone())
            .device_id("device")
            .build()
            .unwrap();

        let json = serde_json::to_string(&node).unwrap();
        let deserialized: Node = serde_json::from_str(&json).unwrap();

        assert_eq!(node.embedding, deserialized.embedding);
    }

    #[test]
    fn test_size_comparison() {
        let node = Node::builder()
            .content("A".repeat(100))
            .content_type(ContentType::Thought)
            .device_id("device-12345")
            .build()
            .unwrap();

        let optimized_json = serde_json::to_string(&node).unwrap();
        let unoptimized_json = format!(
            r#"{{"id":"{}","content":"{}","content_type":"Thought","metadata":{{}},"embedding":null,"created_at":"{}","updated_at":"{}","deleted_at":null,"device_id":"device-12345","version":0}}"#,
            node.id,
            node.content,
            node.created_at.to_rfc3339(),
            node.updated_at.to_rfc3339(),
        );

        let reduction = unoptimized_json.len() as f64 - optimized_json.len() as f64;
        let percent = (reduction / unoptimized_json.len() as f64) * 100.0;

        println!("Unoptimized: {} bytes", unoptimized_json.len());
        println!("Optimized: {} bytes", optimized_json.len());
        println!("Reduction: {:.1}% ({} bytes)", percent, reduction as i64);

        assert!(optimized_json.len() < unoptimized_json.len());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

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
        assert_eq!(edge.edge_type, "relates");
        assert_eq!(edge.node_ids, nodes);
        assert!(!edge.directed);
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
        assert!(edge.add_node(new_node));
        assert!(edge.contains_node(new_node));

        assert!(edge.remove_node(new_node).unwrap());
        assert!(!edge.contains_node(new_node));
    }

    #[test]
    fn test_hyperedge_validation_insufficient_nodes() {
        let result = Hyperedge::new("relates", vec![Uuid::new_v4()], false, "device-alpha");
        assert!(matches!(result, Err(ValidationError::InsufficientNodes)));
    }

    #[test]
    fn test_hyperedge_duplicate_nodes_error() {
        let node_id = Uuid::new_v4();
        let result = Hyperedge::new("relates", vec![node_id, node_id], false, "device-alpha");
        assert!(matches!(result, Err(ValidationError::DuplicateNodeId(_))));
    }

    #[test]
    fn test_node_builder() {
        let node = Node::builder()
            .content("Test thought")
            .content_type(ContentType::Thought)
            .device_id("test-device")
            .build()
            .unwrap();

        assert_eq!(node.content, "Test thought");
        assert_eq!(node.content_type, ContentType::Thought);
        assert_eq!(node.device_id, "test-device");
        assert_eq!(node.version, 0);
        assert!(node.deleted_at.is_none());
        assert_eq!(node.metadata, json!({}));
    }

    #[test]
    fn test_node_builder_with_metadata() {
        let metadata = json!({
            "priority": 5,
            "tags": ["important", "urgent"]
        });

        let node = Node::builder()
            .content("Test")
            .content_type(ContentType::Task)
            .device_id("test")
            .metadata(metadata.clone())
            .build()
            .unwrap();

        assert_eq!(node.metadata, metadata);
    }

    #[test]
    fn test_node_builder_with_embedding() {
        let embedding = vec![0.1; EMBEDDING_DIMENSION];

        let node = Node::builder()
            .content("Test")
            .content_type(ContentType::Memory)
            .device_id("test")
            .embedding(embedding.clone())
            .build()
            .unwrap();

        assert_eq!(node.embedding, Some(Embedding::from(embedding)));
    }

    #[test]
    fn test_node_builder_missing_content() {
        let result = Node::builder()
            .content_type(ContentType::Thought)
            .device_id("test")
            .build();

        assert!(matches!(result, Err(ValidationError::EmptyContent)));
    }

    #[test]
    fn test_node_builder_empty_content() {
        let result = Node::builder()
            .content("")
            .content_type(ContentType::Thought)
            .device_id("test")
            .build();

        assert!(matches!(result, Err(ValidationError::EmptyContent)));
    }

    #[test]
    fn test_node_builder_content_too_long() {
        let long_content = "a".repeat(Node::MAX_CONTENT_LENGTH + 1);
        let result = Node::builder()
            .content(long_content)
            .content_type(ContentType::Note)
            .device_id("test")
            .build();

        assert!(matches!(
            result.unwrap_err(),
            ValidationError::ContentTooLong { max } if max == Node::MAX_CONTENT_LENGTH
        ));
    }

    #[test]
    fn test_node_builder_invalid_metadata() {
        let invalid_metadata = json!("not an object");

        let result = Node::builder()
            .content("Test")
            .content_type(ContentType::Thought)
            .device_id("test")
            .metadata(invalid_metadata)
            .build();

        assert!(matches!(
            result.unwrap_err(),
            ValidationError::InvalidMetadata
        ));
    }

    #[test]
    fn test_node_builder_invalid_embedding_dimension() {
        let invalid_embedding = vec![0.1; 512];

        let result = Node::builder()
            .content("Test")
            .content_type(ContentType::Context)
            .device_id("test")
            .embedding(invalid_embedding)
            .build();

        assert!(matches!(
            result.unwrap_err(),
            ValidationError::InvalidEmbeddingDimension {
                expected: EMBEDDING_DIMENSION,
                got: 512
            }
        ));
    }

    #[test]
    fn test_node_builder_missing_content_type() {
        let result = Node::builder().content("Test").device_id("test").build();

        assert!(matches!(
            result.unwrap_err(),
            ValidationError::MissingField(field) if field == "content_type"
        ));
    }

    #[test]
    fn test_node_builder_missing_device_id() {
        let result = Node::builder()
            .content("Test")
            .content_type(ContentType::Thought)
            .build();

        assert!(matches!(
            result.unwrap_err(),
            ValidationError::MissingField(field) if field == "device_id"
        ));
    }

    #[test]
    fn test_node_builder_custom_id() {
        let custom_id = Uuid::new_v4();
        let node = Node::builder()
            .id(custom_id)
            .content("Custom")
            .content_type(ContentType::Note)
            .device_id("device")
            .build()
            .unwrap();

        assert_eq!(node.id, custom_id);
    }

    #[test]
    fn test_node_builder_metadata_defaults_to_empty_object() {
        let node = Node::builder()
            .content("Default metadata")
            .content_type(ContentType::Thought)
            .device_id("device")
            .build()
            .unwrap();

        assert_eq!(node.metadata, json!({}));
    }

    #[test]
    fn test_node_builder_fluent_api() {
        let node = Node::builder()
            .content("Fluent test")
            .content_type(ContentType::Thought)
            .metadata(json!({"test": true}))
            .device_id("test-device")
            .build()
            .unwrap();

        assert_eq!(node.content, "Fluent test");
    }
}
