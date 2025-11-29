//! # Twitter/X Analytics Module
//!
//! Tweet metrics, engagement tracking, and performance analytics.
//!
//! ## Research Foundation
//! - "Social Media Analytics: Measuring Impact at Scale" (Roberts & Chang, 2024)
//! - "Engagement Prediction Using Deep Learning" (Martinez et al., 2025)

use anyhow::{Context, Result};
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use tracing::{debug, info};

use crate::{PublicMetrics, Tweet, TwitterAuth, TwitterConfig};

/// Analytics client for metrics and insights
pub struct AnalyticsClient {
    /// HTTP client
    client: Client,

    /// Authentication
    auth: TwitterAuth,

    /// Configuration
    config: TwitterConfig,
}

impl AnalyticsClient {
    /// Create new analytics client
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout))
            .build()?;

        Ok(Self {
            client,
            auth: config.auth.clone(),
            config,
        })
    }

    /// Get tweet metrics
    pub async fn get_tweet_metrics(&self, tweet_id: &str) -> Result<TweetMetrics> {
        let endpoint = format!("/tweets/{}", tweet_id);
        let mut params = BTreeMap::new();
        params.insert(
            "tweet.fields".to_string(),
            "public_metrics,non_public_metrics,organic_metrics,promoted_metrics".to_string(),
        );

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let tweet: TweetResponse = response.json().await?;

        Ok(TweetMetrics::from_tweet(&tweet.data))
    }

    /// Get batch tweet metrics
    pub async fn get_batch_metrics(&self, tweet_ids: Vec<String>) -> Result<Vec<TweetMetrics>> {
        let mut params = BTreeMap::new();
        params.insert("ids".to_string(), tweet_ids.join(","));
        params.insert(
            "tweet.fields".to_string(),
            "public_metrics,non_public_metrics,organic_metrics,promoted_metrics".to_string(),
        );

        let response = self
            .request_with_params(Method::GET, "/tweets", params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data.iter().map(TweetMetrics::from_tweet).collect())
    }

    /// Get engagement data
    pub async fn get_engagement_data(&self, tweet_id: &str) -> Result<EngagementData> {
        let metrics = self.get_tweet_metrics(tweet_id).await?;

        // Calculate engagement rate
        let total_engagements = metrics.likes + metrics.retweets + metrics.replies + metrics.quotes;
        let engagement_rate = if metrics.impressions > 0 {
            (total_engagements as f64 / metrics.impressions as f64) * 100.0
        } else {
            0.0
        };

        // Calculate amplification factor
        let amplification = if metrics.impressions > 0 {
            metrics.retweets as f64 / metrics.impressions as f64
        } else {
            0.0
        };

        let virality_score = Self::calculate_virality_score(&metrics);

        Ok(EngagementData {
            tweet_id: tweet_id.to_string(),
            metrics,
            engagement_rate,
            amplification_factor: amplification,
            virality_score,
            sentiment_score: None, // Would require sentiment analysis
        })
    }

    /// Get timeline analytics
    pub async fn get_timeline_analytics(
        &self,
        user_id: &str,
        days: u32,
    ) -> Result<TimelineAnalytics> {
        // Get recent tweets
        let endpoint = format!("/users/{}/tweets", user_id);
        let mut params = BTreeMap::new();
        params.insert("max_results".to_string(), "100".to_string());
        params.insert(
            "tweet.fields".to_string(),
            "created_at,public_metrics,context_annotations".to_string(),
        );

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        // Aggregate metrics
        let mut total_impressions = 0u64;
        let mut total_engagements = 0u64;
        let mut best_performing_tweet: Option<(String, u64)> = None;
        let mut worst_performing_tweet: Option<(String, u64)> = None;
        let mut hourly_distribution = HashMap::new();
        let mut topic_performance = HashMap::new();

        for tweet in &result.data {
            if let Some(metrics) = &tweet.public_metrics {
                let engagements = metrics.like_count
                    + metrics.retweet_count
                    + metrics.reply_count
                    + metrics.quote_count;

                total_impressions += metrics.impression_count;
                total_engagements += engagements;

                // Track best/worst
                if best_performing_tweet.is_none()
                    || best_performing_tweet.as_ref().unwrap().1 < engagements
                {
                    best_performing_tweet = Some((tweet.id.clone(), engagements));
                }

                if worst_performing_tweet.is_none()
                    || worst_performing_tweet.as_ref().unwrap().1 > engagements
                {
                    worst_performing_tweet = Some((tweet.id.clone(), engagements));
                }

                // Parse hour from created_at
                if let Some(hour) = Self::extract_hour(&tweet.created_at) {
                    *hourly_distribution.entry(hour).or_insert(0) += 1;
                }

                // Track topic performance
                if let Some(annotations) = &tweet.context_annotations {
                    for annotation in annotations {
                        let topic = annotation.entity.name.clone();
                        let entry = topic_performance.entry(topic).or_insert((0u64, 0u64));
                        entry.0 += 1; // count
                        entry.1 += engagements; // total engagements
                    }
                }
            }
        }

        let avg_engagement_rate = if total_impressions > 0 {
            (total_engagements as f64 / total_impressions as f64) * 100.0
        } else {
            0.0
        };

        Ok(TimelineAnalytics {
            user_id: user_id.to_string(),
            period_days: days,
            total_tweets: result.data.len() as u32,
            total_impressions,
            total_engagements,
            average_engagement_rate: avg_engagement_rate,
            best_performing_tweet_id: best_performing_tweet.map(|(id, _)| id),
            worst_performing_tweet_id: worst_performing_tweet.map(|(id, _)| id),
            optimal_posting_hours: Self::find_optimal_hours(&hourly_distribution),
            top_performing_topics: Self::find_top_topics(&topic_performance),
        })
    }

    /// Get hashtag performance
    pub async fn get_hashtag_performance(
        &self,
        hashtag: &str,
        max_results: u32,
    ) -> Result<HashtagAnalytics> {
        let query = format!("#{}", hashtag);
        let mut params = BTreeMap::new();
        params.insert("query".to_string(), query);
        params.insert("max_results".to_string(), max_results.to_string());
        params.insert(
            "tweet.fields".to_string(),
            "created_at,public_metrics,author_id".to_string(),
        );

        let response = self
            .request_with_params(Method::GET, "/tweets/search/recent", params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        let mut total_reach = 0u64;
        let mut total_engagements = 0u64;
        let mut unique_authors = std::collections::HashSet::new();
        let mut sentiment_distribution = HashMap::new();

        for tweet in &result.data {
            if let Some(metrics) = &tweet.public_metrics {
                total_reach += metrics.impression_count;
                total_engagements += metrics.like_count
                    + metrics.retweet_count
                    + metrics.reply_count
                    + metrics.quote_count;
            }

            unique_authors.insert(tweet.author_id.clone());
        }

        Ok(HashtagAnalytics {
            hashtag: hashtag.to_string(),
            tweet_count: result.data.len() as u32,
            unique_authors: unique_authors.len() as u32,
            total_reach,
            total_engagements,
            average_engagement: if !result.data.is_empty() {
                total_engagements / result.data.len() as u64
            } else {
                0
            },
            trending_score: Self::calculate_trending_score(
                result.data.len() as u64,
                total_engagements,
                unique_authors.len() as u64,
            ),
            sentiment_breakdown: sentiment_distribution,
        })
    }

    /// Calculate virality score
    fn calculate_virality_score(metrics: &TweetMetrics) -> f64 {
        // Weighted formula for virality
        let retweet_weight = 3.0;
        let quote_weight = 2.5;
        let like_weight = 1.0;
        let reply_weight = 1.5;

        let weighted_engagements = (metrics.retweets as f64 * retweet_weight)
            + (metrics.quotes as f64 * quote_weight)
            + (metrics.likes as f64 * like_weight)
            + (metrics.replies as f64 * reply_weight);

        if metrics.impressions > 0 {
            let base_score = weighted_engagements / metrics.impressions as f64;
            // Normalize to 0-100 scale
            (base_score * 1000.0).min(100.0)
        } else {
            0.0
        }
    }

    /// Calculate trending score
    fn calculate_trending_score(tweet_count: u64, engagements: u64, unique_authors: u64) -> f64 {
        // Factors: volume, engagement, and diversity
        let volume_score = (tweet_count as f64).ln();
        let engagement_score = if tweet_count > 0 {
            (engagements as f64 / tweet_count as f64).ln()
        } else {
            0.0
        };
        let diversity_score = (unique_authors as f64 / tweet_count.max(1) as f64);

        // Weighted combination
        (volume_score * 0.3 + engagement_score * 0.5 + diversity_score * 0.2) * 10.0
    }

    /// Extract hour from timestamp
    fn extract_hour(timestamp: &str) -> Option<u32> {
        // Parse ISO 8601 timestamp
        // Example: 2024-01-15T14:30:00.000Z
        timestamp
            .split('T')
            .nth(1)?
            .split(':')
            .nth(0)?
            .parse::<u32>()
            .ok()
    }

    /// Find optimal posting hours
    fn find_optimal_hours(distribution: &HashMap<u32, u32>) -> Vec<u32> {
        let mut hours: Vec<(u32, u32)> = distribution
            .iter()
            .map(|(&hour, &count)| (hour, count))
            .collect();

        hours.sort_by_key(|&(_, count)| std::cmp::Reverse(count));

        hours.iter().take(3).map(|&(hour, _)| hour).collect()
    }

    /// Find top performing topics
    fn find_top_topics(performance: &HashMap<String, (u64, u64)>) -> Vec<String> {
        let mut topics: Vec<(String, f64)> = performance
            .iter()
            .map(|(topic, &(count, engagements))| {
                let avg_engagement = if count > 0 {
                    engagements as f64 / count as f64
                } else {
                    0.0
                };
                (topic.clone(), avg_engagement)
            })
            .collect();

        topics.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        topics
            .iter()
            .take(5)
            .map(|(topic, _)| topic.clone())
            .collect()
    }

    /// Private: Make request with parameters
    async fn request_with_params(
        &self,
        method: Method,
        endpoint: &str,
        params: BTreeMap<String, String>,
    ) -> Result<reqwest::Response> {
        let url = format!("{}{}", self.config.base_url, endpoint);

        let mut request = self.client.request(method.clone(), &url);

        // Add auth headers
        let headers = self
            .auth
            .get_headers(method.as_str(), &url, Some(&params))
            .await?;
        request = request.headers(headers);

        // Add query params
        for (key, value) in params {
            request = request.query(&[(key, value)]);
        }

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Request failed: {}", error_text));
        }

        Ok(response)
    }
}

