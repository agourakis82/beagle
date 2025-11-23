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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::adversarial::Strategy;

    #[test]
    fn test_player_creation() {
        let strategy = Strategy::new_aggressive();
        let player = ResearchPlayer::new("TestPlayer".to_string(), strategy);

        assert_eq!(player.name, "TestPlayer");
        assert_eq!(player.wins, 0);
        assert_eq!(player.losses, 0);
        assert_eq!(player.elo_rating, 1500.0);
    }

    #[test]
    fn test_win_rate() {
        let strategy = Strategy::new_aggressive();
        let mut player = ResearchPlayer::new("TestPlayer".to_string(), strategy);

        assert_eq!(player.win_rate(), 0.5); // No matches yet

        player.wins = 7;
        player.losses = 3;
        assert_eq!(player.win_rate(), 0.7);
    }

    #[test]
    fn test_elo_update_win() {
        let strategy = Strategy::new_aggressive();
        let mut player = ResearchPlayer::new("TestPlayer".to_string(), strategy);

        let initial_elo = player.elo_rating;
        player.record_win(1500.0);

        // ELO should increase after a win
        assert!(player.elo_rating > initial_elo);
        assert_eq!(player.wins, 1);
    }

    #[test]
    fn test_elo_update_loss() {
        let strategy = Strategy::new_aggressive();
        let mut player = ResearchPlayer::new("TestPlayer".to_string(), strategy);

        let initial_elo = player.elo_rating;
        player.record_loss(1500.0);

        // ELO should decrease after a loss
        assert!(player.elo_rating < initial_elo);
        assert_eq!(player.losses, 1);
    }
}
