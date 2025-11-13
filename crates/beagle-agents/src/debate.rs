use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DebateTranscript {
    pub query: String,
    pub rounds: Vec<DebateRound>,
    pub synthesis: DebateSynthesis,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DebateRound {
    pub round_number: usize,
    pub proponent_argument: String,
    pub opponent_rebuttal: String,
    pub evidence_cited: Vec<String>,
    pub confidence_shift: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DebateSynthesis {
    pub conclusion: String,
    pub proponent_strength: f32,
    pub opponent_strength: f32,
    pub final_confidence: f32,
    pub key_disagreements: Vec<String>,
}

pub struct DebateOrchestrator {
    llm: Arc<AnthropicClient>,
    max_rounds: usize,
}

impl DebateOrchestrator {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm, max_rounds: 3 }
    }

    pub async fn conduct_debate(&self, query: &str) -> Result<DebateTranscript> {
        let start = Instant::now();

        info!("🥊 Starting adversarial debate on: {}", query);

        let mut rounds = Vec::new();
        let mut confidence = 0.5_f32;

        for round in 1..=self.max_rounds {
            info!("Round {}/{}", round, self.max_rounds);

            let proponent_arg = self.generate_argument(query, "PROPONENT", &rounds).await?;
            let opponent_arg = self.generate_argument(query, "OPPONENT", &rounds).await?;
            let shift = self
                .evaluate_arguments(&proponent_arg, &opponent_arg)
                .await?;

            confidence = (confidence + shift).clamp(0.0, 1.0);

            rounds.push(DebateRound {
                round_number: round,
                proponent_argument: proponent_arg,
                opponent_rebuttal: opponent_arg,
                evidence_cited: vec![],
                confidence_shift: shift,
            });
        }

        let synthesis = self.synthesize_debate(query, &rounds, confidence).await?;

        Ok(DebateTranscript {
            query: query.to_string(),
            rounds,
            synthesis,
            duration_ms: start.elapsed().as_millis() as u64,
        })
    }

    async fn generate_argument(
        &self,
        query: &str,
        role: &str,
        previous_rounds: &[DebateRound],
    ) -> Result<String> {
        let context = if previous_rounds.is_empty() {
            String::new()
        } else {
            let history = previous_rounds
                .iter()
                .map(|r| {
                    format!(
                        "Round {}: Pro: {} | Con: {}",
                        r.round_number, r.proponent_argument, r.opponent_rebuttal
                    )
                })
                .collect::<Vec<_>>()
                .join("\n");

            format!("\n\nPrevious debate:\n{}", history)
        };

        let system = match role {
            "PROPONENT" => format!(
                "You are a scientific advocate arguing FOR the position in the query. \
                 Use evidence, logic, and scientific reasoning. Be rigorous but persuasive.{}",
                context
            ),
            "OPPONENT" => format!(
                "You are a critical skeptic arguing AGAINST the position in the query. \
                 Point out limitations, alternative explanations, and methodological issues. \
                 Be rigorous and use devil's advocate reasoning.{}",
                context
            ),
            _ => {
                debug!("Unknown role `{}` provided to generate_argument", role);
                context
            }
        };

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(query.to_string())],
            max_tokens: 500,
            temperature: 0.7,
            system: Some(system),
        };

        let response = self.llm.complete(request).await?;

        Ok(response.content)
    }

    async fn evaluate_arguments(&self, pro: &str, con: &str) -> Result<f32> {
        let prompt = format!(
            "Proponent: {}\n\nOpponent: {}\n\n\
             Which argument is stronger? Rate from -1.0 (opponent much stronger) \
             to +1.0 (proponent much stronger). Output ONLY the number.",
            pro, con
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 10,
            temperature: 0.0,
            system: Some("You are an impartial judge.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        let score = response.content.trim().parse::<f32>().unwrap_or(0.0);

        Ok(score * 0.2)
    }

    async fn synthesize_debate(
        &self,
        query: &str,
        rounds: &[DebateRound],
        final_confidence: f32,
    ) -> Result<DebateSynthesis> {
        let debate_summary = rounds
            .iter()
            .map(|r| {
                format!(
                    "Round {}: Pro: {} | Con: {}",
                    r.round_number, r.proponent_argument, r.opponent_rebuttal
                )
            })
            .collect::<Vec<_>>()
            .join("\n\n");

        let prompt = format!(
            "Query: {}\n\nDebate:\n{}\n\n\
             Synthesize a balanced conclusion considering both perspectives. \
             Be nuanced and acknowledge uncertainties.",
            query, debate_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 800,
            temperature: 0.5,
            system: Some("You are a scientific judge synthesizing a debate.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        Ok(DebateSynthesis {
            conclusion: response.content,
            proponent_strength: (final_confidence * 2.0 - 1.0).max(0.0),
            opponent_strength: (1.0 - final_confidence).max(0.0),
            final_confidence,
            key_disagreements: vec![],
        })
    }
}
