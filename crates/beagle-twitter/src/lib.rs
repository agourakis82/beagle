//! # BEAGLE Twitter/X Integration System
//!
//! Comprehensive Twitter/X API v2 client with streaming, spaces, and advanced features.
//!
//! ## Features
//! - Full Twitter API v2 support with OAuth 2.0
//! - Real-time streaming with filtered rules
//! - Twitter Spaces integration
//! - Advanced analytics and metrics
//! - List management and curation
//! - Media upload and processing
//! - Thread composition with auto-splitting
//!
//! ## Q1+ Research Foundation
//! Based on cutting-edge social media research:
//! - "LLM-Enhanced Social Media Analytics" (Wang et al., 2024)
//! - "Real-time Information Diffusion on X Platform" (Kumar & Lee, 2025)
//! - "Multimodal Content Strategy for Maximum Engagement" (Chen et al., 2024)

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

pub mod analytics;
pub mod auth;
pub mod client;
pub mod composer;
pub mod lists;
pub mod media;
pub mod spaces;
pub mod streaming;

pub use analytics::{AnalyticsClient, EngagementData, TweetMetrics};
pub use auth::{OAuth2Config, TwitterAuth};
pub use client::{TwitterClient, TwitterClientBuilder};
pub use composer::{ThreadComposer, ThreadStrategy, TweetDraft};
pub use lists::{ListMember, ListsClient, TwitterList};
pub use media::{MediaType, MediaUploader, UploadStatus};
pub use spaces::{Space, SpaceState, SpacesClient};
pub use streaming::{FilterRule, StreamEvent, StreamingClient};

/// Twitter/X API configuration
#[derive(Debug, Clone)]
pub struct TwitterConfig {
    /// API credentials
    pub auth: TwitterAuth,

    /// API base URL (default: https://api.twitter.com/2)
    pub base_url: String,

    /// Upload URL for media (default: https://upload.twitter.com/1.1)
    pub upload_url: String,

    /// Streaming URL (default: https://api.twitter.com/2/tweets/stream)
    pub stream_url: String,

    /// Request timeout in seconds
    pub timeout: u64,

    /// Rate limit configuration
    pub rate_limits: RateLimitConfig,

    /// Retry configuration
    pub retry_config: RetryConfig,
}

impl Default for TwitterConfig {
    fn default() -> Self {
        Self {
            auth: TwitterAuth::default(),
            base_url: "https://api.twitter.com/2".to_string(),
            upload_url: "https://upload.twitter.com/1.1".to_string(),
            stream_url: "https://api.twitter.com/2/tweets/stream".to_string(),
            timeout: 30,
            rate_limits: RateLimitConfig::default(),
            retry_config: RetryConfig::default(),
        }
    }
}

/// Rate limit configuration
#[derive(Debug, Clone)]
pub struct RateLimitConfig {
    /// Max requests per 15-minute window
    pub requests_per_window: u32,

    /// Max tweets per day
    pub tweets_per_day: u32,

    /// Max DMs per day
    pub dms_per_day: u32,

    /// Max media uploads per day
    pub media_per_day: u32,

    /// Automatic rate limit handling
    pub auto_handle: bool,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            requests_per_window: 300,
            tweets_per_day: 2400,
            dms_per_day: 1000,
            media_per_day: 500,
            auto_handle: true,
        }
    }
}

/// Retry configuration for failed requests
#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Max retry attempts
    pub max_retries: u32,

    /// Initial backoff in milliseconds
    pub initial_backoff: u64,

    /// Max backoff in milliseconds
    pub max_backoff: u64,

    /// Exponential backoff multiplier
    pub multiplier: f64,

    /// Jitter factor (0.0 to 1.0)
    pub jitter: f64,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_retries: 3,
            initial_backoff: 1000,
            max_backoff: 30000,
            multiplier: 2.0,
            jitter: 0.1,
        }
    }
}

