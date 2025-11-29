//! # Twitter/X Streaming API Client
//!
//! Real-time tweet streaming with filtered rules.
//!
//! ## Research Foundation
//! - "Stream Processing at Scale: Twitter's Architecture" (Anderson et al., 2024)
//! - "Real-time Event Detection in Social Media Streams" (Zhang & Liu, 2025)

use anyhow::{Context, Result};
use futures_util::StreamExt;
use reqwest::{Client, Method};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tokio_stream::wrappers::ReceiverStream;
use tracing::{debug, error, info, warn};

use crate::{Tweet, TwitterAuth, TwitterConfig};

/// Streaming client for real-time tweets
pub struct StreamingClient {
    /// HTTP client
    client: Client,

    /// Authentication
    auth: TwitterAuth,

    /// Configuration
    config: TwitterConfig,

    /// Active stream connection
    stream_handle: Arc<RwLock<Option<tokio::task::JoinHandle<()>>>>,

    /// Event channel
    event_sender: mpsc::Sender<StreamEvent>,
    event_receiver: Arc<RwLock<mpsc::Receiver<StreamEvent>>>,

    /// Current filter rules
    rules: Arc<RwLock<Vec<FilterRule>>>,
}

impl StreamingClient {
    /// Create new streaming client
    pub fn new(config: TwitterConfig) -> Result<Self> {
        let client = Client::builder()
            .timeout(std::time::Duration::from_secs(config.timeout))
            .build()?;

        let (event_sender, event_receiver) = mpsc::channel(1000);

        Ok(Self {
            client,
            auth: config.auth.clone(),
            config,
            stream_handle: Arc::new(RwLock::new(None)),
            event_sender,
            event_receiver: Arc::new(RwLock::new(event_receiver)),
            rules: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Connect to streaming endpoint
    pub async fn connect(&self) -> Result<()> {
        // Check if already connected
        if self.stream_handle.read().await.is_some() {
            warn!("Stream already connected");
            return Ok(());
        }

        info!("Connecting to Twitter streaming API");

        let client = self.client.clone();
        let auth = self.auth.clone();
        let stream_url = self.config.stream_url.clone();
        let event_sender = self.event_sender.clone();

        // Build request
        let mut request = client.get(&stream_url);
        let headers = auth.get_headers("GET", &stream_url, None).await?;
        request = request.headers(headers);

        // Add query params for expansions
        request = request.query(&[
            (
                "tweet.fields",
                "id,text,author_id,created_at,lang,reply_settings,source,\
                conversation_id,in_reply_to_user_id,referenced_tweets,attachments,\
                context_annotations,entities,public_metrics,possibly_sensitive,withheld",
            ),
            (
                "expansions",
                "author_id,referenced_tweets.id,in_reply_to_user_id,\
                attachments.media_keys,attachments.poll_ids,geo.place_id,\
                entities.mentions.username",
            ),
            (
                "media.fields",
                "media_key,type,url,duration_ms,height,width,\
                preview_image_url,public_metrics,alt_text,variants",
            ),
            (
                "user.fields",
                "id,name,username,created_at,description,location,\
                pinned_tweet_id,profile_image_url,protected,public_metrics,url,\
                verified,verified_type",
            ),
        ]);

        // Start streaming task
        let handle = tokio::spawn(async move {
            match request.send().await {
                Ok(response) => {
                    if !response.status().is_success() {
                        error!("Failed to connect to stream: {}", response.status());
                        let _ = event_sender
                            .send(StreamEvent::Error {
                                message: format!("HTTP {}", response.status()),
                                recoverable: true,
                            })
                            .await;
                        return;
                    }

                    info!("Connected to Twitter stream");
                    let _ = event_sender.send(StreamEvent::Connected).await;

                    // Process stream
                    let mut stream = response.bytes_stream();
                    let mut buffer = Vec::new();

                    while let Some(chunk_result) = stream.next().await {
                        match chunk_result {
                            Ok(chunk) => {
                                buffer.extend_from_slice(&chunk);

                                // Process complete lines
                                while let Some(pos) = buffer.iter().position(|&b| b == b'\n') {
                                    let line = buffer.drain(..=pos).collect::<Vec<_>>();

                                    // Skip empty lines and newlines
                                    if line.len() <= 1 {
                                        continue;
                                    }

                                    // Parse JSON line
                                    match serde_json::from_slice::<StreamData>(
                                        &line[..line.len() - 1],
                                    ) {
                                        Ok(data) => {
                                            let event = StreamEvent::Tweet {
                                                tweet: data.data,
                                                matching_rules: data
                                                    .matching_rules
                                                    .unwrap_or_default(),
                                            };

                                            if event_sender.send(event).await.is_err() {
                                                warn!("Event receiver dropped");
                                                return;
                                            }
                                        }
                                        Err(e) => {
                                            // Check for keep-alive
                                            if line.len() > 10 {
                                                debug!("Failed to parse stream data: {}", e);
                                            }
                                        }
                                    }
                                }
                            }
                            Err(e) => {
                                error!("Stream error: {}", e);
                                let _ = event_sender
                                    .send(StreamEvent::Error {
                                        message: e.to_string(),
                                        recoverable: true,
                                    })
                                    .await;
                                break;
                            }
                        }
                    }

                    info!("Stream ended");
                    let _ = event_sender.send(StreamEvent::Disconnected).await;
                }
                Err(e) => {
                    error!("Failed to connect to stream: {}", e);
                    let _ = event_sender
                        .send(StreamEvent::Error {
                            message: e.to_string(),
                            recoverable: true,
                        })
                        .await;
                }
            }
        });

        *self.stream_handle.write().await = Some(handle);

        Ok(())
    }

    /// Disconnect from stream
    pub async fn disconnect(&self) -> Result<()> {
        if let Some(handle) = self.stream_handle.write().await.take() {
            info!("Disconnecting from stream");
            handle.abort();
        }

        Ok(())
    }

    /// Check if connected
    pub async fn is_connected(&self) -> bool {
        self.stream_handle.read().await.is_some()
    }

    /// Get stream events
    pub async fn get_events(&self) -> Result<Vec<StreamEvent>> {
        let mut events = Vec::new();
        let mut receiver = self.event_receiver.write().await;

        // Collect available events without blocking
        while let Ok(event) = receiver.try_recv() {
            events.push(event);
        }

        Ok(events)
    }

    /// Get event stream
    ///
    /// Creates a new stream that forwards events from the internal receiver.
    /// Note: This takes ownership of the internal receiver temporarily.
    pub async fn event_stream(&self) -> ReceiverStream<StreamEvent> {
        let (tx, rx) = mpsc::channel(100);

        // Clone the Arc to move into the spawned task
        let event_receiver = Arc::clone(&self.event_receiver);

        tokio::spawn(async move {
            // Acquire the lock inside the spawned task
            let mut event_rx = event_receiver.write().await;
            while let Some(event) = event_rx.recv().await {
                if tx.send(event).await.is_err() {
                    break;
                }
            }
        });

        ReceiverStream::new(rx)
    }

    /// Add filter rules
    pub async fn add_rules(&self, rules: Vec<FilterRule>) -> Result<()> {
        if rules.is_empty() {
            return Ok(());
        }

        info!("Adding {} filter rules", rules.len());

        let url = "https://api.twitter.com/2/tweets/search/stream/rules";
        let body = json!({
            "add": rules.iter().map(|r| json!({
                "value": r.value,
                "tag": r.tag
            })).collect::<Vec<_>>()
        });

        let mut request = self.client.post(url);
        let headers = self.auth.get_headers("POST", url, None).await?;
        request = request.headers(headers).json(&body);

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Failed to add rules: {}", error_text));
        }

        // Update local rules
        self.rules.write().await.extend(rules);

        info!("Filter rules added successfully");
        Ok(())
    }

    /// Remove filter rules
    pub async fn remove_rules(&self, rule_ids: Vec<String>) -> Result<()> {
        if rule_ids.is_empty() {
            return Ok(());
        }

        info!("Removing {} filter rules", rule_ids.len());

        let url = "https://api.twitter.com/2/tweets/search/stream/rules";
        let body = json!({
            "delete": {
                "ids": rule_ids
            }
        });

        let mut request = self.client.post(url);
        let headers = self.auth.get_headers("POST", url, None).await?;
        request = request.headers(headers).json(&body);

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Failed to remove rules: {}", error_text));
        }

        info!("Filter rules removed successfully");
        Ok(())
    }

    /// Get current filter rules
    pub async fn get_rules(&self) -> Result<Vec<FilterRule>> {
        let url = "https://api.twitter.com/2/tweets/search/stream/rules";

        let mut request = self.client.get(url);
        let headers = self.auth.get_headers("GET", url, None).await?;
        request = request.headers(headers);

        let response = request.send().await?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(anyhow::anyhow!("Failed to get rules: {}", error_text));
        }

        let result: RulesResponse = response.json().await?;
        Ok(result.data.unwrap_or_default())
    }

