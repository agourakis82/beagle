//! Neo4j Graph Client

use super::{
    concepts::ClusteredInsight,
    models::{ConceptNode, InsightNode, PaperNode},
    ConceptCluster,
};
use crate::thought_capture::{CapturedInsight, ExtractedConcept, ConceptType};
use anyhow::{Context, Result};
use chrono::Utc;
use neo4rs::{query, Graph};
use std::sync::Arc;
use uuid::Uuid;

#[derive(Clone)]
pub struct KnowledgeGraph {
    graph: Arc<Graph>,
}

impl KnowledgeGraph {
    /// Create new Neo4j client
    pub async fn new(uri: &str, username: &str, password: &str) -> Result<Self> {
        let graph = Graph::new(uri, username, password)
            .await
            .context("Failed to connect to Neo4j")?;

        Ok(Self {
            graph: Arc::new(graph),
        })
    }

    /// Store captured insight in graph
    pub async fn store_insight(&self, insight: &CapturedInsight) -> Result<Uuid> {
        let mut txn = self.graph.start_txn().await?;

        // 1. Create Insight node
        let create_insight = query(
            "CREATE (i:Insight {
                id: $id,
                text: $text,
                source: $source,
                timestamp: datetime($timestamp),
                confidence: $confidence,
                embedding: $embedding,
                metadata: $metadata
            })",
        )
        .param("id", insight.id.to_string())
        .param("text", insight.text.clone())
        .param("source", format!("{:?}", insight.source))
        .param("timestamp", insight.timestamp.to_rfc3339())
        .param("confidence", insight.metadata.confidence)
        .param(
            "embedding",
            insight
                .concepts
                .first()
                .map(|c| c.embedding.clone())
                .unwrap_or_default(),
        )
        .param("metadata", serde_json::to_string(&insight.metadata)?);

        txn.run(create_insight).await?;

        // 2. Create/Update Concept nodes and relationships
        for concept in &insight.concepts {
            // MERGE concept (create if not exists, update if exists)
            let merge_concept = query(
                "MERGE (c:Concept {name: $name})
                 ON CREATE SET 
                   c.type = $type,
                   c.count = 1,
                   c.embedding = $embedding,
                   c.last_updated = datetime($now),
                   c.metadata = '{}'
                 ON MATCH SET
                   c.count = c.count + 1,
                   c.last_updated = datetime($now)",
            )
            .param("name", concept.text.to_lowercase())
            .param("type", format!("{:?}", concept.concept_type))
            .param("embedding", concept.embedding.clone())
            .param("now", Utc::now().to_rfc3339());

            txn.run(merge_concept).await?;

            // Create CONTAINS relationship
            let create_rel = query(
                "MATCH (i:Insight {id: $insight_id})
                 MATCH (c:Concept {name: $concept_name})
                 CREATE (i)-[:CONTAINS {confidence: $confidence}]->(c)",
            )
            .param("insight_id", insight.id.to_string())
            .param("concept_name", concept.text.to_lowercase())
            .param("confidence", concept.confidence);

            txn.run(create_rel).await?;
        }

        // 3. Create RELATED_TO relationships between co-occurring concepts
        if insight.concepts.len() >= 2 {
            for i in 0..insight.concepts.len() {
                for j in (i + 1)..insight.concepts.len() {
                    let c1 = &insight.concepts[i];
                    let c2 = &insight.concepts[j];

                    let create_relation = query(
                        "MATCH (c1:Concept {name: $name1})
                         MATCH (c2:Concept {name: $name2})
                         MERGE (c1)-[r:RELATED_TO]-(c2)
                         ON CREATE SET r.weight = 1.0
                         ON MATCH SET r.weight = r.weight + 1.0",
                    )
                    .param("name1", c1.text.to_lowercase())
                    .param("name2", c2.text.to_lowercase());

                    txn.run(create_relation).await?;
                }
            }
        }

        txn.commit().await?;

        tracing::info!(
            "Stored insight {} with {} concepts in Neo4j",
            insight.id,
            insight.concepts.len()
        );

        Ok(insight.id)
    }

    /// Detect dense concept clusters (≥threshold insights)
    pub async fn find_concept_clusters(&self, threshold: usize) -> Result<Vec<ConceptCluster>> {
        let query_str = query(
            "MATCH (i:Insight)-[:CONTAINS]->(c:Concept)
             WITH c, collect(i) as insights, count(i) as insight_count
             WHERE insight_count >= $threshold
             RETURN c.name as concept_name,
                    insight_count,
                    [insight IN insights | {
                        id: insight.id,
                        content: coalesce(insight.text, insight.content),
                        timestamp: insight.timestamp
                    }] as insights_data
             ORDER BY insight_count DESC
             LIMIT 20",
        )
        .param("threshold", threshold as i64);

        let mut result = self.graph.execute(query_str).await?;

        let mut clusters = Vec::new();

        while let Some(row) = result.next().await? {
            let concept_name: String = row.get("concept_name")?;
            let insight_count: i64 = row.get("insight_count")?;
            let insights_data: serde_json::Value = row.get("insights_data")?;

            let insights = if let serde_json::Value::Array(arr) = insights_data {
                arr.into_iter()
                    .filter_map(|entry| {
                        if let serde_json::Value::Object(obj) = entry {
                            let id = obj.get("id")?.as_str()?.parse().ok()?;
                            let content = obj.get("content")?.as_str()?.to_string();
                            let timestamp = obj
                                .get("timestamp")?
                                .as_str()?
                                .parse::<chrono::DateTime<chrono::Utc>>()
                                .ok()?;

                            Some(ClusteredInsight {
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

            clusters.push(ConceptCluster {
                concept_name,
                insight_count: insight_count as usize,
                insights,
                last_synthesis: None,
            });
        }

        Ok(clusters)
    }

    /// Create concept node with full metadata
    pub async fn create_concept_node(
        &self,
        concept: &ConceptNode,
    ) -> Result<String> {
        let create_concept = query(
            "CREATE (c:Concept {
                id: $id,
                name: $name,
                domain: $domain,
                created_at: datetime(),
                embedding: $embedding,
                metadata: $metadata
            })
            RETURN c.id as id",
        )
        .param("id", concept.id.to_string())
        .param("name", concept.name.clone())
        .param("domain", concept.domain.clone().unwrap_or_else(|| "general".to_string()))
        .param("embedding", concept.embedding.clone())
        .param("metadata", serde_json::to_string(&concept.metadata)?);

        let mut result = self.graph.execute(create_concept).await?;

        if let Some(row) = result.next().await? {
            let id: String = row.get("id")?;
            Ok(id)
        } else {
            anyhow::bail!("Failed to create concept node")
        }
    }

    /// Create relationship between concepts with strength
    pub async fn create_concept_relationship(
        &self,
        from_id: &str,
        to_id: &str,
        rel_type: &str,
        strength: f64,
    ) -> Result<()> {
        let create_rel = query(
            "MATCH (a:Concept {id: $from_id})
             MATCH (b:Concept {id: $to_id})
             MERGE (a)-[r:RELATES_TO {
                 type: $rel_type,
                 strength: $strength,
                 created_at: datetime()
             }]->(b)
             RETURN r",
        )
        .param("from_id", from_id)
        .param("to_id", to_id)
        .param("rel_type", rel_type)
        .param("strength", strength);

        self.graph.run(create_rel).await?;
        Ok(())
    }

    /// Find related concepts with minimum strength threshold
    pub async fn find_related_concepts(
        &self,
        concept_id: &str,
        min_strength: f64,
        limit: usize,
    ) -> Result<Vec<RelatedConcept>> {
        let query_str = query(
            "MATCH (c:Concept {id: $concept_id})-[r:RELATES_TO]-(related:Concept)
             WHERE r.strength >= $min_strength
             RETURN related.id as id,
                    related.name as name,
                    related.domain as domain,
                    r.strength as strength,
                    r.type as rel_type
             ORDER BY r.strength DESC
             LIMIT $limit",
        )
        .param("concept_id", concept_id)
        .param("min_strength", min_strength)
        .param("limit", limit as i64);

        let mut result = self.graph.execute(query_str).await?;
        let mut concepts = Vec::new();

        while let Some(row) = result.next().await? {
            concepts.push(RelatedConcept {
                id: row.get("id")?,
                name: row.get("name")?,
                domain: row.get("domain").unwrap_or_default(),
                strength: row.get("strength")?,
                rel_type: row.get("rel_type").unwrap_or_default(),
            });
        }

        Ok(concepts)
    }

    /// Get concept cluster with specified depth
    pub async fn get_concept_cluster(
        &self,
        concept_id: &str,
        depth: usize,
    ) -> Result<ConceptCluster> {
        let query_str = format!(
            "MATCH path = (c:Concept {{id: $concept_id}})-[*1..{}]-(related:Concept)
             RETURN DISTINCT related.id as id,
                    related.name as name,
                    related.domain as domain,
                    related.embedding as embedding
             LIMIT 50",
            depth
        );

        let query_obj = query(&query_str)
            .param("concept_id", concept_id);

        let mut result = self.graph.execute(query_obj).await?;

        let mut cluster = ConceptCluster {
            concept_name: concept_id.to_string(),
            insight_count: 0,
            insights: Vec::new(),
            last_synthesis: None,
        };

        // Get insights for this concept
        let insights = self.get_insights_for_concept_by_id(concept_id).await?;
        cluster.insight_count = insights.len();
        cluster.insights = insights;

        Ok(cluster)
    }

    /// Get insights for concept by ID
    async fn get_insights_for_concept_by_id(
        &self,
        concept_id: &str,
    ) -> Result<Vec<ClusteredInsight>> {
        let query_str = query(
            "MATCH (c:Concept {id: $concept_id})<-[:CONTAINS]-(i:Insight)
             RETURN i.id as id,
                    coalesce(i.text, i.content) as content,
                    i.timestamp as timestamp
             ORDER BY i.timestamp DESC
             LIMIT 100",
        )
        .param("concept_id", concept_id);

        let mut result = self.graph.execute(query_str).await?;
        let mut insights = Vec::new();

        while let Some(row) = result.next().await? {
            let id_str: String = row.get("id")?;
            let content: String = row.get("content")?;
            let timestamp_str: String = row.get("timestamp")?;

            if let Ok(id) = Uuid::parse_str(&id_str) {
                if let Ok(timestamp) = chrono::DateTime::parse_from_rfc3339(&timestamp_str) {
                    insights.push(ClusteredInsight {
                        id,
                        content,
                        timestamp: timestamp.with_timezone(&Utc),
                    });
                }
            }
        }

        Ok(insights)
    }

    /// Get insights for a specific concept
    pub async fn get_insights_for_concept(&self, concept_name: &str) -> Result<Vec<InsightNode>> {
        let query_str = query(
            "MATCH (c:Concept {name: $name})<-[:CONTAINS]-(i:Insight)
             RETURN i.id as id,
                    coalesce(i.text, i.content) as text,
                    i.source as source,
                    i.timestamp as timestamp,
                    i.confidence as confidence,
                    i.embedding as embedding,
                    i.metadata as metadata
             ORDER BY i.timestamp ASC",
        )
        .param("name", concept_name.to_lowercase());

        let mut result = self.graph.execute(query_str).await?;

        let mut insights = Vec::new();

        while let Some(row) = result.next().await? {
            let id: String = row.get("id")?;
            let text: String = row.get("text")?;
            let source: String = row.get("source")?;
            let timestamp: String = row.get("timestamp")?;
            let confidence: f64 = row.get("confidence")?;
            let embedding: Vec<f32> = row.get("embedding")?;
            let metadata: String = row.get("metadata")?;

            insights.push(InsightNode {
                id: id.parse()?,
                text,
                source: serde_json::from_str(&format!("\"{}\"", source))?,
                timestamp: timestamp.parse()?,
                confidence,
                embedding,
                metadata: serde_json::from_str(&metadata)?,
            });
        }

        Ok(insights)
    }

    /// Create paper node
    pub async fn create_paper(&self, paper: PaperNode) -> Result<()> {
        let create_paper = query(
            "CREATE (p:Paper {
                id: $id,
                title: $title,
                status: $status,
                created_at: datetime($created_at),
                updated_at: datetime($updated_at),
                sections: $sections,
                metadata: $metadata
            })",
        )
        .param("id", paper.id.to_string())
        .param("title", paper.title)
        .param("status", format!("{:?}", paper.status))
        .param("created_at", paper.created_at.to_rfc3339())
        .param("updated_at", paper.updated_at.to_rfc3339())
        .param("sections", serde_json::to_string(&paper.sections)?)
        .param("metadata", serde_json::to_string(&paper.metadata)?);

        self.graph.run(create_paper).await?;

        Ok(())
    }

    /// Link paper to concepts
    pub async fn link_paper_to_concepts(
        &self,
        paper_id: Uuid,
        concepts: Vec<String>,
    ) -> Result<()> {
        for concept in concepts {
            let link_query = query(
                "MATCH (p:Paper {id: $paper_id})
                 MATCH (c:Concept {name: $concept})
                 CREATE (p)-[:COVERS {centrality: 1.0}]->(c)",
            )
            .param("paper_id", paper_id.to_string())
            .param("concept", concept.to_lowercase());

            self.graph.run(link_query).await?;
        }

        Ok(())
    }
}

/// Related concept with relationship metadata
#[derive(Debug, Clone)]
pub struct RelatedConcept {
    pub id: String,
    pub name: String,
    pub domain: String,
    pub strength: f64,
    pub rel_type: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::thought_capture::*;

    #[tokio::test]
    #[ignore] // Requires Neo4j running
    async fn test_store_insight() {
        let client = KnowledgeGraph::new("bolt://localhost:7687", "neo4j", "password")
            .await
            .unwrap();

        let insight = CapturedInsight {
            id: uuid::Uuid::new_v4(),
            text: "KEC entropy affects collagen degradation".to_string(),
            source: InsightSource::Text,
            concepts: vec![
                ExtractedConcept {
                    text: "KEC entropy".to_string(),
                    concept_type: ConceptType::TechnicalTerm,
                    confidence: 0.9,
                    embedding: vec![0.1; 384],
                },
                ExtractedConcept {
                    text: "collagen degradation".to_string(),
                    concept_type: ConceptType::KeyPhrase,
                    confidence: 0.85,
                    embedding: vec![0.2; 384],
                },
            ],
            timestamp: Utc::now(),
            metadata: InsightMetadata {
                location: None,
                context: None,
                confidence: 1.0,
                language: "en".to_string(),
            },
        };

        client.store_insight(&insight).await.unwrap();

        println!("✅ Insight stored successfully");
    }

    #[tokio::test]
    #[ignore] // Requires Neo4j with data
    async fn test_detect_clusters() {
        let client = KnowledgeGraph::new("bolt://localhost:7687", "neo4j", "password")
            .await
            .unwrap();

        let clusters = client.find_concept_clusters(5).await.unwrap();

        println!("\n🔍 Found {} dense clusters:", clusters.len());
        for cluster in clusters {
            println!(
                "  • {} ({} insights)",
                cluster.concept_name, cluster.insight_count
            );
        }
    }
}
