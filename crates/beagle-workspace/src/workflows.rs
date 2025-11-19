//! Agentic Workflows - ReAct + Reflexion
//! Integrado com beagle-agents

use anyhow::Result;
use beagle_darwin::DarwinCore;
use tracing::info;

pub struct ResearchWorkflow {
    darwin: DarwinCore,
}

impl ResearchWorkflow {
    pub fn new() -> Self {
        info!("🤖 ResearchWorkflow inicializado");
        Self {
            darwin: DarwinCore::new(),
        }
    }

    pub async fn run(&self, question: &str) -> Result<String> {
        info!("🔬 Executando workflow de pesquisa: {}", question);
        
        let initial = self.darwin.graph_rag_query(question).await;
        let refined = self.darwin.self_rag(&initial, question).await;
        
        Ok(refined)
    }
}

impl Default for ResearchWorkflow {
    fn default() -> Self {
        Self::new()
    }
}
