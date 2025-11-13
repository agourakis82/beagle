use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Extracts logical predicates from natural language using LLM
pub struct NeuralExtractor {
    llm: Arc<AnthropicClient>,
}

impl NeuralExtractor {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }
    
    pub async fn extract_predicates(&self, text: &str) -> Result<Vec<Predicate>> {
        let prompt = format!(
            "Extract logical predicates from this text:\n\n\"{}\"\n\n\
             Format as JSON array:\n\
             [{{\n  \
               \"predicate\": \"increases\",\n  \
               \"subject\": \"ssri\",\n  \
               \"object\": \"serotonin\",\n  \
               \"confidence\": 0.9\n\
             }}]\n\n\
             Only include clear logical relationships. Output ONLY valid JSON.",
            text
        );
        
        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 1500,
            temperature: 0.1,
            system: Some("You extract formal logical predicates from natural language.".to_string()),
        };
        
        let response = self.llm.complete(request).await?;
        
        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content.lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };
        
        let predicates: Vec<Predicate> = serde_json::from_str(&json_content)
            .unwrap_or_else(|_| vec![]);
        
        Ok(predicates)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Predicate {
    pub predicate: String,
    pub subject: String,
    pub object: String,
    pub confidence: f64,
}

