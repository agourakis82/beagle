//! Graph Store Abstraction and Implementations
//!
//! Provides trait-based abstraction for graph knowledge storage,
//! with concrete implementations for Neo4j and in-memory graphs.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;

/// Errors that can occur during graph operations
#[derive(Error, Debug)]
pub enum GraphError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Query execution failed: {0}")]
    QueryFailed(String),

    #[error("Node not found: {0}")]
    NodeNotFound(String),

    #[error("Invalid query: {0}")]
    InvalidQuery(String),

    #[error("Serialization error: {0}")]
    SerializationError(String),

    #[error("Graph operation error: {0}")]
    OperationError(String),
}

pub type Result<T> = std::result::Result<T, GraphError>;

/// Represents a node in the knowledge graph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphNode {
    pub id: String,
    pub labels: Vec<String>,
    pub properties: HashMap<String, serde_json::Value>,
}

impl GraphNode {
    pub fn new(id: String, labels: Vec<String>) -> Self {
        Self {
            id,
            labels,
            properties: HashMap::new(),
        }
    }

    pub fn with_property(mut self, key: String, value: serde_json::Value) -> Self {
        self.properties.insert(key, value);
        self
    }
}

/// Represents a relationship/edge in the knowledge graph
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRelationship {
    pub id: String,
    pub from_id: String,
    pub to_id: String,
    pub rel_type: String,
    pub properties: HashMap<String, serde_json::Value>,
}

/// Result of a graph query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphQueryResult {
    pub nodes: Vec<GraphNode>,
    pub relationships: Vec<GraphRelationship>,
    pub metadata: HashMap<String, serde_json::Value>,
}

