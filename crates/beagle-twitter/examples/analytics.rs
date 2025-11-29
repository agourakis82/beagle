//! # Twitter/X Analytics Examples
//!
//! Run with: `cargo run --example analytics`

use anyhow::Result;
use beagle_twitter::TwitterSystem;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    // Create Twitter system
    let system = TwitterSystem::from_env()?;

    println!("=== BEAGLE Twitter/X Analytics Examples ===\n");

    // Example 1: Tweet metrics
    example_tweet_metrics(&system).await?;

    // Example 2: Timeline analytics
    example_timeline_analytics(&system).await?;

    // Example 3: Hashtag performance
    example_hashtag_performance(&system).await?;

    Ok(())
}

async fn example_tweet_metrics(system: &TwitterSystem) -> Result<()> {
    println!("Example 1: Tweet metrics analysis");
    println!("----------------------------------");

    // Post a test tweet
    let tweet = system
        .tweet("Testing BEAGLE analytics capabilities 📊 #Analytics #DataScience")
        .await?;
    println!("Posted tweet: {}", tweet.id);

    // Wait a bit for metrics to populate
    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;

    // Get metrics
    let metrics = system.get_metrics(&tweet.id).await?;

    println!("\n📊 Tweet Metrics:");
    println!("   Impressions: {}", metrics.impressions);
    println!("   Likes: {}", metrics.likes);
    println!("   Retweets: {}", metrics.retweets);
    println!("   Replies: {}", metrics.replies);
    println!("   Quotes: {}", metrics.quotes);
    println!("   URL clicks: {}", metrics.url_clicks);
    println!("   Profile clicks: {}", metrics.profile_clicks);

    // Get engagement data
    let engagement = system.get_engagement(&tweet.id).await?;

    println!("\n📈 Engagement Analysis:");
    println!("   Engagement rate: {:.2}%", engagement.engagement_rate);
    println!(
        "   Amplification factor: {:.4}",
        engagement.amplification_factor
    );
    println!("   Virality score: {:.2}/100", engagement.virality_score);

    Ok(())
}

async fn example_timeline_analytics(system: &TwitterSystem) -> Result<()> {
    println!("\nExample 2: Timeline analytics");
    println!("------------------------------");

    // Get authenticated user ID (would normally be cached)
    let user_id = "1234567890"; // Replace with actual user ID

    // Get 7-day timeline analytics
    match system.analytics.get_timeline_analytics(user_id, 7).await {
        Ok(analytics) => {
            println!(
                "\n📊 7-Day Timeline Analytics for user {}:",
                analytics.user_id
            );
            println!("   Total tweets: {}", analytics.total_tweets);
            println!("   Total impressions: {}", analytics.total_impressions);
            println!("   Total engagements: {}", analytics.total_engagements);
            println!(
                "   Average engagement rate: {:.2}%",
                analytics.average_engagement_rate
            );

            if let Some(best) = analytics.best_performing_tweet_id {
                println!("   Best performing tweet: {}", best);
            }

            if let Some(worst) = analytics.worst_performing_tweet_id {
                println!("   Worst performing tweet: {}", worst);
            }

            println!("\n⏰ Optimal posting hours:");
            for hour in analytics.optimal_posting_hours {
                println!("   - {}:00 UTC", hour);
            }

            println!("\n🏆 Top performing topics:");
            for topic in analytics.top_performing_topics {
                println!("   - {}", topic);
            }
        }
        Err(e) => {
            println!("⚠️  Could not get timeline analytics: {}", e);
        }
    }

    Ok(())
}

async fn example_hashtag_performance(system: &TwitterSystem) -> Result<()> {
    println!("\nExample 3: Hashtag performance");
    println!("-------------------------------");

    let hashtags = vec!["AI", "MachineLearning", "Rust"];

    for hashtag in hashtags {
        match system.analytics.get_hashtag_performance(hashtag, 100).await {
            Ok(analytics) => {
                println!("\n#{} Performance:", analytics.hashtag);
                println!("   Tweet count: {}", analytics.tweet_count);
                println!("   Unique authors: {}", analytics.unique_authors);
                println!("   Total reach: {}", analytics.total_reach);
                println!("   Total engagements: {}", analytics.total_engagements);
                println!("   Average engagement: {}", analytics.average_engagement);
                println!("   Trending score: {:.2}", analytics.trending_score);

                // Calculate engagement quality
                let quality = if analytics.tweet_count > 0 {
                    analytics.unique_authors as f64 / analytics.tweet_count as f64
                } else {
                    0.0
                };
                println!("   Engagement quality: {:.2}%", quality * 100.0);
            }
            Err(e) => {
                println!("\n⚠️  Could not analyze #{}: {}", hashtag, e);
            }
        }
    }

    // Compare hashtags
    println!("\n📊 Hashtag Comparison Summary:");
    println!("   Use hashtags with high trending scores and engagement quality");
    println!("   for maximum visibility and authentic engagement.");

    Ok(())
}
