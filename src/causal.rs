use anyhow::Result;

use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};

use serde::{Deserialize, Serialize};

use std::sync::Arc;

use tracing::info;



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

    llm: Arc<AnthropicClient>,

}



impl CausalReasoner {

    pub fn new(llm: Arc<AnthropicClient>) -> Self {

        Self { llm }

    }

    

    /// Extract causal graph from scientific text

    pub async fn extract_causal_graph(&self, text: &str) -> Result<CausalGraph> {

        info!("🔗 Extracting causal graph from text ({} chars)", text.len());

        

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

        

        let request = CompletionRequest {

            model: ModelType::ClaudeSonnet45,

            messages: vec![Message::user(prompt)],

            max_tokens: 2000,

            temperature: 0.2,

            system: Some(

                "You are a causal inference expert trained in Pearl's causal calculus. \

                 Only extract genuine causal relationships with empirical evidence. \

                 Be conservative and rigorous.".to_string()

            ),

        };

        

        let response = self.llm.complete(request).await?;

        

        // Parse JSON

        let content = response.content.trim();

        let json_content = if content.starts_with("```") {

            // Strip markdown if present

            content.lines()

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

        

        let data: GraphData = serde_json::from_str(&json_content)

            .unwrap_or(GraphData {

                nodes: vec![],

                edges: vec![],

            });

        

        info!("✅ Extracted {} nodes, {} edges", data.nodes.len(), data.edges.len());

        

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

        

        let request = CompletionRequest {

            model: ModelType::ClaudeSonnet45,

            messages: vec![Message::user(prompt)],

            max_tokens: 1000,

            temperature: 0.3,

            system: Some("You are a causal inference expert using Pearl's do-calculus.".to_string()),

        };

        

        let response = self.llm.complete(request).await?;

        

        Ok(InterventionResult {

            intervention: format!("do({} = {})", variable, value),

            target_variable: variable.to_string(),

            predicted_effect: response.content,

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

        info!("🔄 Counterfactual: {} = {} vs {}", variable, actual_value, counterfactual_value);

        

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

            variable, actual_value,

            graph_json,

            variable, counterfactual_value,

            variable, counterfactual_value

        );

        

        let request = CompletionRequest {

            model: ModelType::ClaudeSonnet45,

            messages: vec![Message::user(prompt)],

            max_tokens: 800,

            temperature: 0.3,

            system: Some("You are a causal inference expert using Pearl's counterfactual reasoning.".to_string()),

        };

        

        let response = self.llm.complete(request).await?;

        

        Ok(CounterfactualResult {

            original_scenario: format!("{} = {}", variable, actual_value),

            counterfactual_scenario: format!("{} = {}", variable, counterfactual_value),

            predicted_outcome: response.content,

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

            output.push_str(&format!("  [{}] {} ({:?})\n", 

                                    node.id, node.label, node.node_type));

        }

        

        output.push_str("\nCausal Edges:\n");

        for edge in &graph.edges {

            output.push_str(&format!(

                "  {} --[{:?}, strength: {:.2}]--> {}\n",

                edge.from, edge.edge_type, edge.strength, edge.to

            ));

            

            if !edge.confounders.is_empty() {

                output.push_str(&format!("    Confounders: {}\n", edge.confounders.join(", ")));

            }

        }

        

        output.push_str(&format!("\nConfidence: {:.2}\n", graph.metadata.confidence));

        output.push_str(&format!("Limitations: {}\n", graph.metadata.limitations.join("; ")));

        

        output

    }

}

use anyhow::Result;

use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};

use serde::{Deserialize, Serialize};

use std::collections::HashMap;

use std::sync::Arc;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalGraph {
    pub nodes: Vec<CausalNode>,
    pub edges: Vec<CausalEdge>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalNode {
    pub id: String,
    pub label: String,
    pub node_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalEdge {
    pub from: String,
    pub to: String,
    pub strength: f32,
    pub evidence: Vec<String>,
    pub confounders: Vec<String>,
}

pub struct CausalReasoner {
    llm: Arc<AnthropicClient>,
}

impl CausalReasoner {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }

    pub async fn extract_causal_graph(&self, text: &str) -> Result<CausalGraph> {
        let prompt = format!(
            "Extract causal relationships from this text:\n\n{}\n\n\
             Return a JSON with format:\n\
             {{\n  \
               \"nodes\": [{{\"id\": \"A\", \"label\": \"...\"}}, ...],\n  \
               \"edges\": [{{\"from\": \"A\", \"to\": \"B\", \"strength\": 0.8}}, ...]\n\
             }}",
            text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.3,
            system: Some("You are a causal inference expert. Extract only genuine causal relationships, not correlations.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        // Parse JSON (simplified)
        let graph: CausalGraph = serde_json::from_str(&response.content).unwrap_or(CausalGraph {
            nodes: vec![],
            edges: vec![],
        });

        Ok(graph)
    }

    pub async fn intervention(&self, graph: &CausalGraph, var: &str, value: f32) -> Result<String> {
        let prompt = format!(
            "Given this causal graph:\n{:?}\n\n\
             What would happen if we intervene and set {} = {}?\n\
             Use do-calculus reasoning.",
            graph, var, value
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: 1000,
            temperature: 0.5,
            system: Some("You are a causal inference expert using Pearl's do-calculus.".to_string()),
        };

        let response = self.llm.complete(request).await?;
        Ok(response.content)
    }
}

