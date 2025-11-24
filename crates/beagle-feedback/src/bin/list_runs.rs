//! List all pipeline runs with metadata
//!
//! Usage: cargo run --bin list_runs --package beagle-feedback
//!
//! Lists all runs found in feedback_events.jsonl with:
//! - run_id
//! - date
//! - question (truncated)
//! - has_triad (Y/N)
//! - has_feedback (Y/N)
//! - rating (if available)
//! - accepted (if available)

use beagle_config::beagle_data_dir;
use beagle_feedback::{load_all_events, FeedbackEventType};
use chrono::{DateTime, Utc};
use std::collections::HashMap;

#[derive(Debug, Default)]
struct RunSummary {
    run_id: String,
    timestamp: Option<DateTime<Utc>>,
    question: Option<String>,
    has_pipeline: bool,
    has_triad: bool,
    has_feedback: bool,
    accepted: Option<bool>,
    rating: Option<u8>,
}

fn main() -> anyhow::Result<()> {
    // Get data directory
    let data_dir = beagle_data_dir();

    // Load all feedback events
    let events = load_all_events(&data_dir)?;

    if events.is_empty() {
        println!("No feedback events found in {}", data_dir.display());
        println!("Run some pipelines first to generate data.");
        return Ok(());
    }

    // Group events by run_id
    let mut runs: HashMap<String, RunSummary> = HashMap::new();

    for event in events {
        let entry = runs.entry(event.run_id.clone()).or_insert_with(|| RunSummary {
            run_id: event.run_id.clone(),
            timestamp: Some(event.timestamp),
            question: event.question.clone(),
            ..Default::default()
        });

        // Update timestamp to earliest
        if let Some(ts) = entry.timestamp {
            if event.timestamp < ts {
                entry.timestamp = Some(event.timestamp);
            }
        }

        // Update question if not set
        if entry.question.is_none() && event.question.is_some() {
            entry.question = event.question.clone();
        }

        // Mark event types
        match event.event_type {
            FeedbackEventType::PipelineRun => {
                entry.has_pipeline = true;
            }
            FeedbackEventType::TriadCompleted => {
                entry.has_triad = true;
            }
            FeedbackEventType::HumanFeedback => {
                entry.has_feedback = true;
                if event.accepted.is_some() {
                    entry.accepted = event.accepted;
                }
                if event.rating_0_10.is_some() {
                    entry.rating = event.rating_0_10;
                }
            }
        }
    }

    // Convert to sorted vector
    let mut run_list: Vec<RunSummary> = runs.into_values().collect();
    run_list.sort_by(|a, b| {
        b.timestamp.cmp(&a.timestamp) // Most recent first
    });

    // Print header
    println!("\n=== BEAGLE Pipeline Runs ===\n");
    println!(
        "{:<38} {:<20} {:<50} {:^7} {:^7} {:^7} {:>6} {:>8}",
        "RUN_ID", "DATE", "QUESTION", "PIPE", "TRIAD", "FEEDBK", "RATING", "ACCEPTED"
    );
    println!("{}", "=".repeat(160));

    // Print each run
    for run in &run_list {
        let date_str = run
            .timestamp
            .map(|ts| ts.format("%Y-%m-%d %H:%M").to_string())
            .unwrap_or_else(|| "N/A".to_string());

        let question_str = run
            .question
            .as_ref()
            .map(|q| {
                if q.len() > 47 {
                    format!("{}...", &q[..47])
                } else {
                    q.clone()
                }
            })
            .unwrap_or_else(|| "N/A".to_string());

        let pipeline_mark = if run.has_pipeline { "Y" } else { "-" };
        let triad_mark = if run.has_triad { "Y" } else { "-" };
        let feedback_mark = if run.has_feedback { "Y" } else { "-" };

        let rating_str = run
            .rating
            .map(|r| format!("{}/10", r))
            .unwrap_or_else(|| "-".to_string());

        let accepted_str = match run.accepted {
            Some(true) => "✓",
            Some(false) => "✗",
            None => "-",
        };

        println!(
            "{:<38} {:<20} {:<50} {:^7} {:^7} {:^7} {:>6} {:>8}",
            run.run_id,
            date_str,
            question_str,
            pipeline_mark,
            triad_mark,
            feedback_mark,
            rating_str,
            accepted_str
        );
    }

    println!("\n{} total runs found\n", run_list.len());

    // Print summary stats
    let total_pipeline = run_list.iter().filter(|r| r.has_pipeline).count();
    let total_triad = run_list.iter().filter(|r| r.has_triad).count();
    let total_feedback = run_list.iter().filter(|r| r.has_feedback).count();
    let total_accepted = run_list.iter().filter(|r| r.accepted == Some(true)).count();
    let total_rejected = run_list.iter().filter(|r| r.accepted == Some(false)).count();

    println!("=== SUMMARY ===");
    println!("Pipeline runs:     {}", total_pipeline);
    println!("Triad reviews:     {}", total_triad);
    println!("Human feedback:    {}", total_feedback);
    println!("  Accepted:        {}", total_accepted);
    println!("  Rejected:        {}", total_rejected);

    // Average rating if available
    let ratings: Vec<u8> = run_list.iter().filter_map(|r| r.rating).collect();
    if !ratings.is_empty() {
        let avg_rating = ratings.iter().map(|&r| r as f64).sum::<f64>() / ratings.len() as f64;
        println!("  Avg rating:      {:.1}/10", avg_rating);
    }

    Ok(())
}