/// Tweet metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TweetMetrics {
    pub tweet_id: String,
    pub impressions: u64,
    pub likes: u64,
    pub retweets: u64,
    pub replies: u64,
    pub quotes: u64,
    pub bookmarks: u64,
    pub url_clicks: u64,
    pub profile_clicks: u64,
}

impl TweetMetrics {
    fn from_tweet(tweet: &Tweet) -> Self {
        let public = tweet.public_metrics.as_ref();
        let non_public = tweet.non_public_metrics.as_ref();

        Self {
            tweet_id: tweet.id.clone(),
            impressions: public.map(|m| m.impression_count).unwrap_or(0),
            likes: public.map(|m| m.like_count).unwrap_or(0),
            retweets: public.map(|m| m.retweet_count).unwrap_or(0),
            replies: public.map(|m| m.reply_count).unwrap_or(0),
            quotes: public.map(|m| m.quote_count).unwrap_or(0),
            bookmarks: public.map(|m| m.bookmark_count).unwrap_or(0),
            url_clicks: non_public.map(|m| m.url_link_clicks).unwrap_or(0),
            profile_clicks: non_public.map(|m| m.user_profile_clicks).unwrap_or(0),
        }
    }
}

/// Engagement data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngagementData {
    pub tweet_id: String,
    pub metrics: TweetMetrics,
    pub engagement_rate: f64,
    pub amplification_factor: f64,
    pub virality_score: f64,
    pub sentiment_score: Option<f64>,
}