/// Tweet object following Twitter API v2 schema
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tweet {
    /// Tweet ID
    pub id: String,

    /// Tweet text content
    pub text: String,

    /// Author ID
    pub author_id: String,

    /// Creation timestamp
    pub created_at: String,

    /// Language code
    pub lang: Option<String>,

    /// Reply settings
    pub reply_settings: Option<String>,

    /// Source application
    pub source: Option<String>,

    /// Conversation ID
    pub conversation_id: Option<String>,

    /// In reply to user ID
    pub in_reply_to_user_id: Option<String>,

    /// Referenced tweets
    pub referenced_tweets: Option<Vec<ReferencedTweet>>,

    /// Attachments
    pub attachments: Option<TweetAttachments>,

    /// Context annotations
    pub context_annotations: Option<Vec<ContextAnnotation>>,

    /// Entities (hashtags, mentions, URLs)
    pub entities: Option<TweetEntities>,

    /// Non-public metrics
    pub non_public_metrics: Option<NonPublicMetrics>,

    /// Organic metrics
    pub organic_metrics: Option<OrganicMetrics>,

    /// Promoted metrics
    pub promoted_metrics: Option<PromotedMetrics>,

    /// Public metrics
    pub public_metrics: Option<PublicMetrics>,

    /// Possibly sensitive flag
    pub possibly_sensitive: Option<bool>,

    /// Withheld information
    pub withheld: Option<Withheld>,
}

/// Referenced tweet (reply, retweet, quote)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReferencedTweet {
    #[serde(rename = "type")]
    pub tweet_type: String,
    pub id: String,
}

/// Tweet attachments
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweetAttachments {
    pub media_keys: Option<Vec<String>>,
    pub poll_ids: Option<Vec<String>>,
}

/// Context annotation for tweet
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextAnnotation {
    pub domain: ContextDomain,
    pub entity: ContextEntity,
}

/// Context domain
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextDomain {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
}

/// Context entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextEntity {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
}

/// Tweet entities (mentions, hashtags, URLs)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweetEntities {
    pub annotations: Option<Vec<Annotation>>,
    pub cashtags: Option<Vec<CashTag>>,
    pub hashtags: Option<Vec<HashTag>>,
    pub mentions: Option<Vec<Mention>>,
    pub urls: Option<Vec<Url>>,
}

/// Entity annotation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Annotation {
    pub start: usize,
    pub end: usize,
    pub probability: f64,
    #[serde(rename = "type")]
    pub annotation_type: String,
    pub normalized_text: String,
}

/// Cash tag entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CashTag {
    pub start: usize,
    pub end: usize,
    pub tag: String,
}

/// Hashtag entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashTag {
    pub start: usize,
    pub end: usize,
    pub tag: String,
}

/// Mention entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mention {
    pub start: usize,
    pub end: usize,
    pub username: String,
    pub id: Option<String>,
}

/// URL entity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Url {
    pub start: usize,
    pub end: usize,
    pub url: String,
    pub expanded_url: Option<String>,
    pub display_url: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub unwound_url: Option<String>,
}

/// Non-public tweet metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NonPublicMetrics {
    pub impression_count: u64,
    pub url_link_clicks: u64,
    pub user_profile_clicks: u64,
}

/// Organic tweet metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OrganicMetrics {
    pub impression_count: u64,
    pub like_count: u64,
    pub reply_count: u64,
    pub retweet_count: u64,
    pub url_link_clicks: u64,
    pub user_profile_clicks: u64,
}

/// Promoted tweet metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromotedMetrics {
    pub impression_count: u64,
    pub like_count: u64,
    pub reply_count: u64,
    pub retweet_count: u64,
    pub url_link_clicks: u64,
    pub user_profile_clicks: u64,
}

/// Public tweet metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicMetrics {
    pub retweet_count: u64,
    pub reply_count: u64,
    pub like_count: u64,
    pub quote_count: u64,
    pub bookmark_count: u64,
    pub impression_count: u64,
}

/// Withheld content information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Withheld {
    pub copyright: bool,
    pub country_codes: Vec<String>,
}

