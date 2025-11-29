//! # Basic Twitter/X API Usage Examples
//!
//! Run with: `cargo run --example basic_usage`

use anyhow::Result;
use beagle_twitter::{TwitterAuth, TwitterConfig, TwitterSystem};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create Twitter system from environment
    let system = TwitterSystem::from_env()?;

    println!("=== BEAGLE Twitter/X Basic Examples ===\n");

    // Example 1: Post a simple tweet
    example_simple_tweet(&system).await?;

    // Example 2: Post a thread
    example_thread(&system).await?;

    // Example 3: Search and interact
    example_search_interact(&system).await?;

    // Example 4: Get timeline
    example_timeline(&system).await?;

    Ok(())
}

async fn example_simple_tweet(system: &TwitterSystem) -> Result<()> {
    println!("Example 1: Posting a simple tweet");
    println!("---------------------------------");

    let tweet = system
        .tweet("🚀 Hello from BEAGLE Twitter integration! #AI #Rust")
        .await?;

    println!("✅ Posted tweet: {}", tweet.id);
    println!("   Text: {}", tweet.text);
    println!();

    Ok(())
}

async fn example_thread(system: &TwitterSystem) -> Result<()> {
    println!("Example 2: Posting a thread");
    println!("---------------------------");

    let thread_text = vec![
        "🧵 Let's talk about AI and social media integration!".to_string(),
        "1/ Modern AI systems need to understand and interact with social platforms effectively.".to_string(),
        "2/ BEAGLE's Twitter integration provides comprehensive API v2 support with streaming, analytics, and more.".to_string(),
        "3/ Built with Rust for performance and reliability. Perfect for research and production use cases.".to_string(),
        "/end Learn more at https://github.com/beagle-ai".to_string(),
    ];

    let posted = system.post_thread(thread_text).await?;

    println!("✅ Posted thread with {} tweets:", posted.len());
    for (i, tweet) in posted.iter().enumerate() {
        println!(
            "   {}/{}: {} ({})",
            i + 1,
            posted.len(),
            &tweet.text[..50.min(tweet.text.len())],
            tweet.id
        );
    }
    println!();

    Ok(())
}

async fn example_search_interact(system: &TwitterSystem) -> Result<()> {
    println!("Example 3: Search and interact");
    println!("-------------------------------");

    // Search for tweets
    let results = system.search("AI research lang:en -is:retweet", 10).await?;

    println!("Found {} tweets about AI research:", results.len());

    if let Some(first) = results.first() {
        println!("First result:");
        println!("  Author: {}", first.author_id);
        println!("  Text: {}...", &first.text[..100.min(first.text.len())]);

        // Like the tweet
        system.like(&first.id).await?;
        println!("  ✅ Liked tweet");

        // Reply to the tweet
        let reply = system
            .reply(&first.id, "Interesting perspective on AI research! 🤖")
            .await?;
        println!("  ✅ Posted reply: {}", reply.id);
    }
    println!();

    Ok(())
}

async fn example_timeline(system: &TwitterSystem) -> Result<()> {
    println!("Example 4: Get home timeline");
    println!("-----------------------------");

    let timeline = system.get_home_timeline(5).await?;

    println!("Latest {} tweets from home timeline:", timeline.len());
    for tweet in timeline {
        println!(
            "  - {}: {}...",
            tweet.author_id,
            &tweet.text[..50.min(tweet.text.len())]
        );

        if let Some(metrics) = tweet.public_metrics {
            println!(
                "    📊 {} likes, {} retweets",
                metrics.like_count, metrics.retweet_count
            );
        }
    }
    println!();

    Ok(())
}
