#![allow(dead_code)]

use crate::error::HypergraphError;
use crate::storage::PostgresStorage;
use async_trait::async_trait;
use sqlx::query_scalar;
use std::collections::{HashMap, HashSet, VecDeque};
use tracing::{debug, instrument};
use uuid::Uuid;

/// Trait para estratégias de travessia no hipergrafo.
#[async_trait]
pub trait TraversalStrategy {
    /// Executa travessia a partir de um nó inicial.
    async fn traverse(
        &self,
        storage: &PostgresStorage,
        start_node: Uuid,
        max_depth: Option<usize>,
    ) -> Result<TraversalResult, HypergraphError>;
}

/// Resultado da travessia (BFS/DFS).
#[derive(Debug, Clone)]
pub struct TraversalResult {
    /// Ordem de visitação dos nós.
    pub visited: Vec<Uuid>,
    /// Distâncias (camadas) em relação ao nó inicial.
    pub distances: HashMap<Uuid, usize>,
    /// Ponteiros para reconstrução de caminhos.
    pub parents: HashMap<Uuid, Option<Uuid>>,
    /// Total de nós alcançados.
    pub node_count: usize,
    /// Total de hiperarestas exploradas.
    pub edge_count: usize,
}

impl TraversalResult {
    /// Reconstrói caminho do nó inicial até `target`, se existir.
    pub fn path_to(&self, target: Uuid) -> Option<Vec<Uuid>> {
        if !self.distances.contains_key(&target) {
            return None;
        }

        let mut path = Vec::new();
        let mut current = Some(target);

        while let Some(node) = current {
            path.push(node);
            current = self.parents.get(&node).copied().flatten();
        }

        path.reverse();
        Some(path)
    }
}

/// Travessia em largura.
pub struct BfsTraversal;

#[async_trait]
impl TraversalStrategy for BfsTraversal {
    #[instrument(name = "bfs.traverse", skip(self, storage))]
    async fn traverse(
        &self,
        storage: &PostgresStorage,
        start_node: Uuid,
        max_depth: Option<usize>,
    ) -> Result<TraversalResult, HypergraphError> {
        let mut visited = HashSet::new();
        let mut distances = HashMap::new();
        let mut parents = HashMap::new();
        let mut visit_order = Vec::new();
        let mut edge_count = 0usize;

        let mut queue = VecDeque::new();
        queue.push_back((start_node, 0usize));
        distances.insert(start_node, 0usize);
        parents.insert(start_node, None);

        while let Some((current_node, depth)) = queue.pop_front() {
            if visited.contains(&current_node) {
                continue;
            }

            visited.insert(current_node);
            visit_order.push(current_node);

            debug!(
                node = %current_node,
                depth,
                visited = visited.len(),
                "BFS visiting node"
            );

            if let Some(max_d) = max_depth {
                if depth >= max_d {
                    continue;
                }
            }

            let neighbors = get_neighbors(storage, current_node).await?;
            edge_count += neighbors.len();

            for neighbor in neighbors {
                if visited.contains(&neighbor) {
                    continue;
                }
                if !distances.contains_key(&neighbor) {
                    distances.insert(neighbor, depth + 1);
                    parents.insert(neighbor, Some(current_node));
                }
                queue.push_back((neighbor, depth + 1));
            }
        }

        Ok(TraversalResult {
            visited: visit_order,
            distances,
            parents,
            node_count: visited.len(),
            edge_count,
        })
    }
}

/// Travessia em profundidade.
pub struct DfsTraversal;

#[async_trait]
impl TraversalStrategy for DfsTraversal {
    #[instrument(name = "dfs.traverse", skip(self, storage))]
    async fn traverse(
        &self,
        storage: &PostgresStorage,
        start_node: Uuid,
        max_depth: Option<usize>,
    ) -> Result<TraversalResult, HypergraphError> {
        let mut visited = HashSet::new();
        let mut distances = HashMap::new();
        let mut parents = HashMap::new();
        let mut visit_order = Vec::new();
        let mut edge_count = 0usize;

        let mut stack = Vec::new();
        stack.push((start_node, 0usize, None));

        while let Some((current_node, depth, parent)) = stack.pop() {
            if let Some(max_d) = max_depth {
                if depth > max_d {
                    continue;
                }
            }

            if visited.contains(&current_node) {
                continue;
            }

            visited.insert(current_node);
            visit_order.push(current_node);
            distances.insert(current_node, depth);
            parents.insert(current_node, parent);

            debug!(
                node = %current_node,
                depth,
                visited = visited.len(),
                "DFS visiting node"
            );

            let neighbors = get_neighbors(storage, current_node).await?;
            edge_count += neighbors.len();

            for neighbor in neighbors.into_iter().rev() {
                if visited.contains(&neighbor) {
                    continue;
                }
                stack.push((neighbor, depth + 1, Some(current_node)));
            }
        }

        Ok(TraversalResult {
            visited: visit_order,
            distances,
            parents,
            node_count: visited.len(),
            edge_count,
        })
    }
}