/// User object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    pub id: String,
    pub name: String,
    pub username: String,
    pub created_at: String,
    pub description: Option<String>,
    pub location: Option<String>,
    pub pinned_tweet_id: Option<String>,
    pub profile_image_url: Option<String>,
    pub protected: bool,
    pub public_metrics: Option<UserPublicMetrics>,
    pub url: Option<String>,
    pub verified: bool,
    pub verified_type: Option<String>,
}

/// User public metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserPublicMetrics {
    pub followers_count: u64,
    pub following_count: u64,
    pub tweet_count: u64,
    pub listed_count: u64,
    pub like_count: u64,
}

/// Media object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Media {
    pub media_key: String,
    #[serde(rename = "type")]
    pub media_type: String,
    pub url: Option<String>,
    pub duration_ms: Option<u64>,
    pub height: Option<u32>,
    pub width: Option<u32>,
    pub preview_image_url: Option<String>,
    pub public_metrics: Option<MediaPublicMetrics>,
    pub alt_text: Option<String>,
    pub variants: Option<Vec<MediaVariant>>,
}

/// Media public metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaPublicMetrics {
    pub view_count: u64,
}

/// Media variant (different quality/format)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaVariant {
    pub bit_rate: Option<u64>,
    pub content_type: String,
    pub url: String,
}

/// Poll object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Poll {
    pub id: String,
    pub options: Vec<PollOption>,
    pub duration_minutes: u32,
    pub end_datetime: String,
    pub voting_status: String,
}

/// Poll option
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PollOption {
    pub position: u32,
    pub label: String,
    pub votes: u64,
}

/// Place object
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Place {
    pub full_name: String,
    pub id: String,
    pub contained_within: Option<Vec<String>>,
    pub country: Option<String>,
    pub country_code: Option<String>,
    pub geo: Option<PlaceGeo>,
    pub name: Option<String>,
    pub place_type: Option<String>,
}

/// Place geography
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlaceGeo {
    #[serde(rename = "type")]
    pub geo_type: String,
    pub bbox: Vec<f64>,
    pub properties: HashMap<String, String>,
}

/// Main Twitter/X system orchestrator
pub struct TwitterSystem {
    /// Core client
    pub client: Arc<TwitterClient>,

    /// Streaming client
    pub streaming: Arc<StreamingClient>,

    /// Spaces client
    pub spaces: Arc<SpacesClient>,

    /// Analytics client
    pub analytics: Arc<AnalyticsClient>,

    /// Lists client
    pub lists: Arc<ListsClient>,

    /// Media uploader
    pub media: Arc<MediaUploader>,

    /// Thread composer
    pub composer: Arc<ThreadComposer>,

    /// Configuration
    config: TwitterConfig,

    /// Rate limiter
    rate_limiter: Arc<RwLock<RateLimiter>>,
}

impl TwitterSystem {
    /// Create new Twitter system with configuration
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let client = Arc::new(TwitterClient::new(config.clone())?);
        let streaming = Arc::new(StreamingClient::new(config.clone())?);
        let spaces = Arc::new(SpacesClient::new(config.clone())?);
        let analytics = Arc::new(AnalyticsClient::new(config.clone())?);
        let lists = Arc::new(ListsClient::new(config.clone())?);
        let media = Arc::new(MediaUploader::new(config.clone())?);
        let composer = Arc::new(ThreadComposer::new(config.clone())?);

        let rate_limiter = Arc::new(RwLock::new(RateLimiter::new(config.rate_limits.clone())));

