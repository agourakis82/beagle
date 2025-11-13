use super::{agent::SwarmAgent, emergence::EmergentBehavior, pheromone::PheromoneField};
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use std::sync::Arc;
use tracing::{debug, info};

/// Swarm orchestrator (minimal coordination)
pub struct SwarmOrchestrator {
    agents: Vec<SwarmAgent>,
    field: PheromoneField,
    llm: Arc<AnthropicClient>,
    max_iterations: usize,
}

impl SwarmOrchestrator {
    pub fn new(n_agents: usize, llm: Arc<AnthropicClient>) -> Self {
        let agents = (0..n_agents).map(|_| SwarmAgent::new()).collect();

        Self {
            agents,
            field: PheromoneField::new(0.05),
            llm,
            max_iterations: 50,
        }
    }

    /// Run swarm to explore hypothesis space
    pub async fn explore(&mut self, query: &str) -> Result<SwarmResult> {
        info!("🐝 Swarm exploration started: {} agents", self.agents.len());

        let mut convergence_history = Vec::new();

        for iteration in 0..self.max_iterations {
            debug!("Swarm iteration {}/{}", iteration + 1, self.max_iterations);

            // Each agent acts independently
            for i in 0..self.agents.len() {
                // Explore based on pheromones
                let concept = if let Some(c) = self.agents[i].explore(&self.field) {
                    c
                } else {
                    // Random exploration
                    self.generate_concept(query, iteration).await?
                };

                // Evaluate concept
                let evidence = self.evaluate_concept(&concept).await?;

                // Update belief
                self.agents[i].update_belief(&concept, evidence);

                // Deposit pheromone if confident
                if self.agents[i].should_deposit(&concept) {
                    let pheromone = self.agents[i].deposit_pheromone(concept.clone());
                    self.field.deposit(pheromone);
                }

                // Energy management
                self.agents[i].consume_energy(0.05);
                if self.agents[i].energy < 0.1 {
                    self.agents[i].restore_energy(0.5);
                }
            }

            // Evaporate pheromones
            self.field.evaporate_all();

            // Check for convergence
            let behavior = self.detect_emergence();
            convergence_history.push(behavior.clone());

            if behavior.has_converged {
                info!("✅ Swarm converged at iteration {}", iteration);
                break;
            }
        }

        // Extract consensus
        let consensus = self.extract_consensus();

        Ok(SwarmResult {
            consensus,
            iterations: convergence_history.len(),
            emergent_behavior: convergence_history.last().unwrap().clone(),
            n_agents: self.agents.len(),
        })
    }

    async fn generate_concept(&self, query: &str, iteration: usize) -> Result<String> {
        let prompt = format!(
            "Query: {}\nIteration: {}\n\
             Generate ONE novel concept or hypothesis (one sentence):",
            query, iteration
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 100,
            temperature: 0.9,
            system: None,
        };

        let response = self.llm.complete(request).await?;
        Ok(response.content.trim().to_string())
    }

    async fn evaluate_concept(&self, concept: &str) -> Result<f64> {
        // Simplified evaluation via LLM
        let prompt = format!(
            "Rate this scientific concept from 0.0 (implausible) to 1.0 (highly plausible):\n\
             \"{}\"\n\
             Output ONLY a number:",
            concept
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 10,
            temperature: 0.0,
            system: None,
        };

        let response = self.llm.complete(request).await?;
        let score = response.content.trim().parse::<f64>().unwrap_or(0.5);

        Ok(score.clamp(0.0, 1.0))
    }

    fn detect_emergence(&self) -> EmergentBehavior {
        // Check if agents have converged on similar beliefs
        let mut concept_strengths: std::collections::HashMap<String, f64> =
            std::collections::HashMap::new();

        for agent in &self.agents {
            for (concept, &belief) in &agent.beliefs {
                *concept_strengths.entry(concept.clone()).or_insert(0.0) += belief;
            }
        }

        let max_strength = concept_strengths
            .values()
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(&0.0);

        let has_converged = *max_strength > (self.agents.len() as f64 * 0.6);

        EmergentBehavior {
            has_converged,
            dominant_concept: concept_strengths
                .iter()
                .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
                .map(|(k, _)| k.clone()),
            consensus_strength: *max_strength / self.agents.len() as f64,
        }
    }

    fn extract_consensus(&self) -> Vec<String> {
        let mut concept_votes: std::collections::HashMap<String, usize> =
            std::collections::HashMap::new();

        for agent in &self.agents {
            for (concept, &belief) in &agent.beliefs {
                if belief > 0.6 {
                    *concept_votes.entry(concept.clone()).or_insert(0) += 1;
                }
            }
        }

        let mut consensus: Vec<_> = concept_votes.into_iter().collect();
        consensus.sort_by(|a, b| b.1.cmp(&a.1));

        consensus
            .into_iter()
            .take(5)
            .map(|(concept, _)| concept)
            .collect()
    }
}

#[derive(Debug, Clone)]
pub struct SwarmResult {
    pub consensus: Vec<String>,
    pub iterations: usize,
    pub emergent_behavior: EmergentBehavior,
    pub n_agents: usize,
}


