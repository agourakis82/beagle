use super::{evolution::MatchResult, player::ResearchPlayer};
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use std::sync::Arc;
use tracing::info;

pub struct CompetitionArena {
    llm: Arc<AnthropicClient>,
}

impl CompetitionArena {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }

    pub async fn compete(
        &self,
        player1: &ResearchPlayer,
        player2: &ResearchPlayer,
        query: &str,
    ) -> Result<MatchResult> {
        info!("🥊 Arena match: {} vs {}", player1.name, player2.name);

        // Player 1 proposes hypothesis
        let hyp1 = self.generate_hypothesis(player1, query).await?;

        // Player 2 proposes hypothesis
        let hyp2 = self.generate_hypothesis(player2, query).await?;

        // Judge which is better
        let winner = self.judge_hypotheses(&hyp1, &hyp2).await?;

        Ok(MatchResult {
            player1_id: player1.id,
            player2_id: player2.id,
            player1_hypothesis: hyp1,
            player2_hypothesis: hyp2,
            winner,
        })
    }

    async fn generate_hypothesis(&self, player: &ResearchPlayer, query: &str) -> Result<String> {
        let boldness = player.strategy.parameters.get("boldness").unwrap_or(&0.5);

        let prompt = format!(
            "Query: {}\n\
             Strategy: {:?}\n\
             Boldness: {:.2}\n\n\
             Generate ONE research hypothesis.\n\
             Be {} in your proposal.",
            query,
            player.strategy.approach,
            boldness,
            if *boldness > 0.7 {
                "bold and novel"
            } else {
                "conservative and safe"
            }
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 200,
            temperature: *boldness as f32,
            system: None,
        };

        let response = self.llm.complete(request).await?;
        Ok(response.content)
    }

    async fn judge_hypotheses(&self, hyp1: &str, hyp2: &str) -> Result<usize> {
        let prompt = format!(
            "Judge these two research hypotheses:\n\n\
             Hypothesis A:\n{}\n\n\
             Hypothesis B:\n{}\n\n\
             Which is better in terms of:\n\
             1. Novelty\n\
             2. Plausibility\n\
             3. Testability\n\n\
             Output ONLY: A or B",
            hyp1, hyp2
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 10,
            temperature: 0.0,
            system: Some("You are an impartial scientific judge.".to_string()),
        };

        let response = self.llm.complete(request).await?;
        let content = response.content.trim().to_uppercase();

        // Determine winner: 0 = player1 (A), 1 = player2 (B)
        if content.contains("A") && !content.contains("B") {
            Ok(0)
        } else if content.contains("B") && !content.contains("A") {
            Ok(1)
        } else {
            // Tie breaker: random if ambiguous
            Ok(rand::random::<usize>() % 2)
        }
    }
}