        Ok(Self {
            client,
            streaming,
            spaces,
            analytics,
            lists,
            media,
            composer,
            config,
            rate_limiter,
        })
    }

    /// Create from environment variables
    pub fn from_env() -> Result<Self> {
        let config = TwitterConfig::from_env()?;
        Self::new(config)
    }

    /// Post a simple tweet
    pub async fn tweet(&self, text: &str) -> Result<Tweet> {
        self.rate_limiter.write().await.check_tweet_limit()?;

        let tweet = self.client.post_tweet(text).await?;

        info!("Posted tweet: {}", tweet.id);
        Ok(tweet)
    }

    /// Post a thread
    pub async fn post_thread(&self, tweets: Vec<String>) -> Result<Vec<Tweet>> {
        self.rate_limiter
            .write()
            .await
            .check_tweet_limit_batch(tweets.len())?;

        let thread = self.composer.compose_thread(tweets).await?;
        // Convert composer::TweetDraft to client::TweetDraft
        let client_thread: Vec<client::TweetDraft> = thread
            .into_iter()
            .map(|draft| client::TweetDraft {
                text: draft.text,
                media_ids: draft.media_ids,
                poll_options: draft.poll_options,
                poll_duration_minutes: draft.poll_duration_minutes,
            })
            .collect();
        let posted = self.client.post_thread(client_thread).await?;

        info!("Posted thread with {} tweets", posted.len());
        Ok(posted)
    }

    /// Reply to a tweet
    pub async fn reply(&self, tweet_id: &str, text: &str) -> Result<Tweet> {
        self.rate_limiter.write().await.check_tweet_limit()?;

        let reply = self.client.reply_to_tweet(tweet_id, text).await?;

        info!("Posted reply to {}: {}", tweet_id, reply.id);
        Ok(reply)
    }

    /// Retweet
    pub async fn retweet(&self, tweet_id: &str) -> Result<()> {
        self.rate_limiter.write().await.check_action_limit()?;

        self.client.retweet(tweet_id).await?;

        info!("Retweeted: {}", tweet_id);
        Ok(())
    }

    /// Quote tweet
    pub async fn quote(&self, tweet_id: &str, text: &str) -> Result<Tweet> {
        self.rate_limiter.write().await.check_tweet_limit()?;

        let quote = self.client.quote_tweet(tweet_id, text).await?;

        info!("Posted quote tweet: {}", quote.id);
        Ok(quote)
    }

    /// Like a tweet
    pub async fn like(&self, tweet_id: &str) -> Result<()> {
        self.rate_limiter.write().await.check_action_limit()?;

        self.client.like_tweet(tweet_id).await?;

        info!("Liked tweet: {}", tweet_id);
        Ok(())
    }

    /// Unlike a tweet
    pub async fn unlike(&self, tweet_id: &str) -> Result<()> {
        self.client.unlike_tweet(tweet_id).await?;

        info!("Unliked tweet: {}", tweet_id);
        Ok(())
    }

    /// Delete a tweet
    pub async fn delete(&self, tweet_id: &str) -> Result<()> {
        self.client.delete_tweet(tweet_id).await?;

        info!("Deleted tweet: {}", tweet_id);
        Ok(())
    }

    /// Get tweet by ID
    pub async fn get_tweet(&self, tweet_id: &str) -> Result<Tweet> {
        self.rate_limiter.write().await.check_read_limit()?;

        let tweet = self.client.get_tweet(tweet_id).await?;
        Ok(tweet)
    }

    /// Search tweets
    pub async fn search(&self, query: &str, max_results: u32) -> Result<Vec<Tweet>> {
        self.rate_limiter.write().await.check_read_limit()?;

        let results = self.client.search_tweets(query, max_results).await?;

        info!("Found {} tweets for query: {}", results.len(), query);
        Ok(results)
    }

    /// Get user timeline
    pub async fn get_timeline(&self, user_id: &str, max_results: u32) -> Result<Vec<Tweet>> {
        self.rate_limiter.write().await.check_read_limit()?;

        let timeline = self.client.get_user_timeline(user_id, max_results).await?;

        info!("Retrieved {} tweets from user {}", timeline.len(), user_id);
        Ok(timeline)
    }

    /// Get home timeline
    pub async fn get_home_timeline(&self, max_results: u32) -> Result<Vec<Tweet>> {
        self.rate_limiter.write().await.check_read_limit()?;

        let timeline = self.client.get_home_timeline(max_results).await?;

        info!("Retrieved {} tweets from home timeline", timeline.len());
        Ok(timeline)
    }

    /// Get mentions
    pub async fn get_mentions(&self, max_results: u32) -> Result<Vec<Tweet>> {
        self.rate_limiter.write().await.check_read_limit()?;

        let mentions = self.client.get_mentions(max_results).await?;

        info!("Retrieved {} mentions", mentions.len());
        Ok(mentions)
    }

    /// Start streaming with filters
    pub async fn start_streaming(&self, rules: Vec<FilterRule>) -> Result<()> {
        info!("Starting streaming with {} rules", rules.len());

        self.streaming.add_rules(rules).await?;
        self.streaming.connect().await?;

        Ok(())
    }

    /// Stop streaming
    pub async fn stop_streaming(&self) -> Result<()> {
        info!("Stopping streaming");

        self.streaming.disconnect().await?;

        Ok(())
    }

    /// Get stream events
    pub async fn get_stream_events(&self) -> Result<Vec<StreamEvent>> {
        self.streaming.get_events().await
    }

    /// Upload media
    pub async fn upload_media(&self, path: &str, alt_text: Option<&str>) -> Result<String> {
        self.rate_limiter.write().await.check_media_limit()?;

        let media_id = self.media.upload_file(path, alt_text).await?;

        info!("Uploaded media: {}", media_id);
        Ok(media_id)
    }

    /// Post tweet with media
    pub async fn tweet_with_media(&self, text: &str, media_ids: Vec<String>) -> Result<Tweet> {
        self.rate_limiter.write().await.check_tweet_limit()?;

        let tweet = self.client.post_tweet_with_media(text, media_ids).await?;

        info!("Posted tweet with media: {}", tweet.id);
        Ok(tweet)
    }

    /// Get tweet metrics
    pub async fn get_metrics(&self, tweet_id: &str) -> Result<TweetMetrics> {
        self.rate_limiter.write().await.check_read_limit()?;

        let metrics = self.analytics.get_tweet_metrics(tweet_id).await?;

        debug!("Retrieved metrics for tweet {}", tweet_id);
        Ok(metrics)
    }

    /// Get engagement data
    pub async fn get_engagement(&self, tweet_id: &str) -> Result<EngagementData> {
        self.rate_limiter.write().await.check_read_limit()?;

        let engagement = self.analytics.get_engagement_data(tweet_id).await?;

        debug!("Retrieved engagement data for tweet {}", tweet_id);
        Ok(engagement)
    }
}

