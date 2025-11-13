use anyhow::Result;
use beagle_hypergraph::{CachedPostgresStorage, ContentType, Node, StorageRepository};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReasoningPath {
    pub nodes: Vec<PathNode>,
    pub confidence: f32,
    pub reasoning_type: ReasoningType,
    pub explanation: String,
    pub hops: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathNode {
    pub id: Uuid,
    pub label: String,
    pub node_type: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ReasoningType {
    Causal,
    Correlational,
    Temporal,
    Compositional,
}

pub struct HypergraphReasoner {
    storage: Arc<CachedPostgresStorage>,
    llm: Arc<AnthropicClient>,
}

impl HypergraphReasoner {
    pub fn new(storage: Arc<CachedPostgresStorage>, llm: Arc<AnthropicClient>) -> Self {
        Self { storage, llm }
    }

    /// Find reasoning paths between concepts in the hypergraph.
    pub async fn find_reasoning_paths(
        &self,
        source_query: &str,
        target_query: &str,
        max_hops: usize,
    ) -> Result<Vec<ReasoningPath>> {
        info!("🕸️ Finding paths: '{}' → '{}'", source_query, target_query);

        let source_nodes = self.find_or_create_concept_nodes(source_query).await?;
        let target_nodes = self.find_or_create_concept_nodes(target_query).await?;

        if source_nodes.is_empty() || target_nodes.is_empty() {
            return Ok(vec![]);
        }

        let mut all_paths = Vec::new();

        for source in &source_nodes {
            for target in &target_nodes {
                let paths = self.bfs_paths(source.id, target.id, max_hops).await?;
                all_paths.extend(paths);
            }
        }

        all_paths.sort_by(|a, b| b.confidence.partial_cmp(&a.confidence).unwrap());
        all_paths.truncate(5);

        for path in &mut all_paths {
            path.explanation = self.explain_path(path, source_query, target_query).await?;
        }

        info!("✅ Found {} reasoning paths", all_paths.len());

        Ok(all_paths)
    }

    /// Search existing nodes or create a new concept node when none are available.
    async fn find_or_create_concept_nodes(&self, query: &str) -> Result<Vec<PathNode>> {
        let query_lower = query.to_lowercase();
        let nodes = self.storage.list_nodes(None).await?;
        let mut matches = nodes
            .iter()
            .filter(|node| node.content.to_lowercase().contains(&query_lower))
            .take(3)
            .map(|node| PathNode::from(node.clone()))
            .collect::<Vec<_>>();

        if matches.is_empty() {
            let new_node = Node::builder()
                .content(query)
                .content_type(ContentType::Context)
                .metadata(json!({
                    "source": "hypergraph_reasoner",
                    "query": query,
                }))
                .device_id("hypergraph-reasoner")
                .build()?;

            let created = self.storage.create_node(new_node).await?;
            matches.push(PathNode::from(created));
        }

        Ok(matches)
    }

    /// Breadth-first search to find reasoning paths between nodes.
    async fn bfs_paths(
        &self,
        source_id: Uuid,
        target_id: Uuid,
        max_hops: usize,
    ) -> Result<Vec<ReasoningPath>> {
        let mut paths = Vec::new();
        let mut queue = VecDeque::new();
        let mut visited = HashSet::new();

        queue.push_back((source_id, vec![source_id], 1.0_f32));

        while let Some((current_id, path, confidence)) = queue.pop_front() {
            if path.len() > max_hops + 1 {
                continue;
            }

            if current_id == target_id {
                let path_nodes = self.load_path_nodes(&path).await?;

                paths.push(ReasoningPath {
                    nodes: path_nodes,
                    confidence,
                    reasoning_type: self.infer_reasoning_type(&path).await,
                    explanation: String::new(),
                    hops: path.len().saturating_sub(1),
                });
                continue;
            }

            if !visited.insert(current_id) {
                continue;
            }

            let edges = self.storage.get_edges_for_node(current_id).await?;

            for edge in edges {
                for neighbor_id in edge.node_ids {
                    if neighbor_id != current_id && !path.contains(&neighbor_id) {
                        let mut new_path = path.clone();
                        new_path.push(neighbor_id);
                        let new_confidence = confidence * 0.9;
                        queue.push_back((neighbor_id, new_path, new_confidence));
                    }
                }
            }
        }

        Ok(paths)
    }

    /// Load full node information for a given reasoning path.
    async fn load_path_nodes(&self, node_ids: &[Uuid]) -> Result<Vec<PathNode>> {
        let nodes = self.storage.batch_get_nodes(node_ids.to_vec()).await?;
        let map: HashMap<Uuid, Node> = nodes.into_iter().map(|node| (node.id, node)).collect();

        let mut ordered = Vec::with_capacity(node_ids.len());
        for id in node_ids {
            if let Some(node) = map.get(id) {
                ordered.push(PathNode::from(node.clone()));
            }
        }

        Ok(ordered)
    }

    /// Infer reasoning type from path structure.
    async fn infer_reasoning_type(&self, _path: &[Uuid]) -> ReasoningType {
        // TODO: Inspect hyperedge metadata to refine classification.
        ReasoningType::Causal
    }

    /// Generate natural language explanation for a reasoning path via LLM.
    async fn explain_path(
        &self,
        path: &ReasoningPath,
        source: &str,
        target: &str,
    ) -> Result<String> {
        let path_description = path
            .nodes
            .iter()
            .map(|node| format!("{} ({})", node.label, node.node_type))
            .collect::<Vec<_>>()
            .join(" → ");

        let prompt = format!(
            "Explain this reasoning path from '{}' to '{}':\n\n\
             Path: {}\n\n\
             Reasoning type: {:?}\n\
             Confidence: {:.2}\n\n\
             Provide a concise explanation (2-3 sentences) of how these concepts are related.",
            source, target, path_description, path.reasoning_type, path.confidence
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 200,
            temperature: 0.5,
            system: Some(
                "You are an expert at explaining scientific reasoning chains.".to_string(),
            ),
        };

        let response = self.llm.complete(request).await?;

        Ok(response.content)
    }

    /// Render reasoning paths as ASCII visualization.
    pub fn visualize_paths(&self, paths: &[ReasoningPath]) -> String {
        let mut output = String::new();
        output.push_str("╔════════════════════════════════════════════════════════════╗\n");
        output.push_str("║  REASONING PATHS                                           ║\n");
        output.push_str("╚════════════════════════════════════════════════════════════╝\n\n");

        for (index, path) in paths.iter().enumerate() {
            output.push_str(&format!(
                "Path {} (confidence: {:.2}, hops: {}):\n",
                index + 1,
                path.confidence,
                path.hops
            ));

            for (step, node) in path.nodes.iter().enumerate() {
                output.push_str(&format!("  [{}] {}\n", step + 1, node.label));

                if step < path.nodes.len() - 1 {
                    output.push_str("   |\n");
                    output.push_str("   v\n");
                }
            }

            output.push_str(&format!("\nExplanation: {}\n\n", path.explanation));
        }

        output
    }
}

impl From<Node> for PathNode {
    fn from(node: Node) -> Self {
        let label = node.content.chars().take(80).collect::<String>();
        Self {
            id: node.id,
            label,
            node_type: node.content_type.to_string(),
        }
    }
}
