use std::{collections::HashMap, sync::Arc};

use async_graphql::{
    dataloader::{DataLoader, Loader},
    Context, EmptyMutation, EmptySubscription, Error, ErrorExtensions, Json, Object, Result,
    Schema,
};
use async_trait::async_trait;
use beagle_hypergraph::search::MockEmbeddings;
use beagle_hypergraph::{CachedPostgresStorage, HypergraphError, Node, SemanticSearch};
use tracing::instrument;
use uuid::Uuid;

/// Alias público do schema GraphQL completo.
pub type BeagleSchema = Schema<QueryRoot, MutationRoot, SubscriptionRoot>;

/// Raiz de mutações, atualmente vazia.
pub type MutationRoot = EmptyMutation;

/// Raiz de subscriptions, atualmente vazia.
pub type SubscriptionRoot = EmptySubscription;

/// Constrói o schema GraphQL com injeção de storage e DataLoader de nós.
pub fn build_schema(storage: Arc<CachedPostgresStorage>) -> BeagleSchema {
    let loader = DataLoader::new(NodeLoader::new(storage.clone()), tokio::spawn);

    Schema::build(
        QueryRoot,
        MutationRoot::default(),
        SubscriptionRoot::default(),
    )
    .data(storage)
    .data(loader)
    .finish()
}

/// Raiz de consultas públicas.
#[derive(Debug, Clone, Copy)]
pub struct QueryRoot;

#[Object]
impl QueryRoot {
    /// Recupera um nó pelo identificador único.
    #[instrument(name = "graphql.query.node", skip(self, ctx))]
    async fn node(&self, ctx: &Context<'_>, id: Uuid) -> Result<NodeObject> {
        let loader = ctx.data::<DataLoader<NodeLoader>>()?;

        loader
            .load_one(id)
            .await?
            .ok_or_else(|| not_found_error(id))
            .map(NodeObject::from)
    }

    /// Executa busca semântica textual retornando os nós mais similares.
    #[instrument(name = "graphql.query.search", skip(self, ctx, query))]
    async fn search(&self, ctx: &Context<'_>, query: String) -> Result<Vec<NodeObject>> {
        let storage = ctx.data::<Arc<CachedPostgresStorage>>()?;

        let semantic = SemanticSearch::from_ref(storage.storage());
        let provider = MockEmbeddings;

        let results = semantic
            .search_by_text(&query, &provider, 20, 0.7)
            .await
            .map_err(map_storage_error)?;

        Ok(results
            .into_iter()
            .map(|result| NodeObject::from(result.node))
            .collect())
    }
}

/// Wrapper GraphQL que expõe campos seguros do domínio `Node`.
#[derive(Clone, Debug)]
pub struct NodeObject {
    inner: Node,
}

impl From<Node> for NodeObject {
    fn from(node: Node) -> Self {
        Self { inner: node }
    }
}

#[Object]
impl NodeObject {
    /// UUID do nó.
    async fn id(&self) -> Uuid {
        self.inner.id
    }

    /// Conteúdo textual registrado no nó.
    async fn content(&self) -> &str {
        &self.inner.content
    }

    /// Tipo semântico associado ao nó.
    async fn content_type(&self) -> String {
        self.inner.content_type.to_string()
    }

    /// Metadados estruturados (JSON).
    async fn metadata(&self) -> Json<serde_json::Value> {
        Json(self.inner.metadata.clone())
    }

    /// Embedding vetorial opcional (dimensão 1536).
    async fn embedding(&self) -> Option<Vec<f32>> {
        self.inner.embedding.clone()
    }

    /// Timestamp de criação.
    async fn created_at(&self) -> chrono::DateTime<chrono::Utc> {
        self.inner.created_at
    }

    /// Timestamp da última atualização.
    async fn updated_at(&self) -> chrono::DateTime<chrono::Utc> {
        self.inner.updated_at
    }

    /// Timestamp de deleção lógica, quando existir.
    async fn deleted_at(&self) -> Option<chrono::DateTime<chrono::Utc>> {
        self.inner.deleted_at
    }

    /// Identificador do dispositivo associado ao nó.
    async fn device_id(&self) -> &str {
        &self.inner.device_id
    }

    /// Versão para controle de concorrência optimista.
    async fn version(&self) -> i32 {
        self.inner.version
    }

    /// Vizinhaça direta do nó até a profundidade informada (padrão = 1).
    async fn neighbors(&self, ctx: &Context<'_>, depth: Option<i32>) -> Result<Vec<NodeNeighbor>> {
        let depth = depth.unwrap_or(1).max(1);
        let storage = ctx.data::<Arc<CachedPostgresStorage>>()?;
        let loader = ctx.data::<DataLoader<NodeLoader>>()?;

        let neighborhood = storage
            .query_neighborhood(self.inner.id, depth)
            .await
            .map_err(map_storage_error)?;

        for (neighbor, _) in &neighborhood {
            loader.prime(neighbor.id, neighbor.clone());
        }

        let mut items = Vec::with_capacity(neighborhood.len());
        for (neighbor, distance) in neighborhood {
            if neighbor.id == self.inner.id {
                continue;
            }
            items.push(NodeNeighbor::new(neighbor, distance));
        }

        Ok(items)
    }
}

/// Wrapper que inclui distância topológica da vizinhança.
#[derive(Clone, Debug)]
pub struct NodeNeighbor {
    node: Node,
    distance: i32,
}

impl NodeNeighbor {
    fn new(node: Node, distance: i32) -> Self {
        Self { node, distance }
    }
}

#[Object]
impl NodeNeighbor {
    /// Nó vizinho acessível.
    async fn node(&self) -> NodeObject {
        NodeObject::from(self.node.clone())
    }

    /// Distância topológica (número de passos) entre os nós.
    async fn distance(&self) -> i32 {
        self.distance
    }
}

/// Loader batelado que garante coerência e cache para consultas de `Node`.
#[derive(Clone)]
struct NodeLoader {
    storage: Arc<CachedPostgresStorage>,
}

impl NodeLoader {
    fn new(storage: Arc<CachedPostgresStorage>) -> Self {
        Self { storage }
    }
}

#[async_trait]
impl Loader<Uuid> for NodeLoader {
    type Value = Node;
    type Error = Error;

    async fn load(&self, keys: &[Uuid]) -> Result<HashMap<Uuid, Node>, Self::Error> {
        let nodes = self
            .storage
            .batch_get_nodes(keys.to_vec())
            .await
            .map_err(map_storage_error)?;

        Ok(nodes.into_iter().map(|node| (node.id, node)).collect())
    }
}

fn map_storage_error(err: HypergraphError) -> Error {
    let mut error = Error::new(err.to_string());
    let code = if err.is_client_error() {
        "BAD_REQUEST"
    } else {
        "INTERNAL_SERVER_ERROR"
    };
    let transient = err.is_transient();

    error = error.extend_with(|_, e| {
        e.set("code", code);
        e.set("transient", transient);
    });

    error
}

fn not_found_error(id: Uuid) -> Error {
    Error::new(format!("Node not found: {id}")).extend_with(|_, e| {
        e.set("code", "NOT_FOUND");
    })
}