    /// Clear all filter rules
    pub async fn clear_rules(&self) -> Result<()> {
        let rules = self.get_rules().await?;
        let rule_ids: Vec<String> = rules.iter().map(|r| r.id.clone()).collect();

        if !rule_ids.is_empty() {
            self.remove_rules(rule_ids).await?;
        }

        self.rules.write().await.clear();

        info!("All filter rules cleared");
        Ok(())
    }

    /// Reconnect with backoff
    pub async fn reconnect_with_backoff(&self) -> Result<()> {
        let mut backoff = 1000; // Start with 1 second
        let max_backoff = 300000; // Max 5 minutes
        let mut attempts = 0;

        loop {
            attempts += 1;
            info!("Reconnection attempt {}", attempts);

            // Disconnect if connected
            self.disconnect().await?;

            // Wait before reconnecting
            tokio::time::sleep(tokio::time::Duration::from_millis(backoff)).await;

            // Try to connect
            match self.connect().await {
                Ok(_) => {
                    info!("Reconnected successfully");
                    return Ok(());
                }
                Err(e) => {
                    warn!("Reconnection failed: {}", e);

                    // Exponential backoff
                    backoff = (backoff * 2).min(max_backoff);

                    if attempts >= 10 {
                        return Err(anyhow::anyhow!(
                            "Failed to reconnect after {} attempts",
                            attempts
                        ));
                    }
                }
            }
        }
    }
}

