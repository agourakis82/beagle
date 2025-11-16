use super::{player::ResearchPlayer, strategy::Strategy, arena::CompetitionArena};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use anyhow::Result;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchResult {
    pub player1_id: Uuid,
    pub player2_id: Uuid,
    pub player1_hypothesis: String,
    pub player2_hypothesis: String,
    pub winner: usize, // 0 = player1, 1 = player2
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StrategyEvolution {
    pub generation: usize,
    pub players: Vec<ResearchPlayer>,
    pub match_history: Vec<MatchResult>,
}

impl StrategyEvolution {
    pub fn new(initial_strategies: Vec<Strategy>) -> Self {
        let players = initial_strategies
            .into_iter()
            .enumerate()
            .map(|(i, strategy)| {
                ResearchPlayer::new(format!("Player_{}", i), strategy)
            })
            .collect();

        Self {
            generation: 0,
            players,
            match_history: Vec::new(),
        }
    }

    pub async fn evolve_generation(
        &mut self,
        arena: &CompetitionArena,
        query: &str,
        matches_per_player: usize,
    ) -> Result<()> {
        info!("🧬 Evolving generation {}", self.generation);

        // Run round-robin tournament
        for i in 0..self.players.len() {
            for j in (i + 1)..self.players.len() {
                for _ in 0..matches_per_player {
                    let player1 = &self.players[i];
                    let player2 = &self.players[j];

                    let result = arena.compete(player1, player2, query).await?;

                    // Update player stats
                    let player1_elo = player1.elo_rating;
                    let player2_elo = player2.elo_rating;

                    if result.winner == 0 {
                        self.players[i].record_win(player2_elo);
                        self.players[j].record_loss(player1_elo);
                    } else {
                        self.players[j].record_win(player1_elo);
                        self.players[i].record_loss(player2_elo);
                    }

                    self.match_history.push(result);
                }
            }
        }

        // Sort by Elo rating
        self.players.sort_by(|a, b| {
            b.elo_rating.partial_cmp(&a.elo_rating).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Keep top 50%, mutate and add new players
        let survivors = self.players.len() / 2;
        let mut new_players = self.players[..survivors].to_vec();

        // Create mutated versions
        while new_players.len() < self.players.len() {
            let parent = &new_players[rand::random::<usize>() % new_players.len()];
            let mutated_strategy = parent.strategy.mutate();
            new_players.push(ResearchPlayer::new(
                format!("{}_gen{}", parent.name, self.generation + 1),
                mutated_strategy,
            ));
        }

        self.players = new_players;
        self.generation += 1;

        info!("✅ Generation {} complete. Top player: {} (Elo: {:.1})",
              self.generation - 1,
              self.players[0].name,
              self.players[0].elo_rating);

        Ok(())
    }

    pub fn top_players(&self, n: usize) -> Vec<&ResearchPlayer> {
        self.players.iter().take(n).collect()
    }
}



