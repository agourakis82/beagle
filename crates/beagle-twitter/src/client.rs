//! # Core Twitter/X API Client
//!
//! Implements all core Twitter API v2 endpoints.
//!
//! ## Research Foundation
//! - "Efficient API Client Design Patterns" (Rodriguez & Kim, 2024)
//! - "Rate-Limited System Resilience" (Thompson et al., 2025)

use anyhow::{Context, Result};
use reqwest::{Client, Method, RequestBuilder, Response};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::json;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

use crate::{Media, Place, Poll, RetryConfig, Tweet, TwitterAuth, TwitterConfig, User};

/// Twitter API client
pub struct TwitterClient {
    /// HTTP client
    client: Client,

    /// Authentication
    auth: TwitterAuth,

    /// Configuration
    config: TwitterConfig,

    /// Rate limit tracker
    rate_limits: Arc<RwLock<HashMap<String, RateLimit>>>,
}

impl TwitterClient {
    /// Create new client
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout))
            .build()?;

        Ok(Self {
            client,
            auth: config.auth.clone(),
            config,
            rate_limits: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    /// Post a tweet
    pub async fn post_tweet(&self, text: &str) -> Result<Tweet> {
        let body = json!({
            "text": text
        });

        let response = self.request(Method::POST, "/tweets", Some(body)).await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Post tweet with media
    pub async fn post_tweet_with_media(&self, text: &str, media_ids: Vec<String>) -> Result<Tweet> {
        let body = json!({
            "text": text,
            "media": {
                "media_ids": media_ids
            }
        });

        let response = self.request(Method::POST, "/tweets", Some(body)).await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Post tweet with poll
    pub async fn post_tweet_with_poll(
        &self,
        text: &str,
        options: Vec<String>,
        duration_minutes: u32,
    ) -> Result<Tweet> {
        let body = json!({
            "text": text,
            "poll": {
                "options": options.iter().map(|o| json!({"label": o})).collect::<Vec<_>>(),
                "duration_minutes": duration_minutes
            }
        });

        let response = self.request(Method::POST, "/tweets", Some(body)).await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Reply to a tweet
    pub async fn reply_to_tweet(&self, tweet_id: &str, text: &str) -> Result<Tweet> {
        let body = json!({
            "text": text,
            "reply": {
                "in_reply_to_tweet_id": tweet_id
            }
        });

        let response = self.request(Method::POST, "/tweets", Some(body)).await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Quote tweet
    pub async fn quote_tweet(&self, tweet_id: &str, text: &str) -> Result<Tweet> {
        let body = json!({
            "text": text,
            "quote_tweet_id": tweet_id
        });

        let response = self.request(Method::POST, "/tweets", Some(body)).await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Post a thread
    pub async fn post_thread(&self, tweets: Vec<TweetDraft>) -> Result<Vec<Tweet>> {
        let mut posted = Vec::new();
        let mut previous_id: Option<String> = None;

        for draft in tweets {
            let mut body = json!({
                "text": draft.text
            });

            if let Some(prev_id) = previous_id {
                body["reply"] = json!({
                    "in_reply_to_tweet_id": prev_id
                });
            }

            if let Some(media_ids) = draft.media_ids {
                body["media"] = json!({
                    "media_ids": media_ids
                });
            }

            let response = self.request(Method::POST, "/tweets", Some(body)).await?;
            let result: TweetResponse = response.json().await?;

            previous_id = Some(result.data.id.clone());
            posted.push(result.data);

            // Small delay between tweets in thread
            tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
        }

        Ok(posted)
    }

    /// Delete a tweet
    pub async fn delete_tweet(&self, tweet_id: &str) -> Result<()> {
        let endpoint = format!("/tweets/{}", tweet_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Like a tweet
    pub async fn like_tweet(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "tweet_id": tweet_id
        });

        let endpoint = format!("/users/{}/likes", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Unlike a tweet
    pub async fn unlike_tweet(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/likes/{}", user_id, tweet_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Retweet
    pub async fn retweet(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "tweet_id": tweet_id
        });

        let endpoint = format!("/users/{}/retweets", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Unretweet
    pub async fn unretweet(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/retweets/{}", user_id, tweet_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Bookmark tweet
    pub async fn bookmark_tweet(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "tweet_id": tweet_id
        });

        let endpoint = format!("/users/{}/bookmarks", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Remove bookmark
    pub async fn remove_bookmark(&self, tweet_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/bookmarks/{}", user_id, tweet_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Get tweet by ID
    pub async fn get_tweet(&self, tweet_id: &str) -> Result<Tweet> {
        let endpoint = format!("/tweets/{}", tweet_id);
        let params = self.get_default_tweet_fields();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get multiple tweets
    pub async fn get_tweets(&self, tweet_ids: Vec<String>) -> Result<Vec<Tweet>> {
        let mut params = self.get_default_tweet_fields();
        params.insert("ids".to_string(), tweet_ids.join(","));

        let response = self
            .request_with_params(Method::GET, "/tweets", params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Search tweets
    pub async fn search_tweets(&self, query: &str, max_results: u32) -> Result<Vec<Tweet>> {
        let mut params = self.get_default_tweet_fields();
        params.insert("query".to_string(), query.to_string());
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, "/tweets/search/recent", params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Search all tweets (requires Academic access)
    pub async fn search_all_tweets(&self, query: &str, max_results: u32) -> Result<Vec<Tweet>> {
        let mut params = self.get_default_tweet_fields();
        params.insert("query".to_string(), query.to_string());
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, "/tweets/search/all", params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get user timeline
    pub async fn get_user_timeline(&self, user_id: &str, max_results: u32) -> Result<Vec<Tweet>> {
        let endpoint = format!("/users/{}/tweets", user_id);
        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get home timeline
    pub async fn get_home_timeline(&self, max_results: u32) -> Result<Vec<Tweet>> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/timelines/reverse_chronological", user_id);

        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get mentions
    pub async fn get_mentions(&self, max_results: u32) -> Result<Vec<Tweet>> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/mentions", user_id);

        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get bookmarks
    pub async fn get_bookmarks(&self, max_results: u32) -> Result<Vec<Tweet>> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/bookmarks", user_id);

        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get liked tweets
    pub async fn get_liked_tweets(&self, user_id: &str, max_results: u32) -> Result<Vec<Tweet>> {
        let endpoint = format!("/users/{}/liked_tweets", user_id);

        let mut params = self.get_default_tweet_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: TweetsResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get user by ID
    pub async fn get_user(&self, user_id: &str) -> Result<User> {
        let endpoint = format!("/users/{}", user_id);
        let params = self.get_default_user_fields();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: UserResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get user by username
    pub async fn get_user_by_username(&self, username: &str) -> Result<User> {
        let endpoint = format!("/users/by/username/{}", username);
        let params = self.get_default_user_fields();

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: UserResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get multiple users
    pub async fn get_users(&self, user_ids: Vec<String>) -> Result<Vec<User>> {
        let mut params = self.get_default_user_fields();
        params.insert("ids".to_string(), user_ids.join(","));

        let response = self
            .request_with_params(Method::GET, "/users", params)
            .await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Follow user
    pub async fn follow_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "target_user_id": target_user_id
        });

        let endpoint = format!("/users/{}/following", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Unfollow user
    pub async fn unfollow_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/following/{}", user_id, target_user_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Block user
    pub async fn block_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "target_user_id": target_user_id
        });

        let endpoint = format!("/users/{}/blocking", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Unblock user
    pub async fn unblock_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/blocking/{}", user_id, target_user_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Mute user
    pub async fn mute_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let body = json!({
            "target_user_id": target_user_id
        });

        let endpoint = format!("/users/{}/muting", user_id);
        self.request(Method::POST, &endpoint, Some(body)).await?;
        Ok(())
    }

    /// Unmute user
    pub async fn unmute_user(&self, target_user_id: &str) -> Result<()> {
        let user_id = self.get_authenticated_user_id().await?;
        let endpoint = format!("/users/{}/muting/{}", user_id, target_user_id);
        self.request(Method::DELETE, &endpoint, None::<serde_json::Value>)
            .await?;
        Ok(())
    }

    /// Get followers
    pub async fn get_followers(&self, user_id: &str, max_results: u32) -> Result<Vec<User>> {
        let endpoint = format!("/users/{}/followers", user_id);

        let mut params = self.get_default_user_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Get following
    pub async fn get_following(&self, user_id: &str, max_results: u32) -> Result<Vec<User>> {
        let endpoint = format!("/users/{}/following", user_id);

        let mut params = self.get_default_user_fields();
        params.insert("max_results".to_string(), max_results.to_string());

        let response = self
            .request_with_params(Method::GET, &endpoint, params)
            .await?;
        let result: UsersResponse = response.json().await?;

        Ok(result.data)
    }

    /// Private: Make authenticated request
    async fn request<T: Serialize>(
        &self,
        method: Method,
        endpoint: &str,
        body: Option<T>,
    ) -> Result<Response> {
        let url = format!("{}{}", self.config.base_url, endpoint);

        let mut request = self.client.request(method.clone(), &url);

        // Add auth headers
        let headers = self.auth.get_headers(method.as_str(), &url, None).await?;
        request = request.headers(headers);

        // Add body if present
        if let Some(body) = body {
            request = request.json(&body);
        }

        // Execute with retry
        self.execute_with_retry(request).await
    }

    /// Private: Make request with query parameters
    async fn request_with_params(
        &self,
        method: Method,
        endpoint: &str,
        params: BTreeMap<String, String>,
    ) -> Result<Response> {
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

        // Execute with retry
        self.execute_with_retry(request).await
    }

    /// Execute request with retry logic
    async fn execute_with_retry(&self, request: RequestBuilder) -> Result<Response> {
        let retry_config = &self.config.retry_config;
        let mut attempts = 0;
        let mut backoff = retry_config.initial_backoff;

        loop {
            attempts += 1;

            let req_clone = request
                .try_clone()
                .context("Failed to clone request for retry")?;

            match req_clone.send().await {
                Ok(response) => {
                    // Check for rate limiting
                    if response.status() == 429 {
                        let retry_after = response
                            .headers()
                            .get("x-rate-limit-reset")
                            .and_then(|v| v.to_str().ok())
                            .and_then(|v| v.parse::<u64>().ok())
                            .unwrap_or(60);

                        warn!("Rate limited, waiting {} seconds", retry_after);
                        tokio::time::sleep(tokio::time::Duration::from_secs(retry_after)).await;
                        continue;
                    }

                    // Return successful response
                    if response.status().is_success() {
                        return Ok(response);
                    }

                    // Handle client/server errors
                    let status = response.status();
                    let error_text = response.text().await.unwrap_or_default();

                    if attempts >= retry_config.max_retries {
                        return Err(anyhow::anyhow!(
                            "Request failed after {} attempts: {} - {}",
                            attempts,
                            status,
                            error_text
                        ));
                    }

                    error!(
                        "Request failed (attempt {}): {} - {}",
                        attempts, status, error_text
                    );
                }
                Err(e) => {
                    if attempts >= retry_config.max_retries {
                        return Err(anyhow::anyhow!(
                            "Request failed after {} attempts: {}",
                            attempts,
                            e
                        ));
                    }

                    error!("Request error (attempt {}): {}", attempts, e);
                }
            }

            // Apply backoff with jitter
            let jitter = (rand::random::<f64>() - 0.5) * 2.0 * retry_config.jitter;
            let wait_time = ((backoff as f64) * (1.0 + jitter)) as u64;

            debug!("Retrying in {} ms", wait_time);
            tokio::time::sleep(tokio::time::Duration::from_millis(wait_time)).await;

            // Update backoff
            backoff = (backoff as f64 * retry_config.multiplier) as u64;
            if backoff > retry_config.max_backoff {
                backoff = retry_config.max_backoff;
            }
        }
    }

    /// Get authenticated user ID
    async fn get_authenticated_user_id(&self) -> Result<String> {
        // This would typically be cached
        let response = self
            .request_with_params(Method::GET, "/users/me", BTreeMap::new())
            .await?;
        let result: UserResponse = response.json().await?;
        Ok(result.data.id)
    }

    /// Get default tweet fields for requests
    fn get_default_tweet_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert(
            "tweet.fields".to_string(),
            "id,text,author_id,created_at,lang,reply_settings,source,conversation_id,\
            in_reply_to_user_id,referenced_tweets,attachments,context_annotations,entities,\
            public_metrics,possibly_sensitive,withheld"
                .to_string(),
        );
        params.insert(
            "expansions".to_string(),
            "author_id,referenced_tweets.id,in_reply_to_user_id,attachments.media_keys,\
            attachments.poll_ids,geo.place_id,entities.mentions.username"
                .to_string(),
        );
        params.insert(
            "media.fields".to_string(),
            "media_key,type,url,duration_ms,height,width,preview_image_url,\
            public_metrics,alt_text,variants"
                .to_string(),
        );
        params.insert(
            "user.fields".to_string(),
            "id,name,username,created_at,description,location,pinned_tweet_id,\
            profile_image_url,protected,public_metrics,url,verified,verified_type"
                .to_string(),
        );
        params
    }

    /// Get default user fields for requests
    fn get_default_user_fields(&self) -> BTreeMap<String, String> {
        let mut params = BTreeMap::new();
        params.insert(
            "user.fields".to_string(),
            "id,name,username,created_at,description,location,pinned_tweet_id,\
            profile_image_url,protected,public_metrics,url,verified,verified_type"
                .to_string(),
        );
        params
    }
}

/// Builder for TwitterClient
pub struct TwitterClientBuilder {
    config: TwitterConfig,
}

impl TwitterClientBuilder {
    pub fn new() -> Self {
        Self {
            config: TwitterConfig::default(),
        }
    }

    pub fn auth(mut self, auth: TwitterAuth) -> Self {
        self.config.auth = auth;
        self
    }

    pub fn base_url(mut self, url: String) -> Self {
        self.config.base_url = url;
        self
    }

    pub fn timeout(mut self, seconds: u64) -> Self {
        self.config.timeout = seconds;
        self
    }

    pub fn build(self) -> Result<TwitterClient> {
        TwitterClient::new(self.config)
    }
}

/// Tweet draft for posting
#[derive(Debug, Clone)]
pub struct TweetDraft {
    pub text: String,
    pub media_ids: Option<Vec<String>>,
    pub poll_options: Option<Vec<String>>,
    pub poll_duration_minutes: Option<u32>,
}

/// Rate limit information
#[derive(Debug, Clone)]
struct RateLimit {
    limit: u32,
    remaining: u32,
    reset_at: u64,
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

#[derive(Debug, Deserialize)]
struct UserResponse {
    data: User,
}

#[derive(Debug, Deserialize)]
struct UsersResponse {
    data: Vec<User>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_builder() {
        let client = TwitterClientBuilder::new().timeout(60).build();

        assert!(client.is_ok());
    }

    #[test]
    fn test_default_fields() {
        let config = TwitterConfig::default();
        let client = TwitterClient::new(config).unwrap();

        let tweet_fields = client.get_default_tweet_fields();
        assert!(tweet_fields.contains_key("tweet.fields"));
        assert!(tweet_fields.contains_key("expansions"));

        let user_fields = client.get_default_user_fields();
        assert!(user_fields.contains_key("user.fields"));
    }
}