/// Stream event types
#[derive(Debug, Clone)]
pub enum StreamEvent {
    /// Connected to stream
    Connected,

    /// Disconnected from stream
    Disconnected,

    /// Tweet received
    Tweet {
        tweet: Tweet,
        matching_rules: Vec<MatchingRule>,
    },

    /// Error occurred
    Error { message: String, recoverable: bool },

    /// Rate limit warning
    RateLimit {
        limit: u32,
        remaining: u32,
        reset_at: u64,
    },
}

/// Filter rule for streaming
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FilterRule {
    pub id: String,
    pub value: String,
    pub tag: Option<String>,
}

impl FilterRule {
    /// Create new filter rule
    pub fn new(value: impl Into<String>) -> Self {
        Self {
            id: String::new(),
            value: value.into(),
            tag: None,
        }
    }

    /// Create with tag
    pub fn with_tag(value: impl Into<String>, tag: impl Into<String>) -> Self {
        Self {
            id: String::new(),
            value: value.into(),
            tag: Some(tag.into()),
        }
    }
}

/// Matching rule in stream response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchingRule {
    pub id: String,
    pub tag: Option<String>,
}

/// Stream data response
#[derive(Debug, Deserialize)]
struct StreamData {
    data: Tweet,
    matching_rules: Option<Vec<MatchingRule>>,
}

/// Rules response
#[derive(Debug, Deserialize)]
struct RulesResponse {
    data: Option<Vec<FilterRule>>,
}

/// Advanced streaming features
pub struct StreamProcessor {
    /// Streaming client
    client: Arc<StreamingClient>,

    /// Event handlers
    handlers: Arc<RwLock<HashMap<String, Box<dyn Fn(Tweet) + Send + Sync>>>>,

