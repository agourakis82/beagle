use crate::{thought_capture::CapturedInsight, HermesError, Result};
use neo4rs::{query, Graph};
use tracing::{debug, info};
use uuid::Uuid;

use std::sync::Arc;

#[derive(Clone)]
pub struct KnowledgeGraph {
    graph: Arc<Graph>,
}

impl KnowledgeGraph {
    pub async fn new(uri: &str, user: &str, password: &str) -> Result<Self> {
        let graph = Graph::new(uri, user, password)
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to connect to Neo4j: {}", e)))?;

        // Create constraints and indexes
        Self::setup_schema(&graph).await?;

        info!("Neo4j knowledge graph initialized");
        Ok(Self {
            graph: Arc::new(graph),
        })
    }

    async fn setup_schema(graph: &Graph) -> Result<()> {
        // Create uniqueness constraint on Insight.id
        graph
            .run(query(
                "CREATE CONSTRAINT insight_id IF NOT EXISTS 
             FOR (i:Insight) REQUIRE i.id IS UNIQUE",
            ))
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to create constraint: {}", e)))?;

        // Create index on Insight.timestamp
        graph
            .run(query(
                "CREATE INDEX insight_timestamp IF NOT EXISTS 
             FOR (i:Insight) ON (i.timestamp)",
            ))
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to create index: {}", e)))?;

        // Create index on Concept.name
        graph
            .run(query(
                "CREATE INDEX concept_name IF NOT EXISTS 
             FOR (c:Concept) ON (c.name)",
            ))
            .await
            .map_err(|e| {
                HermesError::Neo4jError(format!("Failed to create concept index: {}", e))
            })?;

        debug!("Neo4j schema setup completed");
        Ok(())
    }

    /// Store insight in knowledge graph
    pub async fn store_insight(&self, insight: &CapturedInsight) -> Result<Uuid> {
        // 1. Create Insight node
        let query_str = "
            CREATE (i:Insight {
                id: $id,
                content: $content,
                timestamp: datetime($timestamp),
                context: $context,
                source: $source
            })
            RETURN i.id as id
        ";

        (*self.graph)
            .run(
                query(query_str)
                    .param("id", insight.id.to_string())
                    .param("content", insight.text.clone())
                    .param("timestamp", insight.timestamp.to_rfc3339())
                    .param(
                        "context",
                        insight.metadata.context.clone().unwrap_or_default(),
                    )
                    .param("source", format!("{:?}", insight.source)),
            )
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to store insight: {}", e)))?;

        // 2. Create Concept nodes and relationships
        for concept in &insight.concepts {
            self.link_concept(insight.id, &concept.text).await?;
        }

        // 4. Detect relationships with existing insights
        self.detect_relationships(insight).await?;

        debug!("Stored insight {} in knowledge graph", insight.id);
        Ok(insight.id)
    }

    async fn link_concept(&self, insight_id: Uuid, concept: &str) -> Result<()> {
        let query_str = "
            MATCH (i:Insight {id: $insight_id})
            MERGE (c:Concept {name: $concept})
            ON CREATE SET c.created_at = datetime(), c.insight_count = 1
            ON MATCH SET c.insight_count = c.insight_count + 1
            MERGE (i)-[:RELATES_TO]->(c)
        ";

        (*self.graph)
            .run(
                query(query_str)
                    .param("insight_id", insight_id.to_string())
                    .param("concept", concept),
            )
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to link concept: {}", e)))?;

        Ok(())
    }

    async fn detect_relationships(&self, insight: &CapturedInsight) -> Result<()> {
        // Find insights with overlapping concepts
        let query_str = "
            MATCH (new:Insight {id: $new_id})-[:RELATES_TO]->(c:Concept)<-[:RELATES_TO]-(existing:Insight)
            WHERE existing.id <> $new_id
            WITH new, existing, count(c) as overlap
            WHERE overlap >= 2
            MERGE (new)-[:RELATES_TO {strength: overlap}]->(existing)
        ";

        (*self.graph)
            .run(query(query_str).param("new_id", insight.id.to_string()))
            .await
            .map_err(|e| {
                HermesError::Neo4jError(format!("Failed to detect relationships: {}", e))
            })?;

        Ok(())
    }

    /// Find dense concept clusters (candidates for synthesis)
    pub async fn find_concept_clusters(
        &self,
        min_insights: usize,
    ) -> Result<Vec<super::ConceptCluster>> {
        let query_str = "
            MATCH (i:Insight)-[:RELATES_TO]->(c:Concept)
            WITH c, collect(i) as insights, count(i) as insight_count
            WHERE insight_count >= $min_insights
            RETURN c.name as concept_name, 
                   insight_count,
                   [insight IN insights | {id: insight.id, content: insight.content, timestamp: insight.timestamp}] as insights_data
            ORDER BY insight_count DESC
            LIMIT 10
        ";

        let mut result = (*self.graph)
            .execute(query(query_str).param("min_insights", min_insights as i64))
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to find clusters: {}", e)))?;

        let mut clusters = Vec::new();

        while let Some(row) = result
            .next()
            .await
            .map_err(|e| HermesError::Neo4jError(format!("Failed to read cluster result: {}", e)))?
        {
            let concept_name: String = row.get("concept_name").map_err(|e| {
                HermesError::Neo4jError(format!("Failed to get concept_name: {}", e))
            })?;
            let insight_count: i64 = row.get("insight_count").map_err(|e| {
                HermesError::Neo4jError(format!("Failed to get insight_count: {}", e))
            })?;

            // Parse insights_data from Neo4j result
            let insights_data: serde_json::Value = row.get("insights_data").map_err(|e| {
                HermesError::Neo4jError(format!("Failed to get insights_data: {}", e))
            })?;

            let insights = if let serde_json::Value::Array(arr) = insights_data {
                arr.into_iter()
                    .filter_map(|v| {
                        if let serde_json::Value::Object(obj) = v {
                            let id_str = obj.get("id")?.as_str()?;
                            let id = Uuid::parse_str(id_str).ok()?;
                            let content = obj.get("content")?.as_str()?.to_string();
                            let timestamp_str = obj.get("timestamp")?.as_str()?;
                            let timestamp = chrono::DateTime::parse_from_rfc3339(timestamp_str)
                                .ok()?
                                .with_timezone(&chrono::Utc);

                            Some(super::concepts::ClusteredInsight {
                                id,
                                content,
                                timestamp,
                            })
                        } else {
                            None
                        }
                    })
                    .collect()
            } else {
                Vec::new()
            };

            clusters.push(super::ConceptCluster {
                concept_name,
                insight_count: insight_count as usize,
                insights,
                last_synthesis: None,
            });
        }

        info!("Found {} concept clusters", clusters.len());
        Ok(clusters)
    }
}

/// Graph query builder
pub struct GraphQuery {
    cypher: String,
    params: Vec<(String, String)>,
}

impl GraphQuery {
    pub fn new(cypher: &str) -> Self {
        Self {
            cypher: cypher.to_string(),
            params: Vec::new(),
        }
    }

    pub fn param(mut self, key: &str, value: &str) -> Self {
        self.params.push((key.to_string(), value.to_string()));
        self
    }
}
