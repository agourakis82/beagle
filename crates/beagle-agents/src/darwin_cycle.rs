//! Darwin Evolutionary Cycle with Semantic Context
//!
//! Implements a comprehensive evolutionary algorithm with:
//! - Population-based optimization
//! - Semantic fitness evaluation using multi-provider LLMs
//! - Crossover and mutation operators
//! - Elite preservation and diversity maintenance
//!
//! References:
//! - Darwin, C. (1859). "On the Origin of Species"
//! - Holland, J.H. (1975). "Adaptation in Natural and Artificial Systems"
//! - Goldberg, D.E. (1989). "Genetic Algorithms in Search, Optimization, and Machine Learning"
//! - Koza, J.R. (1992). "Genetic Programming"

use anyhow::{Context as AnyhowContext, Result};
use async_trait::async_trait;
use rand::{seq::SliceRandom, thread_rng, Rng};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, instrument, warn};
use uuid::Uuid;

use beagle_core::BeagleContext;
use beagle_hypergraph::{HypergraphStorage, Node};
use beagle_llm::{LlmClient, RequestMeta};

/// Configuration for Darwin evolutionary cycle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DarwinConfig {
    /// Population size for each generation
    pub population_size: usize,
    /// Number of elite individuals to preserve
    pub elite_count: usize,
    /// Mutation rate (0.0 to 1.0)
    pub mutation_rate: f64,
    /// Crossover rate (0.0 to 1.0)
    pub crossover_rate: f64,
    /// Maximum generations before termination
    pub max_generations: usize,
    /// Fitness threshold for early stopping
    pub fitness_threshold: f64,
    /// Diversity bonus weight (promotes exploration)
    pub diversity_weight: f64,
    /// Semantic similarity threshold for clustering
    pub semantic_threshold: f64,
    /// Enable adaptive mutation based on fitness stagnation
    pub adaptive_mutation: bool,
    /// Use multiple LLM providers for evaluation diversity
    pub multi_provider_eval: bool,
}

impl Default for DarwinConfig {
    fn default() -> Self {
        Self {
            population_size: 100,
            elite_count: 10,
            mutation_rate: 0.15,
            crossover_rate: 0.85,
            max_generations: 50,
            fitness_threshold: 0.95,
            diversity_weight: 0.2,
            semantic_threshold: 0.85,
            adaptive_mutation: true,
            multi_provider_eval: true,
        }
    }
}

/// Individual in the population
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Individual {
    pub id: Uuid,
    pub genome: Genome,
    pub fitness: f64,
    pub semantic_embedding: Vec<f32>,
    pub generation: usize,
    pub parents: Vec<Uuid>,
    pub mutations: Vec<MutationType>,
    pub provider_scores: HashMap<String, f64>, // Scores from different LLM providers
}