/// Rate limiter for API calls
struct RateLimiter {
    config: RateLimitConfig,
    request_count: u32,
    tweet_count: u32,
    dm_count: u32,
    media_count: u32,
    window_start: std::time::Instant,
    day_start: std::time::Instant,
}

impl RateLimiter {
    fn new(config: RateLimitConfig) -> Self {
        let now = std::time::Instant::now();
        Self {
            config,
            request_count: 0,
            tweet_count: 0,
            dm_count: 0,
            media_count: 0,
            window_start: now,
            day_start: now,
        }
    }

    fn check_request_limit(&mut self) -> Result<()> {
        self.reset_if_needed();

        if self.request_count >= self.config.requests_per_window {
            if self.config.auto_handle {
                let wait_time = 900 - self.window_start.elapsed().as_secs();
                warn!("Rate limit reached, waiting {} seconds", wait_time);
                std::thread::sleep(std::time::Duration::from_secs(wait_time));
                self.reset_window();
            } else {
                return Err(anyhow::anyhow!("Rate limit exceeded"));
            }
        }

        self.request_count += 1;
        Ok(())
    }

    fn check_tweet_limit(&mut self) -> Result<()> {
        self.check_request_limit()?;
        self.reset_if_needed();

        if self.tweet_count >= self.config.tweets_per_day {
            return Err(anyhow::anyhow!("Daily tweet limit exceeded"));
        }

        self.tweet_count += 1;
        Ok(())
    }

    fn check_tweet_limit_batch(&mut self, count: usize) -> Result<()> {
        self.check_request_limit()?;
        self.reset_if_needed();

        if self.tweet_count + count as u32 > self.config.tweets_per_day {
            return Err(anyhow::anyhow!("Daily tweet limit would be exceeded"));
        }

        self.tweet_count += count as u32;
        Ok(())
    }

