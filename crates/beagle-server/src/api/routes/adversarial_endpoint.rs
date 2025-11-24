//! Adversarial Self-Play Competition Endpoint

use axum::{extract::State, http::StatusCode, Json};
use beagle_agents::{
    CompetitionArena, MetaLearner, ResearchPlayer, Strategy, StrategyEvolution, TournamentFormat,
    TournamentResult,
};
use beagle_llm::AnthropicClient;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;
use tracing::{info, warn};

use crate::state::AppState;

/// Request for adversarial competition
#[derive(Debug, Deserialize)]
pub struct AdversarialCompeteRequest {
    /// Research query for agents to compete on
    pub query: String,

    /// Number of players (will create diverse strategies)
    #[serde(default = "default_player_count")]
    pub player_count: usize,

    /// Tournament format
    #[serde(default)]
    pub format: String, // "swiss", "round-robin", "single-elim"

    /// Number of rounds (for Swiss system)
    #[serde(default = "default_rounds")]
    pub rounds: usize,

    /// Enable multi-generation evolution
    #[serde(default)]
    pub enable_evolution: bool,

    /// Number of generations (if evolution enabled)
    #[serde(default = "default_generations")]
    pub generations: usize,
}

fn default_player_count() -> usize {
    8
}

fn default_rounds() -> usize {
    3
}

fn default_generations() -> usize {
    3
}

/// Response from adversarial competition
#[derive(Debug, Serialize)]
pub struct AdversarialCompeteResponse {
    pub tournament_result: TournamentResult,
    pub champion: ChampionInfo,
    pub meta_insights: Option<MetaInsights>,
    pub metadata: CompetitionMetadata,
}

#[derive(Debug, Serialize)]
pub struct ChampionInfo {
    pub name: String,
    pub strategy_type: String,
    pub final_elo: f64,
    pub win_rate: f64,
    pub total_matches: usize,
}

#[derive(Debug, Serialize)]
pub struct MetaInsights {
    pub best_strategy_pattern: String,
    pub optimal_boldness_range: (f64, f64),
    pub convergence_detected: bool,
    pub avg_elo_progression: Vec<f64>,
}

#[derive(Debug, Serialize)]
pub struct CompetitionMetadata {
    pub total_matches: usize,
    pub total_players: usize,
    pub tournament_format: String,
    pub generations_evolved: usize,
    pub processing_time_ms: u64,
}