/// Genetic representation of a solution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Genome {
    /// Core semantic content
    pub content: String,
    /// Structural genes (e.g., argument structure, reasoning patterns)
    pub structure_genes: Vec<StructureGene>,
    /// Style genes (e.g., formality, technical depth)
    pub style_genes: Vec<StyleGene>,
    /// Domain-specific adaptations
    pub domain_genes: Vec<DomainGene>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StructureGene {
    pub pattern: ReasoningPattern,
    pub weight: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReasoningPattern {
    Deductive,
    Inductive,
    Abductive,
    Analogical,
    Causal,
    Dialectical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleGene {
    pub formality: f64,    // 0.0 = informal, 1.0 = formal
    pub technicality: f64, // 0.0 = lay, 1.0 = expert
    pub verbosity: f64,    // 0.0 = concise, 1.0 = verbose
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomainGene {
    pub domain: String,
    pub expertise_level: f64,
    pub terminology: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MutationType {
    ContentMutation {
        position: usize,
        change: String,
    },
    StructuralShift {
        from: ReasoningPattern,
        to: ReasoningPattern,
    },
    StyleAdjustment {
        gene: String,
        delta: f64,
    },
    DomainAdaptation {
        domain: String,
        level: f64,
    },
}

/// Darwin evolutionary cycle implementation
pub struct DarwinCycle {
    config: DarwinConfig,
    context: Arc<BeagleContext>,
    population: Arc<RwLock<Vec<Individual>>>,
    generation: Arc<RwLock<usize>>,
    fitness_history: Arc<RwLock<Vec<f64>>>,
    diversity_metrics: Arc<RwLock<Vec<f64>>>,
}

impl DarwinCycle {
    pub fn new(config: DarwinConfig, context: Arc<BeagleContext>) -> Self {
        Self {
            config,
            context,
            population: Arc::new(RwLock::new(Vec::new())),
            generation: Arc::new(RwLock::new(0)),
            fitness_history: Arc::new(RwLock::new(Vec::new())),
            diversity_metrics: Arc::new(RwLock::new(Vec::new())),
        }
    }

    /// Initialize population with semantic context
    #[instrument(skip(self, seed_content))]
    pub async fn initialize_population(
        &self,
        seed_content: &str,
        context_nodes: Vec<Node>,
    ) -> Result<()> {
        info!(
            "🧬 Initializing Darwin population with {} individuals",
            self.config.population_size
        );

        let mut population = Vec::new();

        for i in 0..self.config.population_size {
            let individual = self
                .create_individual(seed_content, &context_nodes, i)
                .await?;
            population.push(individual);
        }

        *self.population.write().await = population;
        info!("✅ Population initialized");
        Ok(())
    }

    /// Create a new individual with variations
    async fn create_individual(
        &self,
        seed: &str,
        context: &[Node],
        index: usize,
    ) -> Result<Individual> {
        let mut rng = thread_rng();

        // Create varied content based on seed
        let variation_prompts = [
            "Rephrase with more technical depth",
            "Simplify for broader audience",
            "Add empirical evidence",
            "Emphasize theoretical foundations",
            "Focus on practical applications",
        ];

        let prompt = format!(
            "{}: {}",
            variation_prompts[index % variation_prompts.len()],
            seed
        );

        // Use multi-provider routing for diverse initialization
        let meta = RequestMeta {
            requires_high_quality: false,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
            ..Default::default()
        };

        let stats = self.context.get_current_stats().await;
        let (client, tier) = self.context.router().choose_with_limits(&meta, &stats);

        debug!(
            "Creating individual {} with provider tier: {:?}",
            index, tier
        );

        let response = client.complete(&prompt).await?;

        // Generate structure genes
        let patterns = [
            ReasoningPattern::Deductive,
            ReasoningPattern::Inductive,
            ReasoningPattern::Abductive,
            ReasoningPattern::Analogical,
            ReasoningPattern::Causal,
            ReasoningPattern::Dialectical,
        ];
        let structure_genes = vec![StructureGene {
            pattern: patterns.choose(&mut rng).unwrap().clone(),
            weight: rng.gen::<f64>(),
        }];

        // Generate style genes
        let style_genes = vec![StyleGene {
            formality: rng.gen::<f64>(),
            technicality: rng.gen::<f64>(),
            verbosity: rng.gen::<f64>(),
        }];

        // Generate domain genes based on context
        let domain_genes = context
            .iter()
            .filter_map(|node| {
                node.metadata.get("domain").map(|d| DomainGene {
                    domain: d.as_str().unwrap_or("general").to_string(),
                    expertise_level: rng.gen::<f64>(),
                    terminology: Vec::new(),
                })
            })
            .take(3)
            .collect();

        let genome = Genome {
            content: response.text,
            structure_genes,
            style_genes,
            domain_genes,
        };

        // Generate semantic embedding
        let embedding = self.generate_embedding(&genome).await?;

        Ok(Individual {
            id: Uuid::new_v4(),
            genome,
            fitness: 0.0,
            semantic_embedding: embedding,
            generation: 0,
            parents: Vec::new(),
            mutations: Vec::new(),
            provider_scores: HashMap::new(),
        })
    }

    /// Run the evolutionary cycle
    #[instrument(skip(self, fitness_fn))]
    pub async fn evolve<F>(&mut self, fitness_fn: F) -> Result<Individual>
    where
        F: Fn(&Individual) -> f64 + Send + Sync + Clone + 'static,
    {
        info!("🧬 Starting Darwin evolution cycle");

        for gen in 0..self.config.max_generations {
            *self.generation.write().await = gen;
            info!("📊 Generation {}/{}", gen + 1, self.config.max_generations);

            // Evaluate fitness with multiple providers if enabled
            self.evaluate_population(fitness_fn.clone()).await?;

            // Check termination criteria
            let best = self.get_best_individual().await?;
            if best.fitness >= self.config.fitness_threshold {
                info!("🎯 Fitness threshold reached: {:.4}", best.fitness);
                return Ok(best);
            }

            // Calculate diversity
            let diversity = self.calculate_diversity().await?;
            self.diversity_metrics.write().await.push(diversity);
            info!("🌈 Population diversity: {:.4}", diversity);

            // Adaptive mutation if enabled
            if self.config.adaptive_mutation {
                self.adapt_mutation_rate(gen).await?;
            }

            // Selection and reproduction
            let new_population = self.reproduce().await?;
            *self.population.write().await = new_population;

            // Record fitness history
            let avg_fitness = self.calculate_average_fitness().await?;
            self.fitness_history.write().await.push(avg_fitness);
            info!("📈 Average fitness: {:.4}", avg_fitness);
        }

        // Return best individual after all generations
        self.get_best_individual().await
    }

    /// Evaluate population fitness using multiple LLM providers
    async fn evaluate_population<F>(&self, fitness_fn: F) -> Result<()>
    where
        F: Fn(&Individual) -> f64 + Send + Sync,
    {
        let mut population = self.population.write().await;

        // First pass: calculate base fitness and provider scores
        for individual in population.iter_mut() {
            // Base fitness from provided function
            let base_fitness = fitness_fn(individual);

            if self.config.multi_provider_eval {
                // Get evaluations from multiple providers
                let provider_scores = self.evaluate_with_providers(individual).await?;
                individual.provider_scores = provider_scores.clone();

                // Combine scores with base fitness
                let avg_provider_score = if !provider_scores.is_empty() {
                    provider_scores.values().sum::<f64>() / provider_scores.len() as f64
                } else {
                    0.5
                };

                individual.fitness = 0.6 * base_fitness + 0.4 * avg_provider_score;
            } else {
                individual.fitness = base_fitness;
            }
        }

        // Second pass: add diversity bonus (requires immutable access to full population)
        let population_snapshot: Vec<Individual> = population.clone();
        for individual in population.iter_mut() {
            let diversity_bonus = self
                .calculate_individual_diversity(individual, &population_snapshot)
                .await?;
            individual.fitness += self.config.diversity_weight * diversity_bonus;
        }

        Ok(())
    }

    /// Evaluate an individual using multiple LLM providers
    async fn evaluate_with_providers(
        &self,
        individual: &Individual,
    ) -> Result<HashMap<String, f64>> {
        let mut scores = HashMap::new();

        let evaluation_prompt = format!(
            "Evaluate the following solution on a scale of 0.0 to 1.0:\n\n{}\n\n\
            Consider:\n\
            - Correctness and accuracy\n\
            - Clarity and coherence\n\
            - Completeness\n\
            - Innovation\n\
            Provide only a numerical score.",
            individual.genome.content
        );

        // Try different provider tiers for diversity
        let provider_configs = vec![
            (
                RequestMeta {
                    requires_high_quality: false,
                    requires_phd_level_reasoning: false,
                    high_bias_risk: false,
                    critical_section: false,
                    requires_math: false,
                    offline_required: false,
                    ..Default::default()
                },
                "tier1",
            ),
            (
                RequestMeta {
                    requires_high_quality: true,
                    requires_phd_level_reasoning: false,
                    high_bias_risk: false,
                    critical_section: false,
                    requires_math: false,
                    offline_required: false,
                    ..Default::default()
                },
                "tier2",
            ),
            (
                RequestMeta {
                    requires_high_quality: false,
                    requires_phd_level_reasoning: false,
                    high_bias_risk: false,
                    critical_section: false,
                    requires_math: true,
                    offline_required: false,
                    ..Default::default()
                },
                "math",
            ),
        ];

        for (meta, tier_name) in provider_configs {
            let stats = self.context.get_current_stats().await;
            let (client, _tier) = self.context.router().choose_with_limits(&meta, &stats);

            match client.complete(&evaluation_prompt).await {
                Ok(response) => {
                    if let Ok(score) = response.text.trim().parse::<f64>() {
                        scores.insert(tier_name.to_string(), score.clamp(0.0, 1.0));
                    }
                }
                Err(e) => {
                    warn!("Provider evaluation failed for {}: {}", tier_name, e);
                }
            }
        }

        Ok(scores)
    }

    /// Reproduction: selection, crossover, and mutation
    async fn reproduce(&self) -> Result<Vec<Individual>> {
        let population = self.population.read().await;
        let mut new_population = Vec::new();
        let mut rng = thread_rng();

        // Sort by fitness
        let mut sorted_pop = population.clone();
        sorted_pop.sort_by(|a, b| b.fitness.partial_cmp(&a.fitness).unwrap());

        // Elite preservation
        for i in 0..self.config.elite_count.min(sorted_pop.len()) {
            new_population.push(sorted_pop[i].clone());
        }

        // Generate offspring
        while new_population.len() < self.config.population_size {
            // Selection
            let parent1 = self.tournament_selection(&sorted_pop, 5)?;
            let parent2 = self.tournament_selection(&sorted_pop, 5)?;

            // Crossover
            let mut offspring = if rng.gen::<f64>() < self.config.crossover_rate {
                self.crossover(&parent1, &parent2).await?
            } else {
                parent1.clone()
            };

            // Mutation
            if rng.gen::<f64>() < self.config.mutation_rate {
                offspring = self.mutate(offspring).await?;
            }

            // Update generation info
            let gen = *self.generation.read().await;
            offspring.generation = gen + 1;
            offspring.parents = vec![parent1.id, parent2.id];

            new_population.push(offspring);
        }

        Ok(new_population)
    }

    /// Tournament selection
    fn tournament_selection(
        &self,
        population: &[Individual],
        tournament_size: usize,
    ) -> Result<Individual> {
        let mut rng = thread_rng();
        let mut tournament = Vec::new();

        for _ in 0..tournament_size {
            if let Some(individual) = population.choose(&mut rng) {
                tournament.push(individual.clone());
            }
        }

        tournament.sort_by(|a, b| b.fitness.partial_cmp(&a.fitness).unwrap());
        tournament
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("Tournament selection failed"))
    }

    /// Crossover operator with semantic awareness
    async fn crossover(&self, parent1: &Individual, parent2: &Individual) -> Result<Individual> {
        let mut rng = thread_rng();

        // Semantic crossover for content
        let crossover_prompt = format!(
            "Combine the best aspects of these two solutions:\n\n\
            Solution 1:\n{}\n\n\
            Solution 2:\n{}\n\n\
            Create a hybrid that preserves strengths from both.",
            parent1.genome.content, parent2.genome.content
        );

        // Use appropriate provider for crossover
        let meta = RequestMeta {
            requires_high_quality: false,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
            ..Default::default()
        };

        let stats = self.context.get_current_stats().await;
        let (client, _tier) = self.context.router().choose_with_limits(&meta, &stats);

        let response = client.complete(&crossover_prompt).await?;

        // Mix structural genes
        let mut structure_genes = Vec::new();
        for (g1, g2) in parent1
            .genome
            .structure_genes
            .iter()
            .zip(parent2.genome.structure_genes.iter())
        {
            structure_genes.push(if rng.gen_bool(0.5) {
                g1.clone()
            } else {
                g2.clone()
            });
        }

        // Blend style genes
        let style_genes = parent1
            .genome
            .style_genes
            .iter()
            .zip(parent2.genome.style_genes.iter())
            .map(|(s1, s2)| StyleGene {
                formality: (s1.formality + s2.formality) / 2.0,
                technicality: (s1.technicality + s2.technicality) / 2.0,
                verbosity: (s1.verbosity + s2.verbosity) / 2.0,
            })
            .collect();

        // Combine domain genes
        let mut domain_genes = parent1.genome.domain_genes.clone();
        domain_genes.extend(parent2.genome.domain_genes.clone());
        domain_genes.sort_by(|a, b| b.expertise_level.partial_cmp(&a.expertise_level).unwrap());
        domain_genes.truncate(3);

        let genome = Genome {
            content: response.text,
            structure_genes,
            style_genes,
            domain_genes,
        };

        let embedding = self.generate_embedding(&genome).await?;

        Ok(Individual {
            id: Uuid::new_v4(),
            genome,
            fitness: 0.0,
            semantic_embedding: embedding,
            generation: 0,
            parents: vec![parent1.id, parent2.id],
            mutations: Vec::new(),
            provider_scores: HashMap::new(),
        })
    }

    /// Mutation operator
    async fn mutate(&self, mut individual: Individual) -> Result<Individual> {
        let mut rng = thread_rng();
        let mutation_type = rng.gen_range(0..4);

        match mutation_type {
            0 => {
                // Content mutation
                let mutation_prompt = format!(
                    "Introduce a creative variation to this solution while maintaining its core validity:\n\n{}",
                    individual.genome.content
                );

                let meta = RequestMeta {
                    requires_high_quality: false,
                    requires_phd_level_reasoning: false,
                    high_bias_risk: false,
                    critical_section: false,
                    requires_math: false,
                    offline_required: false,
                    ..Default::default()
                };

                let stats = self.context.get_current_stats().await;
                let (client, _tier) = self.context.router().choose_with_limits(&meta, &stats);

                let response = client.complete(&mutation_prompt).await?;
                individual.genome.content = response.text;

                individual.mutations.push(MutationType::ContentMutation {
                    position: 0,
                    change: "LLM-based variation".to_string(),
                });
            }
            1 => {
                // Structural mutation
                if !individual.genome.structure_genes.is_empty() {
                    let idx = rng.gen_range(0..individual.genome.structure_genes.len());
                    let old_pattern = individual.genome.structure_genes[idx].pattern.clone();

                    let patterns = [
                        ReasoningPattern::Deductive,
                        ReasoningPattern::Inductive,
                        ReasoningPattern::Abductive,
                        ReasoningPattern::Analogical,
                        ReasoningPattern::Causal,
                        ReasoningPattern::Dialectical,
                    ];
                    let new_pattern = patterns.choose(&mut rng).unwrap().clone();

                    individual.genome.structure_genes[idx].pattern = new_pattern.clone();
                    individual.mutations.push(MutationType::StructuralShift {
                        from: old_pattern,
                        to: new_pattern,
                    });
                }
            }
            2 => {
                // Style mutation
                if !individual.genome.style_genes.is_empty() {
                    let idx = 0;
                    let delta = rng.gen_range(-0.2..0.2);

                    match rng.gen_range(0..3) {
                        0 => {
                            individual.genome.style_genes[idx].formality =
                                (individual.genome.style_genes[idx].formality + delta)
                                    .clamp(0.0, 1.0);
                            individual.mutations.push(MutationType::StyleAdjustment {
                                gene: "formality".to_string(),
                                delta,
                            });
                        }
                        1 => {
                            individual.genome.style_genes[idx].technicality =
                                (individual.genome.style_genes[idx].technicality + delta)
                                    .clamp(0.0, 1.0);
                            individual.mutations.push(MutationType::StyleAdjustment {
                                gene: "technicality".to_string(),
                                delta,
                            });
                        }
                        _ => {
                            individual.genome.style_genes[idx].verbosity =
                                (individual.genome.style_genes[idx].verbosity + delta)
                                    .clamp(0.0, 1.0);
                            individual.mutations.push(MutationType::StyleAdjustment {
                                gene: "verbosity".to_string(),
                                delta,
                            });
                        }
                    }
                }
            }
            _ => {
                // Domain mutation
                if !individual.genome.domain_genes.is_empty() {
                    let idx = rng.gen_range(0..individual.genome.domain_genes.len());
                    let delta = rng.gen_range(-0.1..0.1);
                    let new_level = (individual.genome.domain_genes[idx].expertise_level + delta)
                        .clamp(0.0, 1.0);

                    individual.mutations.push(MutationType::DomainAdaptation {
                        domain: individual.genome.domain_genes[idx].domain.clone(),
                        level: new_level,
                    });

                    individual.genome.domain_genes[idx].expertise_level = new_level;
                }
            }
        }

        // Regenerate embedding after mutation
        individual.semantic_embedding = self.generate_embedding(&individual.genome).await?;

        Ok(individual)
    }

    /// Generate semantic embedding for a genome
    async fn generate_embedding(&self, genome: &Genome) -> Result<Vec<f32>> {
        // Use a lightweight model for embedding generation
        let embedding_prompt = format!(
            "Generate a semantic fingerprint for:\n{}\n\
            Style: formality={:.2}, technicality={:.2}\n\
            Reasoning: {:?}",
            genome.content.chars().take(500).collect::<String>(),
            genome
                .style_genes
                .first()
                .map(|s| s.formality)
                .unwrap_or(0.5),
            genome
                .style_genes
                .first()
                .map(|s| s.technicality)
                .unwrap_or(0.5),
            genome.structure_genes.first().map(|s| &s.pattern)
        );

        let meta = RequestMeta {
            requires_high_quality: false,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
            ..Default::default()
        };

        let stats = self.context.get_current_stats().await;
        let (client, _tier) = self.context.router().choose_with_limits(&meta, &stats);

        // For now, generate a pseudo-embedding based on content hash
        // In production, use a proper embedding model
        let hash = md5::compute(embedding_prompt.as_bytes());
        let embedding: Vec<f32> = hash.0.iter().map(|&b| b as f32 / 255.0).collect();

        Ok(embedding)
    }

    /// Calculate population diversity
    async fn calculate_diversity(&self) -> Result<f64> {
        let population = self.population.read().await;
        if population.len() < 2 {
            return Ok(0.0);
        }

        let mut total_distance = 0.0;
        let mut count = 0;

        for i in 0..population.len() {
            for j in i + 1..population.len() {
                let distance = self.semantic_distance(
                    &population[i].semantic_embedding,
                    &population[j].semantic_embedding,
                );
                total_distance += distance;
                count += 1;
            }
        }

        Ok(if count > 0 {
            total_distance / count as f64
        } else {
            0.0
        })
    }

    /// Calculate individual diversity bonus
    async fn calculate_individual_diversity(
        &self,
        individual: &Individual,
        population: &[Individual],
    ) -> Result<f64> {
        let distances: Vec<f64> = population
            .iter()
            .filter(|ind| ind.id != individual.id)
            .map(|ind| {
                self.semantic_distance(&individual.semantic_embedding, &ind.semantic_embedding)
            })
            .collect();

        if distances.is_empty() {
            return Ok(0.0);
        }

        Ok(distances.iter().sum::<f64>() / distances.len() as f64)
    }

    /// Calculate semantic distance between embeddings
    fn semantic_distance(&self, emb1: &[f32], emb2: &[f32]) -> f64 {
        if emb1.len() != emb2.len() {
            return 1.0;
        }

        let sum_sq: f32 = emb1
            .iter()
            .zip(emb2.iter())
            .map(|(a, b)| (a - b).powi(2))
            .sum();

        (sum_sq as f64).sqrt() / (emb1.len() as f64).sqrt()
    }

    /// Adapt mutation rate based on fitness stagnation
    async fn adapt_mutation_rate(&mut self, generation: usize) -> Result<()> {
        let history = self.fitness_history.read().await;

        if history.len() < 5 {
            return Ok(());
        }

        // Check if fitness has stagnated
        let recent = &history[history.len().saturating_sub(5)..];
        let variance = self.calculate_variance(recent);

        if variance < 0.001 {
            // Increase mutation if stagnated
            self.config.mutation_rate = (self.config.mutation_rate * 1.2).min(0.5);
            info!(
                "📈 Increased mutation rate to {:.3} due to stagnation",
                self.config.mutation_rate
            );
        } else if variance > 0.01 {
            // Decrease mutation if improving
            self.config.mutation_rate = (self.config.mutation_rate * 0.9).max(0.05);
            info!(
                "📉 Decreased mutation rate to {:.3} due to progress",
                self.config.mutation_rate
            );
        }

        Ok(())
    }

    /// Calculate variance
    fn calculate_variance(&self, values: &[f64]) -> f64 {
        if values.is_empty() {
            return 0.0;
        }

        let mean = values.iter().sum::<f64>() / values.len() as f64;
        let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64;

        variance
    }

    /// Get the best individual from the population
    async fn get_best_individual(&self) -> Result<Individual> {
        let population = self.population.read().await;
        population
            .iter()
            .max_by(|a, b| a.fitness.partial_cmp(&b.fitness).unwrap())
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("Empty population"))
    }

    /// Calculate average fitness
    async fn calculate_average_fitness(&self) -> Result<f64> {
        let population = self.population.read().await;
        if population.is_empty() {
            return Ok(0.0);
        }

        let total: f64 = population.iter().map(|ind| ind.fitness).sum();
        Ok(total / population.len() as f64)
    }

    /// Export evolution statistics
    pub async fn export_statistics(&self) -> Result<EvolutionStatistics> {
        let generation = *self.generation.read().await;
        let fitness_history = self.fitness_history.read().await.clone();
        let diversity_metrics = self.diversity_metrics.read().await.clone();
        let population = self.population.read().await;

        let best = self.get_best_individual().await?;
        let avg_fitness = self.calculate_average_fitness().await?;

        // Provider distribution
        let mut provider_usage = HashMap::new();
        for ind in population.iter() {
            for provider in ind.provider_scores.keys() {
                *provider_usage.entry(provider.clone()).or_insert(0) += 1;
            }
        }

        Ok(EvolutionStatistics {
            total_generations: generation,
            best_fitness: best.fitness,
            average_fitness: avg_fitness,
            fitness_history,
            diversity_metrics,
            population_size: population.len(),
            mutation_rate: self.config.mutation_rate,
            crossover_rate: self.config.crossover_rate,
            best_individual: best,
            provider_usage,
        })
    }
}

/// Evolution statistics for analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvolutionStatistics {
    pub total_generations: usize,
    pub best_fitness: f64,
    pub average_fitness: f64,
    pub fitness_history: Vec<f64>,
    pub diversity_metrics: Vec<f64>,
    pub population_size: usize,
    pub mutation_rate: f64,
    pub crossover_rate: f64,
    pub best_individual: Individual,
    pub provider_usage: HashMap<String, usize>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_darwin_cycle_initialization() {
        let config = DarwinConfig::default();
        let context = Arc::new(BeagleContext::new_with_mock());
        let cycle = DarwinCycle::new(config, context);

        let seed = "Optimize the algorithm for better performance";
        let context_nodes = vec![];

        let result = cycle.initialize_population(seed, context_nodes).await;
        assert!(result.is_ok());

        let population = cycle.population.read().await;
        assert_eq!(population.len(), 100);
    }

    #[tokio::test]
    async fn test_semantic_distance() {
        let config = DarwinConfig::default();
        let context = Arc::new(BeagleContext::new_with_mock());
        let cycle = DarwinCycle::new(config, context);

        let emb1 = vec![0.1, 0.2, 0.3];
        let emb2 = vec![0.1, 0.2, 0.3];
        let emb3 = vec![0.9, 0.8, 0.7];

        let dist_same = cycle.semantic_distance(&emb1, &emb2);
        assert!(dist_same < 0.01);

        let dist_diff = cycle.semantic_distance(&emb1, &emb3);
        assert!(dist_diff > 0.5);
    }

    #[tokio::test]
    async fn test_mutation_rate_adaptation() {
        let mut config = DarwinConfig::default();
        config.adaptive_mutation = true;
        let context = Arc::new(BeagleContext::new_with_mock());
        let mut cycle = DarwinCycle::new(config, context);

        // Simulate stagnation
        let stagnant_history = vec![0.5, 0.5, 0.5, 0.5, 0.5];
        *cycle.fitness_history.write().await = stagnant_history;

        let initial_rate = cycle.config.mutation_rate;
        cycle.adapt_mutation_rate(5).await.unwrap();

        // Mutation rate should increase due to stagnation
        assert!(cycle.config.mutation_rate > initial_rate);
    }
}
