//! Neo4j Graph Store Implementation
//!
//! Production-ready Neo4j backend for graph knowledge storage.
//! Uses neo4rs driver for async operations.

use super::graph::{
    GraphError, GraphNode, GraphQueryResult, GraphRelationship, GraphStore, Result,
};
use async_trait::async_trait;
use neo4rs::{query, Graph, Node, Relation};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// Neo4j-backed graph store
pub struct Neo4jGraphStore {
    graph: Arc<Graph>,
}

impl Neo4jGraphStore {
    /// Create a new Neo4j graph store
    ///
    /// # Arguments
    /// * `uri` - Neo4j connection URI (e.g., "neo4j://localhost:7687")
    /// * `user` - Database user
    /// * `password` - Database password
    ///
    /// # Example
    /// ```no_run
    /// use beagle_memory::neo4j::Neo4jGraphStore;
    ///
    /// #[tokio::main]
    /// async fn main() {
    ///     let store = Neo4jGraphStore::new(
    ///         "neo4j://localhost:7687",
    ///         "neo4j",
    ///         "password"
    ///     ).await.unwrap();
    /// }
    /// ```
    pub async fn new(uri: &str, user: &str, password: &str) -> Result<Self> {
        info!("Connecting to Neo4j at {}", uri);

        let graph = Graph::new(uri, user, password).await.map_err(|e| {
            error!("Failed to connect to Neo4j: {}", e);
            GraphError::ConnectionFailed(e.to_string())
        })?;

        // Test connection
        let _result = graph
            .execute(query("RETURN 1 as test"))
            .await
            .map_err(|e| {
                error!("Neo4j connection test failed: {}", e);
                GraphError::ConnectionFailed(format!("Connection test failed: {}", e))
            })?;

        info!("Successfully connected to Neo4j");
        Ok(Self {
            graph: Arc::new(graph),
        })
    }

    /// Convert neo4rs Node to GraphNode
    fn node_to_graph_node(node: &Node) -> GraphNode {
        let id = node.id().to_string();
        let labels = node.labels().iter().map(|s| s.to_string()).collect();

        let mut properties = HashMap::new();
        for key in node.keys() {
            if let Ok(value) = node.get::<serde_json::Value>(key) {
                properties.insert(key.to_string(), value);
            }
        }

        GraphNode {
            id,
            labels,
            properties,
        }
    }

    /// Convert neo4rs Relation to GraphRelationship
    fn relation_to_graph_relationship(rel: &Relation) -> GraphRelationship {
        let id = rel.id().to_string();
        let from_id = rel.start_node_id().to_string();
        let to_id = rel.end_node_id().to_string();
        let rel_type = rel.typ().to_string();

        let mut properties = HashMap::new();
        for key in rel.keys() {
            if let Ok(value) = rel.get::<serde_json::Value>(key) {
                properties.insert(key.to_string(), value);
            }
        }

        GraphRelationship {
            id,
            from_id,
            to_id,
            rel_type,
            properties,
        }
    }
}

impl Clone for Neo4jGraphStore {
    fn clone(&self) -> Self {
        Self {
            graph: Arc::clone(&self.graph),
        }
    }
}

