use super::{evolution::MatchResult, player::ResearchPlayer};
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

/// Tournament format
#[derive(Debug, Clone, Copy)]
pub enum TournamentFormat {
    RoundRobin, // All vs all
    Swiss,      // Swiss system pairing
    SingleElim, // Single elimination bracket
}

/// Tournament result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TournamentResult {
    pub format: String,
    pub rounds: usize,
    pub matches: Vec<MatchResult>,
    pub final_standings: Vec<StandingEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StandingEntry {
    pub player_name: String,
    pub wins: usize,
    pub losses: usize,
    pub elo_rating: f64,
    pub rank: usize,
}

pub struct CompetitionArena {
    llm: Arc<AnthropicClient>,
    tournament_format: TournamentFormat,
}

impl CompetitionArena {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self {
            llm,
            tournament_format: TournamentFormat::Swiss,
        }
    }

    pub fn with_format(llm: Arc<AnthropicClient>, format: TournamentFormat) -> Self {
        Self {
            llm,
            tournament_format: format,
        }
    }

    /// Run a full tournament with multiple players
    pub async fn run_tournament(
        &self,
        players: &mut [ResearchPlayer],
        query: &str,
        rounds: usize,
    ) -> Result<TournamentResult> {
        info!(
            "🏆 Starting tournament with {} players, {} rounds",
            players.len(),
            rounds
        );

        let mut all_matches = Vec::new();

        match self.tournament_format {
            TournamentFormat::Swiss => {
                all_matches = self.run_swiss_tournament(players, query, rounds).await?;
            }
            TournamentFormat::RoundRobin => {
                all_matches = self.run_round_robin(players, query).await?;
            }
            TournamentFormat::SingleElim => {
                all_matches = self.run_single_elimination(players, query).await?;
            }
        }

        // Generate final standings
        let mut standings: Vec<StandingEntry> = players
            .iter()
            .map(|p| StandingEntry {
                player_name: p.name.clone(),
                wins: p.wins,
                losses: p.losses,
                elo_rating: p.elo_rating,
                rank: 0,
            })
            .collect();

        // Sort by ELO
        standings.sort_by(|a, b| {
            b.elo_rating
                .partial_cmp(&a.elo_rating)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        // Assign ranks
        for (i, standing) in standings.iter_mut().enumerate() {
            standing.rank = i + 1;
        }

        Ok(TournamentResult {
            format: format!("{:?}", self.tournament_format),
            rounds: all_matches.len(),
            matches: all_matches,
            final_standings: standings,
        })
    }

    /// Swiss system tournament - pair players with similar records
    async fn run_swiss_tournament(
        &self,
        players: &mut [ResearchPlayer],
        query: &str,
        rounds: usize,
    ) -> Result<Vec<MatchResult>> {
        let mut all_matches = Vec::new();

        for round in 0..rounds {
            info!("Round {}/{}", round + 1, rounds);

            // Sort by current ELO for Swiss pairing
            players.sort_by(|a, b| {
                b.elo_rating
                    .partial_cmp(&a.elo_rating)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });

            // Pair adjacent players (similar skill levels)
            for i in (0..players.len()).step_by(2) {
                if i + 1 < players.len() {
                    let result = self.compete(&players[i], &players[i + 1], query).await?;

                    // Update ELO ratings
                    let p1_elo = players[i].elo_rating;
                    let p2_elo = players[i + 1].elo_rating;

                    if result.winner == 0 {
                        players[i].record_win(p2_elo);
                        players[i + 1].record_loss(p1_elo);
                    } else {
                        players[i + 1].record_win(p1_elo);
                        players[i].record_loss(p2_elo);
                    }

                    all_matches.push(result);
                }
            }
        }

        Ok(all_matches)
    }

    /// Round-robin tournament - everyone plays everyone
    async fn run_round_robin(
        &self,
        players: &mut [ResearchPlayer],
        query: &str,
    ) -> Result<Vec<MatchResult>> {
        let mut all_matches = Vec::new();

        for i in 0..players.len() {
            for j in (i + 1)..players.len() {
                let result = self.compete(&players[i], &players[j], query).await?;

                let p1_elo = players[i].elo_rating;
                let p2_elo = players[j].elo_rating;

                if result.winner == 0 {
                    players[i].record_win(p2_elo);
                    players[j].record_loss(p1_elo);
                } else {
                    players[j].record_win(p1_elo);
                    players[i].record_loss(p2_elo);
                }

                all_matches.push(result);
            }
        }

        Ok(all_matches)
    }

    /// Single elimination bracket
    async fn run_single_elimination(
        &self,
        players: &mut [ResearchPlayer],
        query: &str,
    ) -> Result<Vec<MatchResult>> {
        let mut all_matches = Vec::new();

        // Work with owned copies for tournament bracket
        let mut active: Vec<ResearchPlayer> = players.iter().cloned().collect();

        while active.len() > 1 {
            let mut next_round = Vec::new();

            for i in (0..active.len()).step_by(2) {
                if i + 1 < active.len() {
                    let result = self.compete(&active[i], &active[i + 1], query).await?;

                    let winner_idx = if result.winner == 0 { i } else { i + 1 };
                    let loser_idx = if result.winner == 0 { i + 1 } else { i };

                    // Clone winner and update their record
                    let mut winner = active[winner_idx].clone();
                    let loser_elo = active[loser_idx].elo_rating;
                    winner.record_win(loser_elo);

                    // Update loser record too (for tracking)
                    let mut loser = active[loser_idx].clone();
                    let winner_elo_before = active[winner_idx].elo_rating;
                    loser.record_loss(winner_elo_before);

                    all_matches.push(result);
                    next_round.push(winner);
                }
            }

            active = next_round;
        }

        // Copy results back to original players (update all ELO ratings)
        for (original, updated) in players.iter_mut().zip(active.iter()) {
            if original.id == updated.id {
                *original = updated.clone();
            }
        }

        Ok(all_matches)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::adversarial::{ResearchPlayer, Strategy};

    #[test]
    fn test_tournament_format() {
        // Test that tournament formats are correctly defined
        let _swiss = TournamentFormat::Swiss;
        let _rr = TournamentFormat::RoundRobin;
        let _elim = TournamentFormat::SingleElim;
    }

    #[test]
    fn test_standing_entry() {
        let standing = StandingEntry {
            player_name: "TestPlayer".to_string(),
            wins: 5,
            losses: 3,
            elo_rating: 1550.0,
            rank: 1,
        };

        assert_eq!(standing.player_name, "TestPlayer");
        assert_eq!(standing.wins, 5);
        assert_eq!(standing.elo_rating, 1550.0);
    }

    #[test]
    fn test_tournament_result_creation() {
        let result = TournamentResult {
            format: "Swiss".to_string(),
            rounds: 3,
            matches: Vec::new(),
            final_standings: Vec::new(),
        };

        assert_eq!(result.format, "Swiss");
        assert_eq!(result.rounds, 3);
    }
}