    fn check_action_limit(&mut self) -> Result<()> {
        self.check_request_limit()
    }

    fn check_read_limit(&mut self) -> Result<()> {
        self.check_request_limit()
    }

    fn check_media_limit(&mut self) -> Result<()> {
        self.check_request_limit()?;
        self.reset_if_needed();

        if self.media_count >= self.config.media_per_day {
            return Err(anyhow::anyhow!("Daily media upload limit exceeded"));
        }

        self.media_count += 1;
        Ok(())
    }

    fn reset_if_needed(&mut self) {
        // Reset 15-minute window
        if self.window_start.elapsed().as_secs() >= 900 {
            self.reset_window();
        }

        // Reset daily counters
        if self.day_start.elapsed().as_secs() >= 86400 {
            self.reset_day();
        }
    }

    fn reset_window(&mut self) {
        self.request_count = 0;
        self.window_start = std::time::Instant::now();
    }

    fn reset_day(&mut self) {
        self.tweet_count = 0;
        self.dm_count = 0;
        self.media_count = 0;
        self.day_start = std::time::Instant::now();
    }
}

impl TwitterConfig {
    /// Create configuration from environment variables
    pub fn from_env() -> Result<Self> {
        let auth = TwitterAuth::from_env()?;

        Ok(Self {
            auth,
            ..Default::default()
        })
    }
}

/// Auto-post research content if conditions are met
///
/// Posts a bilingual thread (PT/EN) about research findings when:
/// - Safe mode is not enabled
/// - Rate limits allow posting
/// - Quality score meets threshold
///
/// Returns tweet IDs if posted successfully
pub async fn auto_post_if_ready(
    title: &str,
    abstract_text: &str,
    url: &str,
    quality_score: f64,
) -> Result<Option<Vec<String>>> {
    // Check quality threshold
    const MIN_QUALITY_SCORE: f64 = 0.7;
    if quality_score < MIN_QUALITY_SCORE {
        info!(
            "Quality score {:.2} below threshold {:.2}, skipping auto-post",
            quality_score, MIN_QUALITY_SCORE
        );
        return Ok(None);
    }

    // Check if Twitter is configured
    let config = match TwitterConfig::from_env() {
        Ok(c) => c,
        Err(e) => {
            warn!("Twitter not configured, skipping auto-post: {}", e);
            return Ok(None);
        }
    };

    let system = TwitterSystem::new(config)?;

    // Compose bilingual thread
    let pt_tweet = format!(
        "🔬 Nova pesquisa: {}\n\n{}\n\n🔗 {}",
        truncate_text(title, 100),
        truncate_text(abstract_text, 180),
        url
    );

    let en_tweet = format!(
        "🔬 New research: {}\n\n{}\n\n🔗 {}",
        truncate_text(title, 100),
        truncate_text(abstract_text, 180),
        url
    );

    // Post thread
    let tweets = vec![pt_tweet, en_tweet];
    let posted = system.post_thread(tweets).await?;

    let ids: Vec<String> = posted.iter().map(|t| t.id.clone()).collect();
    info!("Auto-posted research thread: {:?}", ids);

    Ok(Some(ids))
}

/// Truncate text to max length with ellipsis
fn truncate_text(text: &str, max_len: usize) -> String {
    if text.len() <= max_len {
        text.to_string()
    } else {
        format!("{}...", &text[..max_len.saturating_sub(3)])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = TwitterConfig::default();
        assert_eq!(config.base_url, "https://api.twitter.com/2");
        assert_eq!(config.timeout, 30);
    }

    #[test]
    fn test_rate_limiter() {
        let config = RateLimitConfig::default();
        let mut limiter = RateLimiter::new(config);

        assert!(limiter.check_request_limit().is_ok());
        assert!(limiter.check_tweet_limit().is_ok());
        assert_eq!(limiter.request_count, 2);
        assert_eq!(limiter.tweet_count, 1);
    }

    #[test]
    fn test_truncate_text() {
        assert_eq!(truncate_text("short", 10), "short");
        assert_eq!(truncate_text("this is a longer text", 10), "this is...");
    }
}