/// Adversarial competition endpoint handler
pub async fn adversarial_compete(
    State(state): State<AppState>,
    Json(req): Json<AdversarialCompeteRequest>,
) -> Result<Json<AdversarialCompeteResponse>, StatusCode> {
    let start = Instant::now();

    info!(
        "🥊 Adversarial competition: {} players on query: '{}'",
        req.player_count, req.query
    );

    if req.player_count < 2 {
        warn!("Need at least 2 players");
        return Err(StatusCode::BAD_REQUEST);
    }

    if req.player_count > 32 {
        warn!("Too many players: {}", req.player_count);
        return Err(StatusCode::BAD_REQUEST);
    }

    // Get Claude client from state
    let llm = state.claude_client().ok_or_else(|| {
        warn!("Claude client not available");
        StatusCode::SERVICE_UNAVAILABLE
    })?;

    // Determine tournament format
    let format = match req.format.to_lowercase().as_str() {
        "round-robin" | "rr" => TournamentFormat::RoundRobin,
        "single-elim" | "bracket" => TournamentFormat::SingleElim,
        _ => TournamentFormat::Swiss, // Default
    };

    // Create competition arena
    let arena = CompetitionArena::with_format(Arc::clone(&llm), format);

    // Create diverse initial strategies
    let initial_strategies = create_diverse_strategies(req.player_count);

    if req.enable_evolution {
        // Multi-generation evolution
        let result = run_evolutionary_competition(
            &arena,
            initial_strategies,
            &req.query,
            req.rounds,
            req.generations,
        )
        .await
        .map_err(|e| {
            warn!("Evolution failed: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

        let elapsed = start.elapsed().as_millis() as u64;
        Ok(Json(result.with_timing(elapsed)))
    } else {
        // Single tournament
        let mut players: Vec<ResearchPlayer> = initial_strategies
            .into_iter()
            .enumerate()
            .map(|(i, strategy)| ResearchPlayer::new(format!("Player_{}", i), strategy))
            .collect();

        let tournament_result = arena
            .run_tournament(&mut players, &req.query, req.rounds)
            .await
            .map_err(|e| {
                warn!("Tournament failed: {}", e);
                StatusCode::INTERNAL_SERVER_ERROR
            })?;

        // Find champion
        let champion = players
            .iter()
            .max_by(|a, b| {
                a.elo_rating
                    .partial_cmp(&b.elo_rating)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .unwrap();

        let champion_info = ChampionInfo {
            name: champion.name.clone(),
            strategy_type: format!("{:?}", champion.strategy.approach),
            final_elo: champion.elo_rating,
            win_rate: champion.win_rate(),
            total_matches: champion.wins + champion.losses,
        };

        let elapsed = start.elapsed().as_millis() as u64;

        info!(
            "✅ Competition complete in {}ms. Champion: {} (ELO: {:.1})",
            elapsed, champion_info.name, champion_info.final_elo
        );

        Ok(Json(AdversarialCompeteResponse {
            tournament_result: tournament_result.clone(),
            champion: champion_info,
            meta_insights: None,
            metadata: CompetitionMetadata {
                total_matches: tournament_result.matches.len(),
                total_players: players.len(),
                tournament_format: tournament_result.format.clone(),
                generations_evolved: 0,
                processing_time_ms: elapsed,
            },
        }))
    }
}

/// Run multi-generation evolutionary competition
async fn run_evolutionary_competition(
    arena: &CompetitionArena,
    initial_strategies: Vec<Strategy>,
    query: &str,
    rounds: usize,
    generations: usize,
) -> anyhow::Result<AdversarialCompeteResponse> {
    let mut evolution = StrategyEvolution::new(initial_strategies);
    let mut meta_learner = MetaLearner::new();

    info!("🧬 Starting {} generations of evolution", generations);

    for gen in 0..generations {
        info!("Generation {}/{}", gen + 1, generations);

        // Run tournament for this generation
        let mut players = evolution.players.clone();
        let tournament_result = arena.run_tournament(&mut players, query, rounds).await?;

        // Record for meta-learning
        meta_learner.record_generation(players.clone(), tournament_result.matches.clone());

        // Update evolution state
        evolution.players = players;

        // Evolve to next generation (except last)
        if gen < generations - 1 {
            evolution.evolve_generation(arena, query, 1).await?;
        }
    }

    // Analyze meta-learning insights
    let insights = meta_learner.analyze();

    // Final tournament with evolved players
    let mut final_players = evolution.players.clone();
    let final_tournament = arena
        .run_tournament(&mut final_players, query, rounds)
        .await?;

    // Find champion
    let champion = final_players
        .iter()
        .max_by(|a, b| {
            a.elo_rating
                .partial_cmp(&b.elo_rating)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap();

    let champion_info = ChampionInfo {
        name: champion.name.clone(),
        strategy_type: format!("{:?}", champion.strategy.approach),
        final_elo: champion.elo_rating,
        win_rate: champion.win_rate(),
        total_matches: champion.wins + champion.losses,
    };

    // Extract meta insights
    let best_pattern = insights.top_strategy_patterns.first();
    let boldness_insight = insights.winning_parameters.get("boldness");

    let meta_insights = Some(MetaInsights {
        best_strategy_pattern: best_pattern
            .map(|p| p.approach_name.clone())
            .unwrap_or_else(|| "Unknown".to_string()),
        optimal_boldness_range: boldness_insight
            .map(|i| i.optimal_range)
            .unwrap_or((0.5, 0.7)),
        convergence_detected: insights.performance_trends.convergence_detected,
        avg_elo_progression: insights.performance_trends.avg_elo_by_generation.clone(),
    });

    Ok(AdversarialCompeteResponse {
        tournament_result: final_tournament,
        champion: champion_info,
        meta_insights,
        metadata: CompetitionMetadata {
            total_matches: evolution.match_history.len(),
            total_players: final_players.len(),
            tournament_format: "Evolutionary".to_string(),
            generations_evolved: generations,
            processing_time_ms: 0, // Set by caller
        },
    })
}

impl AdversarialCompeteResponse {
    fn with_timing(mut self, ms: u64) -> Self {
        self.metadata.processing_time_ms = ms;
        self
    }
}

/// Create diverse initial strategies
fn create_diverse_strategies(count: usize) -> Vec<Strategy> {
    let base_strategies = vec![
        Strategy::new_aggressive(),
        Strategy::new_conservative(),
        Strategy::new_exploratory(),
        Strategy::new_exploitative(),
    ];

    let mut strategies = Vec::new();

    for i in 0..count {
        let base = &base_strategies[i % base_strategies.len()];
        if i < base_strategies.len() {
            strategies.push(base.clone());
        } else {
            // Create variants through mutation
            strategies.push(base.mutate());
        }
    }

    strategies
}
