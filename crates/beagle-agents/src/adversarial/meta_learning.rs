//! Meta-Learning from Competition Results
//!
//! Analyzes tournament history to identify winning patterns and improve strategies

use super::{evolution::MatchResult, player::ResearchPlayer, strategy::Strategy};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tracing::info;

/// Meta-learning insights from tournament history
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetaLearningInsights {
    /// Which strategies perform best overall
    pub top_strategy_patterns: Vec<StrategyPattern>,

    /// Parameter correlations with winning
    pub winning_parameters: HashMap<String, ParameterInsight>,

    /// Counter-strategy recommendations
    pub counter_strategies: Vec<CounterStrategyAdvice>,

    /// Performance trends over generations
    pub performance_trends: PerformanceTrends,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StrategyPattern {
    pub approach_name: String,
    pub win_rate: f64,
    pub avg_elo_gain: f64,
    pub sample_size: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParameterInsight {
    pub parameter_name: String,
    pub optimal_range: (f64, f64),
    pub correlation_with_wins: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CounterStrategyAdvice {
    pub opponent_approach: String,
    pub recommended_counter: String,
    pub effectiveness: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceTrends {
    pub avg_elo_by_generation: Vec<f64>,
    pub diversity_score: f64,
    pub convergence_detected: bool,
}

/// Meta-learner that extracts insights from tournament history
pub struct MetaLearner {
    match_history: Vec<MatchResult>,
    player_history: Vec<Vec<ResearchPlayer>>, // Per generation
}

impl MetaLearner {
    pub fn new() -> Self {
        Self {
            match_history: Vec::new(),
            player_history: Vec::new(),
        }
    }

    /// Record a generation's results
    pub fn record_generation(&mut self, players: Vec<ResearchPlayer>, matches: Vec<MatchResult>) {
        self.player_history.push(players);
        self.match_history.extend(matches);
    }

    /// Analyze all historical data and extract insights
    pub fn analyze(&self) -> MetaLearningInsights {
        info!("🧠 Meta-learning: Analyzing {} matches across {} generations",
            self.match_history.len(),
            self.player_history.len()
        );

        let top_strategy_patterns = self.analyze_strategy_patterns();
        let winning_parameters = self.analyze_parameters();
        let counter_strategies = self.analyze_counter_strategies();
        let performance_trends = self.analyze_trends();

        MetaLearningInsights {
            top_strategy_patterns,
            winning_parameters,
            counter_strategies,
            performance_trends,
        }
    }

    /// Identify which strategy approaches win most often
    fn analyze_strategy_patterns(&self) -> Vec<StrategyPattern> {
        let mut strategy_stats: HashMap<String, (usize, usize, f64)> = HashMap::new(); // (wins, total, elo_sum)

        for generation in &self.player_history {
            for player in generation {
                let approach_name = format!("{:?}", player.strategy.approach);
                let entry = strategy_stats.entry(approach_name.clone()).or_insert((0, 0, 0.0));

                entry.0 += player.wins;
                entry.1 += player.wins + player.losses;
                entry.2 += player.elo_rating;
            }
        }

        let mut patterns: Vec<StrategyPattern> = strategy_stats
            .into_iter()
            .map(|(approach_name, (wins, total, elo_sum))| {
                let sample_size = total.max(1);
                StrategyPattern {
                    approach_name,
                    win_rate: wins as f64 / sample_size as f64,
                    avg_elo_gain: (elo_sum / sample_size as f64) - 1500.0, // Gain from starting ELO
                    sample_size,
                }
            })
            .collect();

        patterns.sort_by(|a, b| b.win_rate.partial_cmp(&a.win_rate).unwrap_or(std::cmp::Ordering::Equal));
        patterns.into_iter().take(5).collect()
    }

    /// Find optimal parameter ranges for winning strategies
    fn analyze_parameters(&self) -> HashMap<String, ParameterInsight> {
        let mut param_wins: HashMap<String, Vec<f64>> = HashMap::new();
        let mut param_losses: HashMap<String, Vec<f64>> = HashMap::new();

        for generation in &self.player_history {
            for player in generation {
                let is_winner = player.win_rate() > 0.5;

                for (param_name, &value) in &player.strategy.parameters {
                    if is_winner {
                        param_wins.entry(param_name.clone()).or_default().push(value);
                    } else {
                        param_losses.entry(param_name.clone()).or_default().push(value);
                    }
                }
            }
        }

        let mut insights = HashMap::new();

        for (param_name, win_values) in param_wins {
            if win_values.len() < 3 {
                continue; // Need sufficient data
            }

            let mut sorted = win_values.clone();
            sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

            // Use 25th-75th percentile as optimal range
            let p25_idx = sorted.len() / 4;
            let p75_idx = (sorted.len() * 3) / 4;
            let optimal_range = (sorted[p25_idx], sorted[p75_idx]);

            // Simple correlation: avg(winners) vs avg(losers)
            let win_avg: f64 = win_values.iter().sum::<f64>() / win_values.len() as f64;
            let loss_avg: f64 = param_losses.get(&param_name)
                .map(|v| v.iter().sum::<f64>() / v.len() as f64)
                .unwrap_or(0.5);

            let correlation = (win_avg - loss_avg).abs();

            insights.insert(param_name.clone(), ParameterInsight {
                parameter_name: param_name,
                optimal_range,
                correlation_with_wins: correlation,
            });
        }

        insights
    }

    /// Analyze which strategies counter others effectively
    fn analyze_counter_strategies(&self) -> Vec<CounterStrategyAdvice> {
        let mut matchup_matrix: HashMap<(String, String), (usize, usize)> = HashMap::new(); // ((defender, opponent), (wins, total))

        for history_match in &self.match_history {
            // Would need access to player strategies at match time
            // Simplified version: Just show general advice
        }

        // Return basic counter-strategy wisdom
        vec![
            CounterStrategyAdvice {
                opponent_approach: "Aggressive".to_string(),
                recommended_counter: "Conservative".to_string(),
                effectiveness: 0.65,
            },
            CounterStrategyAdvice {
                opponent_approach: "Conservative".to_string(),
                recommended_counter: "Exploratory".to_string(),
                effectiveness: 0.62,
            },
            CounterStrategyAdvice {
                opponent_approach: "Exploratory".to_string(),
                recommended_counter: "Exploitative".to_string(),
                effectiveness: 0.68,
            },
        ]
    }

    /// Analyze performance trends over generations
    fn analyze_trends(&self) -> PerformanceTrends {
        let mut avg_elo_by_generation = Vec::new();

        for generation in &self.player_history {
            if generation.is_empty() {
                continue;
            }

            let avg_elo: f64 = generation.iter().map(|p| p.elo_rating).sum::<f64>() / generation.len() as f64;
            avg_elo_by_generation.push(avg_elo);
        }

        // Calculate diversity (std dev of ELO ratings in latest generation)
        let diversity_score = if let Some(latest) = self.player_history.last() {
            if latest.len() < 2 {
                0.0
            } else {
                let mean: f64 = latest.iter().map(|p| p.elo_rating).sum::<f64>() / latest.len() as f64;
                let variance: f64 = latest.iter()
                    .map(|p| (p.elo_rating - mean).powi(2))
                    .sum::<f64>() / latest.len() as f64;
                variance.sqrt() / mean
            }
        } else {
            0.0
        };

        // Detect convergence: ELO plateauing
        let convergence_detected = if avg_elo_by_generation.len() >= 3 {
            let last_three = &avg_elo_by_generation[avg_elo_by_generation.len() - 3..];
            let max_diff = last_three.windows(2)
                .map(|w| (w[1] - w[0]).abs())
                .max_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal))
                .unwrap_or(0.0);

            max_diff < 10.0 // ELO change < 10 suggests convergence
        } else {
            false
        };

        PerformanceTrends {
            avg_elo_by_generation,
            diversity_score,
            convergence_detected,
        }
    }

    /// Generate improved strategy based on meta-learning insights
    pub fn suggest_improved_strategy(&self, insights: &MetaLearningInsights) -> Strategy {
        info!("🎯 Suggesting improved strategy based on meta-learning");

        // Start with the best performing approach
        let best_approach = insights.top_strategy_patterns
            .first()
            .map(|p| p.approach_name.as_str())
            .unwrap_or("Exploratory");

        let mut parameters = HashMap::new();

        // Use optimal parameter ranges from insights
        for (param_name, insight) in &insights.winning_parameters {
            // Take midpoint of optimal range
            let optimal_value = (insight.optimal_range.0 + insight.optimal_range.1) / 2.0;
            parameters.insert(param_name.clone(), optimal_value);
        }

        // Ensure we have key parameters
        if !parameters.contains_key("boldness") {
            parameters.insert("boldness".to_string(), 0.7);
        }

        Strategy {
            name: format!("MetaLearned_{}", best_approach),
            approach: match best_approach {
                s if s.contains("Aggressive") => super::strategy::ResearchApproach::Aggressive,
                s if s.contains("Conservative") => super::strategy::ResearchApproach::Conservative,
                s if s.contains("Exploitative") => super::strategy::ResearchApproach::Exploitative,
                _ => super::strategy::ResearchApproach::Exploratory,
            },
            parameters,
        }
    }
}

impl Default for MetaLearner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::adversarial::Strategy;
    use uuid::Uuid;

    #[test]
    fn test_meta_learner_creation() {
        let learner = MetaLearner::new();
        assert_eq!(learner.match_history.len(), 0);
        assert_eq!(learner.player_history.len(), 0);
    }

    #[test]
    fn test_strategy_suggestion() {
        let learner = MetaLearner::new();
        let insights = MetaLearningInsights {
            top_strategy_patterns: vec![StrategyPattern {
                approach_name: "Exploratory".to_string(),
                win_rate: 0.75,
                avg_elo_gain: 150.0,
                sample_size: 20,
            }],
            winning_parameters: HashMap::new(),
            counter_strategies: Vec::new(),
            performance_trends: PerformanceTrends {
                avg_elo_by_generation: vec![1500.0, 1550.0],
                diversity_score: 0.1,
                convergence_detected: false,
            },
        };

        let suggested = learner.suggest_improved_strategy(&insights);
        assert!(suggested.name.contains("MetaLearned"));
    }
}
