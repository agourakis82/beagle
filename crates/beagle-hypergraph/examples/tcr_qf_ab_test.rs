//! A/B Testing Example: TCR-QF vs Baseline RAG
//!
//! This example demonstrates how to run a controlled A/B test comparing:
//! - Control group: Baseline RAG (4 factors)
//! - Treatment group: TCR-QF enhanced RAG (8 factors)
//!
//! The test includes:
//! - Randomized assignment
//! - Statistical significance testing
//! - Effect size calculation
//! - Confidence intervals
//! - Early stopping based on statistical power

use anyhow::Result;
use beagle_hypergraph::rag::ab_testing::{
    ABTestConfig, ABTestRunner, AssignmentGroup, ExperimentSample, SampleMetrics,
};
use beagle_hypergraph::rag::eval::{GroundTruth, QueryResult};
use beagle_hypergraph::rag::tcr_qf::TcrQfConfig;
use chrono::Utc;
use std::collections::HashSet;
use uuid::Uuid;

fn main() -> Result<()> {
    println!("\n╔══════════════════════════════════════════════════════════════╗");
    println!("║  TCR-QF A/B Testing Framework Example                      ║");
    println!("╚══════════════════════════════════════════════════════════════╝\n");

    // Configure A/B test
    let config = ABTestConfig {
        test_id: "tcr_qf_vs_baseline_2025_11_25".to_string(),
        description: "Testing TCR-QF 8-factor fusion vs baseline 4-factor".to_string(),
        treatment_ratio: 0.5,        // 50/50 split
        min_sample_size: 50,         // Minimum 50 samples per group
        max_sample_size: 500,        // Maximum 500 samples per group
        alpha: 0.05,                 // 95% confidence level
        min_detectable_effect: 0.15, // Want to detect 15% improvement
        early_stopping_enabled: true,
        early_stopping_check_interval: 25,
        random_seed: Some(42), // For reproducibility
        tcr_qf_config: TcrQfConfig::default(),
    };

    let mut runner = ABTestRunner::new(config.clone());

    println!("📋 Test Configuration:");
    println!("  Test ID: {}", config.test_id);
    println!("  Treatment ratio: {:.0}%", config.treatment_ratio * 100.0);
    println!(
        "  Sample size: {} - {}",
        config.min_sample_size, config.max_sample_size
    );
    println!("  Significance level: α = {}", config.alpha);
    println!(
        "  Min detectable effect: {:.0}%",
        config.min_detectable_effect * 100.0
    );
    println!(
        "  Early stopping: {}\n",
        if config.early_stopping_enabled {
            "enabled"
        } else {
            "disabled"
        }
    );

    // Simulate experiment with synthetic queries
    println!("🧪 Running simulated experiment...\n");

    let num_simulated_queries = 200;
    for i in 0..num_simulated_queries {
        let query_id = Uuid::new_v4();
        let query = format!("Query {}: Medical research question", i + 1);

        // Assign to group
        let group = runner.assign_group(&query_id);

        // Simulate query execution
        let (result, ground_truth) = simulate_query_execution(&query, group);

        // Compute metrics
        let metrics = SampleMetrics::compute(&result, &ground_truth);

        // Create sample
        let sample = ExperimentSample {
            id: Uuid::new_v4(),
            query,
            group,
            result,
            ground_truth,
            timestamp: Utc::now(),
            metrics,
        };

        // Add to runner
        runner.add_sample(sample);

        // Check early stopping every 25 samples
        if (i + 1) % 25 == 0 {
            let should_continue = runner.should_continue()?;
            println!(
                "  Checkpoint at {} samples: {}",
                i + 1,
                if should_continue {
                    "continuing..."
                } else {
                    "early stop triggered!"
                }
            );

            if !should_continue {
                println!("  Early stopping: Statistical significance reached!\n");
                break;
            }
        }
    }

    // Compute final results
    println!("\n📊 Computing final results...\n");
    let results = runner.compute_results()?;

    // Display results
    println!("{}", results.display());

    // Save to file
    let output_path = "/tmp/tcr_qf_ab_test_results.json";
    results.save_to_file(output_path)?;
    println!("\n💾 Results saved to: {}\n", output_path);

    // Additional analysis
    println!("═══ Additional Analysis ═══\n");

    // Check if we met the 29% improvement target
    let mrr_improvement = results.statistical_tests.mrr_ttest.percent_improvement;
    if mrr_improvement >= 29.0 {
        println!("✓ SUCCESS: Achieved target 29% improvement in MRR!");
        println!("  Actual improvement: {:.2}%", mrr_improvement);
    } else if mrr_improvement >= 20.0 {
        println!(
            "⚠ CLOSE: Achieved {:.2}% improvement (target: 29%)",
            mrr_improvement
        );
        println!("  Recommendation: Fine-tune TCR-QF parameters");
    } else {
        println!(
            "✗ BELOW TARGET: Only {:.2}% improvement (target: 29%)",
            mrr_improvement
        );
        println!("  Recommendation: Re-evaluate TCR-QF architecture");
    }

    println!("\n═══ Power Analysis ═══\n");
    let effect_size = results
        .statistical_tests
        .effect_sizes
        .get("mrr")
        .unwrap_or(&0.0);
    println!("Cohen's d effect size: {:.3}", effect_size);
    if effect_size.abs() >= 0.8 {
        println!("  Classification: LARGE effect");
    } else if effect_size.abs() >= 0.5 {
        println!("  Classification: MEDIUM effect");
    } else if effect_size.abs() >= 0.2 {
        println!("  Classification: SMALL effect");
    } else {
        println!("  Classification: NEGLIGIBLE effect");
    }

    println!("\n═══ Sample Quality ═══\n");
    println!("Control group samples: {}", results.control_samples.len());
    println!(
        "Treatment group samples: {}",
        results.treatment_samples.len()
    );
    println!(
        "Balance ratio: {:.2}",
        results.treatment_samples.len() as f32 / results.control_samples.len() as f32
    );

    if results.early_stopped {
        println!(
            "\nTest stopped early: {}",
            results.stop_reason.unwrap_or_default()
        );
    }

    Ok(())
}

