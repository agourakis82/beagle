use super::strategy::Strategy;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResearchPlayer {
    pub id: Uuid,
    pub name: String,
    pub strategy: Strategy,
    pub wins: usize,
    pub losses: usize,
    pub elo_rating: f64,
}

impl ResearchPlayer {
    pub fn new(name: String, strategy: Strategy) -> Self {
        Self {
            id: Uuid::new_v4(),
            name,
            strategy,
            wins: 0,
            losses: 0,
            elo_rating: 1500.0, // Starting Elo
        }
    }

    pub fn win_rate(&self) -> f64 {
        let total = self.wins + self.losses;
        if total == 0 {
            return 0.5;
        }
        self.wins as f64 / total as f64
    }

    pub fn record_win(&mut self, opponent_elo: f64) {
        self.wins += 1;
        self.update_elo(1.0, opponent_elo);
    }

    pub fn record_loss(&mut self, opponent_elo: f64) {
        self.losses += 1;
        self.update_elo(0.0, opponent_elo);
    }

    fn update_elo(&mut self, score: f64, opponent_elo: f64) {
        let k = 32.0; // Elo K-factor
        let expected = 1.0 / (1.0 + 10_f64.powf((opponent_elo - self.elo_rating) / 400.0));
        self.elo_rating += k * (score - expected);
    }
}