impl GraphQueryResult {
    pub fn empty() -> Self {
        Self {
            nodes: Vec::new(),
            relationships: Vec::new(),
            metadata: HashMap::new(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty() && self.relationships.is_empty()
    }
}

/// Trait for graph knowledge storage backends
#[async_trait]
pub trait GraphStore: Send + Sync {
    /// Execute a raw Cypher query (Neo4j) or equivalent
    async fn query(
        &self,
        query: &str,
        params: HashMap<String, serde_json::Value>,
    ) -> Result<GraphQueryResult>;

    /// Create a node with labels and properties
    async fn create_node(
        &self,
        labels: Vec<String>,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphNode>;

    /// Create a relationship between two nodes
    async fn create_relationship(
        &self,
        from_id: &str,
        to_id: &str,
        rel_type: &str,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphRelationship>;

    /// Find nodes by label and optional property filters
    async fn find_nodes(
        &self,
        label: &str,
        filters: HashMap<String, serde_json::Value>,
    ) -> Result<Vec<GraphNode>>;

    /// Get neighborhood of a node (nodes connected within N hops)
    async fn get_neighborhood(&self, node_id: &str, depth: usize) -> Result<GraphQueryResult>;

    /// Search for paths between two nodes
    async fn find_paths(
        &self,
        from_id: &str,
        to_id: &str,
        max_depth: usize,
    ) -> Result<Vec<Vec<String>>>;

    /// Execute a semantic search (if supported by backend)
    async fn semantic_search(&self, query: &str, limit: usize) -> Result<Vec<GraphNode>>;
}

/// In-memory graph store for testing and development
pub struct InMemoryGraphStore {
    nodes: tokio::sync::RwLock<HashMap<String, GraphNode>>,
    relationships: tokio::sync::RwLock<HashMap<String, GraphRelationship>>,
}

impl InMemoryGraphStore {
    pub fn new() -> Self {
        Self {
            nodes: tokio::sync::RwLock::new(HashMap::new()),
            relationships: tokio::sync::RwLock::new(HashMap::new()),
        }
    }
}

impl Default for InMemoryGraphStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl GraphStore for InMemoryGraphStore {
    async fn query(
        &self,
        _query: &str,
        _params: HashMap<String, serde_json::Value>,
    ) -> Result<GraphQueryResult> {
        // Simple in-memory implementation: just return all nodes
        let nodes = self.nodes.read().await;
        let relationships = self.relationships.read().await;

        Ok(GraphQueryResult {
            nodes: nodes.values().cloned().collect(),
            relationships: relationships.values().cloned().collect(),
            metadata: HashMap::new(),
        })
    }

    async fn create_node(
        &self,
        labels: Vec<String>,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphNode> {
        let id = uuid::Uuid::new_v4().to_string();
        let mut node = GraphNode::new(id.clone(), labels);
        node.properties = properties;

        self.nodes.write().await.insert(id.clone(), node.clone());
        Ok(node)
    }

    async fn create_relationship(
        &self,
        from_id: &str,
        to_id: &str,
        rel_type: &str,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphRelationship> {
        let id = uuid::Uuid::new_v4().to_string();
        let rel = GraphRelationship {
            id: id.clone(),
            from_id: from_id.to_string(),
            to_id: to_id.to_string(),
            rel_type: rel_type.to_string(),
            properties,
        };

        self.relationships.write().await.insert(id, rel.clone());
        Ok(rel)
    }

    async fn find_nodes(
        &self,
        label: &str,
        _filters: HashMap<String, serde_json::Value>,
    ) -> Result<Vec<GraphNode>> {
        let nodes = self.nodes.read().await;
        Ok(nodes
            .values()
            .filter(|n| n.labels.contains(&label.to_string()))
            .cloned()
            .collect())
    }

    async fn get_neighborhood(&self, node_id: &str, _depth: usize) -> Result<GraphQueryResult> {
        let nodes = self.nodes.read().await;
        let relationships = self.relationships.read().await;

        // Find connected nodes
        let connected_node_ids: Vec<String> = relationships
            .values()
            .filter(|r| r.from_id == node_id || r.to_id == node_id)
            .flat_map(|r| vec![r.from_id.clone(), r.to_id.clone()])
            .collect();

        let result_nodes: Vec<GraphNode> = nodes
            .values()
            .filter(|n| connected_node_ids.contains(&n.id))
            .cloned()
            .collect();

        let result_rels: Vec<GraphRelationship> = relationships
            .values()
            .filter(|r| r.from_id == node_id || r.to_id == node_id)
            .cloned()
            .collect();

        Ok(GraphQueryResult {
            nodes: result_nodes,
            relationships: result_rels,
            metadata: HashMap::new(),
        })
    }

    async fn find_paths(
        &self,
        from_id: &str,
        to_id: &str,
        _max_depth: usize,
    ) -> Result<Vec<Vec<String>>> {
        // Simple BFS path finding
        let relationships = self.relationships.read().await;

        let mut queue = vec![vec![from_id.to_string()]];
        let mut paths = Vec::new();

        while let Some(path) = queue.pop() {
            let current = path.last().unwrap();

            if current == to_id {
                paths.push(path.clone());
                continue;
            }

            for rel in relationships.values() {
                if &rel.from_id == current && !path.contains(&rel.to_id) {
                    let mut new_path = path.clone();
                    new_path.push(rel.to_id.clone());
                    queue.push(new_path);
                }
            }
        }

        Ok(paths)
    }

    async fn semantic_search(&self, query: &str, limit: usize) -> Result<Vec<GraphNode>> {
        let nodes = self.nodes.read().await;

        // Simple text matching for in-memory store
        let mut results: Vec<GraphNode> = nodes
            .values()
            .filter(|n| {
                n.properties.values().any(|v| {
                    if let Some(s) = v.as_str() {
                        s.to_lowercase().contains(&query.to_lowercase())
                    } else {
                        false
                    }
                })
            })
            .cloned()
            .collect();

        results.truncate(limit);
        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_in_memory_graph_store() {
        let store = InMemoryGraphStore::new();

        // Create nodes
        let mut props1 = HashMap::new();
        props1.insert("name".to_string(), serde_json::json!("Concept A"));
        let node1 = store
            .create_node(vec!["Concept".to_string()], props1)
            .await
            .unwrap();

        let mut props2 = HashMap::new();
        props2.insert("name".to_string(), serde_json::json!("Concept B"));
        let node2 = store
            .create_node(vec!["Concept".to_string()], props2)
            .await
            .unwrap();

        // Create relationship
        let mut rel_props = HashMap::new();
        rel_props.insert("strength".to_string(), serde_json::json!(0.8));
        let rel = store
            .create_relationship(&node1.id, &node2.id, "RELATES_TO", rel_props)
            .await
            .unwrap();

        assert_eq!(rel.from_id, node1.id);
        assert_eq!(rel.to_id, node2.id);

        // Test neighborhood
        let neighborhood = store.get_neighborhood(&node1.id, 1).await.unwrap();
        assert!(!neighborhood.is_empty());
        assert_eq!(neighborhood.relationships.len(), 1);

        // Test find nodes
        let concepts = store.find_nodes("Concept", HashMap::new()).await.unwrap();
        assert_eq!(concepts.len(), 2);

        // Test semantic search
        let results = store.semantic_search("Concept A", 10).await.unwrap();
        assert!(results.iter().any(|n| n.id == node1.id));
    }
}