/// Simulate query execution for A/B test
///
/// In production, this would call actual RAG pipeline with control/treatment configuration
fn simulate_query_execution(_query: &str, group: AssignmentGroup) -> (QueryResult, GroundTruth) {
    use rand::Rng;
    let mut rng = rand::thread_rng();

    // Generate synthetic relevant documents
    let num_relevant = rng.gen_range(2..=5);
    let relevant_docs: HashSet<Uuid> = (0..num_relevant).map(|_| Uuid::new_v4()).collect();

    // Generate relevance scores
    let mut relevance_scores = std::collections::HashMap::new();
    for doc in &relevant_docs {
        relevance_scores.insert(*doc, rng.gen_range(0.5..=1.0));
    }

    let ground_truth = GroundTruth {
        relevant: relevant_docs.clone(),
        relevance_scores,
    };

    // Simulate retrieval results
    // Treatment group (TCR-QF) has better ranking
    let mut retrieved = Vec::new();
    let mut relevant_vec: Vec<Uuid> = relevant_docs.iter().copied().collect();

    match group {
        AssignmentGroup::Control => {
            // Baseline: First relevant doc appears around rank 3-5
            // Add 2-4 non-relevant docs first
            let noise_count = rng.gen_range(2..=4);
            for _ in 0..noise_count {
                retrieved.push(Uuid::new_v4());
            }

            // Add first relevant doc
            if !relevant_vec.is_empty() {
                retrieved.push(relevant_vec[0]);
                relevant_vec.remove(0);
            }

            // Mix in more noise
            for _ in 0..rng.gen_range(2..=4) {
                retrieved.push(Uuid::new_v4());
            }

            // Add remaining relevant docs scattered
            for (i, doc) in relevant_vec.iter().enumerate() {
                retrieved.push(*doc);
                if i < relevant_vec.len() - 1 {
                    // Add noise between relevant docs
                    for _ in 0..rng.gen_range(1..=2) {
                        retrieved.push(Uuid::new_v4());
                    }
                }
            }

            // Fill to 20 docs
            while retrieved.len() < 20 {
                retrieved.push(Uuid::new_v4());
            }
        }
        AssignmentGroup::Treatment => {
            // TCR-QF: First relevant doc appears at rank 1-2 (35% better than control)
            // Add 0-1 non-relevant docs first
            if rng.gen_bool(0.3) {
                retrieved.push(Uuid::new_v4());
            }

            // Add first relevant doc earlier
            if !relevant_vec.is_empty() {
                retrieved.push(relevant_vec[0]);
                relevant_vec.remove(0);
            }

            // Add one noise doc
            retrieved.push(Uuid::new_v4());

            // Add remaining relevant docs with less noise
            for doc in relevant_vec.iter() {
                retrieved.push(*doc);
                // Less noise in treatment
                if rng.gen_bool(0.3) {
                    retrieved.push(Uuid::new_v4());
                }
            }

            // Fill to 20 docs
            while retrieved.len() < 20 {
                retrieved.push(Uuid::new_v4());
            }
        }
    }

    // Simulate latency (TCR-QF is slightly slower due to additional computation)
    let base_latency = rng.gen_range(50.0..150.0);
    let latency_overhead = match group {
        AssignmentGroup::Control => 1.0,
        AssignmentGroup::Treatment => 1.05, // 5% latency overhead
    };
    let latency_ms = base_latency * latency_overhead;

    let result = QueryResult {
        retrieved,
        latency_ms,
    };

    (result, ground_truth)
}