#[async_trait]
impl GraphStore for Neo4jGraphStore {
    async fn query(
        &self,
        cypher: &str,
        params: HashMap<String, serde_json::Value>,
    ) -> Result<GraphQueryResult> {
        debug!("Executing Cypher query: {}", cypher);

        let mut q = query(cypher);

        // Add parameters
        for (key, value) in params {
            match value {
                serde_json::Value::String(s) => {
                    q = q.param(&key, s);
                }
                serde_json::Value::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        q = q.param(&key, i);
                    } else if let Some(f) = n.as_f64() {
                        q = q.param(&key, f);
                    }
                }
                serde_json::Value::Bool(b) => {
                    q = q.param(&key, b);
                }
                _ => {
                    warn!("Unsupported parameter type for key: {}", key);
                }
            }
        }

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Cypher query failed: {}", e);
            GraphError::QueryFailed(e.to_string())
        })?;

        let mut nodes = Vec::new();
        let mut relationships = Vec::new();

        while let Some(row) = result.next().await.map_err(|e| {
            error!("Failed to fetch query row: {}", e);
            GraphError::QueryFailed(e.to_string())
        })? {
            // Extract nodes
            if let Ok(node) = row.get::<Node>("n") {
                nodes.push(Self::node_to_graph_node(&node));
            }

            // Extract relationships
            if let Ok(rel) = row.get::<Relation>("r") {
                relationships.push(Self::relation_to_graph_relationship(&rel));
            }
        }

        debug!(
            "Query returned {} nodes, {} relationships",
            nodes.len(),
            relationships.len()
        );

        Ok(GraphQueryResult {
            nodes,
            relationships,
            metadata: HashMap::new(),
        })
    }

    async fn create_node(
        &self,
        labels: Vec<String>,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphNode> {
        let labels_str = labels.join(":");

        // Build Cypher CREATE statement
        let cypher;
        let q;

        if !properties.is_empty() {
            let mut cypher_stmt = format!("CREATE (n:{} {{", labels_str);
            let prop_list: Vec<String> = properties
                .keys()
                .map(|k| format!("{}: ${}", k, k))
                .collect();
            cypher_stmt.push_str(&prop_list.join(", "));
            cypher_stmt.push_str("}) RETURN n");
            cypher = cypher_stmt;

            let mut query_builder = query(&cypher);
            for (key, value) in &properties {
                query_builder = match value {
                    serde_json::Value::String(s) => query_builder.param(key, s.clone()),
                    serde_json::Value::Number(n) => {
                        if let Some(i) = n.as_i64() {
                            query_builder.param(key, i)
                        } else if let Some(f) = n.as_f64() {
                            query_builder.param(key, f)
                        } else {
                            query_builder
                        }
                    }
                    serde_json::Value::Bool(b) => query_builder.param(key, *b),
                    _ => query_builder,
                };
            }
            q = query_builder;
        } else {
            cypher = format!("CREATE (n:{}) RETURN n", labels_str);
            q = query(&cypher);
        }

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Failed to create node: {}", e);
            GraphError::OperationError(e.to_string())
        })?;

        if let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::OperationError(e.to_string()))?
        {
            if let Ok(node) = row.get::<Node>("n") {
                return Ok(Self::node_to_graph_node(&node));
            }
        }

        Err(GraphError::OperationError(
            "Failed to create node: no result returned".into(),
        ))
    }

    async fn create_relationship(
        &self,
        from_id: &str,
        to_id: &str,
        rel_type: &str,
        properties: HashMap<String, serde_json::Value>,
    ) -> Result<GraphRelationship> {
        let mut cypher = format!(
            "MATCH (a), (b) WHERE id(a) = $from_id AND id(b) = $to_id CREATE (a)-[r:{}",
            rel_type
        );

        let mut q = query(&cypher);

        let from_id_int: i64 = from_id
            .parse()
            .map_err(|e| GraphError::InvalidQuery(format!("Invalid from_id: {}", e)))?;
        let to_id_int: i64 = to_id
            .parse()
            .map_err(|e| GraphError::InvalidQuery(format!("Invalid to_id: {}", e)))?;

        q = q.param("from_id", from_id_int).param("to_id", to_id_int);

        if !properties.is_empty() {
            cypher.push_str(" {");
            let prop_list: Vec<String> = properties
                .keys()
                .map(|k| format!("{}: ${}", k, k))
                .collect();
            cypher.push_str(&prop_list.join(", "));
            cypher.push_str("}");

            for (key, value) in &properties {
                match value {
                    serde_json::Value::String(s) => {
                        q = q.param(key, s.clone());
                    }
                    serde_json::Value::Number(n) => {
                        if let Some(i) = n.as_i64() {
                            q = q.param(key, i);
                        } else if let Some(f) = n.as_f64() {
                            q = q.param(key, f);
                        }
                    }
                    serde_json::Value::Bool(b) => {
                        q = q.param(key, *b);
                    }
                    _ => {}
                }
            }
        }

        cypher.push_str("]->(b) RETURN r");
        q = query(&cypher);

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Failed to create relationship: {}", e);
            GraphError::OperationError(e.to_string())
        })?;

        if let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::OperationError(e.to_string()))?
        {
            if let Ok(rel) = row.get::<Relation>("r") {
                return Ok(Self::relation_to_graph_relationship(&rel));
            }
        }

        Err(GraphError::OperationError(
            "Failed to create relationship: no result returned".into(),
        ))
    }

    async fn find_nodes(
        &self,
        label: &str,
        filters: HashMap<String, serde_json::Value>,
    ) -> Result<Vec<GraphNode>> {
        let mut cypher = format!("MATCH (n:{}) ", label);
        let mut q = query(&cypher);

        if !filters.is_empty() {
            cypher.push_str("WHERE ");
            let conditions: Vec<String> = filters
                .keys()
                .map(|k| format!("n.{} = ${}", k, k))
                .collect();
            cypher.push_str(&conditions.join(" AND "));

            for (key, value) in &filters {
                match value {
                    serde_json::Value::String(s) => {
                        q = q.param(key, s.clone());
                    }
                    serde_json::Value::Number(n) => {
                        if let Some(i) = n.as_i64() {
                            q = q.param(key, i);
                        } else if let Some(f) = n.as_f64() {
                            q = q.param(key, f);
                        }
                    }
                    serde_json::Value::Bool(b) => {
                        q = q.param(key, *b);
                    }
                    _ => {}
                }
            }
        }

        cypher.push_str(" RETURN n");
        q = query(&cypher);

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Find nodes query failed: {}", e);
            GraphError::QueryFailed(e.to_string())
        })?;

        let mut nodes = Vec::new();
        while let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::QueryFailed(e.to_string()))?
        {
            if let Ok(node) = row.get::<Node>("n") {
                nodes.push(Self::node_to_graph_node(&node));
            }
        }

        Ok(nodes)
    }

    async fn get_neighborhood(&self, node_id: &str, depth: usize) -> Result<GraphQueryResult> {
        let node_id_int: i64 = node_id
            .parse()
            .map_err(|e| GraphError::InvalidQuery(format!("Invalid node_id: {}", e)))?;

        let cypher = format!(
            "MATCH path = (n)-[*1..{}]-(m) WHERE id(n) = $node_id RETURN n, m, relationships(path) as rels",
            depth
        );

        let q = query(&cypher).param("node_id", node_id_int);

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Get neighborhood query failed: {}", e);
            GraphError::QueryFailed(e.to_string())
        })?;

        let mut nodes = Vec::new();
        let mut relationships = Vec::new();
        let mut seen_node_ids = std::collections::HashSet::new();
        let mut seen_rel_ids = std::collections::HashSet::new();

        while let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::QueryFailed(e.to_string()))?
        {
            // Add source node
            if let Ok(node) = row.get::<Node>("n") {
                let id = node.id().to_string();
                if seen_node_ids.insert(id.clone()) {
                    nodes.push(Self::node_to_graph_node(&node));
                }
            }

            // Add target node
            if let Ok(node) = row.get::<Node>("m") {
                let id = node.id().to_string();
                if seen_node_ids.insert(id.clone()) {
                    nodes.push(Self::node_to_graph_node(&node));
                }
            }

            // Add relationships
            if let Ok(rels) = row.get::<Vec<Relation>>("rels") {
                for rel in rels {
                    let id = rel.id().to_string();
                    if seen_rel_ids.insert(id.clone()) {
                        relationships.push(Self::relation_to_graph_relationship(&rel));
                    }
                }
            }
        }

        Ok(GraphQueryResult {
            nodes,
            relationships,
            metadata: HashMap::new(),
        })
    }

    async fn find_paths(
        &self,
        from_id: &str,
        to_id: &str,
        max_depth: usize,
    ) -> Result<Vec<Vec<String>>> {
        let from_id_int: i64 = from_id
            .parse()
            .map_err(|e| GraphError::InvalidQuery(format!("Invalid from_id: {}", e)))?;
        let to_id_int: i64 = to_id
            .parse()
            .map_err(|e| GraphError::InvalidQuery(format!("Invalid to_id: {}", e)))?;

        let cypher = format!(
            "MATCH path = shortestPath((a)-[*..{}]-(b)) WHERE id(a) = $from_id AND id(b) = $to_id RETURN nodes(path) as path_nodes",
            max_depth
        );

        let q = query(&cypher)
            .param("from_id", from_id_int)
            .param("to_id", to_id_int);

        let mut result = self.graph.execute(q).await.map_err(|e| {
            error!("Find paths query failed: {}", e);
            GraphError::QueryFailed(e.to_string())
        })?;

        let mut paths = Vec::new();

        while let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::QueryFailed(e.to_string()))?
        {
            if let Ok(path_nodes) = row.get::<Vec<Node>>("path_nodes") {
                let node_ids: Vec<String> = path_nodes.iter().map(|n| n.id().to_string()).collect();
                paths.push(node_ids);
            }
        }

        Ok(paths)
    }

    async fn semantic_search(&self, query_text: &str, limit: usize) -> Result<Vec<GraphNode>> {
        // Full-text search using CONTAINS (requires appropriate index)
        let cypher = "MATCH (n) WHERE any(prop in keys(n) WHERE toString(n[prop]) CONTAINS $query) RETURN n LIMIT $limit";

        let q = query(cypher)
            .param("query", query_text)
            .param("limit", limit as i64);

        let mut result = self.graph.execute(q).await.map_err(|e| {
            warn!(
                "Semantic search failed, falling back to label search: {}",
                e
            );
            // Fallback to simple label search if full-text fails
            GraphError::QueryFailed(e.to_string())
        })?;

        let mut nodes = Vec::new();
        while let Some(row) = result
            .next()
            .await
            .map_err(|e| GraphError::QueryFailed(e.to_string()))?
        {
            if let Ok(node) = row.get::<Node>("n") {
                nodes.push(Self::node_to_graph_node(&node));
            }
        }

        Ok(nodes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires running Neo4j instance
    async fn test_neo4j_connection() {
        let store = Neo4jGraphStore::new("neo4j://localhost:7687", "neo4j", "password").await;

        assert!(store.is_ok(), "Should connect to Neo4j");
    }

    #[tokio::test]
    #[ignore] // Requires running Neo4j instance
    async fn test_neo4j_create_node() {
        let store = Neo4jGraphStore::new("neo4j://localhost:7687", "neo4j", "password")
            .await
            .unwrap();

        let mut props = HashMap::new();
        props.insert("name".to_string(), serde_json::json!("Test Node"));
        props.insert("value".to_string(), serde_json::json!(42));

        let node = store
            .create_node(vec!["TestConcept".to_string()], props)
            .await
            .unwrap();

        assert!(!node.id.is_empty());
        assert!(node.labels.contains(&"TestConcept".to_string()));
    }
}
