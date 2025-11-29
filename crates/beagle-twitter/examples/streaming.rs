//! # Twitter/X Streaming API Examples
//!
//! Run with: `cargo run --example streaming`

use anyhow::Result;
use beagle_twitter::{FilterRule, StreamEvent, StreamProcessor, TwitterSystem};
use std::sync::Arc;
use tokio::time::{sleep, Duration};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create Twitter system
    let system = TwitterSystem::from_env()?;

    println!("=== BEAGLE Twitter/X Streaming Examples ===\n");

    // Example 1: Basic streaming
    example_basic_streaming(&system).await?;

    // Example 2: Advanced stream processing
    example_advanced_processing(&system).await?;

    Ok(())
}

async fn example_basic_streaming(system: &TwitterSystem) -> Result<()> {
    println!("Example 1: Basic streaming");
    println!("--------------------------");

    // Set up filter rules
    let rules = vec![
        FilterRule::with_tag("from:elonmusk", "elon"),
        FilterRule::with_tag("#AI OR #MachineLearning", "ai"),
        FilterRule::with_tag("bitcoin OR ethereum", "crypto"),
    ];

    println!("Starting stream with {} rules:", rules.len());
    for rule in &rules {
        println!("  - {} (tag: {:?})", rule.value, rule.tag);
    }

    // Start streaming
    system.start_streaming(rules).await?;
    println!("✅ Stream connected\n");

    // Collect events for 30 seconds
    println!("Collecting tweets for 30 seconds...");
    let start = std::time::Instant::now();

    while start.elapsed().as_secs() < 30 {
        sleep(Duration::from_secs(5)).await;

        let events = system.get_stream_events().await?;

        for event in events {
            match event {
                StreamEvent::Tweet {
                    tweet,
                    matching_rules,
                } => {
                    println!("📝 New tweet from @{}", tweet.author_id);
                    println!("   Text: {}...", &tweet.text[..50.min(tweet.text.len())]);
                    println!("   Matching rules: {:?}", matching_rules);

                    if let Some(metrics) = tweet.public_metrics {
                        println!(
                            "   Metrics: {} likes, {} retweets",
                            metrics.like_count, metrics.retweet_count
                        );
                    }
                }
                StreamEvent::Error {
                    message,
                    recoverable,
                } => {
                    println!(
                        "❌ Stream error: {} (recoverable: {})",
                        message, recoverable
                    );
                }
                _ => {}
            }
        }
    }

    // Stop streaming
    system.stop_streaming().await?;
    println!("\n✅ Stream disconnected");

    Ok(())
}

async fn example_advanced_processing(system: &TwitterSystem) -> Result<()> {
    println!("\nExample 2: Advanced stream processing");
    println!("--------------------------------------");

    // Create stream processor
    let processor = Arc::new(StreamProcessor::new(system.streaming.clone()));

    // Add custom handlers
    let processor_clone = processor.clone();
    processor
        .add_handler("sentiment", move |tweet| {
            // Analyze sentiment (simplified)
            let positive_words = ["good", "great", "awesome", "love", "amazing"];
            let negative_words = ["bad", "hate", "terrible", "awful", "worst"];

            let text_lower = tweet.text.to_lowercase();
            let positive_count = positive_words
                .iter()
                .filter(|&&word| text_lower.contains(word))
                .count();
            let negative_count = negative_words
                .iter()
                .filter(|&&word| text_lower.contains(word))
                .count();

            let sentiment = if positive_count > negative_count {
                "POSITIVE"
            } else if negative_count > positive_count {
                "NEGATIVE"
            } else {
                "NEUTRAL"
            };

            println!(
                "📊 Sentiment: {} for tweet: {}...",
                sentiment,
                &tweet.text[..30.min(tweet.text.len())]
            );
        })
        .await;

    processor
        .add_handler("crypto_alert", |tweet| {
            if tweet.text.to_lowercase().contains("bitcoin") {
                println!("🚨 CRYPTO ALERT: Bitcoin mentioned!");
                println!("   Tweet: {}", tweet.text);
            }
        })
        .await;

    processor
        .add_handler("viral_detector", |tweet| {
            if let Some(metrics) = tweet.public_metrics {
                if metrics.retweet_count > 1000 {
                    println!("🔥 VIRAL TWEET DETECTED!");
                    println!("   {} retweets: {}", metrics.retweet_count, tweet.text);
                }
            }
        })
        .await;

    // Set up rules
    let rules = vec![
        FilterRule::new("(bitcoin OR ethereum) -is:retweet"),
        FilterRule::new("AI OR artificial intelligence lang:en"),
    ];

    system.streaming.add_rules(rules).await?;
    system.streaming.connect().await?;

    println!("Processing stream for 60 seconds with custom handlers...\n");

    // Process in background
    let processor_task = processor.clone();
    let process_handle = tokio::spawn(async move { processor_task.process().await });

    // Wait and show stats
    for _ in 0..6 {
        sleep(Duration::from_secs(10)).await;

        let stats = processor.get_stats().await;
        println!("\n📈 Stream Statistics:");
        println!("   Tweets received: {}", stats.tweets_received);
        println!("   Errors: {}", stats.errors);
        println!("   Rate limit hits: {}", stats.rate_limit_hits);

        if let Some(last) = stats.last_tweet_at {
            println!("   Last tweet: {:?} ago", last.elapsed());
        }
    }

    // Stop processing
    system.streaming.disconnect().await?;
    process_handle.abort();

    println!("\n✅ Advanced processing complete");

    Ok(())
}
