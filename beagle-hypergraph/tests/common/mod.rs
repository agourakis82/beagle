use std::sync::Once;

use beagle_hypergraph::{
    cache::RedisCache,
    models::{ContentType, Hyperedge, Node},
    storage::PostgresStorage,
    types::Embedding,
};
use sqlx::PgPool;
use uuid::Uuid;

static INIT: Once = Once::new();

/// Inicializa logging de teste uma única vez por binário de teste.
pub fn init_test_logging() {
    INIT.call_once(|| {
        let _ = tracing_subscriber::fmt()
            .with_test_writer()
            .with_max_level(tracing::Level::DEBUG)
            .try_init();
    });
}

/// Cria um pool de banco PostgreSQL isolado para testes (roda migrações).
pub async fn create_test_db_pool() -> PgPool {
    let database_url = std::env::var("TEST_DATABASE_URL").unwrap_or_else(|_| {
        "postgres://beagle_user:password@localhost:5432/beagle_test".to_string()
    });

    let pool = PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to test database");

    sqlx::migrate!("../beagle-db/migrations")
        .run(&pool)
        .await
        .expect("Failed to run migrations");

    pool
}

/// Cria instância de cache Redis para testes.
pub async fn create_test_redis() -> RedisCache {
    let redis_url =
        std::env::var("TEST_REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379/1".to_string());

    RedisCache::new(&redis_url)
        .await
        .expect("Failed to connect to test Redis")
}

/// Gera nó de teste aleatório.
pub fn random_test_node() -> Node {
    Node::builder()
        .content(format!("Test node {}", Uuid::new_v4()))
        .content_type(ContentType::Thought)
        .device_id("test-device")
        .build()
        .expect("Failed to build random test node")
}

/// Gera nó de teste com conteúdo definido.
pub fn test_node(content: &str, content_type: ContentType) -> Node {
    Node::builder()
        .content(content)
        .content_type(content_type)
        .device_id("test-device")
        .build()
        .expect("Failed to build test node")
}

/// Gera nó de teste com embedding explícito.
pub fn test_node_with_embedding(content: &str, embedding: Vec<f32>) -> Node {
    let embedding = Embedding::new(embedding)
        .expect("embedding de teste deve respeitar dimensionalidade canônica");
    let embedding_vec: Vec<f32> = embedding.into();

    Node::builder()
        .content(content)
        .content_type(ContentType::Thought)
        .embedding(embedding_vec)
        .device_id("test-device")
        .build()
        .expect("Failed to build test node with embedding")
}

/// Gera hiperaresta conectando nós fornecidos.
pub fn test_hyperedge(node_ids: Vec<Uuid>, edge_type: &str) -> Hyperedge {
    Hyperedge::new(
        edge_type.to_string(),
        node_ids,
        false,
        "test-device".to_string(),
    )
}

/// Remove dados residuais do banco de teste.
pub async fn cleanup_test_db(pool: &PgPool) {
    sqlx::query!("DELETE FROM edge_nodes")
        .execute(pool)
        .await
        .expect("failed to cleanup edge_nodes");

    sqlx::query!("DELETE FROM hyperedges")
        .execute(pool)
        .await
        .expect("failed to cleanup hyperedges");

    sqlx::query!("DELETE FROM nodes")
        .execute(pool)
        .await
        .expect("failed to cleanup nodes");
}

/// Cria grafo linear A->B->C em armazenamento PostgreSQL.
pub async fn create_test_graph_linear(storage: &PostgresStorage) -> (Uuid, Uuid, Uuid) {
    let node_a = test_node("Node A", ContentType::Thought);
    let node_b = test_node("Node B", ContentType::Thought);
    let node_c = test_node("Node C", ContentType::Thought);

    let id_a = storage
        .create_node(&node_a)
        .await
        .expect("failed to create node A");
    let id_b = storage
        .create_node(&node_b)
        .await
        .expect("failed to create node B");
    let id_c = storage
        .create_node(&node_c)
        .await
        .expect("failed to create node C");

    let edge_ab = test_hyperedge(vec![id_a, id_b], "connects");
    let edge_bc = test_hyperedge(vec![id_b, id_c], "connects");

    storage
        .create_hyperedge(&edge_ab)
        .await
        .expect("failed to create edge AB");
    storage
        .create_hyperedge(&edge_bc)
        .await
        .expect("failed to create edge BC");

    (id_a, id_b, id_c)
}

/// Cria grafo triangular A-B-C-A.
pub async fn create_test_graph_triangle(storage: &PostgresStorage) -> (Uuid, Uuid, Uuid) {
    let node_a = test_node("Node A", ContentType::Memory);
    let node_b = test_node("Node B", ContentType::Memory);
    let node_c = test_node("Node C", ContentType::Memory);

    let id_a = storage
        .create_node(&node_a)
        .await
        .expect("failed to create node A");
    let id_b = storage
        .create_node(&node_b)
        .await
        .expect("failed to create node B");
    let id_c = storage
        .create_node(&node_c)
        .await
        .expect("failed to create node C");

    let edge_ab = test_hyperedge(vec![id_a, id_b], "relates");
    let edge_bc = test_hyperedge(vec![id_b, id_c], "relates");
    let edge_ca = test_hyperedge(vec![id_c, id_a], "relates");

    storage
        .create_hyperedge(&edge_ab)
        .await
        .expect("failed to create edge AB");
    storage
        .create_hyperedge(&edge_bc)
        .await
        .expect("failed to create edge BC");
    storage
        .create_hyperedge(&edge_ca)
        .await
        .expect("failed to create edge CA");

    (id_a, id_b, id_c)
}

/// Verifica igualdade de nós ignorando timestamps.
pub fn assert_node_eq(node1: &Node, node2: &Node) {
    assert_eq!(node1.id, node2.id);
    assert_eq!(node1.content, node2.content);
    assert_eq!(node1.content_type, node2.content_type);
    assert_eq!(node1.device_id, node2.device_id);
}

/// Mede tempo de execução de futuros assíncronos.
pub async fn measure_async<F, T>(f: F) -> (T, std::time::Duration)
where
    F: std::future::Future<Output = T>,
{
    let start = std::time::Instant::now();
    let result = f.await;
    let elapsed = start.elapsed();
    (result, elapsed)
}