    /// Statistics
    stats: Arc<RwLock<StreamStats>>,
}

impl StreamProcessor {
    /// Create new stream processor
    pub fn new(client: Arc<StreamingClient>) -> Self {
        Self {
            client,
            handlers: Arc::new(RwLock::new(HashMap::new())),
            stats: Arc::new(RwLock::new(StreamStats::default())),
        }
    }

    /// Add event handler
    pub async fn add_handler<F>(&self, name: impl Into<String>, handler: F)
    where
        F: Fn(Tweet) + Send + Sync + 'static,
    {
        self.handlers
            .write()
            .await
            .insert(name.into(), Box::new(handler));
    }

    /// Remove event handler
    pub async fn remove_handler(&self, name: &str) {
        self.handlers.write().await.remove(name);
    }

    /// Process stream with handlers
    pub async fn process(&self) -> Result<()> {
        let mut stream = self.client.event_stream().await;

        while let Some(event) = stream.next().await {
            match event {
                StreamEvent::Connected => {
                    info!("Stream processor connected");
                    self.stats.write().await.connected_at = Some(std::time::Instant::now());
                }

                StreamEvent::Disconnected => {
                    warn!("Stream processor disconnected");
                    self.stats.write().await.disconnected_at = Some(std::time::Instant::now());
                    break;
                }

                StreamEvent::Tweet {
                    tweet,
                    matching_rules,
                } => {
                    // Update stats
                    {
                        let mut stats = self.stats.write().await;
                        stats.tweets_received += 1;
                        stats.last_tweet_at = Some(std::time::Instant::now());
                    }

                    // Call handlers
                    let handlers = self.handlers.read().await;
                    for (name, handler) in handlers.iter() {
                        debug!("Calling handler: {}", name);
                        handler(tweet.clone());
                    }
                }

                StreamEvent::Error {
                    message,
                    recoverable,
                } => {
                    error!("Stream error: {} (recoverable: {})", message, recoverable);

                    let mut stats = self.stats.write().await;
                    stats.errors += 1;

                    if recoverable {
                        // Try to reconnect
                        if let Err(e) = self.client.reconnect_with_backoff().await {
                            error!("Failed to reconnect: {}", e);
                            break;
                        }
                    } else {
                        break;
                    }
                }

                StreamEvent::RateLimit {
                    limit,
                    remaining,
                    reset_at,
                } => {
                    warn!(
                        "Rate limit: {}/{} (resets at {})",
                        remaining, limit, reset_at
                    );

                    let mut stats = self.stats.write().await;
                    stats.rate_limit_hits += 1;
                }
            }
        }

        Ok(())
    }

    /// Get statistics
    pub async fn get_stats(&self) -> StreamStats {
        self.stats.read().await.clone()
    }
}

/// Stream statistics
#[derive(Debug, Clone, Default)]
pub struct StreamStats {
    pub connected_at: Option<std::time::Instant>,
    pub disconnected_at: Option<std::time::Instant>,
    pub tweets_received: u64,
    pub last_tweet_at: Option<std::time::Instant>,
    pub errors: u64,
    pub rate_limit_hits: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_filter_rule() {
        let rule = FilterRule::new("from:elonmusk");
        assert_eq!(rule.value, "from:elonmusk");
        assert!(rule.tag.is_none());

        let rule_with_tag = FilterRule::with_tag("bitcoin", "crypto");
        assert_eq!(rule_with_tag.value, "bitcoin");
        assert_eq!(rule_with_tag.tag.unwrap(), "crypto");
    }

    #[tokio::test]
    async fn test_stream_processor() {
        let config = TwitterConfig::default();
        let client = Arc::new(StreamingClient::new(config).unwrap());
        let processor = StreamProcessor::new(client);

        // Add handler
        processor
            .add_handler("test", |tweet| {
                println!("Tweet: {}", tweet.text);
            })
            .await;

        // Check handler exists
        assert_eq!(processor.handlers.read().await.len(), 1);

        // Remove handler
        processor.remove_handler("test").await;
        assert_eq!(processor.handlers.read().await.len(), 0);
    }
}