/// Recupera vizinhos via hiperarestas.
async fn get_neighbors(
    storage: &PostgresStorage,
    node_id: Uuid,
) -> Result<Vec<Uuid>, HypergraphError> {
    let neighbors = query_scalar::<_, Uuid>(
        r#"
        SELECT DISTINCT en2.node_id
        FROM edge_nodes en1
        JOIN edge_nodes en2 ON en1.hyperedge_id = en2.hyperedge_id
        WHERE en1.node_id = $1 AND en2.node_id != $1
        "#,
    )
    .bind(node_id)
    .fetch_all(storage.pool())
    .await
    .map_err(HypergraphError::DatabaseError)?;

    Ok(neighbors)
}

/// Algoritmo de caminho mínimo (grafo não ponderado).
pub struct ShortestPath;

impl ShortestPath {
    /// Caminho mais curto entre dois nós.
    #[instrument(name = "shortest_path.find", skip(storage))]
    pub async fn find(
        storage: &PostgresStorage,
        start: Uuid,
        goal: Uuid,
    ) -> Result<Option<Vec<Uuid>>, HypergraphError> {
        let bfs = BfsTraversal;
        let traversal = bfs.traverse(storage, start, None).await?;
        Ok(traversal.path_to(goal))
    }

    /// Busca todos os caminhos (limitado por `max_paths`).
    #[instrument(name = "shortest_path.find_all", skip(storage))]
    pub async fn find_all_paths(
        storage: &PostgresStorage,
        start: Uuid,
        goal: Uuid,
        max_paths: usize,
        max_depth: usize,
    ) -> Result<Vec<Vec<Uuid>>, HypergraphError> {
        let mut all_paths = Vec::new();
        let mut seen_paths: HashSet<Vec<Uuid>> = HashSet::new();
        let mut initial_visited = HashSet::new();
        initial_visited.insert(start);
        let mut stack: Vec<(Uuid, Vec<Uuid>, HashSet<Uuid>)> =
            vec![(start, vec![start], initial_visited)];

        while let Some((current, path, visited)) = stack.pop() {
            if all_paths.len() >= max_paths {
                break;
            }

            if path.len() > max_depth {
                continue;
            }

            if current == goal {
                if seen_paths.insert(path.clone()) {
                    all_paths.push(path);
                }
                continue;
            }

            let neighbors = get_neighbors(storage, current).await?;
            for neighbor in neighbors {
                if visited.contains(&neighbor) {
                    continue;
                }

                let mut new_path = path.clone();
                new_path.push(neighbor);

                let mut new_visited = visited.clone();
                new_visited.insert(neighbor);

                stack.push((neighbor, new_path, new_visited));
            }
        }

        Ok(all_paths)
    }
}

/// Descoberta de componentes conectados.
pub struct ConnectedComponents;

impl ConnectedComponents {
    /// Lista todos os componentes conectados.
    #[instrument(name = "connected_components.find_all", skip(storage))]
    pub async fn find_all(storage: &PostgresStorage) -> Result<Vec<Vec<Uuid>>, HypergraphError> {
        let nodes: Vec<Uuid> =
            query_scalar::<_, Uuid>(r#"SELECT id FROM nodes WHERE deleted_at IS NULL"#)
                .fetch_all(storage.pool())
                .await
                .map_err(HypergraphError::DatabaseError)?;

        let mut visited_global = HashSet::new();
        let mut components = Vec::new();

        for node in nodes {
            if visited_global.contains(&node) {
                continue;
            }

            let bfs = BfsTraversal;
            let traversal = bfs.traverse(storage, node, None).await?;

            for v in &traversal.visited {
                visited_global.insert(*v);
            }

            components.push(traversal.visited);
        }

        Ok(components)
    }

    /// Verifica se dois nós pertencem ao mesmo componente.
    #[instrument(name = "connected_components.are_connected", skip(storage))]
    pub async fn are_connected(
        storage: &PostgresStorage,
        node1: Uuid,
        node2: Uuid,
    ) -> Result<bool, HypergraphError> {
        let bfs = BfsTraversal;
        let traversal = bfs.traverse(storage, node1, None).await?;
        Ok(traversal.visited.contains(&node2))
    }
}

#[cfg(test)]
mod traversal_tests {
    use super::*;
    use crate::models::{ContentType, Hyperedge, Node};
    use crate::storage::StorageRepository;

