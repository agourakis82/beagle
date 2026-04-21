use super::{analyzer::FailurePattern, evolver::AgentSpecification};
use crate::causal::AgentLlmClient;
use anyhow::Result;
use std::sync::Arc;

pub struct SpecializedAgentFactory {
    llm: Arc<dyn AgentLlmClient>,
}

impl SpecializedAgentFactory {
    pub fn new(llm: Arc<dyn AgentLlmClient>) -> Self {
        Self { llm }
    }

    pub async fn create_for_pattern(&self, pattern: &FailurePattern) -> Result<AgentSpecification> {
        let prompt = format!(
            "Design a specialized AI agent to handle this failure pattern:\n\n\
             Pattern: {}\n\
             Description: {}\n\
             Recommended fix: {}\n\n\
             Provide:\n\
             1. Agent name (concise, descriptive)\n\
             2. Core capability (one sentence)\n\
             3. System prompt (detailed instructions for the agent)\n\
             4. Recommended model type (haiku/sonnet)\n\n\
             Format as JSON:\n\
             {{\n  \
               \"name\": \"...\",\n  \
               \"capability\": \"...\",\n  \
               \"system_prompt\": \"...\",\n  \
               \"model_type\": \"...\"\n\
             }}",
            pattern.pattern_type, pattern.description, pattern.recommended_fix
        );

        let system = "You are an expert at designing specialized AI agents.";
        let response = self.llm.complete_with_system(&prompt, system).await?;

        #[derive(serde::Deserialize)]
        struct AgentData {
            name: String,
            capability: String,
            system_prompt: String,
            model_type: String,
        }

        let data: AgentData = serde_json::from_str(response.trim()).unwrap_or(AgentData {
            name: "GeneralAgent".to_string(),
            capability: "General purpose reasoning".to_string(),
            system_prompt: "You are a helpful AI assistant.".to_string(),
            model_type: "haiku".to_string(),
        });

        Ok(AgentSpecification {
            name: data.name,
            capability: data.capability,
            system_prompt: data.system_prompt,
            model_type: data.model_type,
        })
    }
}