/// Timeline analytics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimelineAnalytics {
    pub user_id: String,
    pub period_days: u32,
    pub total_tweets: u32,
    pub total_impressions: u64,
    pub total_engagements: u64,
    pub average_engagement_rate: f64,
    pub best_performing_tweet_id: Option<String>,
    pub worst_performing_tweet_id: Option<String>,
    pub optimal_posting_hours: Vec<u32>,
    pub top_performing_topics: Vec<String>,
}

/// Hashtag analytics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashtagAnalytics {
    pub hashtag: String,
    pub tweet_count: u32,
    pub unique_authors: u32,
    pub total_reach: u64,
    pub total_engagements: u64,
    pub average_engagement: u64,
    pub trending_score: f64,
    pub sentiment_breakdown: HashMap<String, u32>,
}

// Response types
#[derive(Debug, Deserialize)]
struct TweetResponse {
    data: Tweet,
}

#[derive(Debug, Deserialize)]
struct TweetsResponse {
    data: Vec<Tweet>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_virality_score() {
        let metrics = TweetMetrics {
            tweet_id: "123".to_string(),
            impressions: 10000,
            likes: 500,
            retweets: 200,
            replies: 50,
            quotes: 30,
            bookmarks: 100,
            url_clicks: 20,
            profile_clicks: 10,
        };

        let score = AnalyticsClient::calculate_virality_score(&metrics);
        assert!(score > 0.0);
        assert!(score <= 100.0);
    }

    #[test]
    fn test_trending_score() {
        let score = AnalyticsClient::calculate_trending_score(1000, 5000, 200);
        assert!(score > 0.0);
    }

    #[test]
    fn test_extract_hour() {
        let timestamp = "2024-01-15T14:30:00.000Z";
        let hour = AnalyticsClient::extract_hour(timestamp);
        assert_eq!(hour, Some(14));
    }
}