    async fn setup_test_graph(
        storage: &PostgresStorage,
    ) -> Result<(Uuid, Uuid, Uuid), HypergraphError> {
        let node_a = Node::builder()
            .content("Node A")
            .content_type(ContentType::Thought)
            .device_id("test-device")
            .build()
            .unwrap();

        let node_b = Node::builder()
            .content("Node B")
            .content_type(ContentType::Thought)
            .device_id("test-device")
            .build()
            .unwrap();

        let node_c = Node::builder()
            .content("Node C")
            .content_type(ContentType::Thought)
            .device_id("test-device")
            .build()
            .unwrap();

        let node_a = StorageRepository::create_node(storage, node_a).await?;
        let node_b = StorageRepository::create_node(storage, node_b).await?;
        let node_c = StorageRepository::create_node(storage, node_c).await?;

        let edge_ab =
            Hyperedge::new("connects", vec![node_a.id, node_b.id], false, "test-device").unwrap();

        let edge_bc =
            Hyperedge::new("connects", vec![node_b.id, node_c.id], false, "test-device").unwrap();

        let edge_ac =
            Hyperedge::new("shortcut", vec![node_a.id, node_c.id], false, "test-device").unwrap();

        StorageRepository::create_hyperedge(storage, edge_ab).await?;
        StorageRepository::create_hyperedge(storage, edge_bc).await?;
        StorageRepository::create_hyperedge(storage, edge_ac).await?;

        Ok((node_a.id, node_b.id, node_c.id))
    }

    #[tokio::test]
    async fn test_bfs_traversal() {
        let storage = PostgresStorage::new(&std::env::var("DATABASE_URL").unwrap())
            .await
            .unwrap();

        let (node_a, node_b, node_c) = setup_test_graph(&storage).await.unwrap();

        let bfs = BfsTraversal;
        let traversal = bfs.traverse(&storage, node_a, None).await.unwrap();

        assert_eq!(traversal.node_count, 3);
        assert!(traversal.visited.contains(&node_a));
        assert!(traversal.visited.contains(&node_b));
        assert!(traversal.visited.contains(&node_c));

        assert_eq!(*traversal.distances.get(&node_a).unwrap(), 0);
        assert_eq!(*traversal.distances.get(&node_b).unwrap(), 1);
        assert_eq!(*traversal.distances.get(&node_c).unwrap(), 1);
    }

    #[tokio::test]
    async fn test_shortest_path() {
        let storage = PostgresStorage::new(&std::env::var("DATABASE_URL").unwrap())
            .await
            .unwrap();

        let (node_a, _node_b, node_c) = setup_test_graph(&storage).await.unwrap();

        let path = ShortestPath::find(&storage, node_a, node_c)
            .await
            .unwrap()
            .unwrap();

        assert_eq!(path.len(), 2);
        assert_eq!(path[0], node_a);
        assert_eq!(path[1], node_c);
    }

    #[tokio::test]
    async fn test_all_paths() {
        let storage = PostgresStorage::new(&std::env::var("DATABASE_URL").unwrap())
            .await
            .unwrap();

        let (node_a, node_b, node_c) = setup_test_graph(&storage).await.unwrap();

        let paths = ShortestPath::find_all_paths(&storage, node_a, node_c, 10, 5)
            .await
            .unwrap();

        assert_eq!(paths.len(), 2);
        assert!(paths.contains(&vec![node_a, node_c]));
        assert!(paths.contains(&vec![node_a, node_b, node_c]));
    }

    #[tokio::test]
    async fn test_dfs_traversal() {
        let storage = PostgresStorage::new(&std::env::var("DATABASE_URL").unwrap())
            .await
            .unwrap();

        let (node_a, _, _) = setup_test_graph(&storage).await.unwrap();

        let dfs = DfsTraversal;
        let traversal = dfs.traverse(&storage, node_a, None).await.unwrap();

        assert_eq!(traversal.node_count, 3);
    }

    #[tokio::test]
    async fn test_connected_components() {
        let storage = PostgresStorage::new(&std::env::var("DATABASE_URL").unwrap())
            .await
            .unwrap();

        let (node_a, node_b, _) = setup_test_graph(&storage).await.unwrap();

        let connected = ConnectedComponents::are_connected(&storage, node_a, node_b)
            .await
            .unwrap();

        assert!(connected);
    }
}
