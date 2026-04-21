use anyhow::Result;
use async_trait::async_trait;

use serde::{Deserialize, Serialize};
use serde_json;

use std::sync::Arc;

use tracing::info;

/// Trait for LLM clients that can be used by agents
#[async_trait]
pub trait AgentLlmClient: Send + Sync {
    /// Complete a prompt and return the response text
    async fn complete(&self, prompt: &str) -> Result<String>;
    /// Complete with system prompt
    async fn complete_with_system(&self, prompt: &str, system: &str) -> Result<String>;
}

// Implement AgentLlmClient for Arc<dyn AgentLlmClient>
#[async_trait]
impl AgentLlmClient for Arc<dyn AgentLlmClient> {
    async fn complete(&self, prompt: &str) -> Result<String> {
        self.as_ref().complete(prompt).await
    }
    async fn complete_with_system(&self, prompt: &str, system: &str) -> Result<String> {
        self.as_ref().complete_with_system(prompt, system).await
    }
}

// Implement AgentLlmClient for Arc<T> where T: AgentLlmClient
#[async_trait]
impl<T: AgentLlmClient + Send + Sync> AgentLlmClient for Arc<T> {
    async fn complete(&self, prompt: &str) -> Result<String> {
        self.as_ref().complete(prompt).await
    }
    async fn complete_with_system(&self, prompt: &str, system: &str) -> Result<String> {
        self.as_ref().complete_with_system(prompt, system).await
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CausalGraph {
    pub nodes: Vec<CausalNode>,

    pub edges: Vec<CausalEdge>,

    pub metadata: CausalMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CausalNode {
    pub id: String,

    pub label: String,

    pub node_type: NodeType,

    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub enum NodeType {
    Variable,

    Intervention,

    Outcome,

    Confounder,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CausalEdge {
    pub from: String,

    pub to: String,

    pub strength: f32,

    pub edge_type: CausalEdgeType,

    pub evidence: Vec<String>,

    pub confounders: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub enum CausalEdgeType {
    DirectCause,

    IndirectCause,

    Mediator,

    Moderator,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CausalMetadata {
    pub source_text: String,

    pub confidence: f32,

    pub limitations: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct InterventionResult {
    pub intervention: String,

    pub target_variable: String,

    pub predicted_effect: String,

    pub effect_size: f32,

    pub confidence: f32,

    pub causal_mechanism: String,

    pub assumptions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CounterfactualResult {
    pub original_scenario: String,

    pub counterfactual_scenario: String,

    pub predicted_outcome: String,

    pub confidence: f32,
}

pub struct CausalReasoner {
    llm: Arc<dyn AgentLlmClient>,
}

impl CausalReasoner {
    pub fn new(llm: Arc<dyn AgentLlmClient>) -> Self {
        Self { llm }
    }

    /// Extract causal graph from scientific text

    pub async fn extract_causal_graph(&self, text: &str) -> Result<CausalGraph> {
        info!(
            "🔗 Extracting causal graph from text ({} chars)",
            text.len()
        );

        let prompt = format!(

            "Extract CAUSAL relationships (not just correlations) from this scientific text:\n\n\

             {}\n\n\

             Return a JSON with this exact format:\n\

             {{\n  \

               \"nodes\": [\n    \

                 {{\"id\": \"A\", \"label\": \"Variable A\", \"node_type\": \"Variable\", \"description\": \"...\"}}\n  \

               ],\n  \

               \"edges\": [\n    \

                 {{\"from\": \"A\", \"to\": \"B\", \"strength\": 0.8, \"edge_type\": \"DirectCause\", \"evidence\": [\"study X\"], \"confounders\": [\"C\"]}}\n  \

               ]\n\

             }}\n\n\

             Only include relationships with causal evidence (RCTs, mechanistic studies, interventions).\n\

             Strength: 0.0 (weak) to 1.0 (strong).\n\

             Output ONLY valid JSON, no markdown.",

            text

        );

        let system = "You are a causal inference expert trained in Pearl's causal calculus. \
                 Only extract genuine causal relationships with empirical evidence. \
                 Be conservative and rigorous.";

        let response = self.llm.complete_with_system(&prompt, system).await?;

        // Parse JSON

        let content = response.trim();

        let json_content = if content.starts_with("```") {
            // Strip markdown if present

            content
                .lines()
                .skip_while(|l| l.starts_with("```"))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        #[derive(Deserialize)]

        struct GraphData {
            nodes: Vec<CausalNode>,

            edges: Vec<CausalEdge>,
        }

        let data: GraphData = serde_json::from_str(&json_content).unwrap_or(GraphData {
            nodes: vec![],

            edges: vec![],
        });

        info!(
            "✅ Extracted {} nodes, {} edges",
            data.nodes.len(),
            data.edges.len()
        );

        Ok(CausalGraph {
            nodes: data.nodes,

            edges: data.edges,

            metadata: CausalMetadata {
                source_text: text.chars().take(200).collect(),

                confidence: 0.7,

                limitations: vec![
                    "Extracted from observational text".to_string(),
                    "Requires experimental validation".to_string(),
                ],
            },
        })
    }

    /// Perform causal intervention: do(X = x)

    pub async fn intervention(
        &self,

        graph: &CausalGraph,

        variable: &str,

        value: &str,
    ) -> Result<InterventionResult> {
        info!("🔬 Simulating intervention: do({} = {})", variable, value);

        let graph_json = serde_json::to_string_pretty(graph)?;

        let prompt = format!(
            "Given this causal graph:\n\n\

             {}\n\n\

             Predict the effect of the intervention: do({} = {})\n\n\

             Use Pearl's do-calculus. Consider:\n\

             1. Direct causal pathways from {} to outcomes\n\

             2. Backdoor paths that need blocking\n\

             3. Confounders and their effects\n\

             4. Effect size estimation\n\n\

             Provide:\n\

             - Predicted effect on each outcome variable\n\

             - Effect size (small/medium/large)\n\

             - Causal mechanism explanation\n\

             - Key assumptions",
            graph_json, variable, value, variable
        );

        let system = "You are a causal inference expert using Pearl's do-calculus.";

        let response = self.llm.complete_with_system(&prompt, system).await?;

        Ok(InterventionResult {
            intervention: format!("do({} = {})", variable, value),

            target_variable: variable.to_string(),

            predicted_effect: response,

            effect_size: 0.5, // TODO: Extract from response

            confidence: 0.7,

            causal_mechanism: "See predicted effect".to_string(),

            assumptions: vec![
                "No unmeasured confounding".to_string(),
                "Graph structure is correct".to_string(),
            ],
        })
    }

    /// Counterfactual reasoning: what if NOT X?

    pub async fn counterfactual(
        &self,

        graph: &CausalGraph,

        variable: &str,

        actual_value: &str,

        counterfactual_value: &str,
    ) -> Result<CounterfactualResult> {
        info!(
            "🔄 Counterfactual: {} = {} vs {}",
            variable, actual_value, counterfactual_value
        );

        let graph_json = serde_json::to_string_pretty(graph)?;

        let prompt = format!(
            "Given this causal graph and observed outcome with {} = {}:\n\n\

             {}\n\n\

             What would have happened if instead {} = {}?\n\n\

             Use Pearl's counterfactual reasoning (3-step process):\n\

             1. Abduction: Update beliefs based on observed evidence\n\

             2. Action: Intervene to set {} = {}\n\

             3. Prediction: Compute counterfactual outcome\n\n\

             Be specific about which outcomes would change and by how much.",
            variable,
            actual_value,
            graph_json,
            variable,
            counterfactual_value,
            variable,
            counterfactual_value
        );

        let system = "You are a causal inference expert using Pearl's counterfactual reasoning.";

        let response = self.llm.complete_with_system(&prompt, system).await?;

        Ok(CounterfactualResult {
            original_scenario: format!("{} = {}", variable, actual_value),

            counterfactual_scenario: format!("{} = {}", variable, counterfactual_value),

            predicted_outcome: response,

            confidence: 0.6,
        })
    }

    /// Visualize causal graph as ASCII art

    pub fn visualize_graph(&self, graph: &CausalGraph) -> String {
        let mut output = String::new();

        output.push_str("╔════════════════════════════════════════════════════════════╗\n");

        output.push_str("║  CAUSAL GRAPH                                              ║\n");

        output.push_str("╚════════════════════════════════════════════════════════════╝\n\n");

        output.push_str("Nodes:\n");

        for node in &graph.nodes {
            output.push_str(&format!(
                "  [{}] {} ({:?})\n",
                node.id, node.label, node.node_type
            ));
        }

        output.push_str("\nCausal Edges:\n");

        for edge in &graph.edges {
            output.push_str(&format!(
                "  {} --[{:?}, strength: {:.2}]--> {}\n",
                edge.from, edge.edge_type, edge.strength, edge.to
            ));

            if !edge.confounders.is_empty() {
                output.push_str(&format!(
                    "    Confounders: {}\n",
                    edge.confounders.join(", ")
                ));
            }
        }

        output.push_str(&format!("\nConfidence: {:.2}\n", graph.metadata.confidence));

        output.push_str(&format!(
            "Limitations: {}\n",
            graph.metadata.limitations.join("; ")
        ));

        output
    }
}
